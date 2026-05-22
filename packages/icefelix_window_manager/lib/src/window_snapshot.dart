// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'package:flutter/material.dart';

import 'display.dart';
import 'title_bar_style.dart';
import 'window_state.dart';

/// Window bounding rectangle.
///
/// [position] is **nullable** because on Wayland, the compositor doesn't expose
/// window position to clients. Outside Wayland, position is always non-null.
///
/// Coordinate system depends on the accompanying setter — see
/// `WindowManager.setBounds` for details (global vs display-relative).
@immutable
class WindowBounds {
  const WindowBounds({this.position, required this.size});

  /// Top-left position in logical px. **Null on Wayland.**
  final Offset? position;
  final Size size;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WindowBounds &&
        other.position == position &&
        other.size == size;
  }

  @override
  int get hashCode => Object.hash(position, size);

  @override
  String toString() => 'WindowBounds(position=$position, size=$size)';
}

/// Immutable snapshot of all window state at a point in time.
///
/// Obtained reactively via `WindowManager.snapshot` (a [ValueListenable]).
/// Updates atomically: all fields change together on each platform event.
@immutable
class WindowSnapshot {
  const WindowSnapshot({
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
    this.backgroundColor,
    required this.hasShadow,
    required this.preventClose,
    required this.currentDisplay,
  });

  final WindowBounds bounds;
  final WindowState state;
  final String title;
  final bool isFocused;

  /// Reflects ACTUAL platform state, not the last `WindowManager.setAlwaysOnTop`
  /// call. On Wayland without zwlr_layer_shell, may stay `false` despite setter.
  final bool alwaysOnTop;
  final bool skipTaskbar;
  final bool resizable;
  final bool movable;
  final bool minimizable;
  final bool maximizable;
  final bool closable;
  final bool frameless;
  final TitleBarStyle titleBarStyle;
  final double opacity;

  /// Null until [WindowManager.setBackgroundColor] called at least once;
  /// then reflects the last-set value (not platform default).
  final Color? backgroundColor;

  final bool hasShadow;
  final bool preventClose;
  final Display currentDisplay;

  /// Computed convenience: window is visible to user (not minimized, not hidden).
  bool get isVisible =>
      state != WindowState.minimized && state != WindowState.hidden;

  WindowSnapshot copyWith({
    WindowBounds? bounds,
    WindowState? state,
    String? title,
    bool? isFocused,
    bool? alwaysOnTop,
    bool? skipTaskbar,
    bool? resizable,
    bool? movable,
    bool? minimizable,
    bool? maximizable,
    bool? closable,
    bool? frameless,
    TitleBarStyle? titleBarStyle,
    double? opacity,
    Color? backgroundColor,
    bool? hasShadow,
    bool? preventClose,
    Display? currentDisplay,
  }) {
    return WindowSnapshot(
      bounds: bounds ?? this.bounds,
      state: state ?? this.state,
      title: title ?? this.title,
      isFocused: isFocused ?? this.isFocused,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      skipTaskbar: skipTaskbar ?? this.skipTaskbar,
      resizable: resizable ?? this.resizable,
      movable: movable ?? this.movable,
      minimizable: minimizable ?? this.minimizable,
      maximizable: maximizable ?? this.maximizable,
      closable: closable ?? this.closable,
      frameless: frameless ?? this.frameless,
      titleBarStyle: titleBarStyle ?? this.titleBarStyle,
      opacity: opacity ?? this.opacity,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      hasShadow: hasShadow ?? this.hasShadow,
      preventClose: preventClose ?? this.preventClose,
      currentDisplay: currentDisplay ?? this.currentDisplay,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WindowSnapshot &&
        other.bounds == bounds &&
        other.state == state &&
        other.title == title &&
        other.isFocused == isFocused &&
        other.alwaysOnTop == alwaysOnTop &&
        other.skipTaskbar == skipTaskbar &&
        other.resizable == resizable &&
        other.movable == movable &&
        other.minimizable == minimizable &&
        other.maximizable == maximizable &&
        other.closable == closable &&
        other.frameless == frameless &&
        other.titleBarStyle == titleBarStyle &&
        other.opacity == opacity &&
        other.backgroundColor == backgroundColor &&
        other.hasShadow == hasShadow &&
        other.preventClose == preventClose &&
        other.currentDisplay == currentDisplay;
  }

  @override
  int get hashCode => Object.hashAll([
        bounds,
        state,
        title,
        isFocused,
        alwaysOnTop,
        skipTaskbar,
        resizable,
        movable,
        minimizable,
        maximizable,
        closable,
        frameless,
        titleBarStyle,
        opacity,
        backgroundColor,
        hasShadow,
        preventClose,
        currentDisplay,
      ]);
}
