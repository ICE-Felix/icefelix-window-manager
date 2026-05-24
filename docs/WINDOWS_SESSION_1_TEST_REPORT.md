# Test report — icefelix_window_manager_windows session 1

**Date:** 2026-05-23
**Branch:** `feature/windows-impl` (merged into `main` at `2884b48`)
**Scope:** bounds vertical (12 of 42 `WindowHostApi` methods), WndProc subclass + snapshot pipeline, display enumeration
**Result:** ✅ GO — all verifications green, session 2 unblocked

---

## 1. Environment

| Item | Value |
|---|---|
| OS | Windows 11 Pro 10.0.26200.8457 (25H2) |
| Flutter | 3.35.6 (channel stable) |
| Dart SDK | 3.9.2 (windows_x64) |
| Visual Studio | Community 2022 17.14.17 (toolset v143) |
| Windows SDK | 10.0.26100.0 |
| Melos | 7.7.0 (global) |
| Pana | 0.23.12 |
| Test monitor | Generic PnP — 2056×1291 physical, scale 1.0× (96 DPI) |

Repo location: `C:\dev\ifw\` (moved from
`C:\Users\Alex Bordei\Desktop\ICEFelix\icefelix-window-manager\` to clear MSVC's
MAX_PATH=260 ceiling under the `example/windows/flutter/ephemeral/.plugin_symlinks/...`
chain).

---

## 2. Static analysis

```
$ flutter analyze   # in packages/icefelix_window_manager_windows
Analyzing icefelix_window_manager_windows...
No issues found! (ran in 1.3s)

$ flutter analyze   # in packages/icefelix_window_manager_windows/example
Analyzing example...
No issues found! (ran in 0.8s)
```

Result: **0 issues** across the package and the example. Strict casts /
inference / raw-types (inherited from root `analysis_options.yaml`) all clean.

---

## 3. Formatting

```
$ dart format --output=none --set-exit-if-changed \
    packages/icefelix_window_manager_windows/lib \
    packages/icefelix_window_manager_windows/example/lib \
    packages/icefelix_window_manager_windows/example/integration_test
