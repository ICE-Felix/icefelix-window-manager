// Copyright 2026 icefelix.com. BSD-3-Clause.

/// Platform interface for icefelix_window_manager.
///
/// This package is NOT consumed directly by app developers; instead, depend on
/// `icefelix_window_manager`. Implement [WindowManagerPlatform] only if writing
/// a new platform implementation.
library;

export 'package:plugin_platform_interface/plugin_platform_interface.dart'
    show MockPlatformInterfaceMixin;

export 'src/messages.g.dart';
export 'src/window_manager_platform.dart';
