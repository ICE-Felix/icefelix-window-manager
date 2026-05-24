# Changelog

## 0.2.1 - 2026-05-24

### Changed
- Dependency on `icefelix_window_manager_platform_interface` bumped to
  `^0.2.0` so the new `setShape` API resolves to a platform interface
  version that actually declares the channel. The 0.2.0 release shipped
  with stale `^0.1.0` constraints and the Pigeon channel was missing at
  runtime — pana / pub.dev flagged the resulting compile error. No API
  changes; consumer apps should bump from 0.2.0 → 0.2.1.

## Unreleased

### Added
- `setShape(List<Offset>? points)` — sets the OS window region to a polygon
  defined by the given points (window-relative logical pixels). Pixels
  outside the polygon don't paint AND clicks pass through to the desktop
  (true non-rectangular hit-testing). Pass `null` to clear and restore the
  default rectangular region. Windows: `CreatePolygonRgn` + `SetWindowRgn`.
  macOS: `NSWindow.contentView.layer` mask (visual only — chrome stays
  rectangular; pair with `setFrameless(true)` for the expected effect).
  Linux: not implemented in v0.3.x.
- `example/polygon_demo/` — showcase Flutter Windows app exercising the
  new shape API together with `setFrameless`, `setOpacity`, `setSize`,
  `startDrag`, `minimize`, and `destroy`. Argv-parameterized so a launcher
  script can spawn a swarm of differently-shaped windows for promo art.
- Promo screenshot at `screenshots/polygon_promo.png` showing 10 such
  windows side-by-side. Declared via the pubspec `screenshots:` field for
  pub.dev rendering.

### Fixed
- `WindowManager.events` stream is now `sync: true` so a listener's
  synchronous `event.preventDefault()` on a `WindowCloseRequestEvent`
  actually blocks the close. Previously the default async broadcast queued
  the listener as a microtask, so the Pigeon-generated synchronous handler
  returned `allow` before the listener could vote — making the
  preventClose flow a silent no-op end-to-end on every platform.

## 0.2.0 - 2026-05-24

### Added
- Windows 10+ support via the new `icefelix_window_manager_windows` package (Win32 implementation, full 42-method `WindowHostApi` coverage). See its CHANGELOG for the platform-specific behavior + limitations.

### Changed
- `pubspec.yaml` `platforms:` now declares `windows:` alongside `macos:`.

## [0.1.0] - 2026-05-22 — First stable (macOS-only)

App-facing public API for the icefelix_window_manager federated plugin.
macOS implementation ships in v0.1.0 of `icefelix_window_manager_macos`;
Windows and Linux are on the roadmap.

### Public API surface (frozen for v0.1.x)
- `WindowManager` singleton: `ensureInitialized()`, `snapshot` (a
  `ValueListenable<WindowSnapshot>`), `events` stream, every setter for
  bounds / state / focus / drag-resize / lifecycle / title / properties /
  visual / close interception
- `WindowDisplays` sub-namespace with `list()`, `getCurrent()`,
  `getPrimary()`, and a broadcast `events` stream
  (`DisplayAdded/Removed/Changed`)
- `WindowPlatform` introspection (`target`, `displayServer`, `isSandboxed`)
- Sealed `WindowEvent` hierarchy (Resize, Move, Focus, StateChange,
  DisplayChange, CloseRequest) and `DisplayEvent` hierarchy
- `WindowCloseRequestEvent.preventDefault()` — sync, idempotent

### Coordinate semantics (documented)
- `setSize`, `setMinSize`, `setMaxSize`, and `snapshot.bounds.size` all
  share frame coordinates (titlebar included on styles that have one).

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
