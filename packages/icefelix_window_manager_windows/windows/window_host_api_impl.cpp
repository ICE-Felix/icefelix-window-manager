// Copyright 2026 icefelix.com. BSD-3-Clause.

#include "window_host_api_impl.h"

#include <ShellScalingApi.h>
#include <windows.h>

#include <algorithm>
#include <cmath>
#include <vector>

namespace icefelix_window_manager_windows {

namespace {

constexpr const char* kNotImplemented = "not_implemented";
constexpr const char* kNoWindow = "no_window";

/// Convert a UTF-16 string to UTF-8. Used for window title + monitor names
/// (Win32 monitor APIs hand back wide strings).
std::string Utf8FromWide(const wchar_t* wide, int wide_len = -1) {
  if (!wide) return {};
  int needed =
      WideCharToMultiByte(CP_UTF8, 0, wide, wide_len, nullptr, 0, nullptr, nullptr);
  if (needed <= 0) return {};
  std::string out;
  out.resize(wide_len == -1 ? needed - 1 : needed);
  WideCharToMultiByte(CP_UTF8, 0, wide, wide_len, out.data(), needed, nullptr,
                      nullptr);
  return out;
}

/// Convert a UTF-8 string to UTF-16 for Win32 wide-string APIs.
std::wstring WideFromUtf8(const std::string& utf8) {
  if (utf8.empty()) return {};
  int needed = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                   static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring out(needed, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                      out.data(), needed);
  return out;
}

/// Round a logical double to physical-pixel LONG. Standard half-away-from-zero
/// so 1.5 → 2, -1.5 → -2.
LONG LogicalToPhysical(double logical, double scale) {
  return static_cast<LONG>(std::round(logical * scale));
}

}  // namespace

// static
WindowHostApiImpl* WindowHostApiImpl::g_instance_ = nullptr;

WindowHostApiImpl::WindowHostApiImpl(flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar),
      flutter_api_(
          std::make_unique<WindowFlutterApi>(registrar->messenger())) {}

WindowHostApiImpl::~WindowHostApiImpl() {
  if (installed_ && hwnd_ && original_wnd_proc_) {
    // Restore the original WndProc so subsequent message dispatch (Flutter or
    // any other subclass) keeps working after we tear down.
    SetWindowLongPtrW(hwnd_, GWLP_WNDPROC,
                      reinterpret_cast<LONG_PTR>(original_wnd_proc_));
    KillTimer(hwnd_, kSnapshotTimerId);
  }
  if (g_instance_ == this) {
    g_instance_ = nullptr;
  }
}

// ============ WndProc dispatch ============

// static
LRESULT CALLBACK WindowHostApiImpl::SubclassedWndProc(HWND hwnd, UINT msg,
                                                     WPARAM wp, LPARAM lp) {
  WindowHostApiImpl* self = g_instance_;
  if (!self || hwnd != self->hwnd_) {
    // Defensive: shouldn't happen, but if we get here without a bound impl
    // (race during teardown), fall back to the default proc rather than
    // crashing.
    return DefWindowProcW(hwnd, msg, wp, lp);
  }
  return self->HandleMessage(hwnd, msg, wp, lp);
}

LRESULT WindowHostApiImpl::HandleMessage(HWND hwnd, UINT msg, WPARAM wp,
                                         LPARAM lp) {
  auto CallOriginal = [&]() -> LRESULT {
    return CallWindowProcW(original_wnd_proc_, hwnd, msg, wp, lp);
  };

  switch (msg) {
    case WM_GETMINMAXINFO: {
      // Let the default proc fill in monitor-work-area defaults first, then
      // overlay our user-supplied min/max. Setting both ptMaxTrackSize (drag
      // resize) and ptMaxSize (ShowWindow(SW_MAXIMIZE)) is what makes
      // `setMaxSize is honored by maximize() in frame coords` pass — without
      // ptMaxSize, ShowWindow overshoots the user's bound to the work-area
      // size (the same class of bug the macOS impl hit with contentMaxSize).
      LRESULT r = CallOriginal();
      auto* mmi = reinterpret_cast<MINMAXINFO*>(lp);
      if (min_size_set_) {
        mmi->ptMinTrackSize.x = min_size_cx_;
        mmi->ptMinTrackSize.y = min_size_cy_;
      }
      if (max_size_set_) {
        mmi->ptMaxTrackSize.x = max_size_cx_;
        mmi->ptMaxTrackSize.y = max_size_cy_;
        mmi->ptMaxSize.x = max_size_cx_;
        mmi->ptMaxSize.y = max_size_cy_;
      }
      return r;
    }

    case WM_SIZE:
    case WM_MOVE:
    case WM_ACTIVATE:
      ScheduleSnapshotEmit();
      return CallOriginal();

    case WM_DPICHANGED:
      // Flutter's own WndProc handles the suggested-rect resize. We just
      // emit the snapshot so Dart sees the new scale factor.
      ScheduleSnapshotEmit();
      return CallOriginal();

    case WM_DISPLAYCHANGE:
      EmitDisplaysChanged();
      return CallOriginal();

    case WM_TIMER:
      if (wp == kSnapshotTimerId) {
        EmitSnapshotNow();
        return 0;
      }
      return CallOriginal();

    default:
      return CallOriginal();
  }
}

bool WindowHostApiImpl::InstallIfNeeded() {
  if (installed_) return true;
  if (!registrar_) return false;
  flutter::FlutterView* view = registrar_->GetView();
  if (!view) return false;
  HWND child = view->GetNativeWindow();
  if (!child) return false;
  HWND root = GetAncestor(child, GA_ROOT);
  if (!root) return false;
  hwnd_ = root;
  original_wnd_proc_ = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(
      hwnd_, GWLP_WNDPROC,
      reinterpret_cast<LONG_PTR>(&WindowHostApiImpl::SubclassedWndProc)));
  if (!original_wnd_proc_) {
    // Subclass failed — surface as an error path via the next API call.
    hwnd_ = nullptr;
    return false;
  }
  g_instance_ = this;
  installed_ = true;
  return true;
}

