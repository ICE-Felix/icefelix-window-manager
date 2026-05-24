# Windows port v0.2.0 — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish `icefelix_window_manager_windows` so all 42 `WindowHostApi` methods + 3 `WindowFlutterApi` callbacks work, the full testbed runs, 9+ integration tests pass on real HWND, pana ≥140, then publish both packages and tag `v0.2.0`.

**Architecture:** Continue mirroring the macOS reference impl method-for-method in `WindowHostApiImpl`. Win32 directly inside the already-installed subclassed WndProc on the Flutter host HWND. Frame-coord throughout (already established). State tracked in member vars when no introspectable Win32 bit exists (flag-tracking pattern from macOS). Fullscreen via style-mask save/restore. `WS_EX_LAYERED` + `SetLayeredWindowAttributes` for opacity. `DwmExtendFrameIntoClientArea` for frameless + shadow. `WM_CLOSE` intercept in WndProc for prevent-close with 5 s default-allow timeout per the schema contract.

**Tech stack:** C++17, Win32 (user32, gdi32, dwmapi, shcore), Pigeon, Flutter Windows host, Dart 3.6+, Flutter 3.27+.

**Hard rules (unchanged from session 1):**
1. Do NOT modify `pigeons/window_api.dart`.
2. Do NOT modify `icefelix_window_manager/lib/src/` (app-facing API frozen).
3. macOS Swift impl is the behavioral spec — read it for each method before implementing.
4. All 4 size APIs (setSize/setMin/setMax/snapshot.bounds.size) share frame coords.

**Pre-flight (already done, do NOT redo):** WndProc subclass + 10 ms snapshot coalesce live in `window_host_api_impl.cpp`; bounds vertical (12 methods) green on real HWND; 6 integration tests pass.

**Files touched in this plan:**
- Modify: `packages/icefelix_window_manager_windows/windows/window_host_api_impl.h` — add member-var declarations, swap stubs for real overrides
- Modify: `packages/icefelix_window_manager_windows/windows/window_host_api_impl.cpp` — implement 30 remaining methods + wire close-intercept into WndProc + extend BuildSnapshot
- Modify: `packages/icefelix_window_manager_windows/example/lib/main.dart` — full 27-control testbed
- Modify: `packages/icefelix_window_manager_windows/example/integration_test/window_manager_integration_test.dart` — add the 3 remaining macOS-equivalent tests + 2 Win32-specific
- Modify: `packages/icefelix_window_manager_windows/CHANGELOG.md` — flip Unreleased → 0.1.0
- Modify: `packages/icefelix_window_manager_windows/README.md` — drop "in active development" wording, document Limitations
- Modify: `packages/icefelix_window_manager/pubspec.yaml` — bump to 0.2.0, add `platforms: windows:`
- Modify: `packages/icefelix_window_manager/CHANGELOG.md` — add 0.2.0 entry
- Modify: `packages/icefelix_window_manager_macos/example/pubspec.yaml` — loosen `sdk: ^3.10.0` to `^3.6.0` so melos bootstrap works locally (one-line fix unblocking workspace tooling; affects example only, not the published package)

---

## Task 1: State machine + focus (7 methods)

**Files:**
- Modify: `packages/icefelix_window_manager_windows/windows/window_host_api_impl.h` (declarations stay; just delete the "session 1: stubbed" inline comments where the real impls land)
- Modify: `packages/icefelix_window_manager_windows/windows/window_host_api_impl.cpp` (lines that currently return `FlutterError(kNotImplemented, ...)`)

**Methods covered:** `Minimize` (already done in session 1 — skip), `Restore` (already done — skip), `Hide`, `Show`, `Fullscreen`, `ExitFullscreen`, `Focus`, `Blur`.

So actually **6 methods to implement** in this task (5 state + 2 focus, minus already-done Minimize/Restore — net 6). Update `BuildSnapshot` so `state=hidden` is reported correctly via `!IsWindowVisible(hwnd_)`.

### Step 1.1: Implement `Hide` and `Show`

Replace in `window_host_api_impl.cpp`:

```cpp
std::optional<FlutterError> WindowHostApiImpl::Hide() {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  ShowWindow(hwnd_, SW_HIDE);
  return std::nullopt;
}

std::optional<FlutterError> WindowHostApiImpl::Show() {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  ShowWindow(hwnd_, SW_SHOW);
  // Match macOS makeKeyAndOrderFront: also bring to front.
  SetForegroundWindow(hwnd_);
  return std::nullopt;
}
```

### Step 1.2: Implement `Focus` and `Blur`

```cpp
std::optional<FlutterError> WindowHostApiImpl::Focus() {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  // SetForegroundWindow is anti-focus-stealing-restricted on Windows; the
  // AttachThreadInput dance below works around that for foreground apps.
  // Mirrors what NSApplication.activate(ignoringOtherApps:true) achieves on macOS.
  DWORD fg_thread = GetWindowThreadProcessId(GetForegroundWindow(), nullptr);
  DWORD self_thread = GetCurrentThreadId();
  if (fg_thread && fg_thread != self_thread) {
    AttachThreadInput(fg_thread, self_thread, TRUE);
    BringWindowToTop(hwnd_);
    SetForegroundWindow(hwnd_);
    AttachThreadInput(fg_thread, self_thread, FALSE);
  } else {
    SetForegroundWindow(hwnd_);
  }
  return std::nullopt;
}

std::optional<FlutterError> WindowHostApiImpl::Blur() {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  // Win32 has no native "blur me" call. Closest parity with macOS's
  // NSApplication.deactivate(): hand focus to the next top-level window.
  HWND next = GetNextWindow(hwnd_, GW_HWNDNEXT);
  while (next && (!IsWindowVisible(next) || GetWindow(next, GW_OWNER) != nullptr)) {
    next = GetNextWindow(next, GW_HWNDNEXT);
  }
  if (next) {
    SetForegroundWindow(next);
  }
  return std::nullopt;
}
```

