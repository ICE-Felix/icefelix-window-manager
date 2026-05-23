# Porting to Linux — implementation guide

**Target:** `icefelix_window_manager_linux` package, published at v0.1.0,
app-facing bumped to v0.3.0 declaring Linux support.

**Estimated effort:** 6-8 weeks. Linux is harder than Windows because
you need to support BOTH X11 and Wayland, and Wayland deliberately
hides things X11 exposes.

**Prerequisite reading:**
- [`PORTING.md`](PORTING.md) — shared context
- [`PORT_TO_WINDOWS.md`](PORT_TO_WINDOWS.md) — handy reference for the Pigeon-method-to-native mapping pattern

---

## The X11 vs Wayland split — read first

Linux has two display servers in production today:

1. **X11** (Xorg) — older, more permissive, exposes window position to
   clients, has well-known APIs (Xlib, xcb). Used on most LTS distros.
2. **Wayland** — newer, security-focused, **does NOT expose window
   position to clients**. Window geometry is owned by the compositor.
   Used on Fedora, Ubuntu 22.04+, GNOME default.

Your plugin must support both. Detect at runtime which one is active
(`XDG_SESSION_TYPE` env var, or check for `WAYLAND_DISPLAY`). The schema
already supports the Wayland gap: `WindowBoundsRaw.position` is
nullable. When on Wayland, set it to `null` in the snapshot.

Implications for the API contract:

| API | X11 | Wayland |
|---|---|---|
| `getBounds().position` | real value | **null** |
| `setPosition(p)` | works | **no-op** with optional warning log |
| `moveToDisplay(id)` | works | **no-op** (compositor decides which output a window is on) |
| `setBounds(b, displayId)` | works fully | only `size` honored; `position` and `displayId` ignored |

Document this clearly in the Dart-side `IcefelixWindowManagerLinux` class.

---

## Toolchain prerequisites

```bash
# Ubuntu/Debian (other distros: equivalent packages)
sudo apt install -y \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev \
  libx11-dev libxcb1-dev libxcb-icccm4-dev libxcb-randr0-dev libxcb-xinerama0-dev \
  libwayland-dev wayland-protocols libdecor-0-dev libxkbcommon-dev

# Verify Flutter Linux toolchain
flutter doctor -v
# Look for [✓] Linux toolchain - develop for Linux desktop

# Verify both session types are available for testing
echo $XDG_SESSION_TYPE   # should be 'x11' or 'wayland'
```

Set up dual-environment testing:
- One VM (or session) running X11 (most distros: select "GNOME on Xorg" at login)
- One running Wayland (default GNOME on modern Fedora/Ubuntu)

You will run integration tests on BOTH before publishing.

---

## Architecture decision — GTK vs raw protocol

Flutter Linux uses **GTK 3** for windowing. Your plugin has two
implementation strategies:

**A) Use GTK APIs throughout** (simplest, most portable)
- `gtk_window_set_default_size`, `gtk_window_move`, `gtk_window_resize`
- Works on both X11 and Wayland (GTK abstracts over both)
- Limitation: GTK doesn't expose everything (e.g. precise X11
  `_NET_WM_*` hints sometimes need raw xcb)

**B) Dual-path X11/Wayland with GTK fallback**
- Detect session at startup
- X11 path uses xcb directly for fine-grained control
- Wayland path uses libdecor + xdg-shell for client-side decorations
- Falls back to GTK for everything else

**Recommendation: start with A.** It's faster, covers ~90% of the API,
and works on both session types. Add specific raw-protocol calls only
where GTK is provably insufficient (likely: `setAlwaysOnTop` on Wayland
requires `xdg-foreign-v2` or `wlr-layer-shell`).

---

## Step 1 — Scaffold the package

```bash
cd packages
flutter create --org com.icefelix --template=plugin --platforms=linux icefelix_window_manager_linux
```

Delete the scaffolded Dart and example, keep the Linux native scaffold.

```yaml
# packages/icefelix_window_manager_linux/pubspec.yaml
name: icefelix_window_manager_linux
description: >-
  Linux (X11 + Wayland) implementation of icefelix_window_manager. Uses
  GTK 3 + libdecor for client-side decorations on Wayland. App developers
  depend on icefelix_window_manager, not this package.
version: 0.1.0
repository: https://github.com/ICE-Felix/icefelix-window-manager
issue_tracker: https://github.com/ICE-Felix/icefelix-window-manager/issues
homepage: https://icefelix.com/packages/window-manager

topics: [window, desktop, linux]

environment:
  sdk: ^3.6.0
  flutter: ">=3.27.0"

dependencies:
  flutter:
    sdk: flutter
  icefelix_window_manager_platform_interface: ^0.1.0

dev_dependencies:
  flutter_lints: ^5.0.0
  flutter_test:
    sdk: flutter

flutter:
  plugin:
    implements: icefelix_window_manager
    platforms:
      linux:
        pluginClass: IcefelixWindowManagerLinuxPlugin
        dartPluginClass: IcefelixWindowManagerLinux
```

