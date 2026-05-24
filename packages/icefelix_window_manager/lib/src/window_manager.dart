// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:icefelix_window_manager_platform_interface/icefelix_window_manager_platform_interface.dart';

import 'display.dart';
import 'resize_direction.dart';
import 'title_bar_style.dart';
import 'window_displays.dart';
import 'window_event.dart';
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
  // sync:true so listeners run synchronously during _events.add(). Required
  // by the preventClose flow: the Pigeon-generated WindowFlutterApi.onCloseRequest
  // returns bool synchronously (no await), so the adapter has to read
  // _closeRequestBlocked BEFORE returning. Default async delivery would queue
  // the listener as a microtask and the adapter would always return allow,
  // making event.preventDefault() a no-op on the close path. Sync delivery is
  // also fine for snapshot/display events — typical listeners are sync.
  final StreamController<WindowEvent> _events =
      StreamController<WindowEvent>.broadcast(sync: true);
  late final WindowDisplays _displays = createWindowDisplays();
  bool _closeRequestBlocked = false;

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

  /// Multi-monitor sub-namespace.
  WindowDisplays get displays => _displays;

  /// All window-related events. **Broadcast stream** — multiple listeners OK.
  /// Listeners should cancel subscriptions in widget `dispose()` to avoid leaks.
  Stream<WindowEvent> get events => _events.stream;

  // =========================================================================
  // BOUNDS + SIZE + POSITION
  // =========================================================================

  /// Set window bounds. Coordinate system depends on [display]:
  /// - If [display] is null: [bounds.position] is in **global** virtual desktop coords.
  /// - If [display] is provided: [bounds.position] is **relative** to that display's origin.
  /// - If [bounds.position] is null: only size applied (position unchanged).
  ///
  /// On Wayland: position is always ignored; size applied.
  Future<void> setBounds(WindowBounds bounds, {DisplayId? display}) {
    return WindowManagerPlatform.instance.setBounds(
      WindowBoundsRaw(
        position: bounds.position == null
            ? null
            : OffsetRaw(dx: bounds.position!.dx, dy: bounds.position!.dy),
        size: SizeRaw(width: bounds.size.width, height: bounds.size.height),
      ),
      display?.value,
    );
  }

  /// Set the window frame size (includes the titlebar on styles that have
  /// one). [setSize], [setMinSize], [setMaxSize] and `snapshot.bounds.size`
  /// all share this frame-based coordinate space. Top-left is preserved.
  Future<void> setSize(Size size) {
    return WindowManagerPlatform.instance.setSize(
      SizeRaw(width: size.width, height: size.height),
    );
  }

  /// Set minimum window frame size. Pass `null` to clear the constraint.
  /// Same coordinate space as [setSize] (frame, titlebar included). Future
  /// drag-resize and `setSize` calls clamp against this bound.
  Future<void> setMinSize(Size? size) {
    return WindowManagerPlatform.instance.setMinSize(
      size == null ? null : SizeRaw(width: size.width, height: size.height),
    );
  }

  /// Set maximum window frame size. Pass `null` to clear the constraint.
  /// Same coordinate space as [setSize] (frame, titlebar included).
  /// `maximize()` (zoom on macOS) also respects this bound.
  Future<void> setMaxSize(Size? size) {
    return WindowManagerPlatform.instance.setMaxSize(
      size == null ? null : SizeRaw(width: size.width, height: size.height),
    );
  }

  /// Set window position in global virtual desktop coords. No-op on Wayland.
  Future<void> setPosition(Offset position) {
    return WindowManagerPlatform.instance.setPosition(
      OffsetRaw(dx: position.dx, dy: position.dy),
    );
  }

  Future<void> center() => WindowManagerPlatform.instance.center();

  /// Move window to [display], **preserving relative position when possible**.
  Future<void> moveToDisplay(DisplayId display) {
    return WindowManagerPlatform.instance.moveToDisplay(display.value);
  }

  // =========================================================================
  // STATE
  // =========================================================================

  Future<void> minimize() => WindowManagerPlatform.instance.minimize();
  Future<void> maximize() => WindowManagerPlatform.instance.maximize();
  Future<void> unmaximize() => WindowManagerPlatform.instance.unmaximize();
  Future<void> restore() => WindowManagerPlatform.instance.restore();
  Future<void> hide() => WindowManagerPlatform.instance.hide();
  Future<void> show() => WindowManagerPlatform.instance.show();
  Future<void> fullscreen() => WindowManagerPlatform.instance.fullscreen();
  Future<void> exitFullscreen() =>
      WindowManagerPlatform.instance.exitFullscreen();

  // =========================================================================
  // FOCUS
  // =========================================================================

  Future<void> focus() => WindowManagerPlatform.instance.focus();
  Future<void> blur() => WindowManagerPlatform.instance.blur();

  // =========================================================================
  // DRAG + RESIZE (frameless essentials)
  // =========================================================================

  /// Begin native window drag. Call from a pointer-down handler on a draggable
  /// region widget (e.g. custom title bar). Essential for frameless windows.
  Future<void> startDrag() => WindowManagerPlatform.instance.startDrag();

  /// Begin native window resize in [direction]. Call from a pointer-down handler
  /// on a resize handle widget. Essential for frameless windows.
  Future<void> startResize(ResizeDirection direction) {
    final raw = switch (direction) {
      ResizeDirection.top => ResizeDirectionRaw.top,
      ResizeDirection.bottom => ResizeDirectionRaw.bottom,
      ResizeDirection.left => ResizeDirectionRaw.left,
      ResizeDirection.right => ResizeDirectionRaw.right,
      ResizeDirection.topLeft => ResizeDirectionRaw.topLeft,
      ResizeDirection.topRight => ResizeDirectionRaw.topRight,
      ResizeDirection.bottomLeft => ResizeDirectionRaw.bottomLeft,
      ResizeDirection.bottomRight => ResizeDirectionRaw.bottomRight,
    };
    return WindowManagerPlatform.instance.startResize(raw);
  }

  // =========================================================================
  // LIFECYCLE
  // =========================================================================

  /// Request window close. Triggers same flow as user clicking the X button:
  /// fires WindowCloseRequestEvent if setPreventClose was called with true,
  /// otherwise closes immediately.
  Future<void> close() => WindowManagerPlatform.instance.close();

  /// Force-close window WITHOUT firing close-request event.
  /// Bypasses any [setPreventClose] interception.
  Future<void> destroy() => WindowManagerPlatform.instance.destroy();

  // =========================================================================
  // TITLE + PROPERTIES
  // =========================================================================

  Future<void> setTitle(String title) =>
      WindowManagerPlatform.instance.setTitle(title);
  Future<void> setAlwaysOnTop(bool value) =>
      WindowManagerPlatform.instance.setAlwaysOnTop(value);
  Future<void> setSkipTaskbar(bool value) =>
      WindowManagerPlatform.instance.setSkipTaskbar(value);
  Future<void> setResizable(bool value) =>
      WindowManagerPlatform.instance.setResizable(value);
  Future<void> setMovable(bool value) =>
      WindowManagerPlatform.instance.setMovable(value);
  Future<void> setMinimizable(bool value) =>
      WindowManagerPlatform.instance.setMinimizable(value);
  Future<void> setMaximizable(bool value) =>
      WindowManagerPlatform.instance.setMaximizable(value);
  Future<void> setClosable(bool value) =>
      WindowManagerPlatform.instance.setClosable(value);

  // =========================================================================
  // FRAMELESS + TITLE BAR
  // =========================================================================

  Future<void> setFrameless(bool value) =>
      WindowManagerPlatform.instance.setFrameless(value);

  Future<void> setTitleBarStyle(TitleBarStyle style) {
    final raw = switch (style) {
      TitleBarStyle.normal => TitleBarStyleRaw.normal,
      TitleBarStyle.hidden => TitleBarStyleRaw.hidden,
      TitleBarStyle.hiddenInset => TitleBarStyleRaw.hiddenInset,
    };
    return WindowManagerPlatform.instance.setTitleBarStyle(raw);
  }

  // =========================================================================
  // VISUAL
  // =========================================================================

  /// Opacity 0.0 (transparent) to 1.0 (opaque). No-op on Wayland.
  Future<void> setOpacity(double opacity) =>
      WindowManagerPlatform.instance.setOpacity(opacity);

  Future<void> setBackgroundColor(Color color) =>
      WindowManagerPlatform.instance.setBackgroundColor(color.toARGB32());

  Future<void> setHasShadow(bool value) =>
      WindowManagerPlatform.instance.setHasShadow(value);

  /// Native icon file. Use platform-appropriate format: .ico (Windows), .icns
  /// (macOS), .png (Linux). Path must be **absolute filesystem path**; Flutter
  /// asset URIs not supported in v0.1.0.
  Future<void> setIcon(String filesystemPath) =>
      WindowManagerPlatform.instance.setIcon(filesystemPath);

  // =========================================================================
  // CLOSE INTERCEPTION
  // =========================================================================

  /// When true, close attempts fire WindowCloseRequestEvent on events stream
  /// (added in Task 8) INSTEAD of closing immediately. Consumer must call
  /// `preventDefault()` synchronously in handler to block; otherwise close proceeds.
  Future<void> setPreventClose(bool value) =>
      WindowManagerPlatform.instance.setPreventClose(value);

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

    // Register Flutter API callback adapter BEFORE asking platform to initialize
    // so events fired during init are not lost.
    WindowManagerPlatform.instance.registerFlutterApi(_FlutterApiAdapter(this));

    final pigeonSnap = await WindowManagerPlatform.instance.ensureInitialized();
    final pigeonInfo = await WindowManagerPlatform.instance.getPlatformInfo();

    _platform = _convertPlatformInfo(pigeonInfo);
    final snapshot = _convertSnapshot(pigeonSnap);
    _snapshot._set(snapshot);

    // Fix C2: seed WindowDisplays._lastKnown with the initial display so the
    // first onDisplaysChanged emission doesn't fire a phantom DisplayAddedEvent
    // for the already-known display.
    _displays.seedLastKnown([snapshot.currentDisplay]);

    _initialized = true;
  }

  /// **Testing only.** Resets singleton state between tests.
  @visibleForTesting
  static void resetForTesting() {
    _instance._snapshot.dispose();
    _instance._events.close();
    _instance._displays.dispose();
    _instance = WindowManager._();
  }

  // =========================================================================
  // INTERNAL — FlutterApi callbacks (called by platform impl in W2-W4)
  // =========================================================================

  /// Called by platform when snapshot changes. Computes diff vs previous
  /// snapshot and emits corresponding WindowEvent(s) on [events] stream.
  void onSnapshotChanged(WindowSnapshotRaw pigeon) {
    final newSnap = _convertSnapshot(pigeon);
    final oldSnap = _snapshot._value;
    _snapshot._set(newSnap);
    if (oldSnap == null) return; // first emit, no diff

    if (oldSnap.bounds.size != newSnap.bounds.size) {
      _events.add(
        WindowResizeEvent(
          oldSize: oldSnap.bounds.size,
          newSize: newSnap.bounds.size,
        ),
      );
    }
    if (oldSnap.bounds.position != newSnap.bounds.position) {
      _events.add(
        WindowMoveEvent(
          oldPosition: oldSnap.bounds.position,
          newPosition: newSnap.bounds.position,
        ),
      );
    }
    if (oldSnap.isFocused != newSnap.isFocused) {
      _events.add(WindowFocusEvent(focused: newSnap.isFocused));
    }
    if (oldSnap.state != newSnap.state) {
      _events.add(
        WindowStateChangeEvent(
          oldState: oldSnap.state,
          newState: newSnap.state,
        ),
      );
    }
    if (oldSnap.currentDisplay != newSnap.currentDisplay) {
      _events.add(
        WindowDisplayChangeEvent(
          oldDisplay: oldSnap.currentDisplay,
          newDisplay: newSnap.currentDisplay,
        ),
      );
    }
  }

  /// Called by platform when displays change (hot-plug).
  void onDisplaysChanged(List<DisplayRaw> displays) {
    _displays.handleDisplaysChanged(displays);
  }

  /// Called by platform when close is requested AND preventClose=true.
  /// Returns true to allow close, false to block.
  /// Fires WindowCloseRequestEvent synchronously; if consumer calls
  /// preventDefault, returns false.
  Future<bool> onCloseRequest() async {
    _closeRequestBlocked = false;
    final event = WindowCloseRequestEvent(
      onPreventDefault: () {
        _closeRequestBlocked = true;
      },
    );
    _events.add(event);
    // Yield one microtask cycle so synchronous handlers run.
    await Future<void>.delayed(Duration.zero);
    return !_closeRequestBlocked;
  }

  // =========================================================================
  // TESTING HELPERS
  // =========================================================================

  @visibleForTesting
  void debugSimulateSnapshotChange(WindowSnapshotRaw snap) =>
      onSnapshotChanged(snap);

  @visibleForTesting
  Future<bool> debugSimulateCloseRequest() => onCloseRequest();

  @visibleForTesting
  void debugSimulateDisplaysChanged(List<DisplayRaw> displays) =>
      onDisplaysChanged(displays);
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

