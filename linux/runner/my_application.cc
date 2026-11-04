#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "site_webviews.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Fork: the window opens with the size it had. Only the size: Wayland does not
// let an app choose its position.
static gchar* window_state_path() {
  return g_build_filename(g_get_user_config_dir(), "aupp-window.ini", nullptr);
}

static void restore_window_state(GtkWindow* window) {
  gint width = 1400;
  gint height = 880;
  gboolean maximized = FALSE;
  g_autofree gchar* path = window_state_path();
  g_autoptr(GKeyFile) file = g_key_file_new();
  if (g_key_file_load_from_file(file, path, G_KEY_FILE_NONE, nullptr)) {
    width = MAX(g_key_file_get_integer(file, "window", "width", nullptr), 420);
    height = MAX(g_key_file_get_integer(file, "window", "height", nullptr), 560);
    maximized = g_key_file_get_boolean(file, "window", "maximized", nullptr);
  }
  gtk_window_set_default_size(window, width, height);
  if (maximized) gtk_window_maximize(window);
}

static gboolean save_window_state(GtkWidget* widget, GdkEvent*, gpointer) {
  GtkWindow* window = GTK_WINDOW(widget);
  gint width = 0;
  gint height = 0;
  gtk_window_get_size(window, &width, &height);
  g_autoptr(GKeyFile) file = g_key_file_new();
  g_key_file_set_integer(file, "window", "width", width);
  g_key_file_set_integer(file, "window", "height", height);
  g_key_file_set_boolean(file, "window", "maximized",
                         gtk_window_is_maximized(window));
  g_autofree gchar* path = window_state_path();
  g_key_file_save_to_file(file, path, nullptr);
  return FALSE;
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Set window icon name (for finding in icon theme)
  gtk_window_set_icon_name(window, "aupp");

  // Set window icon - try multiple locations
  GError* icon_error = nullptr;
  GdkPixbuf* icon = nullptr;

  // Try loading from build directory first (for running from build)
  icon = gdk_pixbuf_new_from_file("linux/assets/aupp.png", &icon_error);

  // If that fails, try loading from installed location
  if (icon == nullptr && icon_error != nullptr) {
    g_clear_error(&icon_error);
    icon = gdk_pixbuf_new_from_file("/usr/share/icons/hicolor/512x512/apps/aupp.png", &icon_error);
  }

  if (icon != nullptr) {
    // Set as window icon
    gtk_window_set_icon(GTK_WINDOW(window), icon);
    // Also set as default icon for all windows
    gtk_window_set_default_icon(icon);
  } else if (icon_error != nullptr) {
    g_warning("Failed to load window icon: %s", icon_error->message);
    g_error_free(icon_error);
  }

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "A Única Planilha Possível");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);

    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "A Única Planilha Possível");
  }

  // Clean up icon now that we're done using it
  if (icon != nullptr) {
    g_object_unref(icon);
  }

  restore_window_state(window);
  g_signal_connect(window, "delete-event", G_CALLBACK(save_window_state),
                   nullptr);
  GdkGeometry min_size = {};
  min_size.min_width = 420;
  min_size.min_height = 560;
  gtk_window_set_geometry_hints(window, nullptr, &min_size, GDK_HINT_MIN_SIZE);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  // Fork: Impeller on OpenGL does not smooth paths, and the round charts are
  // drawn as paths: they came out jagged.
  fl_dart_project_set_enable_impeller(project, FALSE);
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  // Fork: an overlay, so that site tabs can sit over part of the Flutter view.
  GtkWidget* overlay = gtk_overlay_new();
  gtk_widget_show(overlay);
  gtk_container_add(GTK_CONTAINER(overlay), GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), overlay);

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  site_webviews_init(fl_engine_get_binary_messenger(fl_view_get_engine(view)),
                     GTK_OVERLAY(overlay), GTK_WIDGET(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