// ============ Snapshot emit ============

void WindowHostApiImpl::ScheduleSnapshotEmit() {
  if (!hwnd_) return;
  // SetTimer with the same ID resets the timer — exactly the macOS
  // scheduleSnapshotEmit() cancel+reschedule semantics.
  SetTimer(hwnd_, kSnapshotTimerId, kSnapshotTimerIntervalMs, nullptr);
}

void WindowHostApiImpl::EmitSnapshotNow() {
  if (!hwnd_) return;
  KillTimer(hwnd_, kSnapshotTimerId);
  if (!flutter_api_) return;
  flutter_api_->OnSnapshotChanged(
      BuildSnapshot(), []() {}, [](const FlutterError&) {});
}

void WindowHostApiImpl::EmitDisplaysChanged() {
  if (!flutter_api_) return;
  auto displays_or = ListDisplays();
  if (displays_or.has_error()) return;
  // ErrorOr::value() is the public accessor; TakeValue is private. Copy is
  // cheap relative to the marshalling cost of the channel send.
  flutter_api_->OnDisplaysChanged(displays_or.value(), []() {},
                                  [](const FlutterError&) {});
}

// ============ Snapshot builder ============

double WindowHostApiImpl::ScaleFactor() const {
  if (!hwnd_) return 1.0;
  UINT dpi = GetDpiForWindow(hwnd_);
  if (dpi == 0) return 1.0;
  return static_cast<double>(dpi) / 96.0;
}

WindowStateRaw WindowHostApiImpl::CurrentWindowState() {
  if (!hwnd_) return WindowStateRaw::kNormal;
  if (IsIconic(hwnd_)) return WindowStateRaw::kMinimized;
  if (fullscreen_flag_) return WindowStateRaw::kFullscreen;
  if (IsZoomed(hwnd_)) return WindowStateRaw::kMaximized;
  if (!IsWindowVisible(hwnd_)) return WindowStateRaw::kHidden;
  return WindowStateRaw::kNormal;
}

