// Copyright 2026 icefelix.com. BSD-3-Clause.

#include "icefelix_window_manager_windows_plugin.h"

#include <flutter/plugin_registrar_windows.h>

#include "window_host_api_impl.h"

namespace icefelix_window_manager_windows {

// static
void IcefelixWindowManagerWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<IcefelixWindowManagerWindowsPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

IcefelixWindowManagerWindowsPlugin::IcefelixWindowManagerWindowsPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : host_api_impl_(std::make_unique<WindowHostApiImpl>(registrar)) {
  // Pigeon wires WindowHostApi → host_api_impl_ on the registrar's messenger.
  // The impl installs the WndProc subclass + FlutterApi caller lazily inside
  // EnsureInitialized() (mirrors the macOS first-init pattern).
  WindowHostApi::SetUp(registrar->messenger(), host_api_impl_.get());
}

IcefelixWindowManagerWindowsPlugin::~IcefelixWindowManagerWindowsPlugin() =
    default;

}  // namespace icefelix_window_manager_windows
