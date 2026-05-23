# icefelix_window_manager_windows

Windows implementation of [`icefelix_window_manager`](https://pub.dev/packages/icefelix_window_manager).

**App developers should depend on `icefelix_window_manager`, not this package
directly.** This package is wired automatically when you add the app-facing
package to a Flutter Windows app.

## Implementation notes

- Wraps the Flutter Windows host `HWND` via a `WndProc` subclass installed in
  `RegisterWithRegistrar` (preserves the original window proc via
  `CallWindowProc` so Flutter input handling continues to work).
- All four size APIs (`setSize`, `setMinSize`, `setMaxSize`,
  `snapshot.bounds.size`) share the same frame-coordinate space.
  `GetWindowRect` is the source of truth; min/max are enforced via
  `WM_GETMINMAXINFO` setting both `ptMaxTrackSize` and `ptMaxSize` so
  `ShowWindow(SW_MAXIMIZE)` doesn't overshoot.
- Snapshot emits are coalesced to ~10 ms via `SetTimer` to avoid flooding
  the Dart isolate during drag-resize (which fires `WM_SIZE` at the display
  refresh rate).
- Display IDs are derived from `MONITORINFOEX.szDevice` (stable across
  reconfigurations) — `HMONITOR` itself is not stable.

## Requirements

- Windows 10+
- Per-Monitor v2 DPI awareness (Flutter Windows host already enables this)
- Visual Studio 2022 with the Desktop development with C++ workload

## Status

Production-ready for the published v0.1.0 method surface. See CHANGELOG
"Known limitations" for the small set of methods that no-op or approximate
due to Win32 platform constraints.

Tested on Windows 11 25H2 (build 26200) with Visual Studio 2022 17.14 +
Windows 10 SDK 10.0.26100, Flutter 3.27+ on Dart 3.6+. 11 integration
tests pass on a real Windows HWND.