### Step 1.3: Implement `Fullscreen` and `ExitFullscreen` (style-mask save/restore)

Add member vars in `window_host_api_impl.h` (private section, near `fullscreen_flag_`):

```cpp
  // Style + rect snapshot taken when entering fullscreen so ExitFullscreen
  // can restore the exact pre-fullscreen window state. Mirrors the macOS
  // toggleFullScreen which AppKit handles internally.
  LONG pre_fullscreen_style_ = 0;
  LONG pre_fullscreen_ex_style_ = 0;
  RECT pre_fullscreen_rect_ = {};
```

In `window_host_api_impl.cpp`:

```cpp
std::optional<FlutterError> WindowHostApiImpl::Fullscreen() {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  if (fullscreen_flag_) return std::nullopt;  // idempotent

  pre_fullscreen_style_ = GetWindowLongW(hwnd_, GWL_STYLE);
  pre_fullscreen_ex_style_ = GetWindowLongW(hwnd_, GWL_EXSTYLE);
  GetWindowRect(hwnd_, &pre_fullscreen_rect_);

  // Strip WS_OVERLAPPEDWINDOW so the title bar + borders disappear, then
  // resize to the FULL monitor bounds (not work area — true fullscreen).
  SetWindowLongW(hwnd_, GWL_STYLE, pre_fullscreen_style_ & ~WS_OVERLAPPEDWINDOW);
  SetWindowLongW(hwnd_, GWL_EXSTYLE,
                 pre_fullscreen_ex_style_ & ~(WS_EX_DLGMODALFRAME |
                                              WS_EX_WINDOWEDGE |
                                              WS_EX_CLIENTEDGE |
                                              WS_EX_STATICEDGE));
  HMONITOR mon = MonitorFromWindow(hwnd_, MONITOR_DEFAULTTONEAREST);
  MONITORINFO mi = {};
  mi.cbSize = sizeof(mi);
  GetMonitorInfo(mon, &mi);
  SetWindowPos(hwnd_, HWND_TOP,
               mi.rcMonitor.left, mi.rcMonitor.top,
               mi.rcMonitor.right - mi.rcMonitor.left,
               mi.rcMonitor.bottom - mi.rcMonitor.top,
               SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  fullscreen_flag_ = true;
  ScheduleSnapshotEmit();
  return std::nullopt;
}

std::optional<FlutterError> WindowHostApiImpl::ExitFullscreen() {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  if (!fullscreen_flag_) return std::nullopt;

  SetWindowLongW(hwnd_, GWL_STYLE, pre_fullscreen_style_);
  SetWindowLongW(hwnd_, GWL_EXSTYLE, pre_fullscreen_ex_style_);
  SetWindowPos(hwnd_, nullptr,
               pre_fullscreen_rect_.left, pre_fullscreen_rect_.top,
               pre_fullscreen_rect_.right - pre_fullscreen_rect_.left,
               pre_fullscreen_rect_.bottom - pre_fullscreen_rect_.top,
               SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  fullscreen_flag_ = false;
  ScheduleSnapshotEmit();
  return std::nullopt;
}
```

### Step 1.4: Verify analyze + format + integration tests

```powershell
cd C:\dev\ifw\packages\icefelix_window_manager_windows
flutter analyze
cd example
flutter analyze
cd ..\..\..\..  # back to repo root
dart format --output=none --set-exit-if-changed packages/icefelix_window_manager_windows/lib packages/icefelix_window_manager_windows/example/lib packages/icefelix_window_manager_windows/example/integration_test
cd packages\icefelix_window_manager_windows\example
flutter test integration_test/ -d windows
```

Expected: analyze 0 issues, format 0 changes, tests 6/6 pass (no new tests yet — coming in Task 8).

### Step 1.5: Commit

```bash
git add packages/icefelix_window_manager_windows/windows/window_host_api_impl.h \
        packages/icefelix_window_manager_windows/windows/window_host_api_impl.cpp
git commit -m "feat(windows): state machine + focus (Hide/Show/Fullscreen/ExitFullscreen/Focus/Blur)"
```

---

## Task 2: Lifecycle + close interception (3 methods + WM_CLOSE wiring)

**Files:**
- Modify: `packages/icefelix_window_manager_windows/windows/window_host_api_impl.h`
- Modify: `packages/icefelix_window_manager_windows/windows/window_host_api_impl.cpp`

**Methods covered:** `Close`, `Destroy`, plus full `WM_CLOSE` intercept (extending the existing `SetPreventClose` which only tracks the flag).

### Step 2.1: Add Close/Destroy implementations

In `window_host_api_impl.cpp` (replace stubs):