/// Internal adapter that implements [WindowFlutterApi] and forwards to
/// [WindowManager] callbacks. Registered with the platform during
/// [WindowManager.ensureInitialized] so native impls can send events back.
class _FlutterApiAdapter implements WindowFlutterApi {
  _FlutterApiAdapter(this._manager);

  final WindowManager _manager;

  @override
  void onSnapshotChanged(WindowSnapshotRaw snapshot) =>
      _manager.onSnapshotChanged(snapshot);

  @override
  void onDisplaysChanged(List<DisplayRaw> displays) =>
      _manager.onDisplaysChanged(displays);

  /// Pigeon-generated [WindowFlutterApi.onCloseRequest] is synchronous (returns
  /// `bool`). [WindowManager.onCloseRequest] is `Future<bool>` because it
  /// yields a microtask for async listeners. We bridge by reading
  /// `_closeRequestBlocked` immediately after `_events.add(event)` — that
  /// only works because the events stream uses `sync: true`, so any
  /// synchronous `preventDefault()` in a listener runs inline before
  /// `_events.add` returns. The async pieces (e.g. a follow-up dialog) keep
  /// running after we return; they just can't change the close decision.
  @override
  bool onCloseRequest() {
    // Fire & forget the async flow — the synchronous parts (event dispatch +
    // sync preventDefault) complete inline before this returns.
    final pending = _manager.onCloseRequest();
    // Track but don't await — Future is consumed downstream; outcome surfaces
    // through subsequent calls. For sync determination, mirror the manager's
    // semantics: not-blocked → allow.
    pending.ignore();
    return !_manager._closeRequestBlocked;
  }
}
