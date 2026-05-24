# Adding Linux support to icefelix_window_manager

This guide is for the agent (human or Claude) implementing the Linux
backend for `icefelix_window_manager` as of v0.4. Read [`CLAUDE.md`](../CLAUDE.md)
first.

**Target:** the existing `icefelix_window_manager` package gets a `linux/`
sibling to `macos/Classes/` and `windows/`. It ships as v0.4.0. No new
package — this is a mono plugin since v0.3.0.

**Estimated effort:** 6-8 weeks. Linux is harder than Windows because
you need to support BOTH X11 and Wayland, and Wayland deliberately
hides things X11 exposes.

---

## What the work looks like, end to end

1. Add `linux/` directory next to `macos/` and `windows/` in
   `packages/icefelix_window_manager/`.
2. Update `pubspec.yaml` to add a `flutter.plugin.platforms.linux`
   block with `pluginClass: IcefelixWindowManagerPluginCApi` (or similar).
3. Regenerate Pigeon to emit GObject C bindings into `linux/`:
   ```dart
   // In pigeons/window_api.dart
   gobjectHeaderOut: 'linux/messages.g.h',
   gobjectSourceOut: 'linux/messages.g.cc',
   gobjectOptions: GObjectOptions(module: 'icefelix_window_manager'),
   ```
4. Implement every `WindowHostApi` method in C/C++ using GTK 3 + GdkScreen
   for X11, plus libdecor + xdg-shell for Wayland-specific bits.
5. Port the integration tests at `example/integration_test/` to Linux —
   most pass as-is since they target the cross-platform API surface.
6. Add Linux-specific tests for Wayland's `position == null` reality.
7. Update README and CHANGELOG. Bump version to `0.4.0`.
8. `dart pub publish` (single package — no federation dance).

---

## Native API mapping reference