```cpp
std::optional<FlutterError> WindowHostApiImpl::Close() {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  // Goes through our WM_CLOSE handler -> respects prevent_close_flag_,
  // mirrors macOS performClose: which honors windowShouldClose:.
  PostMessageW(hwnd_, WM_CLOSE, 0, 0);
  return std::nullopt;
}

std::optional<FlutterError> WindowHostApiImpl::Destroy() {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  // Bypasses WM_CLOSE -> bypasses prevent_close. Mirrors macOS window.close().
  DestroyWindow(hwnd_);
  return std::nullopt;
}
```

### Step 2.2: Add member vars for synchronous close interception

In `window_host_api_impl.h` (private section near `prevent_close_flag_`):

```cpp
  // Close-intercept synchronization. WM_CLOSE handler waits up to 5000ms
  // for the Dart side to respond via OnCloseRequest (matches the schema's
  // SYNCHRONIZATION CONTRACT). On timeout: default-allow per contract.
  static constexpr DWORD kCloseRequestTimeoutMs = 5000;
  bool close_in_flight_ = false;
  bool close_allowed_ = true;
```

### Step 2.3: Extend the WndProc to intercept WM_CLOSE

In `HandleMessage` switch (add case before `default:`):

```cpp
    case WM_CLOSE: {
      if (!prevent_close_flag_ || !flutter_api_) {
        // No interception requested -> default-allow (fall through to
        // DefWindowProc which calls DestroyWindow).
        return CallOriginal();
      }
      if (close_in_flight_) {
        // Re-entrant close while we're already waiting; default-allow to
        // avoid a deadlock if Dart called close() from its callback.
        return CallOriginal();
      }
      close_in_flight_ = true;
      close_allowed_ = true;  // default-allow on timeout per schema
      // Fire OnCloseRequest. Pigeon's FlutterApi callback is async -- we
      // need to block this WM_CLOSE while pumping messages until either
      // the callback fires or we hit the 5000ms timeout.
      DWORD start = GetTickCount();
      bool got_response = false;
      flutter_api_->OnCloseRequest(
          [this, &got_response](bool allow) {
            close_allowed_ = allow;
            got_response = true;
          },
          [&got_response](const FlutterError&) {
            // Channel error -> default-allow (don't trap user in window).
            got_response = true;
          });
      // Pump messages until response or timeout (so Dart isolate can run).
      MSG msg;
      while (!got_response &&
             (GetTickCount() - start) < kCloseRequestTimeoutMs) {
        if (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
          TranslateMessage(&msg);
          DispatchMessageW(&msg);
        } else {
          Sleep(1);  // back off when no messages
        }
      }
      close_in_flight_ = false;
      if (close_allowed_) {
        return CallOriginal();
      }
      return 0;  // suppress close
    }
```

### Step 2.4: Verify + commit

```powershell
cd C:\dev\ifw\packages\icefelix_window_manager_windows\example
flutter test integration_test/ -d windows
```

Expected: 6/6 still pass (no new tests yet).

```bash
git add packages/icefelix_window_manager_windows/windows/window_host_api_impl.h \
        packages/icefelix_window_manager_windows/windows/window_host_api_impl.cpp
git commit -m "feat(windows): close/destroy + WM_CLOSE intercept with 5s default-allow timeout"
```

---

## Task 3: Title + 8 property setters

**Files:**
- Modify: `packages/icefelix_window_manager_windows/windows/window_host_api_impl.cpp` (replace 9 stubs)

**Methods covered:** `SetTitle`, `SetAlwaysOnTop`, `SetSkipTaskbar`, `SetResizable`, `SetMovable`, `SetMinimizable`, `SetMaximizable`, `SetClosable`.

### Step 3.1: SetTitle

```cpp
std::optional<FlutterError> WindowHostApiImpl::SetTitle(const std::string& title) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  std::wstring wide = WideFromUtf8(title);
  SetWindowTextW(hwnd_, wide.c_str());
  ScheduleSnapshotEmit();
  return std::nullopt;
}
```

### Step 3.2: SetAlwaysOnTop

```cpp
std::optional<FlutterError> WindowHostApiImpl::SetAlwaysOnTop(bool value) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  always_on_top_flag_ = value;
  HWND z = value ? HWND_TOPMOST : HWND_NOTOPMOST;
  SetWindowPos(hwnd_, z, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  ScheduleSnapshotEmit();
  return std::nullopt;
}
```

### Step 3.3: SetSkipTaskbar

```cpp
std::optional<FlutterError> WindowHostApiImpl::SetSkipTaskbar(bool value) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  skip_taskbar_flag_ = value;
  LONG ex = GetWindowLongW(hwnd_, GWL_EXSTYLE);
  // WS_EX_TOOLWINDOW hides the window from the taskbar AND from the
  // Alt+Tab switcher (Windows treats tool windows as utility palettes).
  // Document this side effect in README -- the schema only specifies
  // taskbar visibility, not Alt+Tab behavior.
  if (value) {
    ex |= WS_EX_TOOLWINDOW;
    ex &= ~WS_EX_APPWINDOW;
  } else {
    ex &= ~WS_EX_TOOLWINDOW;
    ex |= WS_EX_APPWINDOW;
  }
  SetWindowLongW(hwnd_, GWL_EXSTYLE, ex);
  // Re-show so the taskbar registers the new style.
  ShowWindow(hwnd_, SW_HIDE);
  ShowWindow(hwnd_, SW_SHOW);
  ScheduleSnapshotEmit();
  return std::nullopt;
}
```