WindowSnapshotRaw WindowHostApiImpl::BuildSnapshot() {
  RECT rect = {};
  GetWindowRect(hwnd_, &rect);
  const double scale = ScaleFactor();
  OffsetRaw position(rect.left / scale, rect.top / scale);
  SizeRaw size((rect.right - rect.left) / scale,
               (rect.bottom - rect.top) / scale);
  WindowBoundsRaw bounds(&position, size);

  wchar_t title_buf[512] = {};
  int title_len = GetWindowTextW(hwnd_, title_buf, 512);
  std::string title = Utf8FromWide(title_buf, title_len);

  const LONG style = GetWindowLongW(hwnd_, GWL_STYLE);
  const bool resizable = (style & WS_THICKFRAME) != 0;
  const bool minimizable = (style & WS_MINIMIZEBOX) != 0;
  const bool frameless = (style & WS_CAPTION) == 0;
  const bool focused = (GetForegroundWindow() == hwnd_);

  DisplayRaw current = BuildDisplayRawForCurrent();
  const int64_t* bg_ptr = background_color_argb_flag_.has_value()
                              ? &background_color_argb_flag_.value()
                              : nullptr;

  return WindowSnapshotRaw(
      bounds, CurrentWindowState(), title, focused, always_on_top_flag_,
      skip_taskbar_flag_, resizable, movable_flag_, minimizable,
      maximizable_flag_, closable_flag_, frameless, title_bar_style_flag_,
      opacity_flag_, bg_ptr, has_shadow_flag_, prevent_close_flag_, current);
}

// ============ Display helpers ============

DisplayRaw WindowHostApiImpl::BuildDisplayRawForMonitor(HMONITOR monitor) {
  MONITORINFOEXW mi = {};
  mi.cbSize = sizeof(mi);
  GetMonitorInfoW(monitor, &mi);

  // szDevice (e.g. "\\.\DISPLAY1") is the stable ID — HMONITOR is recycled
  // across display reconfigurations, but szDevice persists.
  std::string device = Utf8FromWide(mi.szDevice);

  UINT mon_dpi_x = 96, mon_dpi_y = 96;
  // GetDpiForMonitor is the per-monitor effective DPI. Available since
  // Windows 8.1; on older systems we'd fall back to GetDeviceCaps(LOGPIXELSX)
  // — not needed for our Win10+ target.
  GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &mon_dpi_x, &mon_dpi_y);
  const double scale = static_cast<double>(mon_dpi_x) / 96.0;

  RectRaw bounds(mi.rcMonitor.left / scale, mi.rcMonitor.top / scale,
                 (mi.rcMonitor.right - mi.rcMonitor.left) / scale,
                 (mi.rcMonitor.bottom - mi.rcMonitor.top) / scale);
  RectRaw work_area(mi.rcWork.left / scale, mi.rcWork.top / scale,
                    (mi.rcWork.right - mi.rcWork.left) / scale,
                    (mi.rcWork.bottom - mi.rcWork.top) / scale);

  // Refresh rate from current display settings. ENUM_CURRENT_SETTINGS reads
  // what the monitor is actively running at (vs the registered profile).
  int64_t refresh = 0;
  bool have_refresh = false;
  DEVMODEW dm = {};
  dm.dmSize = sizeof(dm);
  if (EnumDisplaySettingsExW(mi.szDevice, ENUM_CURRENT_SETTINGS, &dm, 0)) {
    refresh = static_cast<int64_t>(dm.dmDisplayFrequency);
    have_refresh = refresh > 0;
  }

  // Friendly name via EnumDisplayDevicesW on the device. Falls back to the
  // device string when no friendly name is registered (typical for virtual
  // displays).
  std::string name = device;
  DISPLAY_DEVICEW dd = {};
  dd.cb = sizeof(dd);
  if (EnumDisplayDevicesW(mi.szDevice, 0, &dd, 0)) {
    std::string device_string = Utf8FromWide(dd.DeviceString);
    if (!device_string.empty()) name = device_string;
  }

  const bool is_primary = (mi.dwFlags & MONITORINFOF_PRIMARY) != 0;
  // Physical size (mm) requires EDID parsing or WMI; leaving null for v0.1.0
  // matches the schema's nullability and is honest about what we can read.
  return DisplayRaw(device, &name, bounds, work_area, /*physical_width_mm=*/nullptr,
                    /*physical_height_mm=*/nullptr, /*dpi=*/nullptr, scale,
                    is_primary, have_refresh ? &refresh : nullptr);
}

