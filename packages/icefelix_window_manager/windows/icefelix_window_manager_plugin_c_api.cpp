// Public header is at windows/include/<plugin-name>/...h so consumers can
// `#include <icefelix_window_manager/...>`. Inside the plugin we use
// the shorter sibling-style include via the PRIVATE include dir we set in
// CMakeLists.txt — this avoids constructing an absolute path that overflows
// what some Visual Studio C++ resolvers will follow through the Flutter
// .plugin_symlinks chain in deep workspaces.
#include <icefelix_window_manager/icefelix_window_manager_plugin_c_api.h>

#include <flutter/plugin_registrar_windows.h>

#include "icefelix_window_manager_plugin.h"

void IcefelixWindowManagerPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  icefelix_window_manager::IcefelixWindowManagerPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
