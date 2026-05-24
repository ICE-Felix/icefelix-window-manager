// Copyright 2026 icefelix.com. BSD-3-Clause.
//
// Linux platform implementation of icefelix_window_manager.
//
// v0.4 SCAFFOLD: wires the Pigeon WindowHostApi VTable to a set of stub
// handlers. ensure_initialized() returns a valid default WindowSnapshotRaw
// so the Dart side's `await WindowManager.instance.ensureInitialized()`
// succeeds and the app boots. Every other handler is a no-op returning
// success (or a sensible default for getter-style methods).
//
// Real GTK + libdecor behavior wires up method-by-method in subsequent
// patches following docs/ADDING_LINUX.md.

#include "include/icefelix_window_manager/icefelix_window_manager_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include "messages.g.h"

struct _IcefelixWindowManagerPlugin {
  GObject parent_instance;

  // The Flutter view this plugin is attached to. Resolves to the main
  // GtkWindow via gtk_widget_get_toplevel() when methods need it.
  FlPluginRegistrar* registrar;
};

G_DEFINE_TYPE(IcefelixWindowManagerPlugin, icefelix_window_manager_plugin,
              g_object_get_type())

// ============================================================================
// Helpers
// ============================================================================

// Build a sensible default DisplayRaw — used by ensure_initialized so the
// Dart side gets a non-null currentDisplay even before we wire real
// GdkMonitor introspection.
static IcefelixWindowManagerDisplayRaw* make_default_display_raw() {
  IcefelixWindowManagerRectRaw* bounds =
      icefelix_window_manager_rect_raw_new(0, 0, 1920, 1080);
  IcefelixWindowManagerRectRaw* work_area =
      icefelix_window_manager_rect_raw_new(0, 0, 1920, 1080);
  return icefelix_window_manager_display_raw_new(
      /* id */ "linux-default-display",
      /* name */ "Linux Display",
      bounds, work_area,
      /* physical_width_mm */ nullptr,
      /* physical_height_mm */ nullptr,
      /* dpi */ nullptr,
      /* scale_factor */ 1.0,
      /* is_primary */ TRUE,
      /* refresh_rate */ nullptr);
}

// Build a sensible default WindowSnapshotRaw for ensure_initialized.
static IcefelixWindowManagerWindowSnapshotRaw* make_default_snapshot_raw() {
  IcefelixWindowManagerOffsetRaw* pos = icefelix_window_manager_offset_raw_new(0, 0);
  IcefelixWindowManagerSizeRaw* size = icefelix_window_manager_size_raw_new(800, 600);
  IcefelixWindowManagerWindowBoundsRaw* bounds =
      icefelix_window_manager_window_bounds_raw_new(pos, size);
  IcefelixWindowManagerDisplayRaw* display = make_default_display_raw();
  return icefelix_window_manager_window_snapshot_raw_new(
      bounds,
      ICEFELIX_WINDOW_MANAGER_WINDOW_STATE_RAW_NORMAL,
      /* title */ "",
      /* is_focused */ TRUE,
      /* always_on_top */ FALSE,
      /* skip_taskbar */ FALSE,
      /* resizable */ TRUE,
      /* movable */ TRUE,
      /* minimizable */ TRUE,
      /* maximizable */ TRUE,
      /* closable */ TRUE,
      /* frameless */ FALSE,
      ICEFELIX_WINDOW_MANAGER_TITLE_BAR_STYLE_RAW_NORMAL,
      /* opacity */ 1.0,
      /* background_color_argb */ nullptr,
      /* has_shadow */ TRUE,
      /* prevent_close */ FALSE,
      display);
}

// ============================================================================
// VTable handlers
// ============================================================================
//
// All methods are currently stubs. ensure_initialized + get_platform_info +
// the getter-style methods return valid placeholder data so the Dart side
// boots cleanly. Mutator methods return success no-ops (the Dart-side
// snapshot won't reflect the change until we wire actual GTK calls in
// subsequent patches).

static IcefelixWindowManagerWindowHostApiEnsureInitializedResponse*
h_ensure_initialized(gpointer /*user_data*/) {
  return icefelix_window_manager_window_host_api_ensure_initialized_response_new(
      make_default_snapshot_raw());
}

static IcefelixWindowManagerWindowHostApiGetPlatformInfoResponse*
h_get_platform_info(gpointer /*user_data*/) {
  // Detect X11 vs Wayland from XDG_SESSION_TYPE (best-effort).
  const gchar* session = g_getenv("XDG_SESSION_TYPE");
  IcefelixWindowManagerDisplayServerRaw ds =
      ICEFELIX_WINDOW_MANAGER_DISPLAY_SERVER_RAW_X11;
  if (session != nullptr && g_strcmp0(session, "wayland") == 0) {
    ds = ICEFELIX_WINDOW_MANAGER_DISPLAY_SERVER_RAW_WAYLAND;
  }
  IcefelixWindowManagerPlatformInfoRaw* info =
      icefelix_window_manager_platform_info_raw_new(
          /* target */ "linux",
          /* display_server */ &ds,
          /* is_sandboxed */ FALSE);
  return icefelix_window_manager_window_host_api_get_platform_info_response_new(info);
}

static IcefelixWindowManagerWindowHostApiGetBoundsResponse*
h_get_bounds(gpointer /*user_data*/) {
  IcefelixWindowManagerOffsetRaw* pos = icefelix_window_manager_offset_raw_new(0, 0);
  IcefelixWindowManagerSizeRaw* size = icefelix_window_manager_size_raw_new(800, 600);
  IcefelixWindowManagerWindowBoundsRaw* bounds =
      icefelix_window_manager_window_bounds_raw_new(pos, size);
  return icefelix_window_manager_window_host_api_get_bounds_response_new(bounds);
}

