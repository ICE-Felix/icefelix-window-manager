# Changelog

## 0.2.0 - 2026-05-24

### Changed
- Dependency on `icefelix_window_manager_platform_interface` bumped to
  `^0.2.0` so the new `setShape` Pigeon channel resolves correctly.
  No native behavior change versus 0.1.0 — this is a constraint-fix
  release for federated version alignment. The 0.1.0 release on pub.dev
  shipped with `^0.1.0` and broke when consumers pulled the schema
  without `setShape` declared.

## 0.1.0 - 2026-05-24

First publishable Win32 implementation of `icefelix_window_manager_platform_interface` for Windows 10+.

### Added
- All 42 `WindowHostApi` methods implemented against Win32 (bounds, state, focus, drag/resize, lifecycle, title, properties, frameless, visual, multi-monitor, close interception)
- All 3 `WindowFlutterApi` callbacks (`OnSnapshotChanged`, `OnDisplaysChanged`, `OnCloseRequest`) wired through a subclassed WndProc on the Flutter host HWND
- `WM_GETMINMAXINFO` clamps both `ptMaxTrackSize` and `ptMaxSize` so `ShowWindow(SW_MAXIMIZE)` honors `setMaxSize` — Win32 analog of the macOS contentMaxSize fix
- 10 ms event coalescing via `SetTimer` + `WM_TIMER` so high-frequency `WM_SIZE` / `WM_MOVE` during drag-resize doesn't flood the Dart isolate
- `WM_CLOSE` intercept with 5 s default-allow timeout matching the schema's synchronization contract
- 11 integration tests on real Windows HWND (6 bounds + 3 macOS-port + 2 Win32-specific)
- Comprehensive example testbed at `example/` exercising every API (27 controls, ported verbatim from macOS for cross-platform visual audit parity)

### Known limitations
- `setBackgroundColor`: Win32 windows draw their own background via `WM_ERASEBKGND` with the class brush; per-window color isn't a first-party API. Flag is tracked in the snapshot for round-trip correctness; visual no-op.
- `setHasShadow`: only effective for frameless windows (composed via `DwmExtendFrameIntoClientArea`). Framed windows always have the DWM-managed shadow.
- `setSkipTaskbar`: toggles `WS_EX_TOOLWINDOW` which also hides the window from Alt+Tab.
- `getPlatformInfo().isSandboxed`: returns `false` always. MSIX/AppContainer detection deferred to v0.1.x.
- Physical display size (`DisplayRaw.physicalWidthMm`/`physicalHeightMm`) returns null. Reading these requires EDID/WMI parsing which we don't ship.
- `setIcon`: loads a single size (`LR_DEFAULTSIZE`) and uses it for both `ICON_BIG` and `ICON_SMALL`. Title-bar/taskbar small icons get a software downscale rather than a separate 16×16. Looks fine on modern Windows DPI scaling.
- `setMovable(false)`: implemented via `WM_NCHITTEST` remap of `HTCAPTION → HTBORDER`. Frameless windows with custom-chrome hit-testing may need a follow-up to also remap `HTMOVE`.
- `Focus()`: uses the `AttachThreadInput` workaround; if foreground-lock prevention is active, the call is best-effort. Same caveat applies to macOS.
