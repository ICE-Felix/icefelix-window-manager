# icefelix_window_manager

Window management for Flutter desktop apps — your app, your window.
Control size, position, state, multi-monitor placement, frameless mode,
title bar style, opacity, shadow, drag/resize regions, and listen to
window/display events through a single reactive snapshot.

**Status:** macOS shipping in v0.1.0. Windows + Linux on the roadmap.

## Platform support

| Platform | Status | Version |
|---|---|---|
| macOS 10.15+ | ✅ Shipping | v0.1.0 (Swift + AppKit) |
| Windows 10+ | ⏳ Planned | v0.2.x (C++ + Win32) |
| Linux (X11 + Wayland) | ⏳ Planned | v0.3.x (C++ + GTK + libdecor) |

Mobile (iOS, Android) and web are out of scope — Flutter does not give an
embedded app control over the host window on those platforms.

## Packages

This is a federated plugin: one app-facing package, one platform
interface, and one implementation per platform.

| Package | Purpose | pub.dev |
|---|---|---|
| [`icefelix_window_manager`](https://pub.dev/packages/icefelix_window_manager) | App-facing API | v0.1.0 |
| [`icefelix_window_manager_platform_interface`](https://pub.dev/packages/icefelix_window_manager_platform_interface) | Abstract API + Pigeon schema | v0.1.0 |
| [`icefelix_window_manager_macos`](https://pub.dev/packages/icefelix_window_manager_macos) | macOS implementation | v0.1.0 |

App developers depend on `icefelix_window_manager` only; the federation
resolves the right platform impl automatically.

## Quick start

```yaml
# pubspec.yaml
dependencies:
  icefelix_window_manager: ^0.1.0
```

```dart
import 'package:flutter/material.dart';
import 'package:icefelix_window_manager/icefelix_window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowManager.instance.ensureInitialized();
  runApp(const MyApp());
}
```

See per-package READMEs for the full API surface and the example app at
[`packages/icefelix_window_manager_macos/example/`](packages/icefelix_window_manager_macos/example/)
exercising every method.

## License

BSD-3-Clause © 2026 icefelix.com (Alex Bordei)
