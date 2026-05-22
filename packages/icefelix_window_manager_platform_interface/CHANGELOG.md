# Changelog

## [0.1.0-dev.1] - 2026-05-22

### Added
- Pigeon schema (`pigeons/window_api.dart`) — source of truth for native bridge
  (42 HostApi methods + 3 FlutterApi callbacks)
- Generated Dart bindings (`lib/src/messages.g.dart`, 1621 lines)
- Abstract `WindowManagerPlatform` base class with `PlatformInterface` token
- Default implementation throws `UnimplementedError` on all 42 methods
- `MockPlatformInterfaceMixin` re-export for testability
