// Copyright 2026 icefelix.com. BSD-3-Clause.

#ifndef FLUTTER_PLUGIN_ICEFELIX_WINDOW_MANAGER_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_ICEFELIX_WINDOW_MANAGER_WINDOWS_PLUGIN_H_

#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace icefelix_window_manager_windows {

class WindowHostApiImpl;

/// Flutter Windows plugin entry. Wires the Pigeon-generated `WindowHostApi`
/// to a `WindowHostApiImpl` instance backed by Win32 (HWND, GetWindowRect,
/// SetWindowPos, WM_GETMINMAXINFO, ShowWindow, EnumDisplayMonitors). Mirrors
/// the macOS `IcefelixWindowManagerMacosPlugin` register flow.
class IcefelixWindowManagerWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit IcefelixWindowManagerWindowsPlugin(
      flutter::PluginRegistrarWindows* registrar);
  ~IcefelixWindowManagerWindowsPlugin() override;

  IcefelixWindowManagerWindowsPlugin(const IcefelixWindowManagerWindowsPlugin&) =
      delete;
  IcefelixWindowManagerWindowsPlugin& operator=(
      const IcefelixWindowManagerWindowsPlugin&) = delete;

 private:
  std::unique_ptr<WindowHostApiImpl> host_api_impl_;
};

}  // namespace icefelix_window_manager_windows

#endif  // FLUTTER_PLUGIN_ICEFELIX_WINDOW_MANAGER_WINDOWS_PLUGIN_H_
