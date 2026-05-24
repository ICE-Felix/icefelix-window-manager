// Copyright 2026 icefelix.com. BSD-3-Clause.
//
// Linux platform implementation of icefelix_window_manager.
//
// Etapa 2: wires real GTK 3 behavior to the high-value HostApi methods
// (title, size, min/max, position, center, state, focus, properties).
// Remaining methods are stubs returning success — they get filled in by
// later patches following docs/ADDING_LINUX.md.

#include "include/icefelix_window_manager/icefelix_window_manager_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include "messages.g.h"

struct _IcefelixWindowManagerPlugin {
  GObject parent_instance;

  FlPluginRegistrar* registrar;
  // FlutterApi instance for native -> Dart callbacks (snapshot/displays).
  IcefelixWindowManagerWindowFlutterApi* flutter_api;

  // Tracked flags for properties GTK doesn't expose directly (mirrors macOS).
  gboolean skip_taskbar_flag;
  gboolean maximizable_flag;
  gboolean prevent_close_flag;
  IcefelixWindowManagerTitleBarStyleRaw title_bar_style_flag;
  int64_t background_color_argb_flag;
  gboolean background_color_set;
  gboolean has_shadow_flag;

  // Coalescing timer id for snapshot emit.
  guint snapshot_emit_source;
};

G_DEFINE_TYPE(IcefelixWindowManagerPlugin, icefelix_window_manager_plugin,
              g_object_get_type())

// ============================================================================
// GtkWindow resolution
// ============================================================================

static GtkWindow* get_gtk_window(IcefelixWindowManagerPlugin* self) {
  if (self->registrar == nullptr) return nullptr;
  FlView* view = fl_plugin_registrar_get_view(self->registrar);
  if (view == nullptr) return nullptr;
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  if (toplevel == nullptr || !GTK_IS_WINDOW(toplevel)) return nullptr;
  return GTK_WINDOW(toplevel);
}

// ============================================================================
// Helpers — display + snapshot construction
// ============================================================================

static IcefelixWindowManagerDisplayRaw* make_default_display_raw() {
  // TODO(linux v0.4.x): replace with real gdk_display_get_primary_monitor
  // introspection (model+manufacturer for stable id, scale_factor,
  // refresh_rate, physical size).
  IcefelixWindowManagerRectRaw* bounds =
      icefelix_window_manager_rect_raw_new(0, 0, 1920, 1080);
  IcefelixWindowManagerRectRaw* work_area =
      icefelix_window_manager_rect_raw_new(0, 0, 1920, 1080);
  return icefelix_window_manager_display_raw_new(
      "linux-default-display", "Linux Display", bounds, work_area, nullptr,
      nullptr, nullptr, 1.0, TRUE, nullptr);
}

static IcefelixWindowManagerWindowStateRaw current_state(GtkWindow* window) {
  if (window == nullptr) return ICEFELIX_WINDOW_MANAGER_WINDOW_STATE_RAW_NORMAL;
  GdkWindow* gdk = gtk_widget_get_window(GTK_WIDGET(window));
  GdkWindowState s = gdk == nullptr ? (GdkWindowState)0 : gdk_window_get_state(gdk);
  if (s & GDK_WINDOW_STATE_ICONIFIED)
    return ICEFELIX_WINDOW_MANAGER_WINDOW_STATE_RAW_MINIMIZED;
  if (s & GDK_WINDOW_STATE_FULLSCREEN)
    return ICEFELIX_WINDOW_MANAGER_WINDOW_STATE_RAW_FULLSCREEN;
  if (s & GDK_WINDOW_STATE_MAXIMIZED)
    return ICEFELIX_WINDOW_MANAGER_WINDOW_STATE_RAW_MAXIMIZED;
  if (!gtk_widget_get_visible(GTK_WIDGET(window)))
    return ICEFELIX_WINDOW_MANAGER_WINDOW_STATE_RAW_HIDDEN;
  return ICEFELIX_WINDOW_MANAGER_WINDOW_STATE_RAW_NORMAL;
}

