# Changelog

## 0.4.1 - 2026-05-25 — Integration test fixes for Linux headless

### Fixed
- `flutter test -d linux` (headless, no real GtkWindow) now passes
  14/14: GTK-dependent tests auto-skip via a `hasRealWindow` probe.
- Added `WindowManager.refreshSnapshot()` (`@visibleForTesting`) for
  pull-based snapshot polling in integration tests.
- Made `install_signal_handlers` idempotent (prevents signal handler
  duplication on repeated `ensureInitialized` calls).

## 0.4.0 - 2026-05-24 — Linux support

Adds Linux as a first-class platform alongside macOS and Windows. Both
X11 and Wayland are supported; the Wayland-position-is-null reality is
honored via the existing nullable `WindowBoundsRaw.position` field
(no schema change).

### Added
- **Linux native backend** (`linux/`): GTK 3 + Pigeon GObject
  implementation of the full `WindowHostApi` surface.
- Real GdkMonitor enumeration with hot-plug signals
  (`monitor-added`/`monitor-removed` → `onDisplaysChanged`).
- Two-pass close interception via `delete-event` ↔ `onCloseRequest`,
  honoring `WindowManager.events` `sync: true` contract.
- `startDrag` and `startResize` with captured button-press context.
- `setBackgroundColor` via `GtkCssProvider`.
- `scripts/xvfb-with-wm.sh` wrapper for headless integration tests.
- 4 Linux-specific integration tests (X11 position, Wayland position).

### Known limitations on Linux
- `setShape` is a no-op (logs a one-shot warning). Real impl deferred
  to a 0.4.x patch.
- `setMovable` is flag-only; GTK exposes no titlebar-drag-disable API.
- `setAlwaysOnTop` is best-effort on Wayland (compositors may ignore
  `keep_above` without `wlr-layer-shell`).
- Stable display IDs concatenate `manufacturer|model`; falls back to
  `linux-monitor-N` on VMs / virtual displays.
- Headless integration tests (via xvfb + openbox) cannot validate
  FlutterApi push-channel behavior during `testWidgets` due to a
  flutter_linux + `LiveTestWidgetsFlutterBinding` interaction.
  Manual GNOME smoke testing is recommended for full validation.

### Tested on
Ubuntu 24.04.4 LTS ARM64, Flutter 3.44 stable, GTK 3.24, GNOME 46
(both X11 and Wayland sessions).

## 0.3.0 - 2026-05-24 — Monolithic cross-platform release

Major restructuring: collapses the four federated packages into a single
plugin. No API changes from 0.2.1 — same `WindowManager`, same setters,
same events, same `setShape`. Just one package on pub.dev instead of four.

### Changed
- **Layout: federated → monolithic.** The native code for macOS (Swift +
  AppKit) and Windows (C++ + Win32) now ships inside the same
  `icefelix_window_manager` package as the Dart API. The four packages
  used in 0.2.x are collapsed into one:
  - `icefelix_window_manager_macos@0.2.0` — **discontinued**, code merged
  - `icefelix_window_manager_windows@0.2.0` — **discontinued**, code merged
  - `icefelix_window_manager_platform_interface@0.2.0` — **discontinued**,
    schema and abstract base merged in
  - `icefelix_window_manager@0.2.1` → **`icefelix_window_manager@0.3.0`**
- Pigeon-generated bindings now live at `lib/src/messages.g.dart`,
  `macos/Classes/Messages.g.swift`, `windows/messages.g.{h,cpp}` inside
  the single package.
- Swift plugin class renamed `IcefelixWindowManagerMacosPlugin` →
  `IcefelixWindowManagerPlugin`. Windows C-API plugin class renamed
  similarly. App code does not import these directly so this is
  transparent; only an issue if you were manually invoking
  `IcefelixWindowManagerMacos.registerWith()` — Flutter now
  auto-registers via the `pluginClass` in pubspec.yaml.

### Why
The federated pattern is recommended when multiple vendors own different
platform impls (e.g. Google maintains macOS, community maintains Linux
for a Google plugin). For a single-owner plugin, the federated overhead
— four pubspecs to keep in sync, four CHANGELOGs, version-coordination
bugs every time the schema changes — outweighs the benefits. v0.2.0
shipped with a real broken dep-version mismatch that we papered over in
0.2.1; rather than continue to maintain four packages, we collapse to
one.

### Migration
```yaml
# Before (any 0.2.x):
dependencies:
  icefelix_window_manager: ^0.2.0     # the only thing you wrote anyway
# Plus possibly indirect deps on _macos, _windows, _platform_interface

# After (0.3.0):
dependencies:
  icefelix_window_manager: ^0.3.0     # same one-line dep, fewer transitive packages
```

If your code did `IcefelixWindowManagerMacos.registerWith()` or
`IcefelixWindowManagerWindows.registerWith()` directly, **remove those
calls** — Flutter now auto-registers the plugin via the pubspec
`pluginClass` declarations.

### Verified
- 72 unit tests pass
- 10 integration tests pass on real macOS NSWindow (including the
  `setMaxSize honored by maximize() in frame coords` and `preventClose:
  synchronous preventDefault blocks close` regression contracts)

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
