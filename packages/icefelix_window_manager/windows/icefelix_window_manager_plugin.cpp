// Copyright 2026 icefelix.com. BSD-3-Clause.

#include "icefelix_window_manager_plugin.h"

#include <flutter/plugin_registrar_windows.h>

#include "window_host_api_impl.h"

namespace icefelix_window_manager {

// static
void IcefelixWindowManagerPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<IcefelixWindowManagerPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

IcefelixWindowManagerPlugin::IcefelixWindowManagerPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : host_api_impl_(std::make_unique<WindowHostApiImpl>(registrar)) {
  // Pigeon wires WindowHostApi → host_api_impl_ on the registrar's messenger.
  // The impl installs the WndProc subclass + FlutterApi caller lazily inside
  // EnsureInitialized() (mirrors the macOS first-init pattern).
  WindowHostApi::SetUp(registrar->messenger(), host_api_impl_.get());
}

IcefelixWindowManagerPlugin::~IcefelixWindowManagerPlugin() =
    default;

}  // namespace icefelix_window_manager