static IcefelixWindowManagerWindowSnapshotRaw* build_snapshot(
    IcefelixWindowManagerPlugin* self) {
  GtkWindow* window = get_gtk_window(self);

  // Bounds — use frame coords (include decorations). On Wayland position is
  // not exposed; gtk_window_get_position returns 0,0 which we surface as null
  // via the schema (WindowBoundsRaw.position is nullable).
  gint w = 800, h = 600, x = 0, y = 0;
  if (window != nullptr) {
    gtk_window_get_size(window, &w, &h);
    gtk_window_get_position(window, &x, &y);
  }
  gboolean is_wayland = g_strcmp0(g_getenv("XDG_SESSION_TYPE"), "wayland") == 0;
  IcefelixWindowManagerOffsetRaw* position =
      is_wayland ? nullptr : icefelix_window_manager_offset_raw_new(x, y);
  IcefelixWindowManagerSizeRaw* size =
      icefelix_window_manager_size_raw_new(w, h);
  IcefelixWindowManagerWindowBoundsRaw* bounds =
      icefelix_window_manager_window_bounds_raw_new(position, size);

  const gchar* title =
      window != nullptr ? gtk_window_get_title(window) : "";
  if (title == nullptr) title = "";

  gboolean is_focused =
      window != nullptr && gtk_window_is_active(window);
  gboolean resizable =
      window != nullptr && gtk_window_get_resizable(window);
  gboolean closable =
      window == nullptr || gtk_window_get_deletable(window);
  gboolean frameless =
      window != nullptr && !gtk_window_get_decorated(window);
  gdouble opacity =
      window != nullptr ? gtk_widget_get_opacity(GTK_WIDGET(window)) : 1.0;

  // For "movable" GTK doesn't expose a getter; mirror tracked flag (assume
  // movable=true unless we explicitly disabled it via WM_NCHITTEST analog).
  // For now, just report TRUE.
  gboolean movable = TRUE;
  gboolean minimizable = TRUE;

  return icefelix_window_manager_window_snapshot_raw_new(
      bounds, current_state(window), title, is_focused,
      /* always_on_top */ FALSE,  // TODO: track via gtk_window_set_keep_above
      /* skip_taskbar */ self->skip_taskbar_flag, resizable, movable,
      minimizable, self->maximizable_flag, closable, frameless,
      self->title_bar_style_flag, opacity,
      self->background_color_set ? &self->background_color_argb_flag : nullptr,
      self->has_shadow_flag, self->prevent_close_flag,
      make_default_display_raw());
}

// ============================================================================
// Snapshot emit (coalesced @ 10ms)
// ============================================================================

static gboolean emit_snapshot_cb(gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  self->snapshot_emit_source = 0;
  if (self->flutter_api != nullptr) {
    IcefelixWindowManagerWindowSnapshotRaw* snap = build_snapshot(self);
    icefelix_window_manager_window_flutter_api_on_snapshot_changed(
        self->flutter_api, snap, nullptr, nullptr, nullptr);
    g_object_unref(snap);
  }
  return G_SOURCE_REMOVE;
}

static void schedule_snapshot_emit(IcefelixWindowManagerPlugin* self) {
  if (self->snapshot_emit_source != 0) {
    g_source_remove(self->snapshot_emit_source);
  }
  self->snapshot_emit_source =
      g_timeout_add(10, emit_snapshot_cb, self);
}

