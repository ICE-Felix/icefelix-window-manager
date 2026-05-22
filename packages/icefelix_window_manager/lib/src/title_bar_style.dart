// Copyright 2026 icefelix.com. BSD-3-Clause.

/// Visual style of the window's title bar.
enum TitleBarStyle {
  /// Standard platform title bar with title text, close/minimize/maximize buttons.
  normal,

  /// Title bar hidden entirely; window has no top decoration.
  /// On macOS: traffic lights still visible but title invisible.
  hidden,

  /// macOS-specific: title bar collapsed flush with content area;
  /// traffic lights overlay the content. On non-macOS: treated as [hidden].
  hiddenInset,
}
