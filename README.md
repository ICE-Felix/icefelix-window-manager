# icefelix_window_manager

Cross-platform window management for Flutter desktop — macOS, Windows, Linux (X11+Wayland).

⚠️ **Work in progress** — v0.1.0-dev. Public API stable when v0.1.0 ships (~26 June 2026).

## Status

- ✅ **W1: Dart foundation + Pigeon schema (2026-05-22)** — all Dart-side API + 69 unit tests
- ⏳ W2: macOS native impl (Swift + AppKit)
- ⏳ W3: Windows native impl (C++ + Win32)
- ⏳ W4: Linux native impl (C++ + GTK + libdecor for Wayland)
- ⏳ W5: Example app + 5+ scenarios + launch

## Packages

| Package | Purpose | pub.dev |
|---|---|---|
| `icefelix_window_manager` | app-facing | (pending publish) |
| `icefelix_window_manager_platform_interface` | abstract API + Pigeon | (pending publish) |

## License

BSD-3-Clause © 2026 icefelix.com (Alex Bordei)
