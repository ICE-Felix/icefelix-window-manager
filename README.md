# icefelix_window_manager

Cross-platform window management for Flutter desktop apps — your app, your
window. Control size, position, state, multi-monitor placement, frameless
mode, custom window shapes, title bar style, opacity, shadow, drag/resize
regions, and listen to window/display events through a single reactive
snapshot.

**v0.3.0 — single package, native macOS + Windows.** v0.2.x shipped as
four federated packages; v0.3.0 collapses them into one — same API, same
behavior, just one dependency.

## Platform support

| Platform | Status | Native stack |
|---|---|---|
| macOS 10.15+ | ✅ Shipping | Swift + AppKit (NSWindow) |
| Windows 10+ | ✅ Shipping | C++ + Win32 |
| Linux (X11 + Wayland) | ⏳ Planned for v0.4 | GTK 3 + libdecor |

Mobile (iOS, Android) and web are out of scope — Flutter does not give an
embedded app control over the host window on those platforms.

## Install

```yaml
dependencies:
  icefelix_window_manager: ^0.3.0
```

That's it. No `_macos` / `_windows` / `_platform_interface` to add — those
0.2.x packages are now discontinued and their content lives inside the
single package above.

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:icefelix_window_manager/icefelix_window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowManager.instance.ensureInitialized();
  runApp(const MyApp());
}
```

See per-package README at [`packages/icefelix_window_manager/`](packages/icefelix_window_manager/)
for the full API + the testbed at `example/` exercising every method on
both platforms.

## Migrating from 0.2.x

```yaml
# Before
dependencies:
  icefelix_window_manager: ^0.2.0   # was the only thing you wrote anyway

# After
dependencies:
  icefelix_window_manager: ^0.3.0   # same one-liner; fewer transitive deps now
```

If your code called `IcefelixWindowManagerMacos.registerWith()` or
`IcefelixWindowManagerWindows.registerWith()` directly, **remove those
calls** — Flutter now auto-registers via the pubspec `pluginClass`
declarations.

## License

BSD-3-Clause © 2026 icefelix.com (Alex Bordei)
