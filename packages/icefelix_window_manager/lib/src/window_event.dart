// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'package:flutter/material.dart';

import 'display.dart';
import 'window_state.dart';

/// Base class for all window lifecycle / state events.
///
/// Use exhaustive `switch` for pattern matching (Dart 3 sealed semantics):
///
/// ```dart
/// switch (event) {
///   case WindowResizeEvent(:final newSize): ...
///   case WindowMoveEvent(:final newPosition): ...
///   // ... all subclasses handled or default
/// }
/// ```
sealed class WindowEvent {
  const WindowEvent();
}

@immutable
class WindowResizeEvent extends WindowEvent {
  const WindowResizeEvent({required this.oldSize, required this.newSize});
  final Size oldSize;
  final Size newSize;
}

@immutable
class WindowMoveEvent extends WindowEvent {
  const WindowMoveEvent({this.oldPosition, this.newPosition});
  // Nullable on Wayland.
  final Offset? oldPosition;
  final Offset? newPosition;
}

@immutable
class WindowFocusEvent extends WindowEvent {
  const WindowFocusEvent({required this.focused});
  final bool focused;
}

@immutable
class WindowStateChangeEvent extends WindowEvent {
  const WindowStateChangeEvent({
    required this.oldState,
    required this.newState,
  });
  final WindowState oldState;
  final WindowState newState;
}

@immutable
class WindowDisplayChangeEvent extends WindowEvent {
  const WindowDisplayChangeEvent({
    required this.oldDisplay,
    required this.newDisplay,
  });
  final Display oldDisplay;
  final Display newDisplay;
}

/// Fired when close is requested AND `setPreventClose(true)` was called.
///
/// Consumer **MUST** call [preventDefault] SYNCHRONOUSLY within the event
/// handler to block close. Calling after handler returns has no effect — by
/// then native side has already committed the close decision.
///
/// For async confirmation (e.g. "Save changes?" dialog):
/// 1. Call [preventDefault] synchronously to block immediate close
/// 2. Show your async dialog
/// 3. If user confirms close, call `WindowManager.destroy()` (bypasses interception)
class WindowCloseRequestEvent extends WindowEvent {
  WindowCloseRequestEvent({required VoidCallback onPreventDefault})
      : _onPreventDefault = onPreventDefault;

  final VoidCallback _onPreventDefault;
  bool _preventedDefault = false;

  /// Block the default close action. **Idempotent** — calling twice has no effect.
  void preventDefault() {
    if (_preventedDefault) return;
    _preventedDefault = true;
    _onPreventDefault();
  }

  @visibleForTesting
  bool get wasPreventDefaultCalled => _preventedDefault;
}

// =========================================================================

/// Base class for display configuration events (hot-plug, resolution change).
sealed class DisplayEvent {
  const DisplayEvent();
}

@immutable
class DisplayAddedEvent extends DisplayEvent {
  const DisplayAddedEvent({required this.display});
  final Display display;
}

@immutable
class DisplayRemovedEvent extends DisplayEvent {
  const DisplayRemovedEvent({required this.id});
  final DisplayId id;
}

@immutable
class DisplayChangedEvent extends DisplayEvent {
  const DisplayChangedEvent({
    required this.oldConfig,
    required this.newConfig,
  });
  final Display oldConfig;
  final Display newConfig;
}
