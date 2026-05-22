// Copyright 2026 icefelix.com. BSD-3-Clause.

import Cocoa
import FlutterMacOS

/// Plugin registration entry point. Wires WindowHostApi to a stub
/// implementation that throws PigeonError(.notImplemented) for every method.
/// Real NSWindow logic lands in W2.2-W2.4.
public class IcefelixWindowManagerMacosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger
    let api = WindowHostApiStub()
    WindowHostApiSetup.setUp(binaryMessenger: messenger, api: api)
  }
}

/// Stub implementation — every method throws a fatalError until real NSWindow
/// logic lands in W2.2 through W2.4. Calls bubble back to Dart as
/// PlatformException via Pigeon's standard error wrapping when implementations
/// throw; using fatalError here makes "not yet implemented" obvious during
/// development. Will be replaced before any release.
class WindowHostApiStub: WindowHostApi {
  private func todo(_ method: String) -> Never {
    fatalError(
      "icefelix_window_manager_macos: \(method) not implemented yet (W2.x pending)"
    )
  }

  func ensureInitialized() throws -> WindowSnapshotRaw { todo("ensureInitialized") }
  func getPlatformInfo() throws -> PlatformInfoRaw { todo("getPlatformInfo") }
  func getBounds() throws -> WindowBoundsRaw { todo("getBounds") }
  func setBounds(bounds: WindowBoundsRaw, displayId: String?) throws { todo("setBounds") }
  func setSize(size: SizeRaw) throws { todo("setSize") }
  func setMinSize(size: SizeRaw?) throws { todo("setMinSize") }
  func setMaxSize(size: SizeRaw?) throws { todo("setMaxSize") }
  func setPosition(position: OffsetRaw) throws { todo("setPosition") }
  func center() throws { todo("center") }
  func moveToDisplay(displayId: String) throws { todo("moveToDisplay") }
  func minimize() throws { todo("minimize") }
  func maximize() throws { todo("maximize") }
  func unmaximize() throws { todo("unmaximize") }
  func restore() throws { todo("restore") }
  func hide() throws { todo("hide") }
  func show() throws { todo("show") }
  func fullscreen() throws { todo("fullscreen") }
  func exitFullscreen() throws { todo("exitFullscreen") }
  func focus() throws { todo("focus") }
  func blur() throws { todo("blur") }
  func startDrag() throws { todo("startDrag") }
  func startResize(direction: ResizeDirectionRaw) throws { todo("startResize") }
  func close() throws { todo("close") }
  func destroy() throws { todo("destroy") }
  func setTitle(title: String) throws { todo("setTitle") }
  func setAlwaysOnTop(value: Bool) throws { todo("setAlwaysOnTop") }
  func setSkipTaskbar(value: Bool) throws { todo("setSkipTaskbar") }
  func setResizable(value: Bool) throws { todo("setResizable") }
  func setMovable(value: Bool) throws { todo("setMovable") }
  func setMinimizable(value: Bool) throws { todo("setMinimizable") }
  func setMaximizable(value: Bool) throws { todo("setMaximizable") }
  func setClosable(value: Bool) throws { todo("setClosable") }
  func setFrameless(value: Bool) throws { todo("setFrameless") }
  func setTitleBarStyle(style: TitleBarStyleRaw) throws { todo("setTitleBarStyle") }
  func setOpacity(opacity: Double) throws { todo("setOpacity") }
  func setBackgroundColor(argb: Int64) throws { todo("setBackgroundColor") }
  func setHasShadow(value: Bool) throws { todo("setHasShadow") }
  func setIcon(filesystemPath: String) throws { todo("setIcon") }
  func setPreventClose(value: Bool) throws { todo("setPreventClose") }
  func listDisplays() throws -> [DisplayRaw] { todo("listDisplays") }
  func getCurrentDisplay() throws -> DisplayRaw { todo("getCurrentDisplay") }
  func getPrimaryDisplay() throws -> DisplayRaw { todo("getPrimaryDisplay") }
}