DisplayRaw WindowHostApiImpl::BuildDisplayRawForCurrent() {
  HMONITOR mon = hwnd_ ? MonitorFromWindow(hwnd_, MONITOR_DEFAULTTONEAREST)
                       : MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY);
  return BuildDisplayRawForMonitor(mon);
}

namespace {
BOOL CALLBACK EnumMonitorCallback(HMONITOR mon, HDC, LPRECT, LPARAM lparam) {
  auto* out = reinterpret_cast<std::vector<HMONITOR>*>(lparam);
  out->push_back(mon);
  return TRUE;
}
}  // namespace

// ============ Initialization ============

ErrorOr<WindowSnapshotRaw> WindowHostApiImpl::EnsureInitialized() {
  if (!InstallIfNeeded()) {
    return FlutterError(kNoWindow,
                        "No HWND available — is the Flutter view attached?");
  }
  return BuildSnapshot();
}

ErrorOr<PlatformInfoRaw> WindowHostApiImpl::GetPlatformInfo() {
  // isSandboxed: no real sandbox on classic Win32. MSIX/AppContainer apps
  // could be detected via GetCurrentPackageFullName() but that's a v0.2.x
  // refinement.
  return PlatformInfoRaw("windows", /*is_sandboxed=*/false);
}

// ============ Bounds ============

ErrorOr<WindowBoundsRaw> WindowHostApiImpl::GetBounds() {
  if (!InstallIfNeeded()) {
    return FlutterError(kNoWindow, "No HWND available");
  }
  RECT rect = {};
  GetWindowRect(hwnd_, &rect);
  const double scale = ScaleFactor();
  OffsetRaw pos(rect.left / scale, rect.top / scale);
  SizeRaw sz((rect.right - rect.left) / scale,
             (rect.bottom - rect.top) / scale);
  return WindowBoundsRaw(&pos, sz);
}

std::optional<FlutterError> WindowHostApiImpl::SetBounds(
    const WindowBoundsRaw& bounds, const std::string* /*display_id*/) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  // displayId currently ignored — caller should use moveToDisplay() explicitly.
  // Combining them needs validation that the target display contains the rect.
  const double scale = ScaleFactor();
  RECT cur = {};
  GetWindowRect(hwnd_, &cur);
  LONG x = cur.left;
  LONG y = cur.top;
  if (bounds.position()) {
    x = LogicalToPhysical(bounds.position()->dx(), scale);
    y = LogicalToPhysical(bounds.position()->dy(), scale);
  }
  const LONG w = LogicalToPhysical(bounds.size().width(), scale);
  const LONG h = LogicalToPhysical(bounds.size().height(), scale);
  SetWindowPos(hwnd_, nullptr, x, y, w, h, SWP_NOZORDER | SWP_NOACTIVATE);
  return std::nullopt;
}

std::optional<FlutterError> WindowHostApiImpl::SetSize(const SizeRaw& size) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  const double scale = ScaleFactor();
  RECT cur = {};
  GetWindowRect(hwnd_, &cur);
  const LONG w = LogicalToPhysical(size.width(), scale);
  const LONG h = LogicalToPhysical(size.height(), scale);
  SetWindowPos(hwnd_, nullptr, cur.left, cur.top, w, h,
               SWP_NOZORDER | SWP_NOACTIVATE);
  return std::nullopt;
}

std::optional<FlutterError> WindowHostApiImpl::SetMinSize(const SizeRaw* size) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  if (size) {
    const double scale = ScaleFactor();
    min_size_cx_ = LogicalToPhysical(size->width(), scale);
    min_size_cy_ = LogicalToPhysical(size->height(), scale);
    min_size_set_ = true;
    // If the current frame is below the new min, Windows resizes on the next
    // WM_GETMINMAXINFO during a user drag — but a programmatic constraint
    // change won't fire that on its own. Mirror the macOS pattern: re-apply
    // current size so the OS clamps and we emit a snapshot.
    RECT r = {};
    GetWindowRect(hwnd_, &r);
    LONG w = std::max<LONG>(r.right - r.left, min_size_cx_);
    LONG h = std::max<LONG>(r.bottom - r.top, min_size_cy_);
    if (w != r.right - r.left || h != r.bottom - r.top) {
      SetWindowPos(hwnd_, nullptr, r.left, r.top, w, h,
                   SWP_NOZORDER | SWP_NOACTIVATE);
    }
  } else {
    min_size_set_ = false;
    min_size_cx_ = 0;
    min_size_cy_ = 0;
  }
  ScheduleSnapshotEmit();
  return std::nullopt;
}