Run `melos bootstrap`.

---

## Step 2 — Generate Pigeon C++ bindings for Linux

Same as Windows — Linux uses C/C++. Add a script to `melos.yaml`:

```yaml
scripts:
  pigeon_linux:
    description: Regenerate Pigeon C bindings for Linux (GLib/GObject)
    run: |
      cd packages/icefelix_window_manager_platform_interface && \
      dart run pigeon --input pigeons/window_api.dart \
        --gobject_header_out ../icefelix_window_manager_linux/linux/messages.g.h \
        --gobject_source_out ../icefelix_window_manager_linux/linux/messages.g.cc \
        --gobject_module icefelix_window_manager_linux
```

Pigeon's GObject backend generates idiomatic C with GLib types
(`gchar*`, `gboolean`, etc.). This is the format Flutter Linux expects.

---

## Step 3 — API mapping (GTK-first approach)

### Setup

```c
// Plugin entry point
void icefelix_window_manager_linux_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  // Get the main GtkWindow from the FlView
  FlView* view = fl_plugin_registrar_get_view(registrar);
  GtkWindow* window = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  // ... initialize host_api, register channels, attach signals
}
```

### Bounds

| API | GTK | X11-specific (if needed) | Wayland note |
|---|---|---|---|
| `getBounds()` | `gtk_window_get_size` + `gtk_window_get_position` | `XGetWindowAttributes` for raw frame including WM decorations | position is null |
| `setBounds(b, displayId)` | `gtk_window_resize` + `gtk_window_move` | — | position ignored |
| `setSize(s)` | `gtk_window_resize(window, w, h)` | — | works |
| `setMinSize(s)` | `gtk_window_set_geometry_hints(... GDK_HINT_MIN_SIZE)` | — | works but enforcement is compositor-dependent on Wayland |
| `setMaxSize(s)` | `gtk_window_set_geometry_hints(... GDK_HINT_MAX_SIZE)` | — | same as above |
| `setPosition(p)` | `gtk_window_move(window, x, y)` | — | **no-op on Wayland** |
| `center()` | `gtk_window_set_position(window, GTK_WIN_POS_CENTER)` | — | works |
| `moveToDisplay(id)` | `gtk_window_set_screen` (deprecated in GTK3, use `gtk_window_move` with explicit coords) | translate via monitor geometry from `GdkDisplay` | **no-op on Wayland** |

**The frame-vs-content rule** — GTK's `gtk_window_get_size` returns the
**content** size by default, NOT the frame (decorations excluded). To
match macOS frame semantics, you must include the decoration geometry:
`gdk_window_get_frame_extents(window->window, &frame_rect)`.

This is exactly the trap we hit on macOS with `contentMinSize`. Mirror
the macOS choice: `bounds.size` is the **frame including decorations**.
Add 28-30px (the typical decoration height) on top of the content size.
On Wayland with libdecor, decorations are client-side — use libdecor's
`libdecor_frame_get_content_size` and add the configured decoration
height.

This is the single most error-prone area of the Linux port. Write the
test FIRST: `setMaxSize(1200, 900) + maximize() → snapshot.bounds.size
<= (1200, 900)`. Make it pass.

### State

| API | GTK |
|---|---|
| `minimize()` | `gtk_window_iconify(window)` |
| `maximize()` | `gtk_window_maximize(window)` |
| `unmaximize()` | `gtk_window_unmaximize(window)` |
| `restore()` | `gtk_window_deiconify` and/or `gtk_window_unmaximize` |
| `fullscreen()` | `gtk_window_fullscreen(window)` |
| `exitFullscreen()` | `gtk_window_unfullscreen(window)` |
| `show()` | `gtk_widget_show(GTK_WIDGET(window))` |
| `hide()` | `gtk_widget_hide(GTK_WIDGET(window))` |
| `focus()` | `gtk_window_present(window)` (Wayland: best-effort) |
| `blur()` | no direct GTK API — focus another window or no-op |

### Title + properties