// GTK signal handlers — every fire schedules a snapshot emit.
static void on_size_allocate(GtkWidget* /*w*/, GdkRectangle* /*alloc*/, gpointer ud) {
  schedule_snapshot_emit(ICEFELIX_WINDOW_MANAGER_PLUGIN(ud));
}
static gboolean on_configure_event(GtkWidget* /*w*/, GdkEvent* /*e*/, gpointer ud) {
  schedule_snapshot_emit(ICEFELIX_WINDOW_MANAGER_PLUGIN(ud));
  return FALSE;
}
static gboolean on_window_state_event(GtkWidget* /*w*/, GdkEventWindowState* /*e*/, gpointer ud) {
  schedule_snapshot_emit(ICEFELIX_WINDOW_MANAGER_PLUGIN(ud));
  return FALSE;
}
static gboolean on_focus_in_event(GtkWidget* /*w*/, GdkEvent* /*e*/, gpointer ud) {
  schedule_snapshot_emit(ICEFELIX_WINDOW_MANAGER_PLUGIN(ud));
  return FALSE;
}
static gboolean on_focus_out_event(GtkWidget* /*w*/, GdkEvent* /*e*/, gpointer ud) {
  schedule_snapshot_emit(ICEFELIX_WINDOW_MANAGER_PLUGIN(ud));
  return FALSE;
}
static gboolean on_delete_event(GtkWidget* /*w*/, GdkEvent* /*e*/, gpointer ud) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(ud);
  // If preventClose flag is set, ask Dart side. (Etapa 3 will wire the real
  // sync request flow; for now we just respect the local flag.)
  return self->prevent_close_flag ? TRUE : FALSE;
}

static void install_signal_handlers(IcefelixWindowManagerPlugin* self) {
  GtkWindow* window = get_gtk_window(self);
  if (window == nullptr) return;
  g_signal_connect(window, "size-allocate", G_CALLBACK(on_size_allocate), self);
  g_signal_connect(window, "configure-event", G_CALLBACK(on_configure_event), self);
  g_signal_connect(window, "window-state-event", G_CALLBACK(on_window_state_event), self);
  g_signal_connect(window, "focus-in-event", G_CALLBACK(on_focus_in_event), self);
  g_signal_connect(window, "focus-out-event", G_CALLBACK(on_focus_out_event), self);
  g_signal_connect(window, "delete-event", G_CALLBACK(on_delete_event), self);
}

// ============================================================================
// VTable handlers — real GTK behavior + stubs
// ============================================================================

#define REQ_WINDOW(retname)                                            \
  GtkWindow* window = get_gtk_window(self);                            \
  if (window == nullptr)                                               \
    return icefelix_window_manager_window_host_api_##retname##_response_new_error( \
        "no_window", "Flutter GtkWindow not available yet", nullptr);

static IcefelixWindowManagerWindowHostApiEnsureInitializedResponse*
h_ensure_initialized(gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  // Install signal handlers on first call (the GtkWindow is available by now).
  install_signal_handlers(self);
  return icefelix_window_manager_window_host_api_ensure_initialized_response_new(
      build_snapshot(self));
}

static IcefelixWindowManagerWindowHostApiGetPlatformInfoResponse*
h_get_platform_info(gpointer /*user_data*/) {
  const gchar* session = g_getenv("XDG_SESSION_TYPE");
  IcefelixWindowManagerDisplayServerRaw ds =
      ICEFELIX_WINDOW_MANAGER_DISPLAY_SERVER_RAW_X11;
  if (session != nullptr && g_strcmp0(session, "wayland") == 0) {
    ds = ICEFELIX_WINDOW_MANAGER_DISPLAY_SERVER_RAW_WAYLAND;
  }
  IcefelixWindowManagerPlatformInfoRaw* info =
      icefelix_window_manager_platform_info_raw_new("linux", &ds, FALSE);
  return icefelix_window_manager_window_host_api_get_platform_info_response_new(info);
}

static IcefelixWindowManagerWindowHostApiGetBoundsResponse*
h_get_bounds(gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  gint w = 800, h = 600, x = 0, y = 0;
  if (window != nullptr) {
    gtk_window_get_size(window, &w, &h);
    gtk_window_get_position(window, &x, &y);
  }
  gboolean is_wayland =
      g_strcmp0(g_getenv("XDG_SESSION_TYPE"), "wayland") == 0;
  IcefelixWindowManagerOffsetRaw* pos =
      is_wayland ? nullptr : icefelix_window_manager_offset_raw_new(x, y);
  IcefelixWindowManagerSizeRaw* size = icefelix_window_manager_size_raw_new(w, h);
  return icefelix_window_manager_window_host_api_get_bounds_response_new(
      icefelix_window_manager_window_bounds_raw_new(pos, size));
}

