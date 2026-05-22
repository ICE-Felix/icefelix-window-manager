// Copyright 2026 icefelix.com. BSD-3-Clause.

import Cocoa
import FlutterMacOS

/// Plugin registration entry point. Wires WindowHostApi to a real NSWindow
/// implementation. W2.2 covers bounds, state machine, focus, and lifecycle.
/// Drag/resize, title/properties/visual, frameless, multi-monitor and
/// FlutterApi event emission land in W2.3 / W2.4.
public class IcefelixWindowManagerMacosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger
    let api = WindowHostApiImpl(registrar: registrar)
    WindowHostApiSetup.setUp(binaryMessenger: messenger, api: api)
  }
}

/// Coordinate-system helpers.
///
/// Flutter uses logical px with origin = top-left, Y-axis growing down.
/// AppKit uses points with origin = bottom-left, Y-axis growing up.
/// Conversions below are anchored to the window's current screen (W2.2 scope —
/// proper multi-monitor virtual coord space arrives in W2.4).
extension NSWindow {
  /// Returns the window frame expressed in Flutter coordinates
  /// (top-left origin, Y-down) on the window's current screen.
  func frameInFlutterCoords() -> NSRect {
    guard let screen = self.screen ?? NSScreen.main else { return frame }
    let cocoa = frame
    let flutterY = screen.frame.height - (cocoa.origin.y + cocoa.height)
    return NSRect(
      x: cocoa.origin.x,
      y: flutterY,
      width: cocoa.width,
      height: cocoa.height
    )
  }

  /// Sets the window frame from a rect expressed in Flutter coordinates
  /// (top-left origin, Y-down) on the window's current screen.
  func setFrameFromFlutterCoords(_ rect: NSRect, display: Bool = true) {
    guard let screen = self.screen ?? NSScreen.main else { return }
    let cocoaY = screen.frame.height - (rect.origin.y + rect.height)
    setFrame(
      NSRect(x: rect.origin.x, y: cocoaY, width: rect.width, height: rect.height),
      display: display
    )
  }
}

/// Real WindowHostApi implementation backed by NSWindow + AppKit.
///
/// Scope coverage:
/// - W2.2 (this file): init, bounds, state machine, focus, lifecycle.
/// - W2.3: drag/resize, title/properties, frameless, visual.
/// - W2.4: multi-monitor (listDisplays/getCurrentDisplay/getPrimaryDisplay,
///   moveToDisplay, proper DisplayRaw conversion) + FlutterApi event emission
///   + close-request interception via NSWindowDelegate.
class WindowHostApiImpl: WindowHostApi {
  private weak var registrar: FlutterPluginRegistrar?

  /// W2.2: just stored. W2.4 wires NSWindowDelegate.windowShouldClose: to
  /// fire FlutterApi.onCloseRequest and block the close until Dart responds.
  private var preventCloseFlag = false

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
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

  private func todo(_ method: String) -> Never {
    fatalError(
      "icefelix_window_manager_macos: \(method) — not implemented yet (W2.3/W2.4 pending)"
    )
  }

  // ============ INIT ============

