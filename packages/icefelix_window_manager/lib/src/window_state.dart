// Copyright 2026 icefelix.com. BSD-3-Clause.

/// Window display state.
enum WindowState {
  /// Normal windowed state — visible, not minimized/maximized/fullscreen.
  normal,

  /// Minimized to taskbar/dock.
  minimized,

  /// Maximized (fills work area, taskbar/dock still visible).
  maximized,

  /// Fullscreen (covers entire screen, including taskbar/dock).
  fullscreen,

  /// Hidden — not visible, NOT in taskbar/dock (cf. [minimized]).
  hidden,
}
