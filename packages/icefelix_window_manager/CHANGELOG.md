# Changelog

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