| API | GTK |
|---|---|
| `setTitle(s)` | `gtk_window_set_title(window, s)` |
| `setAlwaysOnTop(b)` | `gtk_window_set_keep_above(window, b)`. On Wayland may need `wlr-layer-shell` extension |
| `setSkipTaskbar(b)` | `gtk_window_set_skip_taskbar_hint(window, b)` |
| `setResizable(b)` | `gtk_window_set_resizable(window, b)` |
| `setMovable(b)` | No direct GTK API. X11: handle `WM_NCHITTEST` analog via window manager hints. Document as best-effort |
| `setMinimizable(b)` | `gtk_window_set_type_hint(GDK_WINDOW_TYPE_HINT_*)` — limited |
| `setMaximizable(b)` | Window manager hint — best-effort |
| `setClosable(b)` | `gtk_window_set_deletable(window, b)` |

### Visual

| API | GTK |
|---|---|
| `setFrameless(b)` | `gtk_window_set_decorated(window, !b)` |
| `setTitleBarStyle(s)` | `hidden` maps to `gtk_window_set_decorated(false)` + custom GtkHeaderBar; `hiddenInset` is GTK's `gtk_window_set_titlebar` with a transparent header |
| `setOpacity(d)` | `gtk_widget_set_opacity(GTK_WIDGET(window), d)` |
| `setBackgroundColor(c)` | Set via CSS: `gtk_widget_override_background_color` (deprecated, but works) or set via `GtkStyleContext` with a CSS provider |
| `setHasShadow(b)` | GTK doesn't expose this directly. On X11, set `_GTK_FRAME_EXTENTS` window property. On Wayland, libdecor controls shadow via `libdecor_frame_set_visibility` |
| `setIcon(path)` | `gtk_window_set_icon_from_file(window, path, &error)` |

### Drag/resize

| API | GTK |
|---|---|
| `startDrag()` | `gtk_window_begin_move_drag(window, button, x, y, time)` — call from a button-press signal handler |
| `startResize(direction)` | `gtk_window_begin_resize_drag(window, edge, button, x, y, time)` — direction maps to `GdkWindowEdge` (GDK_WINDOW_EDGE_NORTH, _SOUTH_EAST, etc.) |

### Lifecycle

| API | GTK |
|---|---|
| `close()` | `gtk_window_close(window)` — fires "delete-event" signal |
| `destroy()` | `gtk_widget_destroy(GTK_WIDGET(window))` |
| `setPreventClose(b)` | flag — used in `delete-event` signal handler |

The "delete-event" signal is your `windowShouldClose:` analog. Connect a
handler:

```c
gulong handler_id = g_signal_connect(
    window, "delete-event",
    G_CALLBACK(on_delete_event), self);

static gboolean on_delete_event(GtkWidget* widget, GdkEvent* event, gpointer user_data) {
  // Fire onCloseRequest via Pigeon, await sync result.
  // Return FALSE to allow close, TRUE to prevent.
  return user_data_handler_says_prevent ? TRUE : FALSE;
}
```

### Multi-monitor

| API | Approach |
|---|---|
| `displays.list()` | Enumerate `GdkMonitor` via `gdk_display_get_monitors` (GTK 3.22+) |
| `displays.getCurrent()` | `gdk_display_get_monitor_at_window` for the GtkWindow |
| `displays.getPrimary()` | `gdk_display_get_primary_monitor` |
| DisplayId (stable) | Use `gdk_monitor_get_model` + `gdk_monitor_get_manufacturer` concatenated as a string. NOT a numeric ID — Linux doesn't have CGDirectDisplayID-equivalent stable numeric IDs. The Pigeon schema's `DisplayId.value` is a `String`, so this fits |
| Refresh rate | `gdk_monitor_get_refresh_rate(monitor) / 1000.0` (millihertz → hertz) |
| Physical size | `gdk_monitor_get_width_mm` + `gdk_monitor_get_height_mm` (often returns 0 — handle null) |
| Hot-plug events | Connect to `GdkDisplay::monitor-added`, `::monitor-removed`, `::monitor-removed` signals |

---

## Step 4 — Coalesce events (mirror macOS)

GTK signals fire on every change. Hook these and coalesce at 10ms:

- `size-allocate` → resize
- `configure-event` → move + resize
- `window-state-event` → state change (covers maximize, minimize, fullscreen)
- `focus-in-event` / `focus-out-event` → focus
- `delete-event` → close request

Use `g_timeout_add(10, fire_snapshot_callback, self)` to schedule the
emit. Cancel and reschedule on each event. Mirror macOS's
`scheduleSnapshotEmit` pattern.