std::optional<FlutterError> WindowHostApiImpl::SetMaxSize(const SizeRaw* size) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  if (size) {
    const double scale = ScaleFactor();
    max_size_cx_ = LogicalToPhysical(size->width(), scale);
    max_size_cy_ = LogicalToPhysical(size->height(), scale);
    max_size_set_ = true;
  } else {
    max_size_set_ = false;
    max_size_cx_ = 0;
    max_size_cy_ = 0;
  }
  ScheduleSnapshotEmit();
  return std::nullopt;
}

std::optional<FlutterError> WindowHostApiImpl::SetPosition(
    const OffsetRaw& position) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  const double scale = ScaleFactor();
  RECT cur = {};
  GetWindowRect(hwnd_, &cur);
  const LONG x = LogicalToPhysical(position.dx(), scale);
  const LONG y = LogicalToPhysical(position.dy(), scale);
  SetWindowPos(hwnd_, nullptr, x, y, cur.right - cur.left, cur.bottom - cur.top,
               SWP_NOZORDER | SWP_NOACTIVATE);
  return std::nullopt;
}

std::optional<FlutterError> WindowHostApiImpl::Center() {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  HMONITOR mon = MonitorFromWindow(hwnd_, MONITOR_DEFAULTTONEAREST);
  MONITORINFO mi = {};
  mi.cbSize = sizeof(mi);
  GetMonitorInfo(mon, &mi);
  RECT cur = {};
  GetWindowRect(hwnd_, &cur);
  const LONG w = cur.right - cur.left;
  const LONG h = cur.bottom - cur.top;
  const LONG x = mi.rcWork.left + (mi.rcWork.right - mi.rcWork.left - w) / 2;
  const LONG y = mi.rcWork.top + (mi.rcWork.bottom - mi.rcWork.top - h) / 2;
  SetWindowPos(hwnd_, nullptr, x, y, w, h, SWP_NOZORDER | SWP_NOACTIVATE);
  return std::nullopt;
}

std::optional<FlutterError> WindowHostApiImpl::MoveToDisplay(
    const std::string& display_id) {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  std::wstring wanted = WideFromUtf8(display_id);
  std::vector<HMONITOR> monitors;
  EnumDisplayMonitors(nullptr, nullptr, &EnumMonitorCallback,
                      reinterpret_cast<LPARAM>(&monitors));
  HMONITOR target = nullptr;
  for (HMONITOR m : monitors) {
    MONITORINFOEXW mi = {};
    mi.cbSize = sizeof(mi);
    GetMonitorInfoW(m, &mi);
    if (wanted == mi.szDevice) {
      target = m;
      break;
    }
  }
  if (!target) {
    return FlutterError("display_not_found",
                        "No display matched szDevice=" + display_id);
  }

  // Preserve relative position within the current monitor; center on the
  // target if the resulting rect doesn't fit.
  HMONITOR current = MonitorFromWindow(hwnd_, MONITOR_DEFAULTTONEAREST);
  MONITORINFOEXW cur_mi = {};
  cur_mi.cbSize = sizeof(cur_mi);
  GetMonitorInfoW(current, &cur_mi);
  MONITORINFOEXW tgt_mi = {};
  tgt_mi.cbSize = sizeof(tgt_mi);
  GetMonitorInfoW(target, &tgt_mi);

  RECT cur_rect = {};
  GetWindowRect(hwnd_, &cur_rect);
  const LONG cur_w = cur_rect.right - cur_rect.left;
  const LONG cur_h = cur_rect.bottom - cur_rect.top;
  const LONG cur_mon_w = cur_mi.rcMonitor.right - cur_mi.rcMonitor.left;
  const LONG cur_mon_h = cur_mi.rcMonitor.bottom - cur_mi.rcMonitor.top;
  const LONG tgt_mon_w = tgt_mi.rcMonitor.right - tgt_mi.rcMonitor.left;
  const LONG tgt_mon_h = tgt_mi.rcMonitor.bottom - tgt_mi.rcMonitor.top;

  double rel_x = cur_mon_w > 0
                     ? double(cur_rect.left - cur_mi.rcMonitor.left) / cur_mon_w
                     : 0.0;
  double rel_y = cur_mon_h > 0
                     ? double(cur_rect.top - cur_mi.rcMonitor.top) / cur_mon_h
                     : 0.0;
  LONG new_x = tgt_mi.rcMonitor.left + LONG(rel_x * tgt_mon_w);
  LONG new_y = tgt_mi.rcMonitor.top + LONG(rel_y * tgt_mon_h);

  // If the preserved rect would fall off the target monitor, center it.
  if (new_x + cur_w > tgt_mi.rcMonitor.right ||
      new_y + cur_h > tgt_mi.rcMonitor.bottom || new_x < tgt_mi.rcMonitor.left ||
      new_y < tgt_mi.rcMonitor.top) {
    new_x = tgt_mi.rcMonitor.left + (tgt_mon_w - cur_w) / 2;
    new_y = tgt_mi.rcMonitor.top + (tgt_mon_h - cur_h) / 2;
  }

  SetWindowPos(hwnd_, nullptr, new_x, new_y, cur_w, cur_h,
               SWP_NOZORDER | SWP_NOACTIVATE);
  return std::nullopt;
}