// ----- Bounds + size + position -----

static IcefelixWindowManagerWindowHostApiSetBoundsResponse* h_set_bounds(
    IcefelixWindowManagerWindowBoundsRaw* bounds,
    const gchar* /*display_id*/, gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) {
    IcefelixWindowManagerSizeRaw* sz =
        icefelix_window_manager_window_bounds_raw_get_size(bounds);
    IcefelixWindowManagerOffsetRaw* pos =
        icefelix_window_manager_window_bounds_raw_get_position(bounds);
    gtk_window_resize(window,
        (gint)icefelix_window_manager_size_raw_get_width(sz),
        (gint)icefelix_window_manager_size_raw_get_height(sz));
    if (pos != nullptr) {
      gtk_window_move(window,
          (gint)icefelix_window_manager_offset_raw_get_dx(pos),
          (gint)icefelix_window_manager_offset_raw_get_dy(pos));
    }
  }
  return icefelix_window_manager_window_host_api_set_bounds_response_new();
}

static IcefelixWindowManagerWindowHostApiSetSizeResponse* h_set_size(
    IcefelixWindowManagerSizeRaw* size, gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) {
    gtk_window_resize(window,
        (gint)icefelix_window_manager_size_raw_get_width(size),
        (gint)icefelix_window_manager_size_raw_get_height(size));
  }
  return icefelix_window_manager_window_host_api_set_size_response_new();
}

static IcefelixWindowManagerWindowHostApiSetMinSizeResponse* h_set_min_size(
    IcefelixWindowManagerSizeRaw* size, gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) {
    GdkGeometry geom = {};
    GdkWindowHints mask = (GdkWindowHints)0;
    if (size != nullptr) {
      geom.min_width =
          (gint)icefelix_window_manager_size_raw_get_width(size);
      geom.min_height =
          (gint)icefelix_window_manager_size_raw_get_height(size);
      mask = GDK_HINT_MIN_SIZE;
    }
    gtk_window_set_geometry_hints(window, nullptr, &geom, mask);
  }
  return icefelix_window_manager_window_host_api_set_min_size_response_new();
}

static IcefelixWindowManagerWindowHostApiSetMaxSizeResponse* h_set_max_size(
    IcefelixWindowManagerSizeRaw* size, gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) {
    GdkGeometry geom = {};
    GdkWindowHints mask = (GdkWindowHints)0;
    if (size != nullptr) {
      geom.max_width =
          (gint)icefelix_window_manager_size_raw_get_width(size);
      geom.max_height =
          (gint)icefelix_window_manager_size_raw_get_height(size);
      mask = GDK_HINT_MAX_SIZE;
    }
    gtk_window_set_geometry_hints(window, nullptr, &geom, mask);
  }
  return icefelix_window_manager_window_host_api_set_max_size_response_new();
}

static IcefelixWindowManagerWindowHostApiSetPositionResponse* h_set_position(
    IcefelixWindowManagerOffsetRaw* position, gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) {
    gtk_window_move(window,
        (gint)icefelix_window_manager_offset_raw_get_dx(position),
        (gint)icefelix_window_manager_offset_raw_get_dy(position));
  }
  return icefelix_window_manager_window_host_api_set_position_response_new();
}

static IcefelixWindowManagerWindowHostApiCenterResponse* h_center(
    gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) {
    gtk_window_set_position(window, GTK_WIN_POS_CENTER);
  }
  return icefelix_window_manager_window_host_api_center_response_new();
}

static IcefelixWindowManagerWindowHostApiMoveToDisplayResponse* h_move_to_display(
    const gchar* /*display_id*/, gpointer /*user_data*/) {
  // TODO(linux v0.4.x): translate via GdkMonitor; on Wayland this is a no-op.
  return icefelix_window_manager_window_host_api_move_to_display_response_new();
}

