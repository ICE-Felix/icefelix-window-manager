// Copyright 2026 icefelix.com. BSD-3-Clause.
//
// This package is the platform interface — it does not run on its own.
// See `icefelix_window_manager_macos` for a complete platform implementation
// (Swift + AppKit + Pigeon channels) and `icefelix_window_manager` for the
// app-facing API that consumers actually depend on.
//
// The minimal shape of a platform implementation looks like this:
//
// ```dart
// import 'package:flutter/services.dart';
// import 'package:icefelix_window_manager_platform_interface/icefelix_window_manager_platform_interface.dart';
//
// class IcefelixWindowManagerMacos extends WindowManagerPlatform {
//   IcefelixWindowManagerMacos({BinaryMessenger? messenger})
//       : _api = WindowHostApi(binaryMessenger: messenger);
//
//   final WindowHostApi _api;
//
//   static void registerWith() {
//     WindowManagerPlatform.instance = IcefelixWindowManagerMacos();
//   }
//
//   @override
//   Future<WindowSnapshotRaw> ensureInitialized() => _api.ensureInitialized();
//
//   // ...implement the remaining 41 methods against your native bridge.
// }
// ```
void main() {
  // Intentionally empty. See doc comment above.
}
