// Copyright 2026 icefelix.com. BSD-3-Clause.

import Cocoa
import FlutterMacOS

/// Plugin registration entry point. Wires WindowHostApi to a real NSWindow
/// implementation, and constructs a `WindowFlutterApi` caller so the native
/// layer can push snapshot/displays/close-request events back into Dart.
public class IcefelixWindowManagerMacosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger
    let api = WindowHostApiImpl(registrar: registrar)
    WindowHostApiSetup.setUp(binaryMessenger: messenger, api: api)

    // FlutterApi caller for native → Dart event emission. The Dart side
    // installs the corresponding handler via WindowFlutterApi.setUp().
    let flutterApi = WindowFlutterApi(binaryMessenger: messenger)
    api.setFlutterApi(flutterApi)
  }
}

/// Coordinate-system helpers.
///
/// Flutter uses logical px with origin = top-left, Y-axis growing down.
/// AppKit uses points with origin = bottom-left, Y-axis growing up.
///
/// All conversions are anchored on the PRIMARY screen (NSScreen.screens.first)
/// so that window position + display bounds share a single virtual coordinate
/// space — matches the Dart-side expectation that `DisplayRaw.bounds` and
/// `WindowBoundsRaw.position` are directly comparable.
extension NSWindow {
  /// Returns the window frame expressed in Flutter virtual coordinates
  /// (top-left origin, Y-down, anchored on the primary screen).
  func frameInFlutterCoords() -> NSRect {
    let primaryHeight = NSScreen.screens.first?.frame.height
      ?? self.screen?.frame.height
      ?? frame.height
    let cocoa = frame
    let flutterY = primaryHeight - (cocoa.origin.y + cocoa.height)
    return NSRect(
      x: cocoa.origin.x,
      y: flutterY,
      width: cocoa.width,
      height: cocoa.height
    )
  }

  /// Sets the window frame from a rect expressed in Flutter virtual
  /// coordinates (top-left origin, Y-down, anchored on the primary screen).
  func setFrameFromFlutterCoords(_ rect: NSRect, display: Bool = true) {
    let primaryHeight = NSScreen.screens.first?.frame.height
      ?? self.screen?.frame.height
      ?? rect.height
    let cocoaY = primaryHeight - (rect.origin.y + rect.height)
    setFrame(
      NSRect(x: rect.origin.x, y: cocoaY, width: rect.width, height: rect.height),
      display: display
    )
  }
}

/// Real WindowHostApi implementation backed by NSWindow + AppKit.
///
/// Scope coverage:
/// - W2.2: init, bounds, state machine, focus, lifecycle.
/// - W2.3: drag/resize, title/properties, frameless, visual.
/// - W2.4 (this file): multi-monitor (listDisplays/getCurrentDisplay/
///   getPrimaryDisplay, moveToDisplay, proper DisplayRaw conversion)
///   + FlutterApi event emission (onSnapshotChanged with 10ms coalescing,
///   onDisplaysChanged on hot-plug)
///   + close-request interception via NSWindowDelegate proxy.
class WindowHostApiImpl: NSObject, WindowHostApi {
  private weak var registrar: FlutterPluginRegistrar?

  /// Stored close-intercept toggle. Honored by the NSWindowDelegate proxy
  /// (`ForwardingWindowDelegate`) installed during `ensureInitialized`.
  private var preventCloseFlag = false

  /// Flags for properties that aren't directly introspectable from NSWindow
  /// state.
  private var alwaysOnTopFlag = false
  private var skipTaskbarFlag = false
  private var maximizableFlag = true
  private var titleBarStyleFlag: TitleBarStyleRaw = .normal

  /// Active local NSEvent monitor for manual window resize. macOS lacks a
  /// public performResize-from-edge API, so we install a temporary monitor
  /// that tracks mouse drags + computes new frames until mouse-up.
  private var activeResizeMonitor: Any?

  /// FlutterApi caller for native → Dart event emission. Injected from
  /// `IcefelixWindowManagerMacosPlugin.register` after Pigeon setUp.
  private var flutterApi: WindowFlutterApi?

  /// In-flight coalesced snapshot emit. We cancel + reschedule on every
  /// window event to avoid flooding the Dart isolate during high-frequency
  /// notifications (drag-resize fires didResize at 60 Hz+).
  private var snapshotEmitWorkItem: DispatchWorkItem?

  /// Notification observers installed on first `ensureInitialized`; removed
  /// in `deinit`.
  private var notificationObservers: [Any] = []

