# Changelog

## [0.2.0] - 2026-05-24

### Added
- `WindowHostApi.setShape(List<OffsetRaw>? points)` — Pigeon schema for
  non-rectangular window regions (polygon). Wire-protocol additive; old
  platform impls (0.1.x) will throw `UnimplementedError` if called. New
  platform impls (0.2.x+) implement it natively. Documented as
  best-effort across platforms.
- `platforms:` now declares both `macos:` and `windows:` (added Windows).

### Bumped
- All federated dependents must move to constraint `^0.2.0` to consume
  the new schema. Stale `^0.1.0` constraints would fail to resolve the
  setShape Pigeon channel at runtime.

## [0.1.0] - 2026-05-22 — First stable

Platform interface for the icefelix_window_manager federated plugin. Used
by platform implementations (`_macos`; `_windows` and `_linux` coming).

### Added
- Pigeon schema (`pigeons/window_api.dart`) — source of truth for the
  native bridge: 42 HostApi methods + 3 FlutterApi callbacks
  (`onSnapshotChanged`, `onDisplaysChanged`, `onCloseRequest`)
- Generated Dart bindings (`lib/src/messages.g.dart`)
- Abstract `WindowManagerPlatform` base class with `PlatformInterface`
  token verification
- Default implementation throws `UnimplementedError` on all methods so
  platform impls fail loudly during development if a method is missed
- `MockPlatformInterfaceMixin` re-export for testability

### Docs
- `setSize` / `setMinSize` / `setMaxSize` documented as operating on
  frame coordinates (titlebar included on platforms that have one).
