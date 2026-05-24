//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <icefelix_window_manager/icefelix_window_manager_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) icefelix_window_manager_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "IcefelixWindowManagerPlugin");
  icefelix_window_manager_plugin_register_with_registrar(icefelix_window_manager_registrar);
}