// ============ State machine ============

std::optional<FlutterError> WindowHostApiImpl::Minimize() {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  ShowWindow(hwnd_, SW_MINIMIZE);
  return std::nullopt;
}

std::optional<FlutterError> WindowHostApiImpl::Maximize() {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  if (!IsZoomed(hwnd_)) {
    ShowWindow(hwnd_, SW_MAXIMIZE);
  }
  return std::nullopt;
}

std::optional<FlutterError> WindowHostApiImpl::Unmaximize() {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  if (IsZoomed(hwnd_)) {
    ShowWindow(hwnd_, SW_RESTORE);
  }
  return std::nullopt;
}

std::optional<FlutterError> WindowHostApiImpl::Restore() {
  if (!InstallIfNeeded()) return FlutterError(kNoWindow, "No HWND available");
  ShowWindow(hwnd_, SW_RESTORE);
  return std::nullopt;
}

// Stubs for session 1 — wired in session 2.
std::optional<FlutterError> WindowHostApiImpl::Hide() {
  return FlutterError(kNotImplemented, "Hide() not implemented in session 1");
}
std::optional<FlutterError> WindowHostApiImpl::Show() {
  return FlutterError(kNotImplemented, "Show() not implemented in session 1");
}
std::optional<FlutterError> WindowHostApiImpl::Fullscreen() {
  return FlutterError(kNotImplemented,
                      "Fullscreen() not implemented in session 1");
}
std::optional<FlutterError> WindowHostApiImpl::ExitFullscreen() {
  return FlutterError(kNotImplemented,
                      "ExitFullscreen() not implemented in session 1");
}

std::optional<FlutterError> WindowHostApiImpl::Focus() {
  return FlutterError(kNotImplemented, "Focus() not implemented in session 1");
}
std::optional<FlutterError> WindowHostApiImpl::Blur() {
  return FlutterError(kNotImplemented, "Blur() not implemented in session 1");
}

std::optional<FlutterError> WindowHostApiImpl::StartDrag() {
  return FlutterError(kNotImplemented,
                      "StartDrag() not implemented in session 1");
}
std::optional<FlutterError> WindowHostApiImpl::StartResize(
    const ResizeDirectionRaw&) {
  return FlutterError(kNotImplemented,
                      "StartResize() not implemented in session 1");
}

std::optional<FlutterError> WindowHostApiImpl::Close() {
  return FlutterError(kNotImplemented, "Close() not implemented in session 1");
}
std::optional<FlutterError> WindowHostApiImpl::Destroy() {
  return FlutterError(kNotImplemented,
                      "Destroy() not implemented in session 1");
}

