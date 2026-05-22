// Copyright 2026 icefelix.com. BSD-3-Clause.
//
// Pigeon schema for icefelix_window_manager. Generated bindings:
// - Dart:  lib/src/messages.g.dart (this package)
// - Swift: ../../packages/icefelix_window_manager_macos/macos/Classes/messages.g.swift   (W2)
// - C++:   ../../packages/icefelix_window_manager_windows/windows/messages.g.{h,cpp}     (W3)
// - C++:   ../../packages/icefelix_window_manager_linux/linux/messages.g.{h,cc}          (W4)
//
// For W1, only the Dart output is generated. Native outputs commented out
// (uncommented in their respective weeks).
//
// Naming: all wire-level types use the `Raw` suffix to distinguish from the
// public Dart domain types created in W1 Tasks 4-7 (WindowSnapshot, Display,
// WindowBounds, WindowState, TitleBarStyle, etc.). Pigeon v22 forbids the
// `Pigeon` prefix on classes and enums.

import 'package:pigeon/pigeon.dart';

// ============ DATA TYPES (POD) ============

class OffsetRaw {
  OffsetRaw({required this.dx, required this.dy});
  double dx;
  double dy;
}

class SizeRaw {
  SizeRaw({required this.width, required this.height});
  double width;
  double height;
}