Use this as a checklist. Each row maps the macOS Swift implementation
(your behavioral spec) to its Linux equivalent. For platform-specific
quirks see [the original Linux porting notes](https://github.com/ICE-Felix/icefelix-window-manager/blob/main/docs/PORT_TO_LINUX.md)
if you find this file's predecessor in git history.

### The X11 vs Wayland split — read first

Linux has two display servers in production:

- **X11 (Xorg)** — older, permissive, exposes window position to clients
- **Wayland** — newer, security-focused, **does NOT expose window position
  to clients**. Window geometry is owned by the compositor.

Your plugin must support both. Detect at runtime via `XDG_SESSION_TYPE`
or `WAYLAND_DISPLAY`. The Pigeon schema is already designed for this
gap — `WindowBoundsRaw.position` is nullable. On Wayland, set it to
`null`. On X11, populate it.

### Bounds

| API | GTK |
|---|---|
| `getBounds()` | `gtk_window_get_size` + `gtk_window_get_position` (returns 0,0 on Wayland — surface as null) |
| `setBounds()` | `gtk_window_resize` + `gtk_window_move` (move is no-op on Wayland) |
| `setSize` | `gtk_window_resize(window, w, h)` |
| `setMinSize/MaxSize` | `gtk_window_set_geometry_hints(GDK_HINT_MIN_SIZE / MAX_SIZE)` — **honor frame coords like macOS/Windows do**; you may need to add the decoration height from `gdk_window_get_frame_extents` |
| `setPosition` | `gtk_window_move` (no-op on Wayland) |
| `center` | `gtk_window_set_position(GTK_WIN_POS_CENTER)` |

### State

| API | GTK |
|---|---|
| `minimize/maximize/unmaximize/restore` | `gtk_window_iconify/maximize/unmaximize/deiconify` |
| `fullscreen/exitFullscreen` | `gtk_window_fullscreen/unfullscreen` |
| `show/hide` | `gtk_widget_show/hide(GTK_WIDGET(window))` |

### Properties

| API | GTK |
|---|---|
| `setTitle` | `gtk_window_set_title` |
| `setAlwaysOnTop` | `gtk_window_set_keep_above` (Wayland needs `wlr-layer-shell` extension) |
| `setSkipTaskbar` | `gtk_window_set_skip_taskbar_hint` |
| `setResizable` | `gtk_window_set_resizable` |
| `setClosable` | `gtk_window_set_deletable` |
| `setFrameless` | `gtk_window_set_decorated(!frameless)` |
| `setOpacity` | `gtk_widget_set_opacity` |
| `setIcon` | `gtk_window_set_icon_from_file` |

### Drag, resize, shape

| API | GTK |
|---|---|
| `startDrag` | `gtk_window_begin_move_drag` (call from button-press handler) |
| `startResize(direction)` | `gtk_window_begin_resize_drag(window, GdkWindowEdge, ...)` |
| `setShape` | X11 SHAPE extension (XShapeCombineRegion) for true hit-test; Wayland needs xdg-surface input region. Deferring to a follow-up patch is acceptable |

### Multi-monitor

| API | GTK |
|---|---|
| `displays.list` | `gdk_display_get_monitors` (GTK 3.22+) |
| `displays.getCurrent` | `gdk_display_get_monitor_at_window` |
| Stable ID | `gdk_monitor_get_model + gdk_monitor_get_manufacturer` concatenated (Linux has no equivalent to macOS's CGDirectDisplayID) |
| Hot-plug | `GdkDisplay::monitor-added/-removed/-changed` signals |

### Close interception

Connect to GTK's `delete-event` signal — return `FALSE` to allow, `TRUE`
to block. This is the GTK analog of macOS `windowShouldClose:` and
Windows `WM_CLOSE`. Fire `onCloseRequest` via Pigeon and respect the
sync verdict (same `sync: true` events stream contract as the other
platforms).

### Event coalescing

Mirror the macOS pattern (`scheduleSnapshotEmit` at 10ms). On Linux, use
`g_timeout_add(10, ..., self)` to schedule the snapshot emit; cancel and
reschedule on each new event. Hook these signals:
- `size-allocate` → resize
- `configure-event` → move + resize
- `window-state-event` → state change
- `focus-in-event` / `focus-out-event` → focus

---

## Pitfalls specific to Linux

1. **`gtk_window_get_position` is unreliable on Wayland** — returns 0,0
   always. Set snapshot.bounds.position to null when on Wayland; don't
   pretend.
2. **Fractional DPI scaling** — different compositors handle this
   differently. Test on at least GNOME (X11 + Wayland) and KDE Plasma.
3. **`gdk_monitor_get_width_mm` returns 0** for virtual displays or VMs.
   Handle the null case in DisplayRaw.
4. **`always-on-top` on Wayland** is broken on most compositors without
   wlr-layer-shell. If you can't get it working, document as best-effort
   in README and let snapshot.alwaysOnTop reflect the request even if
   the compositor ignores it.
5. **GDK signal handlers must not block** — Pigeon calls back to Dart
   are async-safe. Use `g_main_context_invoke` to marshal from non-main
   threads if needed.
6. **GTK 3 is in maintenance mode** — GTK 4 is the future but Flutter
   Linux still uses GTK 3. Target `>= 3.22` (for GdkMonitor APIs). GTK 4
   port can wait until Flutter Linux migrates.

---

## Done-when checklist for v0.4.0

- [ ] Plugin builds and runs on both X11 and Wayland sessions
- [ ] All 42 `WindowHostApi` methods implemented (no-op where the platform
      genuinely can't, with clear docstrings)
- [ ] FlutterApi callbacks fire correctly via GTK signals
- [ ] Frame-vs-content size handled correctly — the test
      `setMaxSize is honored by maximize() in frame coords` passes
- [ ] All 10 existing macOS integration tests pass on Linux (X11)
- [ ] Non-position tests pass on Wayland; position-related tests have
      Wayland-specific variants that expect null
- [ ] At least 2 X11-specific and 2 Wayland-specific integration tests
- [ ] Pana score ≥140/160
- [ ] `flutter pub publish --dry-run` clean
- [ ] README + CHANGELOG updated for v0.4.0 (Linux row added to platform
      support table)
- [ ] PR opened against main and merged
- [ ] Tag v0.4.0 + GitHub Release
- [ ] `dart pub publish` — single package, no federation coordination
