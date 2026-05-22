# Changelog

## [0.1.0-dev.1] - 2026-05-22

### Added (W2 release)
- Initial Swift + AppKit implementation of WindowManagerPlatform for macOS 10.15+
- All 42 WindowHostApi methods + 3 FlutterApi callbacks (onSnapshotChanged,
  onDisplaysChanged, onCloseRequest)
- Multi-monitor support via NSScreen + CGDirectDisplayID
- 10 ms event coalescing
- ForwardingWindowDelegate for preventClose interception
- Comprehensive example app at example/ exercising every API
- 7 integration tests on macOS verify end-to-end behavior

### Known limitations
- See README "Limitations" section