// Pigeon emits CamelCase type names (IcefelixWindowManager...SetBoundsResponse)
// but snake_case function names (..._set_bounds_response_new). The macro takes
// both: `name` is snake_case (used in identifiers), `Name` is CamelCase (used
// in the typedef).
#define STUB(name, Name, SIG)                                                       \
  static IcefelixWindowManagerWindowHostApi##Name##Response* h_##name SIG {         \
    return icefelix_window_manager_window_host_api_##name##_response_new();         \
  }

// Mutator methods: take their args (unused for now), return success.
STUB(set_bounds, SetBounds,
     (IcefelixWindowManagerWindowBoundsRaw* /*bounds*/,
      const gchar* /*display_id*/, gpointer /*user_data*/))
STUB(set_size, SetSize,
     (IcefelixWindowManagerSizeRaw* /*size*/, gpointer /*user_data*/))
STUB(set_min_size, SetMinSize,
     (IcefelixWindowManagerSizeRaw* /*size*/, gpointer /*user_data*/))
STUB(set_max_size, SetMaxSize,
     (IcefelixWindowManagerSizeRaw* /*size*/, gpointer /*user_data*/))
STUB(set_position, SetPosition,
     (IcefelixWindowManagerOffsetRaw* /*position*/, gpointer /*user_data*/))
STUB(center, Center, (gpointer /*user_data*/))
STUB(move_to_display, MoveToDisplay,
     (const gchar* /*display_id*/, gpointer /*user_data*/))
STUB(minimize, Minimize, (gpointer /*user_data*/))
STUB(maximize, Maximize, (gpointer /*user_data*/))
STUB(unmaximize, Unmaximize, (gpointer /*user_data*/))
STUB(restore, Restore, (gpointer /*user_data*/))
STUB(hide, Hide, (gpointer /*user_data*/))
STUB(show, Show, (gpointer /*user_data*/))
STUB(fullscreen, Fullscreen, (gpointer /*user_data*/))
STUB(exit_fullscreen, ExitFullscreen, (gpointer /*user_data*/))
STUB(focus, Focus, (gpointer /*user_data*/))
STUB(blur, Blur, (gpointer /*user_data*/))
STUB(start_drag, StartDrag, (gpointer /*user_data*/))
STUB(start_resize, StartResize,
     (IcefelixWindowManagerResizeDirectionRaw /*direction*/,
      gpointer /*user_data*/))
STUB(close, Close, (gpointer /*user_data*/))
STUB(destroy, Destroy, (gpointer /*user_data*/))
STUB(set_title, SetTitle,
     (const gchar* /*title*/, gpointer /*user_data*/))
STUB(set_always_on_top, SetAlwaysOnTop, (gboolean /*value*/, gpointer /*user_data*/))
STUB(set_skip_taskbar, SetSkipTaskbar, (gboolean /*value*/, gpointer /*user_data*/))
STUB(set_resizable, SetResizable, (gboolean /*value*/, gpointer /*user_data*/))
STUB(set_movable, SetMovable, (gboolean /*value*/, gpointer /*user_data*/))
STUB(set_minimizable, SetMinimizable, (gboolean /*value*/, gpointer /*user_data*/))
STUB(set_maximizable, SetMaximizable, (gboolean /*value*/, gpointer /*user_data*/))
STUB(set_closable, SetClosable, (gboolean /*value*/, gpointer /*user_data*/))
STUB(set_frameless, SetFrameless, (gboolean /*value*/, gpointer /*user_data*/))
STUB(set_title_bar_style, SetTitleBarStyle,
     (IcefelixWindowManagerTitleBarStyleRaw /*style*/, gpointer /*user_data*/))
STUB(set_opacity, SetOpacity, (double /*opacity*/, gpointer /*user_data*/))
STUB(set_background_color, SetBackgroundColor,
     (int64_t /*argb*/, gpointer /*user_data*/))
STUB(set_has_shadow, SetHasShadow, (gboolean /*value*/, gpointer /*user_data*/))
STUB(set_icon, SetIcon, (const gchar* /*filesystem_path*/, gpointer /*user_data*/))
STUB(set_shape, SetShape, (FlValue* /*points*/, gpointer /*user_data*/))
STUB(set_prevent_close, SetPreventClose, (gboolean /*value*/, gpointer /*user_data*/))

#undef STUB

static IcefelixWindowManagerWindowHostApiListDisplaysResponse*
h_list_displays(gpointer /*user_data*/) {
  g_autoptr(FlValue) display_list = fl_value_new_list();
  // Will populate from gdk_display_get_monitors in a later patch.
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
  G_OBJECT_CLASS(icefelix_window_manager_plugin_parent_class)->dispose(object);
}

static void icefelix_window_manager_plugin_class_init(
    IcefelixWindowManagerPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = icefelix_window_manager_plugin_dispose;
}

static void icefelix_window_manager_plugin_init(
    IcefelixWindowManagerPlugin* /*self*/) {}

void icefelix_window_manager_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  IcefelixWindowManagerPlugin* plugin = ICEFELIX_WINDOW_MANAGER_PLUGIN(
      g_object_new(icefelix_window_manager_plugin_get_type(), nullptr));
  plugin->registrar = registrar;

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
      fl_plugin_registrar_get_messenger(registrar),
      /* suffix */ nullptr,
      &kVTable,
      g_object_ref(plugin),
      g_object_unref);

  g_object_unref(plugin);
}
