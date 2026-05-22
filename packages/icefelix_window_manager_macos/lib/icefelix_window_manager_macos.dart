// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'package:icefelix_window_manager_platform_interface/icefelix_window_manager_platform_interface.dart';

/// macOS implementation of [WindowManagerPlatform].
///
/// Delegates every call to the Pigeon-generated [WindowHostApi], which routes
/// to the Swift side via `IcefelixWindowManagerMacosPlugin`. Native-to-Dart
/// callbacks are wired through [registerFlutterApi].
class IcefelixWindowManagerMacos extends WindowManagerPlatform {
  /// Creates the macOS platform implementation.
  IcefelixWindowManagerMacos() : super();

  /// Auto-registered by Flutter when the plugin loads (per pubspec.yaml
  /// flutter.plugin.platforms.macos.dartPluginClass).
  static void registerWith() {
    WindowManagerPlatform.instance = IcefelixWindowManagerMacos();
  }

  final WindowHostApi _hostApi = WindowHostApi();

  // ============ INITIALIZATION ============
  @override
  Future<WindowSnapshotRaw> ensureInitialized() => _hostApi.ensureInitialized();

  @override
  Future<PlatformInfoRaw> getPlatformInfo() => _hostApi.getPlatformInfo();

  // ============ BOUNDS ============
  @override
  Future<WindowBoundsRaw> getBounds() => _hostApi.getBounds();

  @override
  Future<void> setBounds(WindowBoundsRaw bounds, String? displayId) =>
      _hostApi.setBounds(bounds, displayId);

  @override
  Future<void> setSize(SizeRaw size) => _hostApi.setSize(size);

  @override
  Future<void> setMinSize(SizeRaw? size) => _hostApi.setMinSize(size);

  @override
  Future<void> setMaxSize(SizeRaw? size) => _hostApi.setMaxSize(size);

  @override
  Future<void> setPosition(OffsetRaw position) =>
      _hostApi.setPosition(position);

  @override
  Future<void> center() => _hostApi.center();

  @override
  Future<void> moveToDisplay(String displayId) =>
      _hostApi.moveToDisplay(displayId);

  // ============ STATE ============
  @override
  Future<void> minimize() => _hostApi.minimize();
  @override
  Future<void> maximize() => _hostApi.maximize();
  @override
  Future<void> unmaximize() => _hostApi.unmaximize();
  @override
  Future<void> restore() => _hostApi.restore();
  @override
  Future<void> hide() => _hostApi.hide();
  @override
  Future<void> show() => _hostApi.show();
  @override
  Future<void> fullscreen() => _hostApi.fullscreen();
  @override
  Future<void> exitFullscreen() => _hostApi.exitFullscreen();

  // ============ FOCUS ============
  @override
  Future<void> focus() => _hostApi.focus();
  @override
  Future<void> blur() => _hostApi.blur();

  // ============ DRAG + RESIZE ============
  @override
  Future<void> startDrag() => _hostApi.startDrag();
  @override
  Future<void> startResize(ResizeDirectionRaw direction) =>
      _hostApi.startResize(direction);

  // ============ LIFECYCLE ============
  @override
  Future<void> close() => _hostApi.close();
  @override
  Future<void> destroy() => _hostApi.destroy();

  // ============ TITLE + PROPERTIES ============
  @override
  Future<void> setTitle(String title) => _hostApi.setTitle(title);
  @override
  Future<void> setAlwaysOnTop(bool value) => _hostApi.setAlwaysOnTop(value);
  @override
  Future<void> setSkipTaskbar(bool value) => _hostApi.setSkipTaskbar(value);
  @override
  Future<void> setResizable(bool value) => _hostApi.setResizable(value);
  @override
  Future<void> setMovable(bool value) => _hostApi.setMovable(value);
  @override
  Future<void> setMinimizable(bool value) => _hostApi.setMinimizable(value);
  @override
  Future<void> setMaximizable(bool value) => _hostApi.setMaximizable(value);
  @override
  Future<void> setClosable(bool value) => _hostApi.setClosable(value);

  // ============ FRAMELESS + TITLE BAR ============
  @override
  Future<void> setFrameless(bool value) => _hostApi.setFrameless(value);
  @override
  Future<void> setTitleBarStyle(TitleBarStyleRaw style) =>
      _hostApi.setTitleBarStyle(style);

  // ============ VISUAL ============
  @override
  Future<void> setOpacity(double opacity) => _hostApi.setOpacity(opacity);
  @override
  Future<void> setBackgroundColor(int argb) =>
      _hostApi.setBackgroundColor(argb);
  @override
  Future<void> setHasShadow(bool value) => _hostApi.setHasShadow(value);
  @override
  Future<void> setIcon(String filesystemPath) =>
      _hostApi.setIcon(filesystemPath);

  // ============ CLOSE INTERCEPTION ============
  @override
  Future<void> setPreventClose(bool value) => _hostApi.setPreventClose(value);

  // ============ MULTI-MONITOR ============
  @override
  Future<List<DisplayRaw>> listDisplays() => _hostApi.listDisplays();
  @override
  Future<DisplayRaw> getCurrentDisplay() => _hostApi.getCurrentDisplay();
  @override
  Future<DisplayRaw> getPrimaryDisplay() => _hostApi.getPrimaryDisplay();

  // ============ FLUTTER API REGISTRATION ============
  @override
  void registerFlutterApi(WindowFlutterApi api) {
    WindowFlutterApi.setUp(api);
  }
}
