# icefelix_window_manager

[![pub package](https://img.shields.io/pub/v/icefelix_window_manager.svg)](https://pub.dev/packages/icefelix_window_manager)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

Cross-platform window management for Flutter desktop apps. Control your app's own window — size, position, state, multi-monitor, frameless mode, custom shapes, and events — with a type-safe Pigeon-backed API and reactive `ValueListenable<WindowSnapshot>` as the single source of truth.

**v0.4.0 — single package, macOS + Windows + Linux native.** Adds Linux as a first-class platform alongside macOS and Windows. Both X11 and Wayland are supported. This release builds on v0.3.0's monolithic layout — macOS (Swift + AppKit), Windows (C++ + Win32), and Linux (C + GTK 3) all ship inside one package.

## Platform support

| Platform | Status |
|----------|--------|
| macOS 10.15+ | ✅ Shipping |
| Windows 10+ | ✅ Shipping |
| Linux (X11 + Wayland) | ✅ Shipping (v0.4.0) |

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

## Showcase: polygon-shaped windows

`setShape` lets the OS window itself be non-rectangular — pixels outside
the polygon don't paint AND clicks pass through to the desktop. A small
runnable example lives at `example/polygon_demo`:

![10 polygon-shaped counter windows running side by side](screenshots/polygon_promo.png)

```dart
await WindowManager.instance.setFrameless(true);
await WindowManager.instance.setShape([
  for (var i = 0; i < 6; i++)
    Offset(180 + 180 * cos(-pi / 2 + i * pi / 3),
           180 + 180 * sin(-pi / 2 + i * pi / 3)),
]);
```

## Migrating from 0.2.x

`dependencies: icefelix_window_manager: ^0.3.0` — that's it. If you ever called `IcefelixWindowManagerMacos.registerWith()` or `IcefelixWindowManagerWindows.registerWith()` directly, remove those calls. Flutter now auto-registers the plugin via the pubspec `pluginClass` declarations. Nothing else changes.

## Linux

Linux support (X11 + Wayland via GTK 3) ships in v0.4.0. Both display servers are supported; Wayland's position-is-null reality is honored via the existing nullable `WindowBoundsRaw.position` field. See CHANGELOG.md for known limitations (`setShape` is a no-op pending a follow-up patch). Track development on [GitHub](https://github.com/ICE-Felix/icefelix-window-manager).

## License

BSD-3-Clause © 2026 icefelix.com — Alex Bordei <alex.bordei@icefelix.com>
