# Changelog

All notable changes documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

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
