// Public header is at windows/include/<plugin-name>/...h so consumers can
// `#include <icefelix_window_manager_windows/...>`. Inside the plugin we use
// the shorter sibling-style include via the PRIVATE include dir we set in
// CMakeLists.txt — this avoids constructing an absolute path that overflows
// what some Visual Studio C++ resolvers will follow through the Flutter
// .plugin_symlinks chain in deep workspaces.
#include <icefelix_window_manager_windows/icefelix_window_manager_windows_plugin_c_api.h>

#include <flutter/plugin_registrar_windows.h>

#include "icefelix_window_manager_windows_plugin.h"

void IcefelixWindowManagerWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  icefelix_window_manager_windows::IcefelixWindowManagerWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
