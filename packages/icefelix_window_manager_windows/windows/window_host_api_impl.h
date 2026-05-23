// Copyright 2026 icefelix.com. BSD-3-Clause.

#ifndef FLUTTER_PLUGIN_ICEFELIX_WINDOW_HOST_API_IMPL_H_
#define FLUTTER_PLUGIN_ICEFELIX_WINDOW_HOST_API_IMPL_H_

#include <windows.h>

#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <optional>
#include <string>

#include "messages.g.h"

namespace icefelix_window_manager_windows {

/// Real WindowHostApi implementation backed by Win32 (HWND + WndProc subclass
/// on the Flutter host window). Mirrors the macOS reference impl
/// (`WindowHostApiImpl` in `IcefelixWindowManagerMacosPlugin.swift`).
///
/// Coordinate space: every public-facing value (setSize, setMinSize,
/// setMaxSize, snapshot.bounds.size, snapshot.bounds.position) is in
/// *logical* pixels (= physical pixels / scale_factor), matching the macOS
/// "points" convention. Conversion to/from Win32 physical pixels uses
/// `GetDpiForWindow` (the per-window DPI value Windows reports for
/// Per-Monitor v2 aware processes — already enabled by Flutter Windows).
///
/// Frame vs client: every size/position API operates on the **frame**
/// (titlebar included). `GetWindowRect` is the source of truth; min/max
/// clamps are enforced via `WM_GETMINMAXINFO` setting both `ptMaxTrackSize`
/// and `ptMaxSize` so `ShowWindow(SW_MAXIMIZE)` honors `setMaxSize`.
class WindowHostApiImpl : public WindowHostApi {
 public:
  explicit WindowHostApiImpl(flutter::PluginRegistrarWindows* registrar);
  ~WindowHostApiImpl() override;

  WindowHostApiImpl(const WindowHostApiImpl&) = delete;
  WindowHostApiImpl& operator=(const WindowHostApiImpl&) = delete;

  // ===== WindowHostApi overrides =====

  ErrorOr<WindowSnapshotRaw> EnsureInitialized() override;
  ErrorOr<PlatformInfoRaw> GetPlatformInfo() override;

  // Bounds
  ErrorOr<WindowBoundsRaw> GetBounds() override;
  std::optional<FlutterError> SetBounds(const WindowBoundsRaw& bounds,
                                        const std::string* display_id) override;
  std::optional<FlutterError> SetSize(const SizeRaw& size) override;
  std::optional<FlutterError> SetMinSize(const SizeRaw* size) override;
  std::optional<FlutterError> SetMaxSize(const SizeRaw* size) override;
  std::optional<FlutterError> SetPosition(const OffsetRaw& position) override;
  std::optional<FlutterError> Center() override;
  std::optional<FlutterError> MoveToDisplay(
      const std::string& display_id) override;

  // State (session 1: maximize/unmaximize live, rest stubbed)
  std::optional<FlutterError> Minimize() override;
  std::optional<FlutterError> Maximize() override;
  std::optional<FlutterError> Unmaximize() override;
  std::optional<FlutterError> Restore() override;
  std::optional<FlutterError> Hide() override;
  std::optional<FlutterError> Show() override;
  std::optional<FlutterError> Fullscreen() override;
  std::optional<FlutterError> ExitFullscreen() override;

  // Focus
  std::optional<FlutterError> Focus() override;
  std::optional<FlutterError> Blur() override;

  // Drag/resize (session 1: stubbed)
  std::optional<FlutterError> StartDrag() override;
  std::optional<FlutterError> StartResize(
      const ResizeDirectionRaw& direction) override;

  // Lifecycle (session 1: stubbed except close/destroy)
  std::optional<FlutterError> Close() override;
  std::optional<FlutterError> Destroy() override;

  // Title + properties (session 1: stubbed)
  std::optional<FlutterError> SetTitle(const std::string& title) override;
  std::optional<FlutterError> SetAlwaysOnTop(bool value) override;
  std::optional<FlutterError> SetSkipTaskbar(bool value) override;
  std::optional<FlutterError> SetResizable(bool value) override;
  std::optional<FlutterError> SetMovable(bool value) override;
  std::optional<FlutterError> SetMinimizable(bool value) override;
  std::optional<FlutterError> SetMaximizable(bool value) override;
  std::optional<FlutterError> SetClosable(bool value) override;

  // Frameless + title bar (session 1: stubbed)
  std::optional<FlutterError> SetFrameless(bool value) override;
  std::optional<FlutterError> SetTitleBarStyle(
      const TitleBarStyleRaw& style) override;

