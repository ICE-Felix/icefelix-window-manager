# Porting guide — adding a new platform to icefelix_window_manager

You are reading this because you (a human or a fresh Claude agent on a
non-macOS machine) are picking up the project to implement a new platform
target. v0.1.0 shipped with macOS only. Windows and Linux are the next
two milestones.

This document is the **shared entry point**. The platform-specific guides
are:

- [`PORT_TO_WINDOWS.md`](PORT_TO_WINDOWS.md) — Win32 + DWM, target v0.2.0
- [`PORT_TO_LINUX.md`](PORT_TO_LINUX.md) — X11 + Wayland via libdecor, target v0.3.0

Read this file first. Then go to the one for your platform.

---

## What you are picking up

A federated Flutter plugin for desktop window management — controlling
your app's own window (size, position, state, multi-monitor, frameless,
events) through a single reactive snapshot. Published on pub.dev:

- [`icefelix_window_manager`](https://pub.dev/packages/icefelix_window_manager) — app-facing API (1 package, all platforms)
- [`icefelix_window_manager_platform_interface`](https://pub.dev/packages/icefelix_window_manager_platform_interface) — Pigeon schema + abstract base class
- [`icefelix_window_manager_macos`](https://pub.dev/packages/icefelix_window_manager_macos) — Swift + AppKit, **reference implementation**

Your job: add `icefelix_window_manager_windows` (or `_linux`), publish at
`0.1.0` of that package, and bump the app-facing package to declare the
new platform in its `pubspec.yaml` (`platforms:` section).

GitHub: https://github.com/ICE-Felix/icefelix-window-manager
License: BSD-3-Clause.

---

## How to pick this up cleanly

```bash
git clone https://github.com/ICE-Felix/icefelix-window-manager.git
cd icefelix-window-manager
git checkout main
git log --oneline -5
```

You should see commits up to and including `release: v0.1.0` (or later).
There is a tag `v0.1.0` on the macOS release. Branch off main with:

```bash
git checkout -b feature/windows-impl   # or feature/linux-impl
```

Do all your work on this branch. Merge to main only when the platform
package is ready to publish.

---

## Toolchain — same on every platform

```bash
# Dart + Flutter
flutter --version                      # need >= 3.27.0 stable
dart --version                          # need >= 3.6.0

# Melos (workspace manager)
dart pub global activate melos          # version 7.x

# Pana (pub.dev score checker — install before publishing)
dart pub global activate pana

# Pigeon (schema codegen — only needed if you modify pigeons/window_api.dart)
# Already a dev_dependency of icefelix_window_manager_platform_interface
```

Bootstrap the workspace once after cloning:

```bash
melos bootstrap
```

This resolves all 4 packages (3 published + 1 example) with path
overrides so changes to platform_interface immediately reflect in
consumers without a publish round-trip.

---

## Repo layout

```
icefelix-window-manager/
├── CHANGELOG.md                   # workspace-level highlights
├── README.md                      # platform-support matrix
├── melos.yaml                     # workspace config
├── docs/                          # this directory
│   ├── PORTING.md                 # ← you are here
│   ├── PORT_TO_WINDOWS.md
│   └── PORT_TO_LINUX.md
└── packages/
    ├── icefelix_window_manager/                      # app-facing
    │   ├── lib/src/                                  # ← DO NOT modify (consumes the platform interface)
    │   ├── example/main.dart                         # minimal example
    │   ├── CHANGELOG.md
    │   ├── LICENSE
    │   └── pubspec.yaml
    ├── icefelix_window_manager_platform_interface/   # abstract base + Pigeon
    │   ├── pigeons/window_api.dart                   # ← CONTRACT — change ONLY if absolutely needed
    │   ├── lib/src/messages.g.dart                   # ← generated, never edit by hand
    │   ├── lib/src/window_manager_platform.dart      # abstract base class
    │   └── example/main.dart                         # platform-impl skeleton
    ├── icefelix_window_manager_macos/                # ← REFERENCE IMPLEMENTATION
    │   ├── macos/Classes/IcefelixWindowManagerMacosPlugin.swift   # the Swift impl
    │   ├── macos/Classes/Messages.g.swift                         # Pigeon-generated, never edit
    │   ├── lib/icefelix_window_manager_macos.dart                 # Dart-side registerWith()
    │   ├── example/                                               # full testbed Flutter app
    │   │   ├── lib/main.dart                                      # 27-control testbed UI
    │   │   └── integration_test/window_manager_integration_test.dart  # 9 tests on real NSWindow
    │   └── pubspec.yaml
    └── icefelix_window_manager_<your_platform>/      # ← YOU CREATE THIS
```

---

## What you absolutely must NOT change

1. **`pigeons/window_api.dart`** — this is the contract between every
   platform and the app-facing Dart code. Adding a method ripples through
   all 3 platforms and all consumer code. If you think you need a change,
   open an issue first and discuss. Generally, your impl must support
   every existing method — return reasonable defaults / no-ops where the
   platform doesn't have an analog (e.g. `setSkipTaskbar` on macOS is a
   tracked flag; Wayland doesn't expose window position so `position` is
   null in the snapshot — schema is already nullable for that).

2. **`platform_interface/lib/src/window_manager_platform.dart`** — the
   abstract base. Your impl extends this. Adding methods here ripples the
   same way as the Pigeon schema.

3. **`icefelix_window_manager/lib/src/`** — the app-facing API surface
   was frozen at v0.1.0. Bug fixes only.

What you DO change:
- Create `packages/icefelix_window_manager_<platform>/` from scratch
- Update `icefelix_window_manager/pubspec.yaml` `platforms:` section to
  add yours
- Bump `icefelix_window_manager/version` to `0.2.0` (Windows) or
  `0.3.0` (Linux)

---

## The Pigeon contract — what every platform impl must do

The Pigeon schema defines 42 `WindowHostApi` methods (Dart → native)
and 3 `WindowFlutterApi` callbacks (native → Dart). Your impl:

1. Subclasses `WindowManagerPlatform` (Dart-side, public)
2. Implements `WindowHostApi` in native code
3. Fires `WindowFlutterApi` callbacks from the native side when window
   state changes

The **mandatory** native surface (40 methods, all must work):

```
ensureInitialized() → WindowSnapshotRaw

# Bounds (6 methods)
getBounds, setBounds, setSize, setMinSize, setMaxSize, setPosition, center, moveToDisplay

# State (10 methods)
minimize, maximize, unmaximize, restore, fullscreen, exitFullscreen,
show, hide, focus, blur

# Drag/resize (3 methods)
startDrag, startResize

# Lifecycle (3 methods)
close, destroy, setPreventClose

# Title + props (8 methods)
setTitle, setAlwaysOnTop, setSkipTaskbar, setResizable, setMovable,
setMinimizable, setMaximizable, setClosable

# Visual (5 methods)
setFrameless, setTitleBarStyle, setOpacity, setBackgroundColor, setHasShadow, setIcon

# Multi-monitor (5 methods)
displays.list, displays.getCurrent, displays.getPrimary, displays.events
```

The **mandatory** FlutterApi callbacks fired from native:

- `onSnapshotChanged(WindowSnapshotRaw)` — fire whenever the window
  state changes (resize, move, focus, state, title, etc.). Coalesce at
  10ms — see the macOS impl's `scheduleSnapshotEmit()` pattern.
- `onDisplaysChanged(List<DisplayRaw>)` — fire when monitors are
  added/removed/reconfigured.
- `onCloseRequest(int requestId)` → returns `bool` — sync close
  interception. Return `true` to allow close, `false` to prevent.

---

## The big rule we learned the hard way — coordinate space

ALL of these MUST share the same coordinate space:

- `setSize(size)` — applies to the **frame** (the whole window including
  titlebar, on platforms that have one)
- `setMinSize(size)` and `setMaxSize(size)` — same, frame coords
- `getBounds()` and the snapshot's `bounds.size` — same, frame coords

On macOS we picked frame coords (using `NSWindow.minSize` / `maxSize` /
`setFrame` / `window.frame`). **You must mirror this.** If your platform
distinguishes content from frame (Win32 does — `GetWindowRect` is frame,
`GetClientRect` is content; X11 is more complex), pick **frame** every
time. The integration tests will fail otherwise.

See `packages/icefelix_window_manager_macos/example/integration_test/window_manager_integration_test.dart`,
specifically the test `setMaxSize is honored by maximize() in frame coords`.
That test exists because we had a bug where macOS used `contentMaxSize`
and `setMaxSize(1200, 900)` followed by `maximize()` produced 1200×928
(28px overshoot, the titlebar height). Don't repeat that mistake on
Windows or Linux.

---

## Testing strategy

You need **three** levels of evidence before publishing:

1. **Unit tests** — Dart-side, fake your platform impl, verify the
   app-facing API and platform_interface base class. These already exist
   for macOS (74 tests). The Dart side is platform-agnostic; you mostly
   add tests for your registerWith() and any Dart wrappers.

2. **Integration tests on real native window** — port the 9 tests in
   `packages/icefelix_window_manager_macos/example/integration_test/`
   to your platform. Each test calls a public API method (setSize,
   setTitle, etc.) and waits for the snapshot to converge. Run on a
   real Windows / Linux machine. **All 9 must pass before publish.**

3. **Runtime audit harness** — port the testbed app at
   `packages/icefelix_window_manager_macos/example/lib/main.dart` to
   your platform. This is the manual visual verification — click every
   button, watch the snapshot HUD update, verify the visual matches.
   Take screenshots. Compare against the macOS testbed shots in PRs.

The audit harness is what caught the 28-pixel bug on macOS. Neither unit
nor integration tests would have. Run it.

---

## Publishing workflow

When your platform impl is ready:

```bash
# 1. Bump version + update CHANGELOG in your platform package
# 2. Bump app-facing package version (0.2.0 for Windows, 0.3.0 for Linux)
#    and add your platform to its pubspec platforms: section
# 3. Run pana on every changed package — target ≥140/160
dart pub global run pana .

# 4. Dry-run publish
flutter pub publish --dry-run

# 5. Commit + tag + push
git add ...
git commit -m "release: v0.2.0 — Windows implementation"
git tag -a v0.2.0 -m "..."
git push origin <branch>
git push origin v0.2.0

# 6. Open PR to main
gh pr create --title "Add Windows platform implementation"

# 7. After merge to main, publish in dependency order:
#    - Your platform package first
#    - Wait ~1 min for pub.dev indexing
#    - Then the app-facing package (its version bump declaring your platform)
dart pub publish    # from your platform package directory
# wait
dart pub publish    # from icefelix_window_manager directory

# 8. GitHub release
gh release create v0.2.0 --notes-file ...
```

---

## When you get stuck

1. **The macOS Swift impl is your spec.** When in doubt about what a
   method should do, read what `IcefelixWindowManagerMacosPlugin.swift`
   does for that method. The behavior is the contract.

2. **Pigeon docstrings.** Each method in `pigeons/window_api.dart` has a
   docstring explaining intent. Read them.

3. **The integration tests are executable spec.** If you can make all 9
   pass on your platform, the impl is structurally correct.

4. **Open an issue on GitHub before doing anything weird.** Tag
   @alexbordei. The plugin's API surface is more important than your
   platform's specific quirks — sometimes the right answer is to add a
   nullable field to the schema, sometimes it's to no-op gracefully.

Good luck. The macOS impl is ~1200 lines of Swift. Your impl will likely
be 1000-1500 lines of C++ or Rust (or Swift, on macOS-adjacent things).
Plan for 4-6 weeks of solid work for Windows; 6-8 weeks for Linux
because of the X11+Wayland split.