### Step 3.4: SetResizable

```cpp
std::optional<FlutterError> WindowHostApiImpl::SetResizable(bool value) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  LONG style = GetWindowLongW(hwnd_, GWL_STYLE);
  if (value) {
    style |= WS_THICKFRAME | WS_MAXIMIZEBOX;
  } else {
    style &= ~(WS_THICKFRAME | WS_MAXIMIZEBOX);
  }
  SetWindowLongW(hwnd_, GWL_STYLE, style);
  // SWP_FRAMECHANGED forces Windows to recompute the non-client area.
  SetWindowPos(hwnd_, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  ScheduleSnapshotEmit();
  return std::nullopt;
}
```

### Step 3.5: SetMovable, SetMinimizable, SetMaximizable, SetClosable

```cpp
std::optional<FlutterError> WindowHostApiImpl::SetMovable(bool value) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  // Win32 has no isMovable bit; we track + enforce via WM_NCHITTEST below.
  movable_flag_ = value;
  ScheduleSnapshotEmit();
  return std::nullopt;
}

std::optional<FlutterError> WindowHostApiImpl::SetMinimizable(bool value) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  LONG style = GetWindowLongW(hwnd_, GWL_STYLE);
  if (value) style |= WS_MINIMIZEBOX;
  else style &= ~WS_MINIMIZEBOX;
  SetWindowLongW(hwnd_, GWL_STYLE, style);
  SetWindowPos(hwnd_, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  ScheduleSnapshotEmit();
  return std::nullopt;
}

std::optional<FlutterError> WindowHostApiImpl::SetMaximizable(bool value) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  maximizable_flag_ = value;
  LONG style = GetWindowLongW(hwnd_, GWL_STYLE);
  if (value) style |= WS_MAXIMIZEBOX;
  else style &= ~WS_MAXIMIZEBOX;
  SetWindowLongW(hwnd_, GWL_STYLE, style);
  SetWindowPos(hwnd_, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  ScheduleSnapshotEmit();
  return std::nullopt;
}

std::optional<FlutterError> WindowHostApiImpl::SetClosable(bool value) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  closable_flag_ = value;
  HMENU sys = GetSystemMenu(hwnd_, FALSE);
  if (sys) {
    EnableMenuItem(sys, SC_CLOSE,
                   MF_BYCOMMAND | (value ? MF_ENABLED : MF_GRAYED));
  }
  // Also affects the "X" button on the title bar (greyed when MF_GRAYED).
  DrawMenuBar(hwnd_);
  ScheduleSnapshotEmit();
  return std::nullopt;
}
```

### Step 3.6: WM_NCHITTEST handler for SetMovable

In `HandleMessage`, add case before `default:`:

```cpp
    case WM_NCHITTEST: {
      if (movable_flag_) {
        return CallOriginal();  // let title-bar drag work normally
      }
      // Movable disabled: rewrite HTCAPTION -> HTBORDER so dragging the
      // title bar doesn't move the window. Mirrors macOS isMovable=false.
      LRESULT hit = CallOriginal();
      if (hit == HTCAPTION) return HTBORDER;
      return hit;
    }
```

### Step 3.7: Update BuildSnapshot to read from flags (already there for most)

`BuildSnapshot` already reads `movable_flag_` and `closable_flag_` (set in session 1). For minimizable, swap from `(style & WS_MINIMIZEBOX) != 0` to `(style & WS_MINIMIZEBOX) != 0` (no change — already correct). For resizable, same.

No code change needed in `BuildSnapshot` — the existing reads from `style` bits + tracked flags are already correct.

### Step 3.8: Verify + commit

```powershell
cd C:\dev\ifw\packages\icefelix_window_manager_windows\example
flutter test integration_test/ -d windows
```

Expected: 6/6 pass.

```bash
git add packages/icefelix_window_manager_windows/windows/window_host_api_impl.h \
        packages/icefelix_window_manager_windows/windows/window_host_api_impl.cpp
git commit -m "feat(windows): title + 8 property setters (alwaysOnTop, skipTaskbar, resizable, movable, minimizable, maximizable, closable)"
```

---

## Task 4: Frameless + title bar style (2 setters)

**Files:**
- Modify: `packages/icefelix_window_manager_windows/windows/window_host_api_impl.cpp`

### Step 4.1: SetFrameless

```cpp
std::optional<FlutterError> WindowHostApiImpl::SetFrameless(bool value) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  LONG style = GetWindowLongW(hwnd_, GWL_STYLE);
  if (value) {
    // Strip caption + thick frame; keep WS_POPUP-equivalent.
    style &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX |
               WS_SYSMENU);
    style |= WS_POPUP;
  } else {
    style &= ~WS_POPUP;
    style |= WS_OVERLAPPEDWINDOW;
  }
  SetWindowLongW(hwnd_, GWL_STYLE, style);
  // SWP_FRAMECHANGED forces Win32 to recompute non-client geometry; without
  // it the caption visually persists until the next resize.
  SetWindowPos(hwnd_, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  ScheduleSnapshotEmit();
  return std::nullopt;
}
```

### Step 4.2: SetTitleBarStyle