  // Visual (session 1: stubbed)
  std::optional<FlutterError> SetOpacity(double opacity) override;
  std::optional<FlutterError> SetBackgroundColor(int64_t argb) override;
  std::optional<FlutterError> SetHasShadow(bool value) override;
  std::optional<FlutterError> SetIcon(
      const std::string& filesystem_path) override;

  // Close interception (session 1: flag tracked only — wiring deferred)
  std::optional<FlutterError> SetPreventClose(bool value) override;

  // Multi-monitor
  ErrorOr<flutter::EncodableList> ListDisplays() override;
  ErrorOr<DisplayRaw> GetCurrentDisplay() override;
  ErrorOr<DisplayRaw> GetPrimaryDisplay() override;

 private:
  flutter::PluginRegistrarWindows* registrar_;
  HWND hwnd_ = nullptr;
  WNDPROC original_wnd_proc_ = nullptr;
  bool installed_ = false;
  std::unique_ptr<WindowFlutterApi> flutter_api_;

  // Min/max enforced by WM_GETMINMAXINFO. Stored in PHYSICAL pixels so the
  // handler can write them straight into MINMAXINFO without re-querying DPI
  // (DPI is stable while the window stays on one monitor; on WM_DPICHANGED
  // we recompute by re-running the last set via the cached logical value).
  bool min_size_set_ = false;
  LONG min_size_cx_ = 0;
  LONG min_size_cy_ = 0;
  bool max_size_set_ = false;
  LONG max_size_cx_ = 0;
  LONG max_size_cy_ = 0;

  // Tracked flags — Win32 has no introspectable bit for these so we mirror
  // the macOS flag-tracking pattern.
  bool always_on_top_flag_ = false;
  bool skip_taskbar_flag_ = false;
  bool maximizable_flag_ = true;
  bool closable_flag_ = true;
  bool movable_flag_ = true;
  bool prevent_close_flag_ = false;

  // Close-intercept synchronization. WM_CLOSE handler waits up to 5000ms
  // for the Dart side to respond via OnCloseRequest (matches the schema's
  // SYNCHRONIZATION CONTRACT). On timeout: default-allow per contract.
  static constexpr DWORD kCloseRequestTimeoutMs = 5000;
  bool close_in_flight_ = false;
  bool close_allowed_ = true;

  bool has_shadow_flag_ = true;
  double opacity_flag_ = 1.0;
  std::optional<int64_t> background_color_argb_flag_;
  TitleBarStyleRaw title_bar_style_flag_ = TitleBarStyleRaw::kNormal;
  bool fullscreen_flag_ = false;

  // Style + rect snapshot taken when entering fullscreen so ExitFullscreen
  // can restore the exact pre-fullscreen window state. Mirrors the macOS
  // toggleFullScreen which AppKit handles internally.
  LONG pre_fullscreen_style_ = 0;
  LONG pre_fullscreen_ex_style_ = 0;
  RECT pre_fullscreen_rect_ = {};

  // Snapshot emit coalescing (10 ms, mirrors macOS scheduleSnapshotEmit).
  static constexpr UINT_PTR kSnapshotTimerId = 0xCAFE;
  static constexpr UINT kSnapshotTimerIntervalMs = 10;

  // Single-instance dispatch for the WndProc thunk. Flutter Windows has one
  // host HWND per FlutterViewController; we expect exactly one plugin
  // instance. If a second is registered, the WndProc will dispatch to
  // whichever is current; the destructor of the previous one will fail to
  // restore its hook (warned in logs). Document and move on — multiple
  // FlutterViewControllers in the same process are rare.
  static WindowHostApiImpl* g_instance_;
  static LRESULT CALLBACK SubclassedWndProc(HWND hwnd, UINT msg, WPARAM wp,
                                            LPARAM lp);

  LRESULT HandleMessage(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);

  bool InstallIfNeeded();
  void ScheduleSnapshotEmit();
  void EmitSnapshotNow();
  void EmitDisplaysChanged();

  WindowSnapshotRaw BuildSnapshot();
  WindowStateRaw CurrentWindowState();
  DisplayRaw BuildDisplayRawForMonitor(HMONITOR monitor);
  DisplayRaw BuildDisplayRawForCurrent();

  /// Per-window DPI scale (e.g. 1.0 for 96 DPI, 1.5 for 144 DPI). Sourced
  /// from `GetDpiForWindow` which is the Per-Monitor v2 value Windows
  /// reports for the window's current monitor.
  double ScaleFactor() const;
};

}  // namespace icefelix_window_manager_windows

#endif  // FLUTTER_PLUGIN_ICEFELIX_WINDOW_HOST_API_IMPL_H_
