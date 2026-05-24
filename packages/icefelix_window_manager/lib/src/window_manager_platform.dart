// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'messages.g.dart';

/// Abstract base class for the native bridge. The default implementation
/// (`_NativeBridge`) delegates every method to the Pigeon-generated
/// [WindowHostApi], which Flutter wires to the Swift / C++ plugin at app
/// startup via the platform `pluginClass` declarations in `pubspec.yaml`.
///
/// Tests override this via `WindowManagerPlatform.instance = MyMock();`
/// (using `MockPlatformInterfaceMixin` to bypass the token check).
abstract class WindowManagerPlatform extends PlatformInterface {
  WindowManagerPlatform() : super(token: _token);

  static final Object _token = Object();
  static WindowManagerPlatform _instance = _NativeBridge();

  /// The current platform implementation. Defaults to `_NativeBridge`, which
  /// routes through Pigeon channels to the auto-loaded native plugin. Tests
  /// override this.
  static WindowManagerPlatform get instance => _instance;
  static set instance(WindowManagerPlatform impl) {
    PlatformInterface.verifyToken(impl, _token);
    _instance = impl;
  }

  // ============ INITIALIZATION ============
  Future<WindowSnapshotRaw> ensureInitialized() =>
      throw UnimplementedError('ensureInitialized() not implemented');
  Future<PlatformInfoRaw> getPlatformInfo() =>
      throw UnimplementedError('getPlatformInfo() not implemented');

  // ============ BOUNDS ============
  Future<WindowBoundsRaw> getBounds() =>
      throw UnimplementedError('getBounds() not implemented');
  Future<void> setBounds(WindowBoundsRaw bounds, String? displayId) =>
      throw UnimplementedError('setBounds() not implemented');
  Future<void> setSize(SizeRaw size) =>
      throw UnimplementedError('setSize() not implemented');
  Future<void> setMinSize(SizeRaw? size) =>
      throw UnimplementedError('setMinSize() not implemented');
  Future<void> setMaxSize(SizeRaw? size) =>
      throw UnimplementedError('setMaxSize() not implemented');
  Future<void> setPosition(OffsetRaw position) =>
      throw UnimplementedError('setPosition() not implemented');
  Future<void> center() => throw UnimplementedError('center() not implemented');
  Future<void> moveToDisplay(String displayId) =>
      throw UnimplementedError('moveToDisplay() not implemented');

  // ============ STATE ============
  Future<void> minimize() => throw UnimplementedError();
  Future<void> maximize() => throw UnimplementedError();
  Future<void> unmaximize() => throw UnimplementedError();
  Future<void> restore() => throw UnimplementedError();
  Future<void> hide() => throw UnimplementedError();
  Future<void> show() => throw UnimplementedError();
  Future<void> fullscreen() => throw UnimplementedError();
  Future<void> exitFullscreen() => throw UnimplementedError();

  // ============ FOCUS ============
  Future<void> focus() => throw UnimplementedError();
  Future<void> blur() => throw UnimplementedError();

  // ============ DRAG + RESIZE ============
  Future<void> startDrag() => throw UnimplementedError();
  Future<void> startResize(ResizeDirectionRaw direction) =>
      throw UnimplementedError();

  // ============ LIFECYCLE ============
  Future<void> close() => throw UnimplementedError();
  Future<void> destroy() => throw UnimplementedError();

  // ============ TITLE + PROPERTIES ============
  Future<void> setTitle(String title) => throw UnimplementedError();
  Future<void> setAlwaysOnTop(bool value) => throw UnimplementedError();
  Future<void> setSkipTaskbar(bool value) => throw UnimplementedError();
  Future<void> setResizable(bool value) => throw UnimplementedError();
  Future<void> setMovable(bool value) => throw UnimplementedError();
  Future<void> setMinimizable(bool value) => throw UnimplementedError();
  Future<void> setMaximizable(bool value) => throw UnimplementedError();
  Future<void> setClosable(bool value) => throw UnimplementedError();

  // ============ FRAMELESS + TITLE BAR ============
  Future<void> setFrameless(bool value) => throw UnimplementedError();
  Future<void> setTitleBarStyle(TitleBarStyleRaw style) =>
      throw UnimplementedError();

  // ============ VISUAL ============
  Future<void> setOpacity(double opacity) => throw UnimplementedError();
  Future<void> setBackgroundColor(int argb) => throw UnimplementedError();
  Future<void> setHasShadow(bool value) => throw UnimplementedError();
  Future<void> setIcon(String filesystemPath) => throw UnimplementedError();
  Future<void> setShape(List<OffsetRaw>? points) => throw UnimplementedError();

  // ============ CLOSE INTERCEPTION ============
  Future<void> setPreventClose(bool value) => throw UnimplementedError();