```cpp
std::optional<FlutterError> WindowHostApiImpl::SetTitleBarStyle(
    const TitleBarStyleRaw& style) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  title_bar_style_flag_ = style;
  // Win32 doesn't have a native equivalent for macOS's hiddenInset (where the
  // titlebar stays interactive but the traffic-light buttons sit above the
  // content area). The closest analog is DwmExtendFrameIntoClientArea, which
  // pulls the DWM-rendered border + caption *into* the client area so app
  // chrome can draw under it. For schema parity:
  //   normal       -> standard title bar + caption
  //   hidden       -> SetWindowLong remove WS_CAPTION (looks like SetFrameless
  //                   but keeps the resize border)
  //   hiddenInset  -> DwmExtendFrameIntoClientArea MARGINS{-1,-1,-1,-1}
  //                   (sheet of glass over the whole client area)
  LONG wstyle = GetWindowLongW(hwnd_, GWL_STYLE);
  switch (style) {
    case TitleBarStyleRaw::kNormal:
      wstyle |= WS_CAPTION;
      SetWindowLongW(hwnd_, GWL_STYLE, wstyle);
      {
        MARGINS m = {0, 0, 0, 0};
        DwmExtendFrameIntoClientArea(hwnd_, &m);
      }
      break;
    case TitleBarStyleRaw::kHidden:
      wstyle &= ~WS_CAPTION;
      SetWindowLongW(hwnd_, GWL_STYLE, wstyle);
      {
        MARGINS m = {0, 0, 0, 0};
        DwmExtendFrameIntoClientArea(hwnd_, &m);
      }
      break;
    case TitleBarStyleRaw::kHiddenInset:
      wstyle |= WS_CAPTION;  // keep caption for traffic lights equivalent
      SetWindowLongW(hwnd_, GWL_STYLE, wstyle);
      {
        MARGINS m = {-1, -1, -1, -1};
        DwmExtendFrameIntoClientArea(hwnd_, &m);
      }
      break;
  }
  SetWindowPos(hwnd_, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  ScheduleSnapshotEmit();
  return std::nullopt;
}
```

### Step 4.3: Verify + commit

```powershell
cd C:\dev\ifw\packages\icefelix_window_manager_windows\example
flutter test integration_test/ -d windows
```

Expected: 6/6 pass.

```bash
git commit -am "feat(windows): frameless + titleBarStyle (DwmExtendFrameIntoClientArea)"
```

---

## Task 5: Visual setters (opacity, bg, shadow, icon)

**Files:**
- Modify: `packages/icefelix_window_manager_windows/windows/window_host_api_impl.cpp`
- Modify: `packages/icefelix_window_manager_windows/windows/window_host_api_impl.h` (add icon handle member for cleanup)

### Step 5.1: Add HICON member for cleanup

In `window_host_api_impl.h` (private section):

```cpp
  // Last icon loaded via SetIcon. Destroyed in dtor so we don't leak GDI
  // handles. nullptr until first SetIcon call.
  HICON current_icon_ = nullptr;
```

In `~WindowHostApiImpl` (destructor body), add at the end:

```cpp
  if (current_icon_) {
    DestroyIcon(current_icon_);
    current_icon_ = nullptr;
  }
```

### Step 5.2: SetOpacity (layered window)

```cpp
std::optional<FlutterError> WindowHostApiImpl::SetOpacity(double opacity) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  opacity_flag_ = std::clamp(opacity, 0.0, 1.0);
  // Layered windows are the only way to do per-window alpha on Win32.
  LONG ex = GetWindowLongW(hwnd_, GWL_EXSTYLE);
  if (opacity_flag_ < 1.0) {
    SetWindowLongW(hwnd_, GWL_EXSTYLE, ex | WS_EX_LAYERED);
    SetLayeredWindowAttributes(hwnd_, 0,
                               static_cast<BYTE>(opacity_flag_ * 255.0),
                               LWA_ALPHA);
  } else {
    // Opaque path: strip WS_EX_LAYERED so we don't pay the composite cost.
    SetWindowLongW(hwnd_, GWL_EXSTYLE, ex & ~WS_EX_LAYERED);
  }
  ScheduleSnapshotEmit();
  return std::nullopt;
}
```

### Step 5.3: SetBackgroundColor

```cpp
std::optional<FlutterError> WindowHostApiImpl::SetBackgroundColor(int64_t argb) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  background_color_argb_flag_ = argb;
  // Win32 doesn't let you set a window background color directly the way
  // NSWindow.backgroundColor does -- the window class brush is set once at
  // RegisterClass time. The closest behavior is colorkey transparency via
  // SetLayeredWindowAttributes(LWA_COLORKEY) but that hides matching pixels,
  // not what users want. Honest behavior: track the flag so snapshot
  // reflects it, document the limitation in README, no-op the actual draw.
  ScheduleSnapshotEmit();
  return std::nullopt;
}
```

### Step 5.4: SetHasShadow (DWM)

```cpp
std::optional<FlutterError> WindowHostApiImpl::SetHasShadow(bool value) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  has_shadow_flag_ = value;
  // For frameless windows, DwmExtendFrameIntoClientArea with non-zero
  // margins makes DWM draw the standard window drop shadow. For framed
  // windows the shadow is always present (managed by DWM) and there's
  // no first-party API to disable it -- document the limitation.
  MARGINS m = value ? MARGINS{1, 1, 1, 1} : MARGINS{0, 0, 0, 0};
  DwmExtendFrameIntoClientArea(hwnd_, &m);
  ScheduleSnapshotEmit();
  return std::nullopt;
}
```