class RectRaw {
  RectRaw({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
  double x;
  double y;
  double width;
  double height;
}

class WindowBoundsRaw {
  WindowBoundsRaw({this.position, required this.size});
  // Nullable: on Wayland, position not exposed by compositor.
  OffsetRaw? position;
  SizeRaw size;
}

class DisplayRaw {
  DisplayRaw({
    required this.id,
    this.name,
    required this.bounds,
    required this.workArea,
    this.physicalWidthMm,
    this.physicalHeightMm,
    this.dpi,
    required this.scaleFactor,
    required this.isPrimary,
    this.refreshRate,
  });
  String id;
  String? name;
  RectRaw bounds;
  RectRaw workArea;
  double? physicalWidthMm;
  double? physicalHeightMm;
  double? dpi;
  double scaleFactor;
  bool isPrimary;
  int? refreshRate;
}

class WindowSnapshotRaw {
  WindowSnapshotRaw({
    required this.bounds,
    required this.state,
    required this.title,
    required this.isFocused,
    required this.alwaysOnTop,
    required this.skipTaskbar,
    required this.resizable,
    required this.movable,
    required this.minimizable,
    required this.maximizable,
    required this.closable,
    required this.frameless,
    required this.titleBarStyle,
    required this.opacity,
    this.backgroundColorArgb,
    required this.hasShadow,
    required this.preventClose,
    required this.currentDisplay,
  });
  WindowBoundsRaw bounds;
  WindowStateRaw state;
  String title;
  bool isFocused;
  bool alwaysOnTop;
  bool skipTaskbar;
  bool resizable;
  bool movable;
  bool minimizable;
  bool maximizable;
  bool closable;
  bool frameless;
  TitleBarStyleRaw titleBarStyle;
  double opacity;
  int? backgroundColorArgb;
  bool hasShadow;
  bool preventClose;
  DisplayRaw currentDisplay;
}

class PlatformInfoRaw {
  PlatformInfoRaw({
    required this.target,
    this.displayServer,
    required this.isSandboxed,
  });
  // "macos" | "windows" | "linux" — Pigeon doesn't support TargetPlatform enum.
  String target;
  DisplayServerRaw? displayServer;
  bool isSandboxed;
}

// ============ ENUMS ============

enum WindowStateRaw { normal, minimized, maximized, fullscreen, hidden }

enum TitleBarStyleRaw { normal, hidden, hiddenInset }

enum ResizeDirectionRaw {
  top,
  bottom,
  left,
  right,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

enum DisplayServerRaw { x11, wayland }

// ============ HOST API (Dart → native) ============

// NOTE: @ConfigurePigeon is file-level configuration despite being attached to
// WindowHostApi. Pigeon v22 requires the annotation on a class declaration. If
// you add a second @HostApi class, DO NOT duplicate this annotation.
@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    swiftOut: '../icefelix_window_manager_macos/macos/Classes/Messages.g.swift',
    swiftOptions: SwiftOptions(),
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
@HostApi()
abstract class WindowHostApi {
  // Initialization
  WindowSnapshotRaw ensureInitialized();
  PlatformInfoRaw getPlatformInfo();

  // Bounds + size + position
  WindowBoundsRaw getBounds();

  /// Set window bounds. Coordinate system depends on [displayId]:
  /// - If [displayId] is null: bounds.position is in GLOBAL virtual desktop coords.
  /// - If [displayId] is provided: bounds.position is RELATIVE to that display's origin.
  ///
  /// NOTE: distinct from moveToDisplay():
  /// - setBounds(bounds, displayId) = "set window to specific bounds, optionally on display X"
  /// - moveToDisplay(displayId) = "move window to display X, preserving current relative position"
  /// Use setBounds when you have specific coordinates; use moveToDisplay when you just want to switch monitors.
  void setBounds(WindowBoundsRaw bounds, String? displayId);

  /// Set the window frame size (titlebar included on platforms that have one).
  /// All size APIs and snapshot.bounds.size share this frame-based coordinate
  /// space. Top-left position is preserved.
  void setSize(SizeRaw size);

  /// Set minimum window frame size, or `null` to clear the constraint.
  /// Coordinate space matches [setSize] — same frame, including titlebar.
  /// Future drag-resize and `setSize` calls clamp against this bound.
  void setMinSize(SizeRaw? size);

  /// Set maximum window frame size, or `null` to clear the constraint.
  /// Coordinate space matches [setSize] — same frame, including titlebar.
  /// `maximize()` (a.k.a. zoom) also respects this bound.
  void setMaxSize(SizeRaw? size);

  void setPosition(OffsetRaw position);
  void center();

  /// Move window to [displayId], **preserving relative position when possible**.
  /// If the preserved position doesn't fit on the new display, centers instead.
  /// Distinct from setBounds(bounds, displayId) — see setBounds for explicit positioning.
  void moveToDisplay(String displayId);

  // State
  void minimize();
  void maximize();
  void unmaximize();
  void restore();
  void hide();
  void show();
  void fullscreen();
  void exitFullscreen();

  // Focus
  void focus();
  void blur();

  // Drag + resize (frameless essentials)
  void startDrag();
  void startResize(ResizeDirectionRaw direction);

  // Lifecycle
  void close();
  void destroy();

  // Title + properties
  void setTitle(String title);
  void setAlwaysOnTop(bool value);
  void setSkipTaskbar(bool value);
  void setResizable(bool value);
  void setMovable(bool value);
  void setMinimizable(bool value);
  void setMaximizable(bool value);
  void setClosable(bool value);

  // Frameless + title bar
  void setFrameless(bool value);
  void setTitleBarStyle(TitleBarStyleRaw style);

  // Visual
  void setOpacity(double opacity);
  void setBackgroundColor(int argb);
  void setHasShadow(bool value);
  void setIcon(String filesystemPath);

  // Close interception
  void setPreventClose(bool value);

  // Multi-monitor
  List<DisplayRaw> listDisplays();
  DisplayRaw getCurrentDisplay();
  DisplayRaw getPrimaryDisplay();
}

// ============ FLUTTER API (native → Dart) ============

@FlutterApi()
abstract class WindowFlutterApi {
  /// Called whenever the window snapshot changes. Single notification for all
  /// state transitions — Dart side derives WindowEvent from snapshot diff.
  void onSnapshotChanged(WindowSnapshotRaw snapshot);

  /// Called when displays are added, removed, or reconfigured.
  void onDisplaysChanged(List<DisplayRaw> displays);

  /// Called when close is requested AND setPreventClose(true) was previously called.
  /// Return value: true = allow close (default), false = block.
  ///
  /// SYNCHRONIZATION CONTRACT FOR NATIVE IMPLEMENTATIONS:
  /// - Native side MUST wait for Dart's response before deciding.
  /// - Default-allow on timeout: if Dart doesn't respond within 5000ms, treat as `true`
  ///   (allow close). Rationale: blocking close indefinitely on a hung Dart isolate
  ///   would prevent user from force-quitting the app.
  /// - Implementations on macOS/Windows/Linux MUST agree on this timeout to keep
  ///   behavior consistent across platforms.
  bool onCloseRequest();
}