  /// NSWindowDelegate proxy installed on first `ensureInitialized`. Wraps
  /// any pre-existing Flutter-installed delegate via forwardingTarget(for:).
  private var customDelegate: ForwardingWindowDelegate?
  private weak var originalDelegate: NSWindowDelegate?

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
  }

  /// Injection point for the Pigeon-generated FlutterApi caller. Called from
  /// the plugin's `register(with:)` after `WindowHostApiSetup.setUp`.
  func setFlutterApi(_ api: WindowFlutterApi) {
    self.flutterApi = api
  }

  deinit {
    notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    snapshotEmitWorkItem?.cancel()
    if let m = activeResizeMonitor {
      NSEvent.removeMonitor(m)
    }
    // Restore the original delegate if we replaced it, so the host app's
    // delegate chain is intact after the plugin tears down.
    if let w = window, let proxy = customDelegate, w.delegate === proxy {
      w.delegate = originalDelegate
    }
  }

  /// Resolves the NSWindow that hosts the FlutterViewController for this
  /// plugin's registrar. Falls back to NSApplication.shared.mainWindow if
  /// the registrar's view is not yet attached (headless or early registration).
  private var window: NSWindow? {
    return registrar?.view?.window ?? NSApplication.shared.mainWindow
  }

  private func requireWindow() throws -> NSWindow {
    guard let w = window else {
      throw PigeonError(
        code: "no_window",
        message: "No NSWindow available — is FlutterViewController attached?",
        details: nil
      )
    }
    return w
  }

  // ============ INIT ============

  func ensureInitialized() throws -> WindowSnapshotRaw {
    let w = try requireWindow()
    if notificationObservers.isEmpty {
      installNotificationObservers(window: w)
      installWindowDelegate(window: w)
    }
    return buildSnapshot(window: w)
  }

  func getPlatformInfo() throws -> PlatformInfoRaw {
    // Sandbox container heuristic: sandboxed apps have $HOME rewritten to
    // ~/Library/Containers/<bundle-id>/Data. Avoids needing entitlement
    // introspection (which requires reading the embedded provisioning profile).
    let home = NSHomeDirectory()
    let sandboxed = home.contains("/Library/Containers/")
    return PlatformInfoRaw(
      target: "macos",
      displayServer: nil,
      isSandboxed: sandboxed
    )
  }

  // ============ BOUNDS ============

  func getBounds() throws -> WindowBoundsRaw {
    let w = try requireWindow()
    let frame = w.frameInFlutterCoords()
    return WindowBoundsRaw(
      position: OffsetRaw(dx: frame.origin.x, dy: frame.origin.y),
      size: SizeRaw(width: frame.width, height: frame.height)
    )
  }

  func setBounds(bounds: WindowBoundsRaw, displayId: String?) throws {
    let w = try requireWindow()
    // displayId is currently ignored here; callers that need to move across
    // displays should invoke moveToDisplay() explicitly. Combining the two
    // in one call is a future polish item once we can validate that the
    // target display contains the requested rect.
    let size = bounds.size
    let currentFlutterFrame = w.frameInFlutterCoords()
    let pos = bounds.position
    let rect = NSRect(
      x: pos?.dx ?? currentFlutterFrame.origin.x,
      y: pos?.dy ?? currentFlutterFrame.origin.y,
      width: size.width,
      height: size.height
    )
    w.setFrameFromFlutterCoords(rect)
  }

  func setSize(size: SizeRaw) throws {
    let w = try requireWindow()
    // Preserve top-left in Flutter coords (NSWindow.setFrame anchors at
    // bottom-left, so naive size change visually shifts the window up/down).
    let current = w.frameInFlutterCoords()
    let rect = NSRect(
      x: current.origin.x,
      y: current.origin.y,
      width: size.width,
      height: size.height
    )
    w.setFrameFromFlutterCoords(rect)
  }

  func setMinSize(size: SizeRaw?) throws {
    let w = try requireWindow()
    if let s = size {
      w.contentMinSize = NSSize(width: s.width, height: s.height)
    } else {
      w.contentMinSize = NSSize(width: 0, height: 0)
    }
  }

  func setMaxSize(size: SizeRaw?) throws {
    let w = try requireWindow()
    if let s = size {
      w.contentMaxSize = NSSize(width: s.width, height: s.height)
    } else {
      // Effectively unlimited.
      w.contentMaxSize = NSSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
      )
    }
  }

  func setPosition(position: OffsetRaw) throws {
    let w = try requireWindow()
    let current = w.frameInFlutterCoords()
    let rect = NSRect(
      x: position.dx,
      y: position.dy,
      width: current.width,
      height: current.height
    )
    w.setFrameFromFlutterCoords(rect)
  }

  func center() throws {
    let w = try requireWindow()
    w.center()
  }

  func moveToDisplay(displayId: String) throws {
    let w = try requireWindow()
    guard let displayID = UInt32(displayId) else {
      throw PigeonError(
        code: "invalid_display_id",
        message: "Display ID '\(displayId)' is not a numeric CGDirectDisplayID",
        details: nil
      )
    }
    let target = NSScreen.screens.first { screen in
      (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
        .uint32Value == displayID
    }
    guard let targetScreen = target else {
      throw PigeonError(
        code: "display_not_found",
        message: "No NSScreen with ID \(displayId)",
        details: nil
      )
    }
    // Preserve relative position within the current display; center on the
    // target if the relative-position rect doesn't fit inside it.
    let currentScreen = w.screen ?? NSScreen.main ?? targetScreen
    let curFrame = currentScreen.frame
    let relX = curFrame.width > 0
      ? (w.frame.origin.x - curFrame.origin.x) / curFrame.width
      : 0
    let relY = curFrame.height > 0
      ? (w.frame.origin.y - curFrame.origin.y) / curFrame.height
      : 0

    let tgtFrame = targetScreen.frame
    let newX = tgtFrame.origin.x + relX * tgtFrame.width
    let newY = tgtFrame.origin.y + relY * tgtFrame.height
    var newFrame = w.frame
    newFrame.origin = NSPoint(x: newX, y: newY)

    if !tgtFrame.contains(newFrame) {
      newFrame.origin.x = tgtFrame.midX - newFrame.width / 2
      newFrame.origin.y = tgtFrame.midY - newFrame.height / 2
    }
    w.setFrame(newFrame, display: true)
  }

  // ============ STATE MACHINE ============

  func minimize() throws {
    let w = try requireWindow()
    w.miniaturize(nil)
  }

  func maximize() throws {
    let w = try requireWindow()
    // zoom(_:) toggles, so only call when not already zoomed.
    if !w.isZoomed {
      w.zoom(nil)
    }
  }

  func unmaximize() throws {
    let w = try requireWindow()
    if w.isZoomed {
      w.zoom(nil)
    }
  }

  func restore() throws {
    let w = try requireWindow()
    if w.isMiniaturized {
      w.deminiaturize(nil)
    } else if !w.isVisible {
      w.makeKeyAndOrderFront(nil)
    }
    if w.isZoomed {
      w.zoom(nil)
    }
  }

  func hide() throws {
    let w = try requireWindow()
    w.orderOut(nil)
  }

  func show() throws {
    let w = try requireWindow()
    w.makeKeyAndOrderFront(nil)
  }

  func fullscreen() throws {
    let w = try requireWindow()
    // Idempotent: only toggle if not already fullscreen.
    if !w.styleMask.contains(.fullScreen) {
      w.toggleFullScreen(nil)
    }
  }

  func exitFullscreen() throws {
    let w = try requireWindow()
    if w.styleMask.contains(.fullScreen) {
      w.toggleFullScreen(nil)
    }
  }

  // ============ FOCUS ============

  func focus() throws {
    let w = try requireWindow()
    NSApplication.shared.activate(ignoringOtherApps: true)
    w.makeKeyAndOrderFront(nil)
  }

  func blur() throws {
    // macOS doesn't expose a true "blur this window" API; deactivating the
    // app pushes focus to the previously-active app, which is the closest
    // best-effort equivalent.
    NSApplication.shared.deactivate()
  }

  // ============ DRAG + RESIZE ============

  func startDrag() throws {
    let w = try requireWindow()
    // Prefer the current event when invoked from inside a real mouse-down
    // dispatch (e.g. a Flutter pointer handler driven by AppKit); fall back
    // to a synthesized leftMouseDown event for programmatic callers.
    if let evt = NSApp.currentEvent, evt.type == .leftMouseDown {
      w.performDrag(with: evt)
      return
    }
    let loc = NSEvent.mouseLocation
    if let evt = NSEvent.mouseEvent(
      with: .leftMouseDown,
      location: loc,
      modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: w.windowNumber,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: 1.0
    ) {
      w.performDrag(with: evt)
    }
  }

  func startResize(direction: ResizeDirectionRaw) throws {
    let w = try requireWindow()
    startManualResize(window: w, direction: direction)
  }

  /// Installs a local NSEvent monitor that tracks `.leftMouseDragged` events
  /// and updates the window frame per the requested resize direction until
  /// `.leftMouseUp`. Coordinates are in AppKit space (bottom-left origin) —
  /// `window.setFrame` takes AppKit coords directly so no Flutter-coord flip
  /// is needed here.
  private func startManualResize(window: NSWindow, direction: ResizeDirectionRaw) {
    // Cancel any in-flight resize before starting a new one.
    if let m = activeResizeMonitor {
      NSEvent.removeMonitor(m)
      activeResizeMonitor = nil
    }

    let startFrame = window.frame
    let startMouse = NSEvent.mouseLocation
    let minW: CGFloat = max(window.contentMinSize.width, 100)
    let minH: CGFloat = max(window.contentMinSize.height, 100)

    activeResizeMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDragged, .leftMouseUp]
    ) { [weak self] event in
      guard let self = self else { return event }

      if event.type == .leftMouseUp {
        if let m = self.activeResizeMonitor {
          NSEvent.removeMonitor(m)
          self.activeResizeMonitor = nil
        }
        return event
      }

      let currentMouse = NSEvent.mouseLocation
      let dx = currentMouse.x - startMouse.x
      let dy = currentMouse.y - startMouse.y

      var newFrame = startFrame
      switch direction {
      case .top:
        newFrame.size.height = max(minH, startFrame.size.height + dy)
      case .bottom:
        let newHeight = max(minH, startFrame.size.height - dy)
        newFrame.size.height = newHeight
        newFrame.origin.y = startFrame.origin.y + (startFrame.size.height - newHeight)
      case .left:
        let newWidth = max(minW, startFrame.size.width - dx)
        newFrame.size.width = newWidth
        newFrame.origin.x = startFrame.origin.x + (startFrame.size.width - newWidth)
      case .right:
        newFrame.size.width = max(minW, startFrame.size.width + dx)
      case .topLeft:
        let newWidth = max(minW, startFrame.size.width - dx)
        newFrame.size.width = newWidth
        newFrame.origin.x = startFrame.origin.x + (startFrame.size.width - newWidth)
        newFrame.size.height = max(minH, startFrame.size.height + dy)
      case .topRight:
        newFrame.size.width = max(minW, startFrame.size.width + dx)
        newFrame.size.height = max(minH, startFrame.size.height + dy)
      case .bottomLeft:
        let newWidth = max(minW, startFrame.size.width - dx)
        newFrame.size.width = newWidth
        newFrame.origin.x = startFrame.origin.x + (startFrame.size.width - newWidth)
        let newHeight = max(minH, startFrame.size.height - dy)
        newFrame.size.height = newHeight
        newFrame.origin.y = startFrame.origin.y + (startFrame.size.height - newHeight)
      case .bottomRight:
        newFrame.size.width = max(minW, startFrame.size.width + dx)
        let newHeight = max(minH, startFrame.size.height - dy)
        newFrame.size.height = newHeight
        newFrame.origin.y = startFrame.origin.y + (startFrame.size.height - newHeight)
      }

      window.setFrame(newFrame, display: true)
      return event
    }
  }

  // ============ LIFECYCLE ============

  func close() throws {
    let w = try requireWindow()
    // Goes through NSWindowDelegate.windowShouldClose:, which our
    // ForwardingWindowDelegate intercepts to honor preventCloseFlag and
    // emit FlutterApi.onCloseRequest before actually closing.
    w.performClose(nil)
  }

  func destroy() throws {
    let w = try requireWindow()
    // Bypasses delegate — guaranteed close.
    w.close()
  }

  // ============ TITLE + PROPERTIES ============

  func setTitle(title: String) throws {
    let w = try requireWindow()
    w.title = title
  }

  func setAlwaysOnTop(value: Bool) throws {
    let w = try requireWindow()
    alwaysOnTopFlag = value
    w.level = value ? .floating : .normal
  }

  func setSkipTaskbar(value: Bool) throws {
    let w = try requireWindow()
    skipTaskbarFlag = value
    // macOS has no true taskbar. The closest analog is excluding the window
    // from Mission Control / window cycling via collectionBehavior. Note this
    // does NOT hide the app from the Dock — that requires LSUIElement=YES in
    // Info.plist (a build-time decision, not a per-window runtime toggle).
    if value {
      w.collectionBehavior.insert(.transient)
      w.collectionBehavior.insert(.ignoresCycle)
    } else {
      w.collectionBehavior.remove(.transient)
      w.collectionBehavior.remove(.ignoresCycle)
    }
  }

  func setResizable(value: Bool) throws {
    let w = try requireWindow()
    if value {
      w.styleMask.insert(.resizable)
    } else {
      w.styleMask.remove(.resizable)
    }
  }

  func setMovable(value: Bool) throws {
    let w = try requireWindow()
    w.isMovable = value
  }

  func setMinimizable(value: Bool) throws {
    let w = try requireWindow()
    if value {
      w.styleMask.insert(.miniaturizable)
    } else {
      w.styleMask.remove(.miniaturizable)
    }
  }

  func setMaximizable(value: Bool) throws {
    _ = try requireWindow()
    // Flag-tracked for now: macOS shows a zoom (maximize) button whenever
    // .resizable is in the styleMask, with no separate "maximizable" bit.
    // True enforcement requires NSWindowDelegate.windowShouldZoom(_:toFrame:)
    // returning false; that delegate lands in W2.4.
    maximizableFlag = value
  }

  func setClosable(value: Bool) throws {
    let w = try requireWindow()
    if value {
      w.styleMask.insert(.closable)
    } else {
      w.styleMask.remove(.closable)
    }
  }

  // ============ FRAMELESS + TITLE BAR ============

  func setFrameless(value: Bool) throws {
    let w = try requireWindow()
    if value {
      w.styleMask.remove(.titled)
      w.titlebarAppearsTransparent = true
    } else {
      w.styleMask.insert(.titled)
      // Only un-transparent the titlebar if the active title-bar style would
      // normally show it; .hiddenInset keeps the transparent titlebar.
      if titleBarStyleFlag != .hiddenInset {
        w.titlebarAppearsTransparent = false
      }
    }
  }

  func setTitleBarStyle(style: TitleBarStyleRaw) throws {
    let w = try requireWindow()
    titleBarStyleFlag = style
    switch style {
    case .normal:
      w.titlebarAppearsTransparent = false
      w.titleVisibility = .visible
      w.styleMask.remove(.fullSizeContentView)
    case .hidden:
      w.titlebarAppearsTransparent = false
      w.titleVisibility = .hidden
      w.styleMask.remove(.fullSizeContentView)
    case .hiddenInset:
      // Title bar stays present (so traffic lights remain), but content
      // extends underneath it and the bar itself goes transparent.
      w.titlebarAppearsTransparent = true
      w.titleVisibility = .hidden
      w.styleMask.insert(.fullSizeContentView)
    }
  }

  // ============ VISUAL ============

  func setOpacity(opacity: Double) throws {
    let w = try requireWindow()
    let clamped = max(0.0, min(1.0, opacity))
    w.alphaValue = CGFloat(clamped)
  }

  func setBackgroundColor(argb: Int64) throws {
    let w = try requireWindow()
    let a = CGFloat((argb >> 24) & 0xFF) / 255.0
    let r = CGFloat((argb >> 16) & 0xFF) / 255.0
    let g = CGFloat((argb >> 8) & 0xFF) / 255.0
    let b = CGFloat(argb & 0xFF) / 255.0
    w.backgroundColor = NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    // Opaque windows render via a fast path; transparency demands isOpaque=false
    // so AppKit composites alpha properly.
    w.isOpaque = (a >= 1.0)
  }

  func setHasShadow(value: Bool) throws {
    let w = try requireWindow()
    w.hasShadow = value
  }

  func setIcon(filesystemPath: String) throws {
    let url = URL(fileURLWithPath: filesystemPath)
    guard let img = NSImage(contentsOf: url) else {
      throw PigeonError(
        code: "invalid_icon_path",
        message: "Could not load NSImage from \(filesystemPath)",
        details: nil
      )
    }
    // macOS has no per-window icon concept; this sets the app's Dock icon.
    NSApplication.shared.applicationIconImage = img
  }

  // ============ CLOSE INTERCEPTION ============

  func setPreventClose(value: Bool) throws {
    // Honored by ForwardingWindowDelegate.windowShouldClose(_:), which the
    // first ensureInitialized() call installs on the host NSWindow.
    preventCloseFlag = value
  }

  // ============ MULTI-MONITOR ============

  func listDisplays() throws -> [DisplayRaw] {
    return NSScreen.screens.map(displayRawFromScreen)
  }

  func getCurrentDisplay() throws -> DisplayRaw {
    let w = try requireWindow()
    guard let screen = w.screen ?? NSScreen.main ?? NSScreen.screens.first else {
      throw PigeonError(
        code: "no_screens",
        message: "No NSScreens available",
        details: nil
      )
    }
    return displayRawFromScreen(screen)
  }

  func getPrimaryDisplay() throws -> DisplayRaw {
    guard let primary = NSScreen.screens.first else {
      throw PigeonError(
        code: "no_screens",
        message: "No NSScreens available",
        details: nil
      )
    }
    return displayRawFromScreen(primary)
  }

  // ============ SNAPSHOT BUILDER (private helper) ============

  private func buildSnapshot(window: NSWindow) -> WindowSnapshotRaw {
    let frame = window.frameInFlutterCoords()
    // Force-unwrap is safe: NSScreen.main is nil only on a truly headless
    // machine without any displays attached; not a realistic scenario for a
    // Flutter desktop app, and requireWindow() would already have returned
    // a window in such an environment only if one had been programmatically
    // created off-screen — at which point a snapshot is undefined.
    let screen = window.screen ?? NSScreen.main!
    return WindowSnapshotRaw(
      bounds: WindowBoundsRaw(
        position: OffsetRaw(dx: frame.origin.x, dy: frame.origin.y),
        size: SizeRaw(width: frame.width, height: frame.height)
      ),
      state: currentWindowState(window),
      title: window.title,
      isFocused: window.isKeyWindow,
      // Prefer the tracked flag; fall back to the live NSWindow level for
      // windows that were elevated without going through setAlwaysOnTop.
      alwaysOnTop: alwaysOnTopFlag
        || window.level.rawValue >= NSWindow.Level.floating.rawValue,
      // No direct platform read for "skip taskbar" on macOS; mirror the flag
      // set via setSkipTaskbar.
      skipTaskbar: skipTaskbarFlag,
      resizable: window.styleMask.contains(.resizable),
      movable: window.isMovable,
      minimizable: window.styleMask.contains(.miniaturizable),
      // No dedicated macOS bit for "maximizable"; mirror the flag set via
      // setMaximizable. True enforcement would require
      // NSWindowDelegate.windowShouldZoom(_:toFrame:) returning false.
      maximizable: maximizableFlag,
      closable: window.styleMask.contains(.closable),
      frameless: !window.styleMask.contains(.titled),
      titleBarStyle: titleBarStyleFlag,
      opacity: Double(window.alphaValue),
      backgroundColorArgb: argbFromNSColor(window.backgroundColor),
      hasShadow: window.hasShadow,
      preventClose: preventCloseFlag,
      currentDisplay: displayRawFromScreen(screen)
    )
  }

  private func currentWindowState(_ window: NSWindow) -> WindowStateRaw {
    if window.isMiniaturized { return .minimized }
    if window.styleMask.contains(.fullScreen) { return .fullscreen }
    if window.isZoomed { return .maximized }
    if !window.isVisible { return .hidden }
    return .normal
  }

  private func argbFromNSColor(_ color: NSColor?) -> Int64? {
    guard let c = color?.usingColorSpace(.sRGB) else { return nil }
    let a = Int(c.alphaComponent * 255) & 0xFF
    let r = Int(c.redComponent * 255) & 0xFF
    let g = Int(c.greenComponent * 255) & 0xFF
    let b = Int(c.blueComponent * 255) & 0xFF
    return Int64((a << 24) | (r << 16) | (g << 8) | b)
  }

  // ============ DISPLAY CONVERSION (private helper) ============

  /// Converts an NSScreen to the cross-platform DisplayRaw shape:
  /// - id: CGDirectDisplayID stringified (stable for the process session)
  /// - bounds/workArea: re-projected from AppKit (bottom-left, Y-up) to
  ///   Flutter (top-left, Y-down) coordinates anchored on the PRIMARY
  ///   screen's origin (matches NSScreen.screens.first, which is the
  ///   user-designated primary display in System Settings → Displays)
  /// - physicalWidthMm / physicalHeightMm: from CGDisplayScreenSize, nullable
  ///   when the EDID reports 0×0 (e.g., virtual displays, mirrored sessions)
  /// - dpi: derived from physical mm + native pixel dimensions, nullable
  ///   when physical size is unknown
  /// - refreshRate: from CGDisplayCopyDisplayMode, nullable when the mode
  ///   is unavailable or the panel reports 0 Hz (some VMs / virtual displays)
  /// - isPrimary: matches NSScreen.screens.first (the virtual-coord origin)
  private func displayRawFromScreen(_ screen: NSScreen) -> DisplayRaw {
    let screenNumber = screen.deviceDescription[
      NSDeviceDescriptionKey("NSScreenNumber")
    ] as? NSNumber
    let displayID = screenNumber.map { CGDirectDisplayID($0.uint32Value) } ?? 0

    // Physical size in millimetres; CGDisplayScreenSize returns CGSize(0,0)
    // when unknown (typical for virtual / mirrored displays).
    let physicalSize = CGDisplayScreenSize(displayID)
    let physicalW: Double? = physicalSize.width > 0 ? Double(physicalSize.width) : nil
    let physicalH: Double? = physicalSize.height > 0 ? Double(physicalSize.height) : nil

    // DPI from physical mm + native pixel dimensions, when both known.
    var dpi: Double? = nil
    if let pw = physicalW, pw > 0 {
      let pixelWidth = Double(screen.frame.width) * Double(screen.backingScaleFactor)
      let inchesWide = pw / 25.4
      if inchesWide > 0 {
        dpi = pixelWidth / inchesWide
      }
    }

    // Refresh rate; CGDisplayModeGetRefreshRate returns 0.0 when the panel
    // doesn't advertise a refresh (some VMs).
    let refreshRate: Int64? = {
      guard let mode = CGDisplayCopyDisplayMode(displayID) else { return nil }
      let rr = mode.refreshRate
      return rr > 0 ? Int64(round(rr)) : nil
    }()

    // Y-flip relative to the primary screen so all displays share a single
    // Flutter virtual coordinate space (top-left origin at primary's
    // top-left, growing down + right). Matches the protocol Linux/Windows
    // backends are expected to honor.
    let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
    let cocoaFrame = screen.frame
    let cocoaWorkArea = screen.visibleFrame
    let flutterFrameY = primaryHeight - (cocoaFrame.origin.y + cocoaFrame.height)
    let flutterWorkY = primaryHeight - (cocoaWorkArea.origin.y + cocoaWorkArea.height)

    return DisplayRaw(
      id: String(displayID),
      name: screen.localizedName,
      bounds: RectRaw(
        x: cocoaFrame.origin.x,
        y: flutterFrameY,
        width: cocoaFrame.width,
        height: cocoaFrame.height
      ),
      workArea: RectRaw(
        x: cocoaWorkArea.origin.x,
        y: flutterWorkY,
        width: cocoaWorkArea.width,
        height: cocoaWorkArea.height
      ),
      physicalWidthMm: physicalW,
      physicalHeightMm: physicalH,
      dpi: dpi,
      scaleFactor: Double(screen.backingScaleFactor),
      // NSScreen.screens[0] is the user-designated primary display
      // (the one with the menu bar, top-left of the virtual coord space).
      isPrimary: screen == NSScreen.screens.first,
      refreshRate: refreshRate
    )
  }

  // ============ EVENT EMISSION ============

  /// Coalesces snapshot emit calls to ~10 ms to avoid flooding the Dart
  /// isolate during high-frequency notifications (drag-resize fires
  /// didResize at 60 Hz+, didMove similarly during drag).
  private func scheduleSnapshotEmit() {
    snapshotEmitWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      self?.emitSnapshotNow()
    }
    snapshotEmitWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10), execute: work)
  }

  private func emitSnapshotNow() {
    guard let w = window, let api = flutterApi else { return }
    let snapshot = buildSnapshot(window: w)
    api.onSnapshotChanged(snapshot: snapshot) { _ in /* ignore */ }
  }

  private func emitDisplaysChanged() {
    guard let api = flutterApi else { return }
    let displays = NSScreen.screens.map(displayRawFromScreen)
    api.onDisplaysChanged(displays: displays) { _ in /* ignore */ }
  }

  /// Subscribes to NSWindow lifecycle notifications (size/position/focus/
  /// state/screen) and NSApplication.didChangeScreenParameters so the
  /// Dart side stays in sync with platform-driven changes (user drags
  /// window, toggles fullscreen via menu, plugs in / unplugs a monitor).
  private func installNotificationObservers(window: NSWindow) {
    let nc = NotificationCenter.default
    let queue = OperationQueue.main

    let snapshotTriggers: [Notification.Name] = [
      NSWindow.didResizeNotification,
      NSWindow.didMoveNotification,
      NSWindow.didBecomeKeyNotification,
      NSWindow.didResignKeyNotification,
      NSWindow.didMiniaturizeNotification,
      NSWindow.didDeminiaturizeNotification,
      NSWindow.didEnterFullScreenNotification,
      NSWindow.didExitFullScreenNotification,
      NSWindow.didChangeScreenNotification,
    ]
    for name in snapshotTriggers {
      let token = nc.addObserver(forName: name, object: window, queue: queue) {
        [weak self] _ in self?.scheduleSnapshotEmit()
      }
      notificationObservers.append(token)
    }

    let displaysToken = nc.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: queue
    ) { [weak self] _ in
      self?.emitDisplaysChanged()
    }
    notificationObservers.append(displaysToken)
  }

  // ============ CLOSE INTERCEPT (NSWindowDelegate proxy) ============

  /// Installs a `ForwardingWindowDelegate` proxy that intercepts only
  /// `windowShouldClose:`, forwarding every other selector to the original
  /// delegate (typically Flutter's FlutterViewController-installed one).
  /// This lets us honor `preventClose` without breaking Flutter's normal
  /// window-event flow.
  private func installWindowDelegate(window: NSWindow) {
    let original = window.delegate
    let proxy = ForwardingWindowDelegate(
      original: original,
      onShouldClose: { [weak self] in self?.handleShouldClose() ?? true }
    )
    self.originalDelegate = original
    self.customDelegate = proxy
    window.delegate = proxy
  }

  /// Called by `ForwardingWindowDelegate` from `windowShouldClose:`.
  /// Returns true to allow immediate close, false to block.
  ///
  /// When `preventCloseFlag` is true and a FlutterApi caller is available:
  ///  - fire `onCloseRequest` (async, returns Bool from Dart)
  ///  - return false now to block the immediate close
  ///  - on Dart response, either call `window.close()` to actually close
  ///    (bypassing the delegate, which would re-trigger preventClose) or
  ///    do nothing (window stays open)
  ///  - on Pigeon channel error, default to allow close (don't trap the user
  ///    in a window they can't dismiss)
  private func handleShouldClose() -> Bool {
    guard preventCloseFlag, let api = flutterApi else { return true }
    api.onCloseRequest { [weak self] result in
      guard let self = self else { return }
      switch result {
      case .success(let allow):
        if allow {
          DispatchQueue.main.async { [weak self] in
            self?.window?.close()
          }
        }
      case .failure:
        DispatchQueue.main.async { [weak self] in
          self?.window?.close()
        }
      }
    }
    return false
  }
}