// ----- State -----

static IcefelixWindowManagerWindowHostApiMinimizeResponse* h_minimize(
    gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) gtk_window_iconify(window);
  return icefelix_window_manager_window_host_api_minimize_response_new();
}
static IcefelixWindowManagerWindowHostApiMaximizeResponse* h_maximize(
    gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) gtk_window_maximize(window);
  return icefelix_window_manager_window_host_api_maximize_response_new();
}
static IcefelixWindowManagerWindowHostApiUnmaximizeResponse* h_unmaximize(
    gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) gtk_window_unmaximize(window);
  return icefelix_window_manager_window_host_api_unmaximize_response_new();
}
static IcefelixWindowManagerWindowHostApiRestoreResponse* h_restore(
    gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) {
    gtk_window_deiconify(window);
    gtk_window_unmaximize(window);
  }
  return icefelix_window_manager_window_host_api_restore_response_new();
}
static IcefelixWindowManagerWindowHostApiHideResponse* h_hide(
    gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) gtk_widget_hide(GTK_WIDGET(window));
  return icefelix_window_manager_window_host_api_hide_response_new();
}
static IcefelixWindowManagerWindowHostApiShowResponse* h_show(
    gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) gtk_widget_show(GTK_WIDGET(window));
  return icefelix_window_manager_window_host_api_show_response_new();
}
static IcefelixWindowManagerWindowHostApiFullscreenResponse* h_fullscreen(
    gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) gtk_window_fullscreen(window);
  return icefelix_window_manager_window_host_api_fullscreen_response_new();
}
static IcefelixWindowManagerWindowHostApiExitFullscreenResponse* h_exit_fullscreen(
    gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) gtk_window_unfullscreen(window);
  return icefelix_window_manager_window_host_api_exit_fullscreen_response_new();
}

// ----- Focus -----

static IcefelixWindowManagerWindowHostApiFocusResponse* h_focus(
    gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) gtk_window_present(window);
  return icefelix_window_manager_window_host_api_focus_response_new();
}

// ----- Drag, resize, lifecycle, title, properties, visual -----

static IcefelixWindowManagerWindowHostApiSetTitleResponse* h_set_title(
    const gchar* title, gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) gtk_window_set_title(window, title);
  schedule_snapshot_emit(self);
  return icefelix_window_manager_window_host_api_set_title_response_new();
}

static IcefelixWindowManagerWindowHostApiSetAlwaysOnTopResponse* h_set_always_on_top(
    gboolean value, gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) gtk_window_set_keep_above(window, value);
  schedule_snapshot_emit(self);
  return icefelix_window_manager_window_host_api_set_always_on_top_response_new();
}

static IcefelixWindowManagerWindowHostApiSetSkipTaskbarResponse* h_set_skip_taskbar(
    gboolean value, gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  self->skip_taskbar_flag = value;
  if (window != nullptr) gtk_window_set_skip_taskbar_hint(window, value);
  schedule_snapshot_emit(self);
  return icefelix_window_manager_window_host_api_set_skip_taskbar_response_new();
}

static IcefelixWindowManagerWindowHostApiSetResizableResponse* h_set_resizable(
    gboolean value, gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) gtk_window_set_resizable(window, value);
  schedule_snapshot_emit(self);
  return icefelix_window_manager_window_host_api_set_resizable_response_new();
}

static IcefelixWindowManagerWindowHostApiSetClosableResponse* h_set_closable(
    gboolean value, gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) gtk_window_set_deletable(window, value);
  schedule_snapshot_emit(self);
  return icefelix_window_manager_window_host_api_set_closable_response_new();
}

static IcefelixWindowManagerWindowHostApiSetMaximizableResponse* h_set_maximizable(
    gboolean value, gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  self->maximizable_flag = value;
  schedule_snapshot_emit(self);
  return icefelix_window_manager_window_host_api_set_maximizable_response_new();
}