  // ============ MULTI-MONITOR ============
  Future<List<DisplayRaw>> listDisplays() => throw UnimplementedError();
  Future<DisplayRaw> getCurrentDisplay() => throw UnimplementedError();
  Future<DisplayRaw> getPrimaryDisplay() => throw UnimplementedError();

  // ============ FLUTTER API REGISTRATION (native → Dart) ============
  void registerFlutterApi(WindowFlutterApi api) {
    throw UnimplementedError('registerFlutterApi() not implemented');
  }
}

/// Default in-process bridge. Delegates every call to the Pigeon-generated
/// `WindowHostApi`, which routes to the native plugin auto-loaded by Flutter
/// based on `pubspec.yaml` `flutter.plugin.platforms.<os>.pluginClass`.
class _NativeBridge extends WindowManagerPlatform {
  _NativeBridge() : super();
  final WindowHostApi _api = WindowHostApi();

  @override
  Future<WindowSnapshotRaw> ensureInitialized() => _api.ensureInitialized();
  @override
  Future<PlatformInfoRaw> getPlatformInfo() => _api.getPlatformInfo();
  @override
  Future<WindowBoundsRaw> getBounds() => _api.getBounds();
  @override
  Future<void> setBounds(WindowBoundsRaw bounds, String? displayId) =>
      _api.setBounds(bounds, displayId);
  @override
  Future<void> setSize(SizeRaw size) => _api.setSize(size);
  @override
  Future<void> setMinSize(SizeRaw? size) => _api.setMinSize(size);
  @override
  Future<void> setMaxSize(SizeRaw? size) => _api.setMaxSize(size);
  @override
  Future<void> setPosition(OffsetRaw position) => _api.setPosition(position);
  @override
  Future<void> center() => _api.center();
  @override
  Future<void> moveToDisplay(String displayId) =>
      _api.moveToDisplay(displayId);

  @override
  Future<void> minimize() => _api.minimize();
  @override
  Future<void> maximize() => _api.maximize();
  @override
  Future<void> unmaximize() => _api.unmaximize();
  @override
  Future<void> restore() => _api.restore();
  @override
  Future<void> hide() => _api.hide();
  @override
  Future<void> show() => _api.show();
  @override
  Future<void> fullscreen() => _api.fullscreen();
  @override
  Future<void> exitFullscreen() => _api.exitFullscreen();

  @override
  Future<void> focus() => _api.focus();
  @override
  Future<void> blur() => _api.blur();

  @override
  Future<void> startDrag() => _api.startDrag();
  @override
  Future<void> startResize(ResizeDirectionRaw direction) =>
      _api.startResize(direction);

  @override
  Future<void> close() => _api.close();
  @override
  Future<void> destroy() => _api.destroy();

  @override
  Future<void> setTitle(String title) => _api.setTitle(title);
  @override
  Future<void> setAlwaysOnTop(bool value) => _api.setAlwaysOnTop(value);
  @override
  Future<void> setSkipTaskbar(bool value) => _api.setSkipTaskbar(value);
  @override
  Future<void> setResizable(bool value) => _api.setResizable(value);
  @override
  Future<void> setMovable(bool value) => _api.setMovable(value);
  @override
  Future<void> setMinimizable(bool value) => _api.setMinimizable(value);
  @override
  Future<void> setMaximizable(bool value) => _api.setMaximizable(value);
  @override
  Future<void> setClosable(bool value) => _api.setClosable(value);

  @override
  Future<void> setFrameless(bool value) => _api.setFrameless(value);
  @override
  Future<void> setTitleBarStyle(TitleBarStyleRaw style) =>
      _api.setTitleBarStyle(style);

  @override
  Future<void> setOpacity(double opacity) => _api.setOpacity(opacity);
  @override
  Future<void> setBackgroundColor(int argb) => _api.setBackgroundColor(argb);
  @override
  Future<void> setHasShadow(bool value) => _api.setHasShadow(value);
  @override
  Future<void> setIcon(String filesystemPath) => _api.setIcon(filesystemPath);
  @override
  Future<void> setShape(List<OffsetRaw>? points) => _api.setShape(points);

  @override
  Future<void> setPreventClose(bool value) => _api.setPreventClose(value);

  @override
  Future<List<DisplayRaw>> listDisplays() => _api.listDisplays();
  @override
  Future<DisplayRaw> getCurrentDisplay() => _api.getCurrentDisplay();
  @override
  Future<DisplayRaw> getPrimaryDisplay() => _api.getPrimaryDisplay();

  @override
  void registerFlutterApi(WindowFlutterApi api) {
    WindowFlutterApi.setUp(api);
  }
}
