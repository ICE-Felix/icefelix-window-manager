# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "icefelix_window_manager_windows")
project(${PROJECT_NAME} LANGUAGES CXX)

# Long-path manifest for cl.exe — Flutter symlinks plugins under
# `example/windows/flutter/ephemeral/.plugin_symlinks/<plugin>/windows/` which
# in a deep repo path (`C:\Users\<name>\Desktop\...`) easily pushes generated
# include paths past Windows' MAX_PATH=260. The `LongPathAware` element makes
# the compiler honor the system-wide `HKLM\SYSTEM\CurrentControlSet\Control\
# FileSystem\LongPathsEnabled=1` registry setting at process start.
set(CMAKE_VS_GLOBALS "EnableLongPaths=true")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "icefelix_window_manager_windows_plugin")

# Any new source files that you add to the plugin should be added here.
list(APPEND PLUGIN_SOURCES
  "icefelix_window_manager_windows_plugin.cpp"
  "icefelix_window_manager_windows_plugin.h"
  "window_host_api_impl.cpp"
  "window_host_api_impl.h"
  "messages.g.cpp"
  "messages.g.h"
)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED
  "include/icefelix_window_manager_windows/icefelix_window_manager_windows_plugin_c_api.h"
  "icefelix_window_manager_windows_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

# C++17 — required for std::optional, std::variant, etc. used by the
# Pigeon-generated bindings.
target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_17)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins. This should not be removed; any symbols that should be
# exported should be explicitly exported with the FLUTTER_PLUGIN_EXPORT macro.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Source include directories and library dependencies. Add any plugin-specific
# dependencies here.
target_include_directories(${PLUGIN_NAME}
  INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include"
  PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include")
# Shcore = GetDpiForMonitor (per-monitor DPI). Dwmapi reserved for the
# frameless/shadow work in session 2 (DwmExtendFrameIntoClientArea).
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin
  Shcore Dwmapi)

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(icefelix_window_manager_windows_bundled_libraries
  ""
  PARENT_SCOPE
)

# === Tests ===
# Native unit tests removed in favor of Dart integration tests under example/.
# The plugin is exercised via real Flutter widget tests on a real HWND, which
# is the only way to validate WndProc subclass + WM_GETMINMAXINFO behavior
# anyway (mock HWNDs would defeat the purpose).