static IcefelixWindowManagerWindowHostApiSetFramelessResponse* h_set_frameless(
    gboolean value, gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) gtk_window_set_decorated(window, !value);
  schedule_snapshot_emit(self);
  return icefelix_window_manager_window_host_api_set_frameless_response_new();
}

static IcefelixWindowManagerWindowHostApiSetTitleBarStyleResponse*
h_set_title_bar_style(IcefelixWindowManagerTitleBarStyleRaw style,
                      gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  self->title_bar_style_flag = style;
  // hidden / hiddenInset both translate to undecorated on GTK; users
  // typically combine with a Flutter custom title bar widget.
  if (window != nullptr) {
    gboolean show_decor =
        (style == ICEFELIX_WINDOW_MANAGER_TITLE_BAR_STYLE_RAW_NORMAL);
    gtk_window_set_decorated(window, show_decor);
  }
  return icefelix_window_manager_window_host_api_set_title_bar_style_response_new();
}

static IcefelixWindowManagerWindowHostApiSetOpacityResponse* h_set_opacity(
    double opacity, gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr) gtk_widget_set_opacity(GTK_WIDGET(window), opacity);
  schedule_snapshot_emit(self);
  return icefelix_window_manager_window_host_api_set_opacity_response_new();
}

static IcefelixWindowManagerWindowHostApiSetBackgroundColorResponse*
h_set_background_color(int64_t argb, gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  self->background_color_argb_flag = argb;
  self->background_color_set = TRUE;
  // TODO(linux v0.4.x): apply via GtkStyleContext + CSS provider, or set
  // GdkRGBA on the GtkWindow background. Currently flag-tracked only.
  schedule_snapshot_emit(self);
  return icefelix_window_manager_window_host_api_set_background_color_response_new();
}

static IcefelixWindowManagerWindowHostApiSetIconResponse* h_set_icon(
    const gchar* filesystem_path, gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  GtkWindow* window = get_gtk_window(self);
  if (window != nullptr && filesystem_path != nullptr) {
    gtk_window_set_icon_from_file(window, filesystem_path, nullptr);
  }
  schedule_snapshot_emit(self);
  return icefelix_window_manager_window_host_api_set_icon_response_new();
}

static IcefelixWindowManagerWindowHostApiSetPreventCloseResponse* h_set_prevent_close(
    gboolean value, gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  self->prevent_close_flag = value;
  schedule_snapshot_emit(self);
  return icefelix_window_manager_window_host_api_set_prevent_close_response_new();
}

static IcefelixWindowManagerWindowHostApiSetHasShadowResponse* h_set_has_shadow(
    gboolean value, gpointer user_data) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(user_data);
  self->has_shadow_flag = value;
  schedule_snapshot_emit(self);
  return icefelix_window_manager_window_host_api_set_has_shadow_response_new();
}

// ----- Stub-only handlers (filled in later patches) -----

#define STUB(name, Name, SIG)                                                       \
  static IcefelixWindowManagerWindowHostApi##Name##Response* h_##name SIG {         \
    return icefelix_window_manager_window_host_api_##name##_response_new();         \
  }

STUB(blur, Blur, (gpointer /*ud*/))
STUB(start_drag, StartDrag, (gpointer /*ud*/))
STUB(start_resize, StartResize,
     (IcefelixWindowManagerResizeDirectionRaw /*dir*/, gpointer /*ud*/))
STUB(close, Close, (gpointer /*ud*/))
STUB(destroy, Destroy, (gpointer /*ud*/))
STUB(set_movable, SetMovable, (gboolean /*value*/, gpointer /*ud*/))
STUB(set_minimizable, SetMinimizable, (gboolean /*value*/, gpointer /*ud*/))
STUB(set_shape, SetShape, (FlValue* /*points*/, gpointer /*ud*/))

#undef STUB

// ----- Multi-monitor (stubs returning defaults) -----