std::optional<FlutterError> WindowHostApiImpl::SetTitle(const std::string&) {
  return FlutterError(kNotImplemented,
                      "SetTitle() not implemented in session 1");
}
std::optional<FlutterError> WindowHostApiImpl::SetAlwaysOnTop(bool) {
  return FlutterError(kNotImplemented,
                      "SetAlwaysOnTop() not implemented in session 1");
}
std::optional<FlutterError> WindowHostApiImpl::SetSkipTaskbar(bool) {
  return FlutterError(kNotImplemented,
                      "SetSkipTaskbar() not implemented in session 1");
}
std::optional<FlutterError> WindowHostApiImpl::SetResizable(bool) {
  return FlutterError(kNotImplemented,
                      "SetResizable() not implemented in session 1");
}
std::optional<FlutterError> WindowHostApiImpl::SetMovable(bool) {
  return FlutterError(kNotImplemented,
                      "SetMovable() not implemented in session 1");
}
std::optional<FlutterError> WindowHostApiImpl::SetMinimizable(bool) {
  return FlutterError(kNotImplemented,
                      "SetMinimizable() not implemented in session 1");
}
std::optional<FlutterError> WindowHostApiImpl::SetMaximizable(bool) {
  return FlutterError(kNotImplemented,
                      "SetMaximizable() not implemented in session 1");
}
std::optional<FlutterError> WindowHostApiImpl::SetClosable(bool) {
  return FlutterError(kNotImplemented,
                      "SetClosable() not implemented in session 1");
}

std::optional<FlutterError> WindowHostApiImpl::SetFrameless(bool) {
  return FlutterError(kNotImplemented,
                      "SetFrameless() not implemented in session 1");
}
std::optional<FlutterError> WindowHostApiImpl::SetTitleBarStyle(
    const TitleBarStyleRaw&) {
  return FlutterError(kNotImplemented,
                      "SetTitleBarStyle() not implemented in session 1");
}

std::optional<FlutterError> WindowHostApiImpl::SetOpacity(double) {
  return FlutterError(kNotImplemented,
                      "SetOpacity() not implemented in session 1");
}
std::optional<FlutterError> WindowHostApiImpl::SetBackgroundColor(int64_t) {
  return FlutterError(kNotImplemented,
                      "SetBackgroundColor() not implemented in session 1");
}
std::optional<FlutterError> WindowHostApiImpl::SetHasShadow(bool) {
  return FlutterError(kNotImplemented,
                      "SetHasShadow() not implemented in session 1");
}
std::optional<FlutterError> WindowHostApiImpl::SetIcon(const std::string&) {
  return FlutterError(kNotImplemented,
                      "SetIcon() not implemented in session 1");
}

std::optional<FlutterError> WindowHostApiImpl::SetPreventClose(bool value) {
  // Flag tracked so the snapshot reports it; actual close-intercept wiring
  // (subclass WM_CLOSE, fire OnCloseRequest, default-allow on 5 s timeout)
  // is session 2.
  prevent_close_flag_ = value;
  ScheduleSnapshotEmit();
  return std::nullopt;
}

// ============ Multi-monitor ============

ErrorOr<flutter::EncodableList> WindowHostApiImpl::ListDisplays() {
  std::vector<HMONITOR> monitors;
  EnumDisplayMonitors(nullptr, nullptr, &EnumMonitorCallback,
                      reinterpret_cast<LPARAM>(&monitors));
  flutter::EncodableList out;
  out.reserve(monitors.size());
  for (HMONITOR m : monitors) {
    out.push_back(
        flutter::CustomEncodableValue(BuildDisplayRawForMonitor(m)));
  }
  return out;
}

ErrorOr<DisplayRaw> WindowHostApiImpl::GetCurrentDisplay() {
  if (!InstallIfNeeded()) {
    return FlutterError(kNoWindow, "No HWND available");
  }
  return BuildDisplayRawForCurrent();
}

ErrorOr<DisplayRaw> WindowHostApiImpl::GetPrimaryDisplay() {
  HMONITOR mon = MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY);
  return BuildDisplayRawForMonitor(mon);
}

}  // namespace icefelix_window_manager_windows
