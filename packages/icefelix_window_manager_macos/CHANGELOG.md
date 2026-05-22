# Changelog

## [0.1.0] - 2026-05-22 — First stable

Swift + AppKit implementation of `icefelix_window_manager_platform_interface`
for macOS 10.15+.

### Added
- Full Swift + AppKit implementation: 42 `WindowHostApi` methods backed by
  NSWindow APIs (bounds, state, focus, drag/resize, lifecycle, title,
  properties, frameless, visual, multi-monitor, close interception)
- 3 `WindowFlutterApi` callbacks (`onSnapshotChanged`, `onDisplaysChanged`,
  `onCloseRequest`) wired through 9 NSWindow notification observers +
  `NSApplication.didChangeScreenParametersNotification`
- `ForwardingWindowDelegate` preserves Flutter's existing
  `NSWindowDelegate` while intercepting `windowShouldClose:` for the
  `preventClose` flow
- Multi-monitor support: `DisplayRaw` conversion uses `CGDirectDisplayID`
  (stable session ID), `CGDisplayScreenSize` for physical size,
  `CGDisplayCopyDisplayMode` for refresh rate
- 10 ms event coalescing on high-frequency notifications
- Comprehensive example app at `example/` exercising every API
- 9 integration tests on macOS verify end-to-end behavior on real NSWindow

### Fixed (vs. internal dev.3)
- `setMinSize` / `setMaxSize` now use `NSWindow.minSize` / `maxSize`
  (frame coordinates), matching `setSize` and `snapshot.bounds.size`. The
  internal dev builds used `contentMinSize` / `contentMaxSize`, causing a
  ~28px asymmetry on titled styles (e.g. `setMaxSize(1200, 900)` followed
  by `maximize()` returned 1200×928 instead of 1200×900). Internal
  `startManualResize` clamp aligned to the same coord space.

### Known limitations
- See README "Limitations" section
