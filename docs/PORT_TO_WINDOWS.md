# Porting to Windows — implementation guide

**Target:** `icefelix_window_manager_windows` package, published at v0.1.0,
app-facing bumped to v0.2.0 declaring Windows support.

**Estimated effort:** 4-6 weeks for a Flutter dev who knows Win32 basics.
8-10 weeks if Win32 is new to you.

**Prerequisite reading:** [`PORTING.md`](PORTING.md) — read it first. This
guide assumes you have.

---

## Toolchain prerequisites (Windows-specific)

```powershell
# Visual Studio 2022 with these workloads:
#   - Desktop development with C++
#   - C++ ATL for v143 build tools
#   - Windows 10/11 SDK (latest)
# Without these, `flutter run -d windows` won't build the Flutter Windows host.

# CMake 3.20+ (ships with Flutter, but verify)
cmake --version

# Flutter doctor must show Windows green:
flutter doctor -v
# Look for:
#   [✓] Windows Version (Installed version of Windows is version 10 or higher)
#   [✓] Visual Studio - develop Windows apps
```

Verify the Flutter Windows toolchain works by running the existing
example app (which has no Windows plugin yet — it will run but window
manager calls will throw `MissingPluginException`):

```powershell
cd packages\icefelix_window_manager_macos\example
flutter run -d windows
```

If a window appears (even if it throws when you click anything), the
Flutter Windows side is healthy.

---

## Step 1 — Scaffold the package

```powershell
cd packages
flutter create --org com.icefelix --template=plugin --platforms=windows icefelix_window_manager_windows
```

Delete the default scaffolded `lib/` Dart code and `windows/runner/` (Flutter
will regenerate the example runner when you create the example). Keep:

