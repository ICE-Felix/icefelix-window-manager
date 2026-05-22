# Changelog

## [0.1.0-dev.3] - 2026-05-22

### Added (W2 — macOS native impl)
- `icefelix_window_manager_macos` package — Swift + AppKit implementation
  for macOS 10.15+
- All WindowHostApi methods backed by NSWindow APIs (bounds, state, focus,
  drag/resize, lifecycle, title/props, frameless, visual, multi-monitor,
  close interception)
- ForwardingWindowDelegate preserves Flutter's NSWindowDelegate while
  intercepting windowShouldClose: for preventClose flow
- 9 NSWindow notification observers + NSApplication.didChangeScreenParameters
  → 10 ms coalesced WindowFlutterApi.onSnapshotChanged / onDisplaysChanged
- DisplayRaw conversion uses CGDirectDisplayID (stable session ID),
  CGDisplayScreenSize for physicalSize, CGDisplayCopyDisplayMode for refresh rate

### Changed
- Pure-property setters (setTitle, setAlwaysOnTop, setOpacity, etc.) now
  explicitly call scheduleSnapshotEmit() since they don't trigger NSWindow
  notifications natively — fixes "snapshot doesn't update after property
  change" gap discovered during W2.5 integration testing

### W2 integration test coverage
- 7 integration tests on macOS verify happy paths end-to-end (ensureInitialized,
  setSize, setTitle, setAlwaysOnTop, platform.target, displays.list, minimize→restore)
- Comprehensive testbed app at packages/icefelix_window_manager_macos/example/
  mirrors design spec §7 manual checklist for fast verification

## [0.1.0-dev.1] - 2026-05-22

### Added (W1 — Dart foundation)
- `WindowManager` singleton with `ensureInitialized()` (throws `StateError`
  on double-call, `UnsupportedError` on android/ios/web/fuchsia)
- `ValueListenable<WindowSnapshot>` as single source of truth (throws
  `StateError` on pre-init access)
- Full API surface: bounds, size, position, state, focus, drag/resize,
  lifecycle (close/destroy), title, properties, frameless, visual,
  close interception
- `WindowDisplays` sub-namespace with hot-plug events (broadcast stream
  emitting `DisplayAddedEvent` / `DisplayRemovedEvent` / `DisplayChangedEvent`)
- `WindowPlatform` runtime introspection (display server detection,
  sandbox detection, target platform)
- Sealed `WindowEvent` hierarchy (Resize, Move, Focus, StateChange,
  DisplayChange, CloseRequest)
- Sealed `DisplayEvent` hierarchy (Added, Removed, Changed)
- `WindowCloseRequestEvent.preventDefault()` (idempotent, sync-only)

### Notes
- Native implementations pending: macOS (W2), Windows (W3), Linux (W4)
- API surface frozen for v0.1.0