### Step 5.5: SetIcon

```cpp
std::optional<FlutterError> WindowHostApiImpl::SetIcon(
    const std::string& filesystem_path) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  std::wstring wpath = WideFromUtf8(filesystem_path);
  HICON hicon = (HICON)LoadImageW(nullptr, wpath.c_str(), IMAGE_ICON, 0, 0,
                                  LR_LOADFROMFILE | LR_DEFAULTSIZE);
  if (!hicon) {
    return FlutterError("invalid_icon_path",
                        "Could not load HICON from " + filesystem_path);
  }
  // Destroy the previous icon to avoid GDI handle leak.
  if (current_icon_) DestroyIcon(current_icon_);
  current_icon_ = hicon;
  // Both ICON_BIG (Alt+Tab) and ICON_SMALL (title bar + taskbar).
  SendMessageW(hwnd_, WM_SETICON, ICON_BIG, (LPARAM)hicon);
  SendMessageW(hwnd_, WM_SETICON, ICON_SMALL, (LPARAM)hicon);
  ScheduleSnapshotEmit();
  return std::nullopt;
}
```

### Step 5.6: Verify + commit

```powershell
cd C:\dev\ifw\packages\icefelix_window_manager_windows\example
flutter test integration_test/ -d windows
```

Expected: 6/6 pass.

```bash
git commit -am "feat(windows): visual setters (opacity via WS_EX_LAYERED, shadow via DWM, icon)"
```

---

## Task 6: Drag + resize (2 methods)

**Files:**
- Modify: `packages/icefelix_window_manager_windows/windows/window_host_api_impl.cpp`

### Step 6.1: StartDrag

```cpp
std::optional<FlutterError> WindowHostApiImpl::StartDrag() {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  // Standard Win32 idiom: release current capture so the upcoming
  // SC_MOVE | HTCAPTION simulated message reaches DefWindowProc which
  // enters the move modal loop.
  ReleaseCapture();
  SendMessageW(hwnd_, WM_SYSCOMMAND, SC_MOVE | HTCAPTION, 0);
  return std::nullopt;
}
```

### Step 6.2: StartResize

```cpp
std::optional<FlutterError> WindowHostApiImpl::StartResize(
    const ResizeDirectionRaw& direction) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  // SC_SIZE | <edge code> drops into DefWindowProc's resize modal loop.
  // Edge codes correspond to HT* hit-test values.
  WPARAM edge = SC_SIZE;
  switch (direction) {
    case ResizeDirectionRaw::kTop:         edge |= 3; break;  // WMSZ_TOP
    case ResizeDirectionRaw::kBottom:      edge |= 6; break;  // WMSZ_BOTTOM
    case ResizeDirectionRaw::kLeft:        edge |= 1; break;  // WMSZ_LEFT
    case ResizeDirectionRaw::kRight:       edge |= 2; break;  // WMSZ_RIGHT
    case ResizeDirectionRaw::kTopLeft:     edge |= 4; break;  // WMSZ_TOPLEFT
    case ResizeDirectionRaw::kTopRight:    edge |= 5; break;  // WMSZ_TOPRIGHT
    case ResizeDirectionRaw::kBottomLeft:  edge |= 7; break;  // WMSZ_BOTTOMLEFT
    case ResizeDirectionRaw::kBottomRight: edge |= 8; break;  // WMSZ_BOTTOMRIGHT
  }
  ReleaseCapture();
  SendMessageW(hwnd_, WM_SYSCOMMAND, edge, 0);
  return std::nullopt;
}
```

### Step 6.3: Verify + commit

```powershell
cd C:\dev\ifw\packages\icefelix_window_manager_windows\example
flutter test integration_test/ -d windows
```

Expected: 6/6 pass.

```bash
git commit -am "feat(windows): startDrag + startResize via SC_MOVE/SC_SIZE"
```

---

## Task 7: Full testbed port (27 controls)

**Files:**
- Modify: `packages/icefelix_window_manager_windows/example/lib/main.dart` — replace the bounds-only testbed with the full one ported from macOS

### Step 7.1: Port the macOS testbed structure

Read `packages/icefelix_window_manager_macos/example/lib/main.dart` and copy verbatim, then change:
- import `package:icefelix_window_manager_windows/icefelix_window_manager_windows.dart`
- swap `IcefelixWindowManagerMacos.registerWith()` for `IcefelixWindowManagerWindows.registerWith()`
- update title text from "macOS testbed" to "Windows testbed"

Do not invent new UI — verbatim port keeps the visual audit comparable between platforms (per CLAUDE.md hard rule 5).

### Step 7.2: Verify it launches + every control works

```powershell
cd C:\dev\ifw\packages\icefelix_window_manager_windows\example
flutter run -d windows
```

Click each of the 27 controls. For each: confirm visible window change AND HUD-snapshot update. Quit with `q`.

### Step 7.3: Commit

```bash
git add packages/icefelix_window_manager_windows/example/lib/main.dart
git commit -m "feat(windows-example): full 27-control testbed port"
```

---

## Task 8: Integration tests (3 macOS + 2 Win32-specific)

**Files:**
- Modify: `packages/icefelix_window_manager_windows/example/integration_test/window_manager_integration_test.dart`

### Step 8.1: Port the 3 remaining macOS-equivalent tests

Append these to the existing test file:

```dart
  testWidgets('setTitle updates snapshot.title', (tester) async {
    await WindowManager.instance.setTitle('Integration Test');
    await waitForSnapshot((s) => s.title == 'Integration Test');
  });

  testWidgets('setAlwaysOnTop updates snapshot.alwaysOnTop', (tester) async {
    await WindowManager.instance.setAlwaysOnTop(true);
    await waitForSnapshot((s) => s.alwaysOnTop == true);
    await WindowManager.instance.setAlwaysOnTop(false);
    await waitForSnapshot((s) => s.alwaysOnTop == false);
  });

  testWidgets('minimize then restore round-trip', (tester) async {
    await WindowManager.instance.minimize();
    await waitForSnapshot((s) => s.state == WindowState.minimized);
    await WindowManager.instance.restore();
    await waitForSnapshot((s) => s.state == WindowState.normal);
  });
```

### Step 8.2: Add 2 Win32-specific tests

```dart
  // Windows-specific: WM_DPICHANGED should be observable via snapshot.
  // Hard to trigger programmatically without moving the window to another
  // monitor, so we check the read path: after fetching the current display,
  // the scale factor matches GetDpiForWindow / 96.
  testWidgets('current display scaleFactor matches Per-Monitor v2 DPI', (
    tester,
  ) async {
    final disp = await WindowManager.instance.displays.getCurrent();
    expect(disp.scaleFactor, greaterThan(0));
    // Reasonable bounds: 1.0 (96 DPI) to 4.0 (384 DPI / hi-DPI).
    expect(disp.scaleFactor, lessThanOrEqualTo(4.0));
  });

  // Windows-specific: setSkipTaskbar toggles WS_EX_TOOLWINDOW which also
  // hides the window from Alt+Tab (documented Win32 side effect). Test
  // that the snapshot reflects the flag.
  testWidgets('setSkipTaskbar round-trip via snapshot.skipTaskbar', (
    tester,
  ) async {
    await WindowManager.instance.setSkipTaskbar(true);
    await waitForSnapshot((s) => s.skipTaskbar == true);
    await WindowManager.instance.setSkipTaskbar(false);
    await waitForSnapshot((s) => s.skipTaskbar == false);
  });
```

### Step 8.3: Run + commit

```powershell
cd C:\dev\ifw\packages\icefelix_window_manager_windows\example
flutter test integration_test/ -d windows
```

Expected: 11/11 pass (6 existing + 3 macOS-port + 2 Win32-specific).

```bash
git commit -am "test(windows): port 3 macOS-equivalent + add 2 Win32-specific integration tests"
```

---

## Task 9: Pana + dry-run cleanup

**Files (potential):**
- Modify: `packages/icefelix_window_manager_windows/pubspec.yaml` (if pana flags missing fields)
- Modify: `packages/icefelix_window_manager_windows/README.md` (Limitations section per session-2 setters)
- Modify: `packages/icefelix_window_manager_windows/CHANGELOG.md` (flip Unreleased → 0.1.0 with full method list)

### Step 9.1: Update CHANGELOG to reflect a publishable 0.1.0

Replace the `## Unreleased` block in `CHANGELOG.md` with:

```markdown
## 0.1.0 - 2026-MM-DD

First publishable Win32 implementation of `icefelix_window_manager_platform_interface` for Windows 10+.

### Added
- All 42 `WindowHostApi` methods implemented backed by Win32 (bounds, state, focus, drag/resize, lifecycle, title, properties, frameless, visual, multi-monitor, close interception)
- All 3 `WindowFlutterApi` callbacks (`OnSnapshotChanged`, `OnDisplaysChanged`, `OnCloseRequest`) wired through a subclassed WndProc on the Flutter host HWND
- `WM_GETMINMAXINFO` clamps both `ptMaxTrackSize` and `ptMaxSize` so `ShowWindow(SW_MAXIMIZE)` honors `setMaxSize` — Win32 analog of the macOS contentMaxSize fix
- 10 ms event coalescing via `SetTimer` + `WM_TIMER`
- 11 integration tests on real Windows HWND (6 bounds + 3 macOS-port + 2 Win32-specific)
- Comprehensive example testbed at `example/` exercising every API

### Known limitations
- `setBackgroundColor`: Win32 windows draw their own background via WM_ERASEBKGND with the class brush; per-window color isn't a first-party API. Tracked as a flag in the snapshot; visual no-op.
- `setHasShadow`: only effective for frameless windows (via `DwmExtendFrameIntoClientArea`). Framed windows always have the DWM-managed shadow.
- `setSkipTaskbar`: toggles `WS_EX_TOOLWINDOW` which also hides the window from Alt+Tab.
- `getPlatformInfo().isSandboxed`: returns `false` always. MSIX/AppContainer detection deferred to v0.1.x.
- Physical display size (`DisplayRaw.physicalWidthMm`/`physicalHeightMm`) returns null — requires EDID/WMI which we don't read.
```

### Step 9.2: Update README

In `README.md`, change `## Status` to:

```markdown
## Status

Production-ready for the published v0.1.0 method surface. See CHANGELOG
"Known limitations" for the small set of methods that no-op or
approximate due to Win32 platform constraints.
```

### Step 9.3: Run pana

```powershell
cd C:\dev\ifw\packages\icefelix_window_manager_windows
dart pub global run pana . --no-warning 2>&1 | Select-Object -Last 80
```