  func ensureInitialized() throws -> WindowSnapshotRaw {
    let w = try requireWindow()
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
    // W2.2: ignore displayId. Multi-monitor logic comes in W2.4 once
    // listDisplays() establishes stable display IDs.
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
    // W2.4: needs NSScreen enumeration + stable DisplayId mapping.
    todo("moveToDisplay (W2.4)")
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

  // ============ DRAG + RESIZE (W2.3) ============

  func startDrag() throws { todo("startDrag (W2.3)") }
  func startResize(direction: ResizeDirectionRaw) throws { todo("startResize (W2.3)") }

  // ============ LIFECYCLE ============

  func close() throws {
    let w = try requireWindow()
    // Goes through NSWindowDelegate.windowShouldClose: — W2.4 hooks this
    // to honor preventCloseFlag and emit FlutterApi.onCloseRequest.
    w.performClose(nil)
  }

  func destroy() throws {
    let w = try requireWindow()
    // Bypasses delegate — guaranteed close.
    w.close()
  }

  // ============ TITLE + PROPERTIES (W2.3) ============

  func setTitle(title: String) throws { todo("setTitle (W2.3)") }
  func setAlwaysOnTop(value: Bool) throws { todo("setAlwaysOnTop (W2.3)") }
  func setSkipTaskbar(value: Bool) throws { todo("setSkipTaskbar (W2.3)") }
  func setResizable(value: Bool) throws { todo("setResizable (W2.3)") }
  func setMovable(value: Bool) throws { todo("setMovable (W2.3)") }
  func setMinimizable(value: Bool) throws { todo("setMinimizable (W2.3)") }
  func setMaximizable(value: Bool) throws { todo("setMaximizable (W2.3)") }
  func setClosable(value: Bool) throws { todo("setClosable (W2.3)") }

  // ============ FRAMELESS + TITLE BAR (W2.3) ============

  func setFrameless(value: Bool) throws { todo("setFrameless (W2.3)") }
  func setTitleBarStyle(style: TitleBarStyleRaw) throws { todo("setTitleBarStyle (W2.3)") }

  // ============ VISUAL (W2.3) ============

  func setOpacity(opacity: Double) throws { todo("setOpacity (W2.3)") }
  func setBackgroundColor(argb: Int64) throws { todo("setBackgroundColor (W2.3)") }
  func setHasShadow(value: Bool) throws { todo("setHasShadow (W2.3)") }
  func setIcon(filesystemPath: String) throws { todo("setIcon (W2.3)") }

  // ============ CLOSE INTERCEPTION ============

  func setPreventClose(value: Bool) throws {
    // W2.2: store only. W2.4 wires NSWindowDelegate.windowShouldClose: to
    // emit FlutterApi.onCloseRequest and block close until Dart responds.
    preventCloseFlag = value
  }

  // ============ MULTI-MONITOR (W2.4) ============

  func listDisplays() throws -> [DisplayRaw] { todo("listDisplays (W2.4)") }
  func getCurrentDisplay() throws -> DisplayRaw { todo("getCurrentDisplay (W2.4)") }
  func getPrimaryDisplay() throws -> DisplayRaw { todo("getPrimaryDisplay (W2.4)") }

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
      alwaysOnTop: window.level.rawValue >= NSWindow.Level.floating.rawValue,
      // macOS doesn't have a direct "skip taskbar" concept; refined in W2.3.
      skipTaskbar: false,
      resizable: window.styleMask.contains(.resizable),
      movable: window.isMovable,
      minimizable: window.styleMask.contains(.miniaturizable),
      // macOS exposes a zoom button when .resizable is set; refined in W2.3.
      maximizable: true,
      closable: window.styleMask.contains(.closable),
      frameless: !window.styleMask.contains(.titled),
      // Refined in W2.3 once setTitleBarStyle is wired.
      titleBarStyle: .normal,
      opacity: Double(window.alphaValue),
      backgroundColorArgb: argbFromNSColor(window.backgroundColor),
      hasShadow: window.hasShadow,
      preventClose: preventCloseFlag,
      currentDisplay: placeholderDisplay(screen)
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

  /// W2.2 placeholder. W2.4 replaces with proper DisplayRaw conversion that:
  /// - assigns stable IDs from NSScreenNumber (CGDirectDisplayID)
  /// - converts NSScreen.frame from AppKit (bottom-left) → Flutter (top-left)
  ///   coordinates relative to the virtual desktop origin
  /// - resolves physical width/height/DPI via CGDisplay APIs
  /// - reads refresh rate via CGDisplayModeGetRefreshRate
  private func placeholderDisplay(_ screen: NSScreen) -> DisplayRaw {
    let frame = screen.frame
    let workArea = screen.visibleFrame
    return DisplayRaw(
      id: "screen-placeholder",
      name: screen.localizedName,
      bounds: RectRaw(
        x: frame.origin.x,
        y: frame.origin.y,
        width: frame.width,
        height: frame.height
      ),
      workArea: RectRaw(
        x: workArea.origin.x,
        y: workArea.origin.y,
        width: workArea.width,
        height: workArea.height
      ),
      physicalWidthMm: nil,
      physicalHeightMm: nil,
      dpi: nil,
      scaleFactor: Double(screen.backingScaleFactor),
      isPrimary: screen == NSScreen.main,
      refreshRate: nil
    )
  }
}