Formatted 3 files (0 changed) in 0.22 seconds.
```

Result: **0 files need reformatting**.

---

## 4. Integration tests (real HWND)

Run via:
```powershell
cd packages\icefelix_window_manager_windows\example
flutter test integration_test/ -d windows
```

```
Building Windows application...                                    14.2s
√ Built build\windows\x64\runner\Debug\icefelix_window_manager_windows_example.exe
00:00 +0: (setUpAll)
00:00 +0: ensureInitialized returns valid snapshot
00:00 +1: platform.target == TargetPlatform.windows
00:00 +2: displays.list returns at least one Display with primary
00:00 +3: setSize updates snapshot bounds within 2s
00:00 +4: setMaxSize is honored by maximize() in frame coords
00:00 +5: setMinSize clamps subsequent setSize in frame coords
00:00 +6: (tearDownAll)
00:00 +6: All tests passed!
```

Result: **6/6 pass** on real Win32 HWND. Total wall-clock ~17 s
(14.2 s build + ~3 s test execution).

### Test-by-test detail

| # | Test | Asserts | Validates |
|---|---|---|---|
| 1 | `ensureInitialized returns valid snapshot` | `bounds.size > 0`, `currentDisplay.scaleFactor > 0` | HWND found via `registrar->GetView()->GetNativeWindow()` + `GetAncestor(GA_ROOT)`; WndProc subclass installed; `GetWindowRect` returned real frame coords; `GetDpiForWindow` returned valid scale. |
| 2 | `platform.target == TargetPlatform.windows` | `platform.target == TargetPlatform.windows`, `displayServer == null` | `GetPlatformInfo` returns `"windows"` and the Dart adapter maps it correctly. `displayServer` is Linux-only — correctly null. |
| 3 | `displays.list returns at least one Display with primary` | `displays.length >= 1`, at least one has `isPrimary == true` | `EnumDisplayMonitors` callback fires per monitor; each is wrapped via `BuildDisplayRawForMonitor` (calls `GetMonitorInfoExW`, `GetDpiForMonitor(MDT_EFFECTIVE_DPI)`, `EnumDisplaySettingsExW` for refresh rate, `EnumDisplayDevicesW` for friendly name). `MONITORINFOF_PRIMARY` flag detection works. |
| 4 | `setSize updates snapshot bounds within 2s` | After `setSize(900, 700)`, snapshot reports 900×700 (±1 px DPI slop) within 2 s | **End-to-end snapshot pipeline:** Dart call → Pigeon → `SetSize` (logical→physical via `GetDpiForWindow`) → `SetWindowPos` → `WM_SIZE` → subclassed WndProc → `ScheduleSnapshotEmit` resets 10 ms `SetTimer` → `WM_TIMER` → `EmitSnapshotNow` → `WindowFlutterApi::OnSnapshotChanged` → Dart `_FlutterApiAdapter` → `ValueNotifier<WindowSnapshot>` update. |
| 5 | **`setMaxSize is honored by maximize() in frame coords`** | After `setMaxSize(1200,900)` then `maximize()`: `state == maximized`, `bounds.size <= (1200, 900)` (±1 px slop) | **The load-bearing test.** `SetMaxSize` stores physical px in `max_size_cx_`/`max_size_cy_`; `ShowWindow(SW_MAXIMIZE)` triggers `WM_GETMINMAXINFO`; our handler clamps **both** `ptMaxTrackSize` AND `ptMaxSize`. Without `ptMaxSize`, `SW_MAXIMIZE` would expand to the full work area. This is the Win32 analog of the macOS `contentMaxSize` bug fixed in v0.1.0. |
| 6 | `setMinSize clamps subsequent setSize in frame coords` | After `setMinSize(800,600)` then `setSize(400,300)`: snapshot bounds ≥ 800×600 | `SetMinSize` stores physical px and re-applies the current size clamped to the new floor via `SetWindowPos` (Windows doesn't auto-resize on pure-constraint changes). Subsequent `SetSize(400)` triggers another `WM_GETMINMAXINFO` round which the handler also clamps. |

---

## 5. Manual visual verification (testbed)

Launched via:
```powershell
cd packages\icefelix_window_manager_windows\example
flutter run -d windows
```

### Initial state (just after `ensureInitialized`)

```
bounds = WindowBounds(position=Offset(454.0, 166.0), size=Size(1280.0, 720.0))
state = normal
display = Generic PnP Monitor scale=1.0
```

Validated:
- ✓ Window 1280×720 (Flutter default size)
- ✓ Position (454, 166) — Flutter centered on the primary monitor
- ✓ State `normal` — not maximized/minimized/fullscreen
- ✓ Display name resolved via `EnumDisplayDevicesW.DeviceString`
- ✓ Scale 1.0 (96 DPI) — monitor at 100% scaling
- ✓ Screenshot pixel count (1280×720) matched physical rect — no DPI lying

### After `setMaxSize 1200×900` → `maximize` (driven via Win32 `mouse_event`)

```
bounds = WindowBounds(position=Offset(-8.0, -8.0), size=Size(1200.0, 900.0))
state = maximized
display = Generic PnP Monitor scale=1.0
```

Validated:
- ✓ `state` flipped to `maximized` — `IsZoomed(hwnd_)` returned true
- ✓ `bounds.size = (1200, 900)` — clamped **exactly** to the user-supplied
  cap, NOT the 2048×1241 work area that `SW_MAXIMIZE` would otherwise fill
- ✓ `position = (-8, -8)` — standard Windows maximize offset (extends 8 px
  off-screen on each side to hide the resize border, even when capped)
- ✓ HUD updated live — full pipeline ran in well under 100 ms
- ✓ Window visibly did NOT fill the primary monitor (the desktop wallpaper
  and other windows were visible around it in the full-screen screenshot)

Screenshots captured during the session (untracked in repo root):
- `testbed-initial.png` — fresh launch, 1280×720
- `testbed-maximized-with-cap.png` — full-screen view showing the capped
  window not filling the display
- `testbed-maximized-final.png` — window-only view with the HUD readable

---

## 6. What was NOT tested (deferred to session 2)

### Methods stubbed as `not_implemented`

The Pigeon abstract base requires all 42 methods. The following 30 return
`FlutterError("not_implemented")` so the C++ abstract class compiles — they
will be wired in session 2:

- State: `minimize`, `restore`, `hide`, `show`, `fullscreen`, `exitFullscreen`
- Focus: `focus`, `blur`
- Drag/resize: `startDrag`, `startResize`
- Lifecycle: `close`, `destroy`
- Title + properties: `setTitle`, `setAlwaysOnTop`, `setSkipTaskbar`,
  `setResizable`, `setMovable`, `setMinimizable`, `setMaximizable`,
  `setClosable`
- Frameless: `setFrameless`, `setTitleBarStyle`
- Visual: `setOpacity`, `setBackgroundColor`, `setHasShadow`, `setIcon`

(Plus `setPreventClose` which tracks the flag only — full WM_CLOSE intercept
is session 2.)

### Integration tests not yet ported from macOS

3 of the 9 macOS-equivalent tests skipped this session (they exercise
methods that are still stubbed):

- `setTitle updates snapshot.title`
- `setAlwaysOnTop updates snapshot.alwaysOnTop`
- `minimize then restore round-trip`

Will be ported when the underlying methods land.

### Win32-specific tests not yet added

The done-when checklist asks for ≥2 Windows-specific tests; none added
yet:

- `WM_DPICHANGED` event emits a snapshot with the new scale factor
- `setSkipTaskbar` toggles `WS_EX_TOOLWINDOW`

### Coverage scenarios not exercised

- Multi-monitor `moveToDisplay` — requires a second physical/virtual display
- Different DPI scales — single 1.0× test machine; no validation of 1.25×,
  1.5×, 2.0×
- `WM_DPICHANGED` cross-monitor drag — needs heterogeneous DPI setup
- High-frequency drag-resize stress test for the 10 ms coalescer

### Quality gates not yet run

- `pana` score (target ≥140/160)
- `flutter pub publish --dry-run`

---

## 7. Result

✅ **GO for session 2.**

The bounds vertical is structurally correct on Win32. The load-bearing
`setMaxSize is honored by maximize()` case — the entire reason this vertical
was the chosen session-1 endpoint — passes both as an automated test and as
a manual visual confirmation. The WndProc subclass + 10 ms snapshot coalesce
pipeline is wired end-to-end. Display enumeration with stable IDs works.

Session 2 picks up the remaining 30 methods, the full 27-button testbed,
the 3 remaining macOS-equivalent integration tests + 2 Win32-specific ones,
pana ≥140, dry-run, the app-facing v0.2.0 bump declaring Windows, and
publishing.
