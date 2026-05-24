# Copyright 2026 icefelix.com. BSD-3-Clause.
# Build configuration for the Linux native side of icefelix_window_manager.

cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "icefelix_window_manager")
project(${PROJECT_NAME} LANGUAGES CXX)

# Must match `pluginClass` in pubspec.yaml > flutter.plugin.platforms.linux.
set(PLUGIN_NAME "icefelix_window_manager_plugin")

list(APPEND PLUGIN_SOURCES
  "icefelix_window_manager_plugin.cc"
  "messages.g.cc"
)

add_library(${PLUGIN_NAME} SHARED
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

set(icefelix_window_manager_bundled_libraries
  ""
  PARENT_SCOPE
)
