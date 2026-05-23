# Changelog

## Unreleased

In-progress Win32 implementation of `icefelix_window_manager_platform_interface`
for Windows 10+. Tracks the macOS reference impl method-for-method.

### Added (so far)
- Package scaffolded, dependency on shared platform interface wired
- Pigeon C++ bindings generated from `pigeons/window_api.dart`
- Plugin entry point (`IcefelixWindowManagerWindowsPluginCApi`) registered
  via Flutter Windows C API
- WndProc subclass on the Flutter host HWND, preserving the original proc
  via `CallWindowProc`, with 10 ms snapshot-emit coalescing
- Bounds vertical (`ensureInitialized`, `getBounds`, `setBounds`, `setSize`,
  `setMinSize`/`setMaxSize` via `WM_GETMINMAXINFO` clamping both
  `ptMaxTrackSize` and `ptMaxSize`, `setPosition`, `center`,
  `moveToDisplay`, `maximize`, `unmaximize`)
- Multi-monitor enumeration via `EnumDisplayMonitors`, stable display IDs
  derived from `MONITORINFOEX.szDevice`

### Deferred (next session)
- State machine remainder (`minimize`, `restore`, `hide`/`show`,
  `fullscreen`/`exitFullscreen`), focus, drag/resize, title/properties,
  visual (opacity/bg/shadow/icon), close interception, full `FlutterApi`
  callbacks wiring
