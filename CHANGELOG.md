# Changelog

All notable changes documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

## [0.1.0] - 2026-05-22 — First stable (macOS-only)

First publishable release. macOS implementation complete and audited. Windows
and Linux implementations are on the roadmap (v0.2.x / v0.3.x).

### Added
- **App-facing API** (`icefelix_window_manager`): `WindowManager` singleton
  with `ensureInitialized()`, `ValueListenable<WindowSnapshot>` as single
  source of truth, full setter surface (bounds, state, focus, drag/resize,
  lifecycle, title, properties, frameless, visual, close interception),
  `WindowDisplays` sub-namespace with hot-plug events, `WindowPlatform`
  runtime introspection, sealed `WindowEvent` + `DisplayEvent` hierarchies,
  `WindowCloseRequestEvent.preventDefault()`.
- **Platform interface** (`icefelix_window_manager_platform_interface`):
  Pigeon schema (42 HostApi methods + 3 FlutterApi callbacks), generated
  Dart bindings, abstract `WindowManagerPlatform` with `PlatformInterface`
  token.
- **macOS impl** (`icefelix_window_manager_macos`): Swift + AppKit, full
  NSWindow coverage, multi-monitor via CGDirectDisplayID, 10 ms event
  coalescing, `ForwardingWindowDelegate` preserving Flutter's delegate while
  intercepting `windowShouldClose:`.

### Fixed (vs. internal dev.3)
- **Size coordinate alignment**: `setMinSize` and `setMaxSize` now operate
  in frame coordinates (using `NSWindow.minSize`/`maxSize`), matching
  `setSize` / `setBounds` / `snapshot.bounds.size`. Previous internal builds
  used `contentMinSize`/`contentMaxSize`, causing a ~28px asymmetry on
  styles with a titlebar — `setMaxSize(1200, 900)` followed by `maximize()`
  produced a 1200×928 frame. Now respects the bound exactly. Internal
  `startManualResize` clamp aligned to the same coord space.

### Tests
- 74 unit tests across the Dart packages (snapshot, events, displays,
  platform introspection, manager wiring)
- 9 integration tests on real macOS, including 2 contract tests for the
  size-coordinate alignment fix above

### Known limitations
- macOS only on v0.1.x. Windows planned for v0.2.x, Linux (X11 + Wayland
  via libdecor) for v0.3.x.
- `setBackgroundColor` is only visible when the Flutter widget tree leaves
  pixels transparent or when the window opacity is below 1.0 — this is
  standard NSWindow behavior (`isOpaque` is computed from the color's
  alpha channel), not a plugin limitation.

## [0.1.0-dev.3] - 2026-05-22 — W2 macOS native impl complete

### Added
- macOS platform implementation (Swift + AppKit) — packages/icefelix_window_manager_macos/
- All WindowHostApi methods + FlutterApi event emission wired
- ForwardingWindowDelegate for preventClose
- Multi-monitor support (NSScreen → DisplayRaw conversion with CGDirectDisplayID
  stable IDs, CGDisplayScreenSize for physical size, refresh rate via CGDisplayMode)
- 10 ms event coalescing for high-frequency notifications
- Example testbed app exercising every API surface
- 7 integration tests on macOS

### Fixed
- Pure-property setters (setTitle, setAlwaysOnTop, setOpacity, etc.) now emit
  snapshot changes via explicit scheduleSnapshotEmit() — fixes "snapshot stale
  after property change" gap

### Verified
- macOS 14+ build green, integration tests pass, 76 unit tests pass (Dart side)

## [0.1.0-dev.1] - 2026-05-22 — W1 Dart foundation complete

### Added
- Melos workspace with 2 packages (app-facing + platform_interface)
- Complete Pigeon schema (`pigeons/window_api.dart`) — 42 HostApi methods +
  3 FlutterApi callbacks
- Generated Dart bindings (`messages.g.dart`, 1621 lines)
- `WindowManagerPlatform` abstract base + PlatformInterface token verification
- Full app-facing API: `WindowManager` singleton with all setters,
  `WindowDisplays` sub-namespace, `WindowPlatform` introspection, sealed
  `WindowEvent` + `DisplayEvent` hierarchies
- Reactive `ValueListenable<WindowSnapshot>` single source of truth
- Snapshot diff → event derivation in `WindowManager.onSnapshotChanged`
- Close interception via `WindowCloseRequestEvent.preventDefault()` (sync)
- 69 unit tests covering all Dart-side logic (mocked platform)

### Notes
- Native implementations pending (W2 macOS, W3 Windows, W4 Linux)
- All Dart-side tests pass; native impls plug in via
  `WindowManagerPlatform.instance = MyImpl()`
- `pana .` won't score 160/160 yet (no native impls = platform support
  points lower); target is to bump to 160 by v0.1.0 stable
