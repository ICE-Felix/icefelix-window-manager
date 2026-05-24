// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'messages.g.dart';

/// Abstract base class that platform implementations extend.
///
/// Each platform package (macOS, Windows, Linux) provides a concrete subclass
/// that wires Pigeon-generated [WindowHostApi] calls to native code.
///
/// The default implementation throws [UnimplementedError] on every method,
/// ensuring missing platform implementations fail loudly rather than silently
/// no-op.
abstract class WindowManagerPlatform extends PlatformInterface {
  WindowManagerPlatform() : super(token: _token);

  static final Object _token = Object();
  static WindowManagerPlatform _instance = _DefaultPlatform();

  /// The current platform implementation. Default is a stub that throws on
  /// every method; platform packages override this via their `registerWith`.
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

  // ============ FLUTTER API REGISTRATION ============
  /// Subclasses set up [WindowFlutterApi] to receive native callbacks.
  /// The default does nothing — subclasses must override to wire events.
  void registerFlutterApi(WindowFlutterApi api) {}
}

class _DefaultPlatform extends WindowManagerPlatform {
  _DefaultPlatform() : super();
}
