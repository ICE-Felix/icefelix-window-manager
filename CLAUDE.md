# Agent onboarding — icefelix_window_manager

This file is auto-loaded by Claude Code when working in this repository.
If you are a fresh agent picking up this project on Windows or Linux to
implement the next platform target, **read `docs/PORTING.md` first**,
then the platform-specific guide:

- Windows → [`docs/PORT_TO_WINDOWS.md`](docs/PORT_TO_WINDOWS.md)
- Linux → [`docs/PORT_TO_LINUX.md`](docs/PORT_TO_LINUX.md)

Those documents are self-contained briefs — toolchain, architecture,
API mapping, pitfalls, done-when criteria.

## Repository at a glance

A federated Flutter desktop plugin for window management. v0.1.0
shipped 2026-05-22 with macOS only. Windows = v0.2.0, Linux = v0.3.0.

```
packages/
├── icefelix_window_manager/                      app-facing API
├── icefelix_window_manager_platform_interface/   abstract base + Pigeon schema (the CONTRACT)
├── icefelix_window_manager_macos/                Swift + AppKit reference impl
└── icefelix_window_manager_<platform>/           your target — create from scratch
```

## Hard rules

1. **Do not modify `pigeons/window_api.dart`** unless you have an open
   issue with rationale. The schema is shared across all platforms.

2. **Do not modify `icefelix_window_manager/lib/src/`** — the
   app-facing API surface is frozen at v0.1.0. Bug fixes only.

3. **The macOS Swift code at `packages/icefelix_window_manager_macos/macos/Classes/IcefelixWindowManagerMacosPlugin.swift`
   is your behavioral spec.** When in doubt about what a method should
   do, read the Swift impl. Your native impl mirrors its semantics.

4. **All four size APIs share the same coordinate space — frame
   coordinates (titlebar included).** `setSize`, `setMinSize`,
   `setMaxSize`, `snapshot.bounds.size`. We had a bug here on macOS
   (1200×900 max + maximize → 1200×928); test
   `setMaxSize is honored by maximize() in frame coords` exists
   specifically to prevent it on every platform. Make it pass first.

5. **Use the testbed app at `packages/icefelix_window_manager_macos/example/lib/main.dart`
   as the manual verification target.** Port it to your platform —
   every control on it must produce a visible AND snapshot-confirmed
   change.

## Tooling

```bash
flutter --version       # >= 3.27.0 stable
dart pub global activate melos
melos bootstrap         # run once after cloning
```

After making changes:

```bash
melos run analyze       # static analysis on all packages
# Per-package unit tests
cd packages/<your_pkg> && flutter test
# Integration tests (must pass on the real native platform)
cd packages/<your_pkg>/example && flutter test integration_test/ -d <linux|windows>
```

## Publishing workflow (when ready)

See `docs/PORTING.md` "Publishing workflow". TL;DR:

1. Bump versions in your platform package and the app-facing one
2. Run pana — target ≥140/160 on each
3. `flutter pub publish --dry-run` per package
4. Commit, tag (v0.2.0 for Windows / v0.3.0 for Linux), push
5. Open PR, merge after review
6. Publish in dependency order: platform package first, wait ~1 min,
   then app-facing
7. `gh release create` with notes

## When stuck

- Open a GitHub issue: https://github.com/ICE-Felix/icefelix-window-manager/issues
- The integration tests are the executable spec. If your impl makes the
  9 macOS-equivalent integration tests pass on your platform, it's
  structurally correct.
- Tag @alexbordei in PRs / issues for review.

Good luck.
