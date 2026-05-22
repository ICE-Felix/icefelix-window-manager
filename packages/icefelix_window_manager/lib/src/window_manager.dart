// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:icefelix_window_manager_platform_interface/icefelix_window_manager_platform_interface.dart';

import 'display.dart';
import 'title_bar_style.dart';
import 'window_platform.dart';
import 'window_snapshot.dart';
import 'window_state.dart';

/// Entry point for window management.
///
/// Initialize before `runApp`:
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await WindowManager.instance.ensureInitialized();
///   runApp(const MyApp());
/// }
/// ```
class WindowManager {
  WindowManager._();

  static WindowManager _instance = WindowManager._();
  static WindowManager get instance => _instance;

  // ============ INTERNAL STATE ============
  final _SnapshotValueNotifier _snapshot = _SnapshotValueNotifier();
  WindowPlatform? _platform;
  bool _initialized = false;

  /// Reactive snapshot of all window state.
  ///
  /// Accessing `snapshot.value` before [ensureInitialized] completes throws
  /// [StateError].
  ValueListenable<WindowSnapshot> get snapshot => _snapshot;

  /// Runtime platform info (display server, sandboxing, target OS).
  ///
  /// Throws [StateError] if accessed before [ensureInitialized] completes.
  WindowPlatform get platform {
    final p = _platform;
    if (p == null) {
      throw StateError(
        'WindowManager.platform accessed before ensureInitialized(). '
        'Call `await WindowManager.instance.ensureInitialized()` first.',
      );
    }
    return p;
  }

  /// Initializes platform-side hooks + populates the initial snapshot.
  ///
  /// Must be called BEFORE `runApp` and before any other API call.
  ///
  /// Throws [UnsupportedError] if called on Android, iOS, Web, or Fuchsia.
  /// Throws [StateError] if called twice.
  Future<void> ensureInitialized() async {
    if (_initialized) {
      throw StateError('WindowManager.ensureInitialized() called twice.');
    }

    final pigeonSnap = await WindowManagerPlatform.instance.ensureInitialized();
    final pigeonInfo = await WindowManagerPlatform.instance.getPlatformInfo();

    _platform = _convertPlatformInfo(pigeonInfo);
    _snapshot._set(_convertSnapshot(pigeonSnap));
    _initialized = true;
  }

  /// **Testing only.** Resets singleton state between tests.
  @visibleForTesting
  static void resetForTesting() {
    _instance._snapshot.dispose();
    _instance = WindowManager._();
  }
}

// =========================================================================
// CONVERTERS (Pigeon POD → Dart rich types)
// =========================================================================

WindowPlatform _convertPlatformInfo(PlatformInfoRaw info) {
  final target = switch (info.target) {
    'macos' => TargetPlatform.macOS,
    'windows' => TargetPlatform.windows,
    'linux' => TargetPlatform.linux,
    _ => throw UnsupportedError(
        'icefelix_window_manager does not support platform: ${info.target}. '
        'Supported: macos, windows, linux.',
      ),
  };
  final ds = switch (info.displayServer) {
    DisplayServerRaw.x11 => DisplayServer.x11,
    DisplayServerRaw.wayland => DisplayServer.wayland,
    null => null,
  };
  return WindowPlatform(
    target: target,
    displayServer: ds,
    isSandboxed: info.isSandboxed,
  );
}

WindowSnapshot _convertSnapshot(WindowSnapshotRaw p) {
  return WindowSnapshot(
    bounds: WindowBounds(
      position: p.bounds.position == null
          ? null
          : Offset(p.bounds.position!.dx, p.bounds.position!.dy),
      size: Size(p.bounds.size.width, p.bounds.size.height),
    ),
    state: switch (p.state) {
      WindowStateRaw.normal => WindowState.normal,
      WindowStateRaw.minimized => WindowState.minimized,
      WindowStateRaw.maximized => WindowState.maximized,
      WindowStateRaw.fullscreen => WindowState.fullscreen,
      WindowStateRaw.hidden => WindowState.hidden,
    },
    title: p.title,
    isFocused: p.isFocused,
    alwaysOnTop: p.alwaysOnTop,
    skipTaskbar: p.skipTaskbar,
    resizable: p.resizable,
    movable: p.movable,
    minimizable: p.minimizable,
    maximizable: p.maximizable,
    closable: p.closable,
    frameless: p.frameless,
    titleBarStyle: switch (p.titleBarStyle) {
      TitleBarStyleRaw.normal => TitleBarStyle.normal,
      TitleBarStyleRaw.hidden => TitleBarStyle.hidden,
      TitleBarStyleRaw.hiddenInset => TitleBarStyle.hiddenInset,
    },
    opacity: p.opacity,
    backgroundColor:
        p.backgroundColorArgb == null ? null : Color(p.backgroundColorArgb!),
    hasShadow: p.hasShadow,
    preventClose: p.preventClose,
    currentDisplay: _convertDisplay(p.currentDisplay),
  );
}

Display _convertDisplay(DisplayRaw p) {
  return Display(
    id: DisplayId(p.id),
    name: p.name,
    bounds: Rect.fromLTWH(
      p.bounds.x,
      p.bounds.y,
      p.bounds.width,
      p.bounds.height,
    ),
    workArea: Rect.fromLTWH(
      p.workArea.x,
      p.workArea.y,
      p.workArea.width,
      p.workArea.height,
    ),
    physicalSize: (p.physicalWidthMm != null && p.physicalHeightMm != null)
        ? Size(p.physicalWidthMm!, p.physicalHeightMm!)
        : null,
    dpi: p.dpi,
    scaleFactor: p.scaleFactor,
    isPrimary: p.isPrimary,
    refreshRate: p.refreshRate,
  );
}

// =========================================================================
// SNAPSHOT NOTIFIER (private)
// =========================================================================

/// ValueNotifier that throws StateError on access before first set.
class _SnapshotValueNotifier extends ChangeNotifier
    implements ValueListenable<WindowSnapshot> {
  WindowSnapshot? _value;

  @override
  WindowSnapshot get value {
    final v = _value;
    if (v == null) {
      throw StateError(
        'WindowManager.snapshot.value accessed before ensureInitialized(). '
        'Call `await WindowManager.instance.ensureInitialized()` first.',
      );
    }
    return v;
  }

  void _set(WindowSnapshot snap) {
    _value = snap;
    notifyListeners();
  }
}
