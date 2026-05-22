// Copyright 2026 icefelix.com. BSD-3-Clause.

import 'package:flutter/foundation.dart';

/// Linux display server flavor.
enum DisplayServer { x11, wayland }

/// Runtime platform information.
@immutable
class WindowPlatform {
  const WindowPlatform({
    required this.target,
    this.displayServer,
    required this.isSandboxed,
  });

  /// Target platform. Always [TargetPlatform.macOS], [TargetPlatform.windows],
  /// or [TargetPlatform.linux] — other values are rejected by
  /// `WindowManager.ensureInitialized`.
  final TargetPlatform target;

  /// Linux only: X11 vs Wayland. Null on macOS / Windows.
  final DisplayServer? displayServer;

  /// True if running in a sandboxed context (macOS App Sandbox, Linux Flatpak/Snap).
  /// Always false on Windows.
  final bool isSandboxed;
}
