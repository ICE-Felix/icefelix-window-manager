# icefelix_window_manager

[![pub package](https://img.shields.io/pub/v/icefelix_window_manager.svg)](https://pub.dev/packages/icefelix_window_manager)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

Cross-platform window management for Flutter desktop apps. Control your app's own window — size, position, state, multi-monitor, frameless mode, and events — with a type-safe Pigeon-backed API and reactive `ValueListenable<WindowSnapshot>` as the single source of truth.

⚠️ **Pre-release: v0.1.0-dev.1.** Native implementations land in W2 (macOS), W3 (Windows), W4 (Linux). v0.1.0 stable ships ~26 June 2026. The Dart API in this dev release is the final shape.

## Platform support

| macOS | Windows | Linux (X11) | Linux (Wayland) |
|:-:|:-:|:-:|:-:|
| ⏳ W2 | ⏳ W3 | ⏳ W4 | ⏳ W4 |

## Installation

```bash
flutter pub add icefelix_window_manager
```

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:icefelix_window_manager/icefelix_window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowManager.instance.ensureInitialized();
  runApp(const MyApp());
}
```

## API overview

```dart
// Reactive UI — single source of truth
ValueListenableBuilder<WindowSnapshot>(
  valueListenable: WindowManager.instance.snapshot,
  builder: (context, snap, _) => Text('${snap.bounds.size}'),
);

// Imperative ops
await WindowManager.instance.setSize(const Size(1024, 768));
await WindowManager.instance.center();
await WindowManager.instance.setAlwaysOnTop(true);

// Multi-monitor
final displays = await WindowManager.instance.displays.list();
await WindowManager.instance.moveToDisplay(displays.last.id);

// Events with exhaustive pattern matching (Dart 3 sealed)
WindowManager.instance.events.listen((event) {
  switch (event) {
    case WindowResizeEvent(:final newSize): print('Resized to $newSize');
    case WindowCloseRequestEvent(:final preventDefault):
      preventDefault();
      // Show dialog, then if confirmed: WindowManager.instance.destroy();
    default: // exhaustive
  }
});
```

## Status

This is **W1 (Dart foundation)**. See [project tracker](https://github.com/ICE-Felix/icefelix-window-manager) for native implementation progress.

## License

BSD-3-Clause © 2026 icefelix.com — Alex Bordei <alex.bordei@icefelix.com>
