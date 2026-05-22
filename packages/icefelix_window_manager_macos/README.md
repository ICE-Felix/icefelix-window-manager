# icefelix_window_manager_macos

[![pub package](https://img.shields.io/pub/v/icefelix_window_manager_macos.svg)](https://pub.dev/packages/icefelix_window_manager_macos)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

macOS implementation of [`icefelix_window_manager`](https://pub.dev/packages/icefelix_window_manager). Wraps NSWindow + AppKit via Pigeon-typed channels.

**App developers: depend on `icefelix_window_manager`, not this package.** It's auto-included.

## Requirements
- macOS 10.15+
- Flutter 3.27+, Dart 3.6+
- Swift 5.0

## Implementation notes
- Coordinate system flipped (AppKit bottom-left → Flutter top-left) at the API boundary
- 10ms event coalescing for high-frequency NSWindow notifications (drag-resize)
- ForwardingWindowDelegate preserves any existing NSWindowDelegate while intercepting windowShouldClose: for preventClose flow
- Sandbox detection via $HOME containing /Library/Containers/

## Limitations (macOS-specific)
- `setSkipTaskbar(true)` adds `.transient` collectionBehavior (out of Mission Control). True "hide from Dock" requires `LSUIElement=YES` in app's Info.plist (build-time, not runtime).
- `setIcon` sets `NSApplication.shared.applicationIconImage` (per-app, not per-window — macOS has no per-window icon concept).
- `setMaximizable(false)` is flag-tracked; granular enforcement requires `windowShouldZoom:to:` delegate hook (v0.2.0).

## License
BSD-3-Clause © 2026 icefelix.com (Alex Bordei)