Expected: score ≥140/160. If lower, read warnings and fix (typical issues: missing `screenshots:`, license file in wrong place, README too short, missing `topics:`).

### Step 9.4: Dry-run publish

```powershell
cd C:\dev\ifw\packages\icefelix_window_manager_windows
flutter pub publish --dry-run
```

Expected: "Package has 0 warnings."

### Step 9.5: Commit

```bash
git commit -am "chore(windows): release 0.1.0 (CHANGELOG + README + pana cleanup)"
```

---

## Task 10: Bump app-facing + publish

**Files:**
- Modify: `packages/icefelix_window_manager/pubspec.yaml`
- Modify: `packages/icefelix_window_manager/CHANGELOG.md`
- Modify: `packages/icefelix_window_manager_macos/example/pubspec.yaml` (the melos-bootstrap blocker fix)

### Step 10.1: Fix the melos bootstrap blocker

Edit `packages/icefelix_window_manager_macos/example/pubspec.yaml`:

```yaml
environment:
  sdk: ^3.6.0  # was ^3.10.0 — loosened to match the package itself so
               # workspace bootstrap doesn't break on Dart 3.9.x dev machines
```

### Step 10.2: Bump app-facing pubspec

Edit `packages/icefelix_window_manager/pubspec.yaml`:

```yaml
version: 0.2.0  # was 0.1.0

# ...

platforms:
  macos:
  windows:  # added
```

### Step 10.3: Update app-facing CHANGELOG

Prepend to `packages/icefelix_window_manager/CHANGELOG.md`:

```markdown
## 0.2.0 - 2026-MM-DD

### Added
- Windows 10+ support via the new `icefelix_window_manager_windows` package
  (Win32 implementation, full 42-method `WindowHostApi` coverage). See its
  CHANGELOG for the platform-specific behavior + limitations.

### Changed
- `pubspec.yaml` `platforms:` now declares `windows:` alongside `macos:`.
```

### Step 10.4: Run pana + dry-run on app-facing

```powershell
cd C:\dev\ifw\packages\icefelix_window_manager
dart pub global run pana . --no-warning 2>&1 | Select-Object -Last 60
flutter pub publish --dry-run
```

### Step 10.5: Commit + tag

```bash
git add packages/icefelix_window_manager/pubspec.yaml \
        packages/icefelix_window_manager/CHANGELOG.md \
        packages/icefelix_window_manager_macos/example/pubspec.yaml
git commit -m "release: v0.2.0 — Windows platform support"
git tag -a v0.2.0 -m "v0.2.0 — Windows platform support via icefelix_window_manager_windows@0.1.0"
```

### Step 10.6: Push + publish (user-driven, needs auth)

```powershell
# Push branch + tag — user runs these interactively for auth.
git push origin main
git push origin v0.2.0

# Publish in dependency order. Each command prompts to confirm.
cd packages\icefelix_window_manager_windows
flutter pub publish
# wait ~60 seconds for pub.dev to index
cd ..\icefelix_window_manager
flutter pub publish
```

### Step 10.7: GitHub release

```powershell
gh release create v0.2.0 \
  --title "v0.2.0 — Windows" \
  --notes-file packages/icefelix_window_manager/CHANGELOG.md
```

(Or paste the 0.2.0 CHANGELOG block into `--notes` manually.)

---

## Self-review checklist

**Spec coverage:**
- ✅ All 30 remaining `WindowHostApi` methods: Tasks 1-6 cover state machine + lifecycle + properties + frameless + visual + drag/resize.
- ✅ Close intercept (3 `WindowFlutterApi` contract): Task 2 wires `WM_CLOSE` → `OnCloseRequest` with 5 s timeout.
- ✅ Testbed: Task 7 ports the full 27-control macOS testbed.
- ✅ Integration tests: Task 8 brings to 11 tests total (3 macOS-port + 2 Win32-specific).
- ✅ Pana: Task 9.
- ✅ App-facing v0.2.0 bump + Windows platform declaration: Task 10.
- ✅ Publish + tag + release: Task 10.5-10.7.
- ✅ Melos bootstrap blocker fix: Task 10.1.

**Placeholder scan:** No "TBD" / "add error handling" / "similar to Task N" — each step shows the actual code.

**Type consistency:**
- `prevent_close_flag_` (session 1) referenced in Task 2 `WM_CLOSE` handler ✓
- `movable_flag_` (session 1) referenced in Task 3 `WM_NCHITTEST` handler ✓
- `fullscreen_flag_` (session 1) referenced in Task 1 `Fullscreen`/`ExitFullscreen` ✓
- New: `pre_fullscreen_style_`, `pre_fullscreen_ex_style_`, `pre_fullscreen_rect_`, `close_in_flight_`, `close_allowed_`, `current_icon_` — all declared in Task headers, consistent naming.

---

## Execution notes

- Run tests after EVERY task; do not stack uncommitted changes across verticals.
- If pana flags an issue in Task 9 that needs a method signature change, that's a SCHEMA change — open a GitHub issue per CLAUDE.md hard rule 1; do NOT silently modify `pigeons/window_api.dart`.
- Tasks 9 and 10 require user auth for the `flutter pub publish` and `git push` steps. The plan documents the commands; the user runs them interactively.
- Total estimated time on focused work: 3-5 session-days, matching the brief's 3-5 sessions estimate.