---

## Step 5 — Port the example testbed

Copy `packages/icefelix_window_manager_macos/example/` to your package
and adjust the runner for Linux. The Flutter side is platform-agnostic.

---

## Step 6 — Port integration tests, run BOTH session types

```bash
# Run on X11
XDG_SESSION_TYPE=x11 flutter test integration_test/ -d linux

# Run on Wayland (in a Wayland session)
flutter test integration_test/ -d linux
```

The 9 macOS tests should pass on X11. On Wayland, a few will need
adjustment:

- `setPosition + snapshot.bounds.position` test — expect null on Wayland
- `moveToDisplay` test — skip on Wayland (or expect no-op)

Add Wayland-specific tests:
- Snapshot's `bounds.position` is `null` on Wayland
- `setBounds(bounds: WindowBoundsRaw(position: ..., size: ...))` ignores
  position silently (no exception)

Add X11-specific tests:
- Multi-monitor `moveToDisplay` works
- Position is preserved across `setSize` calls

---

## Step 7 — Pana, dry-run, publish

Same workflow as Windows. Order:
1. Publish `icefelix_window_manager_linux@0.1.0` first
2. Wait ~1 min
3. Bump `icefelix_window_manager` to 0.3.0 (Linux added to `platforms:`)
4. Publish

---

## Linux-specific pitfalls

1. **Fractional scaling on Wayland** — different compositors handle this
   differently. GNOME has it experimental. Test on at least GNOME and
   KDE Plasma.

2. **`gtk_window_get_position` is unreliable on Wayland** — returns 0,0
   always. Set snapshot.bounds.position to null instead of pretending.

3. **`gdk_monitor_get_width_mm` often returns 0** for virtual displays
   or VMs. Handle the null case in DisplayRaw.

4. **libdecor decoration heights** vary by theme. Don't hardcode 30px;
   query `libdecor_frame_get_content_size` and derive from the frame
   geometry difference.

5. **Always-on-top on Wayland** is broken on most compositors without
   the wlr-layer-shell extension. If you can't get it working, document
   that `setAlwaysOnTop` is best-effort on Wayland and snapshot
   `alwaysOnTop` may not reflect the request.

6. **GDK signal handlers must not block.** All Pigeon calls back to Dart
   must be async-safe. Use `g_main_context_invoke` if you need to
   marshal from a non-main thread.

7. **GTK 3 is in maintenance mode.** GTK 4 is the future, but Flutter
   Linux still uses GTK 3. Your plugin should target GTK 3 ≥ 3.22 (for
   GdkMonitor APIs). GTK 4 port can wait for Flutter Linux to migrate.

8. **HiDPI scaling on X11** is set via `GDK_SCALE` env var or X
   resources. Read `gdk_monitor_get_scale_factor` for the current
   display, but be aware it's integer (1, 2, 3...) — fractional needs
   `gdk_screen_get_monitor_scale_factor` plus DPI math.

---

## Done-when checklist for v0.3.0

- [ ] Plugin builds and runs on both X11 and Wayland sessions
- [ ] All 42 HostApi methods implemented (no-ops where the platform
      genuinely can't, with clear docstrings)
- [ ] FlutterApi callbacks fire correctly under GTK signals
- [ ] Frame-vs-content size handled correctly (test
      `setMaxSize + maximize` passes)
- [ ] All 9 ported macOS integration tests pass on X11
- [ ] All non-position tests pass on Wayland; position-related tests
      have Wayland-specific variants that expect null
- [ ] At least 2 X11-specific and 2 Wayland-specific integration tests
- [ ] Example testbed exercised manually on both X11 and Wayland
- [ ] Pana score ≥140/160
- [ ] `flutter pub publish --dry-run` clean
- [ ] README and CHANGELOG updated
- [ ] PR opened and merged
- [ ] Tag v0.3.0 created and pushed
- [ ] Both packages (`_linux` and `icefelix_window_manager`) published
- [ ] GitHub Release v0.3.0 created

---

## When you must change the schema

If you genuinely cannot implement something within the existing schema
(e.g. you need a new field to surface a Wayland-specific capability),
follow this path:

1. Open a GitHub issue describing the gap with rationale
2. Wait for ack (the schema change ripples to every platform)
3. Bump `icefelix_window_manager_platform_interface` to 0.2.0
4. Update the schema, regenerate, update macOS impl to use the new
   field (typically a no-op default)
5. Then proceed with your Linux impl

Don't fork the schema or add side-channel methods. The whole point of
the federated plugin pattern is one contract.