// MARK: - ForwardingWindowDelegate

/// Wraps any pre-existing NSWindowDelegate, intercepting `windowShouldClose:`
/// to drive icefelix_window_manager's preventClose flow while forwarding
/// every other selector to the original delegate (typically Flutter's
/// FlutterViewController-installed delegate). Uses `forwardingTarget(for:)`
/// for transparent NSInvocation forwarding rather than re-implementing every
/// NSWindowDelegate method.
class ForwardingWindowDelegate: NSObject, NSWindowDelegate {
  weak var original: NSWindowDelegate?
  let onShouldClose: () -> Bool

  init(original: NSWindowDelegate?, onShouldClose: @escaping () -> Bool) {
    self.original = original
    self.onShouldClose = onShouldClose
    super.init()
  }

  // Intercept the one method we care about. Give the original delegate
  // (if any) first refusal — if it denies the close, we never reach our
  // own preventClose logic.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if let orig = original,
      orig.responds(to: #selector(NSWindowDelegate.windowShouldClose(_:)))
    {
      if let answer = orig.windowShouldClose?(sender), !answer {
        return false
      }
    }
    return onShouldClose()
  }

  // Forward every other selector to the original delegate via NSInvocation,
  // so methods like windowDidBecomeKey, windowWillResize:toSize:, etc. still
  // reach Flutter's delegate exactly as if we weren't in the chain.
  override func responds(to aSelector: Selector!) -> Bool {
    if aSelector == #selector(NSWindowDelegate.windowShouldClose(_:)) {
      return true
    }
    return original?.responds(to: aSelector) ?? super.responds(to: aSelector)
  }

  override func forwardingTarget(for aSelector: Selector!) -> Any? {
    if let original = original, original.responds(to: aSelector) {
      return original
    }
    return nil
  }
}