static IcefelixWindowManagerWindowHostApiListDisplaysResponse* h_list_displays(
    gpointer /*user_data*/) {
  g_autoptr(FlValue) display_list = fl_value_new_list();
  return icefelix_window_manager_window_host_api_list_displays_response_new(display_list);
}
static IcefelixWindowManagerWindowHostApiGetCurrentDisplayResponse*
h_get_current_display(gpointer /*user_data*/) {
  return icefelix_window_manager_window_host_api_get_current_display_response_new(
      make_default_display_raw());
}
static IcefelixWindowManagerWindowHostApiGetPrimaryDisplayResponse*
h_get_primary_display(gpointer /*user_data*/) {
  return icefelix_window_manager_window_host_api_get_primary_display_response_new(
      make_default_display_raw());
}

// ============================================================================
// Plugin lifecycle
// ============================================================================

static void icefelix_window_manager_plugin_dispose(GObject* object) {
  IcefelixWindowManagerPlugin* self = ICEFELIX_WINDOW_MANAGER_PLUGIN(object);
  if (self->snapshot_emit_source != 0) {
    g_source_remove(self->snapshot_emit_source);
    self->snapshot_emit_source = 0;
  }
  g_clear_object(&self->flutter_api);
  G_OBJECT_CLASS(icefelix_window_manager_plugin_parent_class)->dispose(object);
}

static void icefelix_window_manager_plugin_class_init(
    IcefelixWindowManagerPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = icefelix_window_manager_plugin_dispose;
}

static void icefelix_window_manager_plugin_init(IcefelixWindowManagerPlugin* self) {
  self->maximizable_flag = TRUE;
  self->has_shadow_flag = TRUE;
  self->title_bar_style_flag = ICEFELIX_WINDOW_MANAGER_TITLE_BAR_STYLE_RAW_NORMAL;
}

void icefelix_window_manager_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  IcefelixWindowManagerPlugin* plugin = ICEFELIX_WINDOW_MANAGER_PLUGIN(
      g_object_new(icefelix_window_manager_plugin_get_type(), nullptr));
  plugin->registrar = registrar;
  plugin->flutter_api = icefelix_window_manager_window_flutter_api_new(
      fl_plugin_registrar_get_messenger(registrar), nullptr);

  static const IcefelixWindowManagerWindowHostApiVTable kVTable = {
      .ensure_initialized = h_ensure_initialized,
      .get_platform_info = h_get_platform_info,
      .get_bounds = h_get_bounds,
      .set_bounds = h_set_bounds,
      .set_size = h_set_size,
      .set_min_size = h_set_min_size,
      .set_max_size = h_set_max_size,
      .set_position = h_set_position,
      .center = h_center,
      .move_to_display = h_move_to_display,
      .minimize = h_minimize,
      .maximize = h_maximize,
      .unmaximize = h_unmaximize,
      .restore = h_restore,
      .hide = h_hide,
      .show = h_show,
      .fullscreen = h_fullscreen,
      .exit_fullscreen = h_exit_fullscreen,
      .focus = h_focus,
      .blur = h_blur,
      .start_drag = h_start_drag,
      .start_resize = h_start_resize,
      .close = h_close,
      .destroy = h_destroy,
      .set_title = h_set_title,
      .set_always_on_top = h_set_always_on_top,
      .set_skip_taskbar = h_set_skip_taskbar,
      .set_resizable = h_set_resizable,
      .set_movable = h_set_movable,
      .set_minimizable = h_set_minimizable,
      .set_maximizable = h_set_maximizable,
      .set_closable = h_set_closable,
      .set_frameless = h_set_frameless,
      .set_title_bar_style = h_set_title_bar_style,
      .set_opacity = h_set_opacity,
      .set_background_color = h_set_background_color,
      .set_has_shadow = h_set_has_shadow,
      .set_icon = h_set_icon,
      .set_shape = h_set_shape,
      .set_prevent_close = h_set_prevent_close,
      .list_displays = h_list_displays,
      .get_current_display = h_get_current_display,
      .get_primary_display = h_get_primary_display,
  };

  icefelix_window_manager_window_host_api_set_method_handlers(
      fl_plugin_registrar_get_messenger(registrar), nullptr, &kVTable,
      g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