- `windows/CMakeLists.txt` (you'll edit it heavily)
- `windows/icefelix_window_manager_windows_plugin.cpp` / `.h` (rename to
  match the macOS naming convention)
- `pubspec.yaml`

Copy `LICENSE` and the README/CHANGELOG conventions from the macOS package.

Update `pubspec.yaml` to mirror the macOS one:

```yaml
name: icefelix_window_manager_windows
description: >-
  Windows implementation of icefelix_window_manager. Wraps the Win32 window
  API via Pigeon-typed channels. App developers depend on icefelix_window_manager,
  not this package.
version: 0.1.0
repository: https://github.com/ICE-Felix/icefelix-window-manager
issue_tracker: https://github.com/ICE-Felix/icefelix-window-manager/issues
homepage: https://icefelix.com/packages/window-manager

topics: [window, desktop, windows]

environment:
  sdk: ^3.6.0
  flutter: ">=3.27.0"

dependencies:
  flutter:
    sdk: flutter
  icefelix_window_manager_platform_interface: ^0.1.0

dev_dependencies:
  flutter_lints: ^5.0.0
  flutter_test:
    sdk: flutter

flutter:
  plugin:
    implements: icefelix_window_manager
    platforms:
      windows:
        pluginClass: IcefelixWindowManagerWindowsPlugin
        dartPluginClass: IcefelixWindowManagerWindows
```

Then `melos bootstrap` to wire it into the workspace.

---

## Step 2 — Generate the Pigeon C++ bindings

The platform_interface package generates Dart bindings on every build,
but C++ bindings need a separate Pigeon run. Add a script to
`melos.yaml`:

```yaml
scripts:
  pigeon_windows:
    description: Regenerate Pigeon C++ bindings for Windows
    run: |
      cd packages/icefelix_window_manager_platform_interface && \
      dart run pigeon --input pigeons/window_api.dart \
        --cpp_header_out ../icefelix_window_manager_windows/windows/messages.g.h \
        --cpp_source_out ../icefelix_window_manager_windows/windows/messages.g.cpp \
        --cpp_namespace icefelix_window_manager_windows
```

Run it:

```powershell
melos run pigeon_windows
```

This generates `messages.g.h` and `messages.g.cpp` in the Windows
package. **Do not edit these files.** Re-run the script whenever the
schema changes (which should be never, by the rules in PORTING.md).

---

## Step 3 — The Win32 implementation map

This is the heart of the work. For each macOS Swift method in
`IcefelixWindowManagerMacosPlugin.swift`, here is the Win32 equivalent.
Use this as a checklist.

### Setup

| Concern | macOS | Win32 |
|---|---|---|
| Plugin entry point | `IcefelixWindowManagerMacosPlugin.swift` `register` | `IcefelixWindowManagerWindowsPlugin::RegisterWithRegistrar` |
| Get main window | `NSApplication.shared.windows.first` | `GetAncestor(registrar->GetView()->GetNativeWindow(), GA_ROOT)` to get the HWND |
| Plugin lifetime | Tied to FlutterPlugin | Tied to `flutter::PluginRegistrarWindows*` |

### DPI awareness — CRITICAL

Before you do any window math, set DPI awareness in your application
manifest (the example app's `runner.exe.manifest`):

```xml
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
    </windowsSettings>
  </application>
</assembly>
```

Without `PerMonitorV2`, all your size/position reads will be wrong on
multi-DPI setups. The Flutter Windows host already sets DPI awareness
programmatically in `win32_window.cpp` (`SetThreadDpiAwarenessContext`),
but verify it. The example app you write must inherit this.

### Bounds

| API | macOS (NSWindow) | Win32 |
|---|---|---|
| `getBounds()` | `window.frame` | `GetWindowRect(hwnd, &rect)` — **frame, not client** |
| `setBounds(b, displayId)` | `setFrameFromFlutterCoords` | `SetWindowPos(hwnd, NULL, x, y, w, h, SWP_NOZORDER \| SWP_NOACTIVATE)` |
| `setSize(s)` | preserve top-left, set frame | `SetWindowPos` with current x,y, new w,h |
| `setMinSize(s)` | `w.minSize = s` (frame) | Store in member var; enforce via `WM_GETMINMAXINFO` handler (see below) |
| `setMaxSize(s)` | `w.maxSize = s` (frame) | Store in member var; enforce via `WM_GETMINMAXINFO` handler |
| `setPosition(p)` | preserve size, set frame origin | `SetWindowPos` with new x,y, current w,h |
| `center()` | `window.center()` | Compute center of monitor work area via `MONITORINFO`, `SetWindowPos` |
| `moveToDisplay(id)` | preserve relative position, switch screen | Find monitor by HMONITOR or device name, translate position |

**`WM_GETMINMAXINFO` handler** — this is how you enforce min/max size on
Windows. Subclass the window proc and intercept the message:

```cpp
case WM_GETMINMAXINFO: {
  MINMAXINFO* mmi = reinterpret_cast<MINMAXINFO*>(lParam);
  if (has_min_size_) {
    mmi->ptMinTrackSize.x = min_size_.cx;
    mmi->ptMinTrackSize.y = min_size_.cy;
  }
  if (has_max_size_) {
    mmi->ptMaxTrackSize.x = max_size_.cx;
    mmi->ptMaxTrackSize.y = max_size_.cy;
    // Also clamp ptMaxSize for maximize behavior (mirrors macOS zoom() respecting maxSize)
    mmi->ptMaxSize.x = max_size_.cx;
    mmi->ptMaxSize.y = max_size_.cy;
  }
  return 0;
}
```

This is the canonical Win32 idiom. Without setting `ptMaxSize`,
`ShowWindow(SW_MAXIMIZE)` will overshoot — exactly the same class of bug
we hit on macOS. The integration test
`setMaxSize is honored by maximize() in frame coords` will catch you.

### State

| API | macOS | Win32 |
|---|---|---|
| `minimize()` | `window.miniaturize(nil)` | `ShowWindow(hwnd, SW_MINIMIZE)` |
| `maximize()` | `window.zoom(nil)` if not zoomed | `ShowWindow(hwnd, SW_MAXIMIZE)` |
| `unmaximize()` | `window.zoom(nil)` if zoomed | `ShowWindow(hwnd, SW_RESTORE)` |
| `restore()` | `window.deminiaturize` or `zoom` if needed | `ShowWindow(hwnd, SW_RESTORE)` |
| `fullscreen()` | toggle `.fullScreen` style mask | Save current style/rect; remove WS_OVERLAPPEDWINDOW; resize to monitor bounds |
| `exitFullscreen()` | toggle off | Restore saved style + rect |
| `show()` | `window.makeKeyAndOrderFront(nil)` | `ShowWindow(hwnd, SW_SHOW)` |
| `hide()` | `window.orderOut(nil)` | `ShowWindow(hwnd, SW_HIDE)` |
| `focus()` | `window.makeKeyAndOrderFront(nil)` | `SetForegroundWindow(hwnd)` (subject to attach-thread rules) |
| `blur()` | resign key | No direct API — set foreground to another window |

For fullscreen, mirror Flutter's own implementation in
`flutter_windows.cpp` — they handle the style mask gymnastics
correctly.

### Title + properties

| API | macOS | Win32 |
|---|---|---|
| `setTitle(s)` | `window.title = s` | `SetWindowTextW(hwnd, wide_str.c_str())` |
| `setAlwaysOnTop(b)` | `window.level = .floating` or `.normal` | `SetWindowPos(hwnd, b ? HWND_TOPMOST : HWND_NOTOPMOST, 0,0,0,0, SWP_NOMOVE \| SWP_NOSIZE)` |
| `setSkipTaskbar(b)` | flag-tracked (no NSWindow API) | Toggle `WS_EX_TOOLWINDOW` via `SetWindowLongPtr(hwnd, GWL_EXSTYLE, ...)` |
| `setResizable(b)` | toggle `.resizable` style mask | Toggle `WS_THICKFRAME` and `WS_MAXIMIZEBOX` via `SetWindowLongPtr` |
| `setMovable(b)` | `window.isMovable = b` | Hook `WM_NCHITTEST` and return `HTBORDER` instead of `HTCAPTION` when disabled |
| `setMinimizable(b)` | toggle `.miniaturizable` style mask | Toggle `WS_MINIMIZEBOX` |
| `setMaximizable(b)` | flag-tracked | Toggle `WS_MAXIMIZEBOX` |
| `setClosable(b)` | toggle `.closable` style mask | Disable Close in system menu via `GetSystemMenu`, `EnableMenuItem(SC_CLOSE, MF_GRAYED)` |

### Visual

| API | macOS | Win32 |
|---|---|---|
| `setFrameless(b)` | toggle `.titled` style mask | Toggle `WS_CAPTION` / `WS_THICKFRAME`. For frameless with shadow, use `DwmExtendFrameIntoClientArea` |
| `setTitleBarStyle(s)` | various NSWindow titlebar props | Custom titlebar: extend client area + draw your own; the "hidden" style maps to `DwmExtendFrameIntoClientArea(MARGINS{-1})` |
| `setOpacity(d)` | `window.alphaValue = d` | `SetLayeredWindowAttributes(hwnd, 0, (BYTE)(d*255), LWA_ALPHA)`. Also need `WS_EX_LAYERED` set |
| `setBackgroundColor(c)` | `window.backgroundColor = ...` | Limited — Win32 windows draw their own background via WM_ERASEBKGND. For transparency, use `SetLayeredWindowAttributes` with colorkey or alpha. Document the limitations honestly |
| `setHasShadow(b)` | `window.hasShadow = b` | Frameless windows: `DwmExtendFrameIntoClientArea` with MARGINS{1} for shadow; MARGINS{0} no shadow |
| `setIcon(path)` | `NSApp.applicationIconImage = ...` | `SendMessage(hwnd, WM_SETICON, ICON_BIG, (LPARAM)hIcon)` after loading icon from file |

### Drag/resize

| API | macOS | Win32 |
|---|---|---|
| `startDrag()` | `window.performDrag(with: event)` | `ReleaseCapture(); SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);` |
| `startResize(direction)` | event monitor + manual frame math | `ReleaseCapture(); SendMessage(hwnd, WM_NCLBUTTONDOWN, HT* code, 0);` — use HTLEFT/HTRIGHT/HTTOP/etc. based on direction |

### Lifecycle

| API | macOS | Win32 |
|---|---|---|
| `close()` | `window.close()` (respects delegate) | `SendMessage(hwnd, WM_CLOSE, 0, 0)` |
| `destroy()` | `window.close(); orderOut` | `DestroyWindow(hwnd)` |
| `setPreventClose(b)` | flag — used in `windowShouldClose:` | flag — used in `WM_CLOSE` handler (return 0 = allow, anything else = prevent) |

### Multi-monitor

| API | macOS | Win32 |
|---|---|---|
| `displays.list()` | enumerate `NSScreen.screens` | `EnumDisplayMonitors(NULL, NULL, callback, lParam)` |
| `displays.getCurrent()` | `window.screen` | `MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST)` |
| `displays.getPrimary()` | `NSScreen.main` | `MonitorFromPoint({0,0}, MONITOR_DEFAULTTOPRIMARY)` |
| DisplayId (stable) | `CGDirectDisplayID` from `NSScreenNumber` | Device name from `MONITORINFOEX.szDevice` — HMONITOR itself is **NOT** stable across reconfigurations |
| Refresh rate | `CGDisplayCopyDisplayMode` | `EnumDisplaySettingsEx` with `ENUM_CURRENT_SETTINGS`, read `DEVMODE.dmDisplayFrequency` |
| Physical size | `CGDisplayScreenSize` | `EnumDisplayDevices` + `WMI` query (or `EDID` parsing — complex, may leave nullable) |

### Event coalescing (mirror macOS pattern)

Hook these messages in your subclass'd WndProc and emit
`onSnapshotChanged` (coalesced at 10ms via a timer):

- `WM_SIZE` → resize event
- `WM_MOVE` → move event
- `WM_ACTIVATE` (WA_ACTIVE / WA_INACTIVE) → focus event
- `WM_SIZE` with `SIZE_MAXIMIZED` / `SIZE_MINIMIZED` / `SIZE_RESTORED` → state event
- `WM_DPICHANGED` → display change event + recompute bounds
- `WM_DISPLAYCHANGE` → emit `onDisplaysChanged` with updated list
- `WM_CLOSE` → call `onCloseRequest` synchronously, respect the return value

Coalescing: use a `SetTimer(hwnd, COALESCE_TIMER_ID, 10, NULL)` pattern.
On each event, restart the timer. On `WM_TIMER` for that ID, build
snapshot and fire `onSnapshotChanged`, then `KillTimer`. This mirrors
the macOS `scheduleSnapshotEmit` rescheduling pattern.

---

## Step 4 — Subclass the Flutter Windows host window

Flutter Windows already owns the main HWND and runs its own WndProc. To
intercept messages without breaking Flutter:

```cpp
WNDPROC g_original_wnd_proc = nullptr;

LRESULT CALLBACK IcefelixWndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  // Handle our messages
  switch (msg) {
    case WM_GETMINMAXINFO: { /* clamp to min/max */ break; }
    case WM_SIZE: { /* fire snapshot change */ break; }
    case WM_CLOSE: { /* fire onCloseRequest */ break; }
    // ... etc
  }
  // Always fall through to original
  return CallWindowProc(g_original_wnd_proc, hwnd, msg, wp, lp);
}

// In plugin RegisterWithRegistrar:
HWND hwnd = GetAncestor(registrar->GetView()->GetNativeWindow(), GA_ROOT);
g_original_wnd_proc = reinterpret_cast<WNDPROC>(
    SetWindowLongPtr(hwnd, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(IcefelixWndProc)));
```

Always call `CallWindowProc` with the original at the end so Flutter
keeps working. This mirrors macOS's `ForwardingWindowDelegate` pattern.

---

## Step 5 — Port the example testbed

Copy `packages/icefelix_window_manager_macos/example/` to your package
(adjust the `pubspec.yaml` and `windows/` runner). The Flutter side
(`lib/main.dart`) is platform-agnostic — change only the `registerWith`
call to use your Windows class.

Verify every button in the testbed works:
- Bounds: center, setSize, setMinSize, setMaxSize
- State: minimize / maximize / unmaximize / restore / fullscreen
- Title + properties toggles
- Visual: opacity slider, bg color, frameless
- Multi-monitor: list, moveToDisplay
- Close interception: tick "preventClose" + "hasUnsavedChanges", try
  to close — must fire dialog

---

## Step 6 — Port the integration tests

Copy `packages/icefelix_window_manager_macos/example/integration_test/window_manager_integration_test.dart`
to your package's example. The 9 tests are platform-agnostic in their
assertions — they just call public APIs and wait for the snapshot. They
will reveal any bug.

Run them:

```powershell
cd packages\icefelix_window_manager_windows\example
flutter test integration_test\ -d windows
```

All 9 must pass. Add Windows-specific ones for things macOS doesn't
have (e.g. `WM_DPICHANGED` should emit a snapshot with the new
display's scale factor).

---

## Step 7 — Pana, dry-run, publish

```powershell
cd packages\icefelix_window_manager_windows
dart pub global run pana .
# Target ≥140/160

flutter pub publish --dry-run
# Resolve any warnings
```

Then follow the publish workflow in [`PORTING.md`](PORTING.md#publishing-workflow).
Order:
1. Publish `icefelix_window_manager_windows@0.1.0` first
2. Wait ~1 min for pub.dev indexing
3. Bump `icefelix_window_manager` to 0.2.0 with `platforms: windows:` added
4. Publish `icefelix_window_manager@0.2.0`

---

## Common Win32 pitfalls — read before starting

1. **DPI awareness must be Per-Monitor v2.** Otherwise sizes lie on
   multi-DPI setups.
2. **HMONITOR is not stable across display reconfigurations.** Use
   `MONITORINFOEX.szDevice` (the device name string) as your stable ID,
   the same way macOS uses `CGDirectDisplayID`.
3. **`SetForegroundWindow` can fail.** Windows restricts it for
   anti-focus-stealing. Use `AttachThreadInput` workaround only if you
   really need it; otherwise document the limitation.
4. **Layered windows can't accept opacity AND have full keyboard input
   on every Windows version.** Test on Windows 10 and 11 separately.
5. **Frameless + DwmExtendFrameIntoClientArea** is the modern shadow
   path. Don't try to draw your own shadow — it always looks wrong.
6. **`WS_EX_TOOLWINDOW` for setSkipTaskbar** also affects the
   Alt+Tab switcher behavior. Document the side effect.
7. **`SetWindowLongPtr(GWLP_WNDPROC)` must save the old proc and
   call it in a fallthrough.** If you forget, Flutter stops receiving
   input events and the app appears frozen.
8. **Frame vs client confusion** — Win32 distinguishes `GetWindowRect`
   (frame) from `GetClientRect` (content). We use **frame** everywhere
   (matches macOS). Don't mix.

---

## When to bump the schema (you probably shouldn't)

If you find a Windows-specific capability that doesn't fit the existing
schema (e.g. Windows has Aero Snap zones, taskbar progress bars, jump
lists), DO NOT add it to the shared schema. Either:

- Skip it for v0.2.0 and propose it as a v0.3.0 feature spec
- Add it as a platform-specific extension method on
  `IcefelixWindowManagerWindows` (the Dart subclass), separate from the
  abstract base

The schema is shared across all platforms. Bloat it carefully.

---

## Done-when checklist for v0.2.0

- [ ] All 42 HostApi methods implemented (no `unimplemented` placeholders)
- [ ] All 3 FlutterApi callbacks fire correctly (snapshot, displays, close)
- [ ] Example testbed runs and all 27 buttons produce visible/snapshot-confirmed change
- [ ] All 9 ported integration tests pass on Windows
- [ ] At least 2 Windows-specific integration tests added (e.g. WM_DPICHANGED, taskbar interaction)
- [ ] Pana score ≥140/160
- [ ] `flutter pub publish --dry-run` clean
- [ ] README updated to reflect Windows support
- [ ] CHANGELOG entry written
- [ ] PR opened, reviewed (or self-merged after manual audit)
- [ ] Tag v0.2.0 created and pushed
- [ ] Both packages (`_windows` and `icefelix_window_manager`) published to pub.dev
- [ ] GitHub Release v0.2.0 created with notes
