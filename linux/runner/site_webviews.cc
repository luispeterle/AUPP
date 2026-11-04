#include "site_webviews.h"

#ifdef HAS_WEBKIT

#include <webkit2/webkit2.h>

#include <map>
#include <string>

namespace {

GtkOverlay* g_overlay = nullptr;
GtkWidget* g_flutter_view = nullptr;
FlMethodChannel* g_channel = nullptr;
WebKitWebContext* g_context = nullptr;
std::map<std::string, WebKitWebView*> g_views;
WebKitUserContentFilter* g_ad_filter = nullptr;
std::string g_dark_script;
bool g_dark = true;

// Logins stay between runs, apart from the app's own data.
WebKitWebContext* web_context() {
  if (g_context == nullptr) {
    g_autofree gchar* data = g_build_filename(
        g_get_user_data_dir(), APPLICATION_ID, "webview", nullptr);
    g_autofree gchar* cache = g_build_filename(
        g_get_user_cache_dir(), APPLICATION_ID, "webview", nullptr);
    g_autoptr(WebKitWebsiteDataManager) manager =
        webkit_website_data_manager_new("base-data-directory", data,
                                        "base-cache-directory", cache, nullptr);
    g_context = webkit_web_context_new_with_website_data_manager(manager);
    g_autofree gchar* cookies = g_build_filename(data, "cookies.sqlite", nullptr);
    webkit_cookie_manager_set_persistent_storage(
        webkit_web_context_get_cookie_manager(g_context), cookies,
        WEBKIT_COOKIE_PERSISTENT_STORAGE_SQLITE);
  }
  return g_context;
}

void block_ads(WebKitWebView* view) {
  webkit_user_content_manager_add_filter(
      webkit_web_view_get_user_content_manager(view), g_ad_filter);
}

void on_ad_filter_ready(GObject* store, GAsyncResult* result, gpointer) {
  g_autoptr(GError) error = nullptr;
  g_ad_filter = webkit_user_content_filter_store_save_finish(
      WEBKIT_USER_CONTENT_FILTER_STORE(store), result, &error);
  if (g_ad_filter == nullptr) {
    g_warning("Ad blocking unavailable: %s", error->message);
    return;
  }
  // Pages opened meanwhile: from their next load on.
  for (const auto& entry : g_views) {
    block_ads(entry.second);
  }
}

// assets/adblock/rules.json (scripts/adblock_rules.py), next to the executable.
void compile_ad_filter() {
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe == nullptr) return;
  g_autofree gchar* dir = g_path_get_dirname(exe);
  g_autofree gchar* rules = g_build_filename(
      dir, "data", "flutter_assets", "assets", "adblock", "rules.json", nullptr);
  gchar* contents = nullptr;
  gsize length = 0;
  if (!g_file_get_contents(rules, &contents, &length, nullptr)) {
    g_warning("Ad blocking rules not found: %s", rules);
    return;
  }
  g_autoptr(GBytes) bytes = g_bytes_new_take(contents, length);
  g_autofree gchar* filters = g_build_filename(
      g_get_user_cache_dir(), APPLICATION_ID, "webview", "filters", nullptr);
  WebKitUserContentFilterStore* store =
      webkit_user_content_filter_store_new(filters);
  webkit_user_content_filter_store_save(store, "aupp-adblock", bytes, nullptr,
                                        on_ad_filter_ready, nullptr);
}

// assets/darkreader/darkreader.js: the Dark Reader extension's engine, which
// darkens any page. WebKitGTK takes no browser extensions, but this one also
// ships as a library. The parameters hide a page's own module loader from it,
// which would otherwise keep DarkReader out of the global scope.
void load_dark_script() {
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe == nullptr) return;
  g_autofree gchar* dir = g_path_get_dirname(exe);
  g_autofree gchar* path = g_build_filename(
      dir, "data", "flutter_assets", "assets", "darkreader", "darkreader.js",
      nullptr);
  g_autofree gchar* contents = nullptr;
  if (!g_file_get_contents(path, &contents, nullptr, nullptr)) {
    g_warning("Dark mode script not found: %s", path);
    return;
  }
  g_dark_script =
      std::string("if(!window.DarkReader){(function(exports,module,define){") +
      contents +
      "\n})();}\n"
      "DarkReader.setFetchMethod(window.fetch);"
      "DarkReader.enable({brightness:100,contrast:100,sepia:0});";
}

// For what the view loads from now on. The background avoids a white flash.
void apply_dark(WebKitWebView* view) {
  WebKitUserContentManager* manager =
      webkit_web_view_get_user_content_manager(view);
  webkit_user_content_manager_remove_all_scripts(manager);
  if (g_dark && !g_dark_script.empty()) {
    WebKitUserScript* script = webkit_user_script_new(
        g_dark_script.c_str(), WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES,
        WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, nullptr, nullptr);
    webkit_user_content_manager_add_script(manager, script);
    webkit_user_script_unref(script);
  }
  GdkRGBA background = {1, 1, 1, 1};
  if (g_dark) background = {24 / 255.0, 26 / 255.0, 27 / 255.0, 1};
  webkit_web_view_set_background_color(view, &background);
}

// Pages already open change without reloading.
void set_dark(bool on) {
  g_dark = on;
  for (const auto& entry : g_views) {
    apply_dark(entry.second);
    const std::string& code =
        on ? g_dark_script
           : std::string("if(window.DarkReader)DarkReader.disable();");
    if (code.empty()) continue;
    webkit_web_view_evaluate_javascript(entry.second, code.c_str(), -1, nullptr,
                                        nullptr, nullptr, nullptr, nullptr);
  }
}

WebKitWebsiteDataManager* data_manager() {
  return webkit_web_context_get_website_data_manager(web_context());
}

void respond_true(FlMethodCall* call) {
  g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
  fl_method_call_respond_success(call, result, nullptr);
}

void on_data_changed(GObject*, GAsyncResult*, gpointer data) {
  g_autoptr(FlMethodCall) call = FL_METHOD_CALL(data);
  respond_true(call);
}

void on_sites_fetched(GObject* manager, GAsyncResult* result, gpointer data) {
  g_autoptr(FlMethodCall) call = FL_METHOD_CALL(data);
  GList* sites = webkit_website_data_manager_fetch_finish(
      WEBKIT_WEBSITE_DATA_MANAGER(manager), result, nullptr);
  g_autoptr(FlValue) names = fl_value_new_list();
  for (GList* item = sites; item != nullptr; item = item->next) {
    fl_value_append_take(
        names,
        fl_value_new_string(webkit_website_data_get_name(
            static_cast<WebKitWebsiteData*>(item->data))));
  }
  g_list_free_full(sites, reinterpret_cast<GDestroyNotify>(webkit_website_data_unref));
  fl_method_call_respond_success(call, names, nullptr);
}

// A site is named by the data WebKit has for it, so it is looked up first.
void on_site_to_remove_fetched(GObject* manager, GAsyncResult* result,
                               gpointer data) {
  FlMethodCall* call = FL_METHOD_CALL(data);
  FlValue* name = fl_value_lookup_string(fl_method_call_get_args(call), "name");
  GList* sites = webkit_website_data_manager_fetch_finish(
      WEBKIT_WEBSITE_DATA_MANAGER(manager), result, nullptr);
  GList* matching = nullptr;
  for (GList* item = sites; item != nullptr; item = item->next) {
    auto* site = static_cast<WebKitWebsiteData*>(item->data);
    if (name != nullptr &&
        g_strcmp0(webkit_website_data_get_name(site),
                  fl_value_get_string(name)) == 0) {
      matching = g_list_prepend(matching, site);
    }
  }
  webkit_website_data_manager_remove(WEBKIT_WEBSITE_DATA_MANAGER(manager),
                                     WEBKIT_WEBSITE_DATA_ALL, matching, nullptr,
                                     on_data_changed, call);
  g_list_free(matching);
  g_list_free_full(sites, reinterpret_cast<GDestroyNotify>(webkit_website_data_unref));
}

void notify_dart(WebKitWebView* view, const std::string& id) {
  g_autoptr(FlValue) args = fl_value_new_map();
  const gchar* title = webkit_web_view_get_title(view);
  const gchar* uri = webkit_web_view_get_uri(view);
  fl_value_set_string_take(args, "id", fl_value_new_string(id.c_str()));
  fl_value_set_string_take(args, "title",
                           fl_value_new_string(title != nullptr ? title : ""));
  fl_value_set_string_take(args, "url",
                           fl_value_new_string(uri != nullptr ? uri : ""));
  fl_value_set_string_take(args, "loading",
                           fl_value_new_bool(webkit_web_view_is_loading(view)));
  fl_value_set_string_take(
      args, "canBack", fl_value_new_bool(webkit_web_view_can_go_back(view)));
  fl_value_set_string_take(
      args, "canForward",
      fl_value_new_bool(webkit_web_view_can_go_forward(view)));
  fl_method_channel_invoke_method(g_channel, "changed", args, nullptr, nullptr,
                                  nullptr);
}

const gchar* view_id(GObject* view) {
  return static_cast<const gchar*>(g_object_get_data(view, "aupp-id"));
}

void on_view_changed(GObject* object, GParamSpec*, gpointer) {
  const gchar* id = view_id(object);
  if (id != nullptr) notify_dart(WEBKIT_WEB_VIEW(object), id);
}

// Links that would open a new window stay in the same tab.
GtkWidget* on_create(WebKitWebView* view, WebKitNavigationAction* action,
                     gpointer) {
  webkit_web_view_load_request(
      view, webkit_navigation_action_get_request(action));
  return nullptr;
}

// A page whose process died would stay blank. Only once a minute: a page that
// always crashes must not keep reloading.
void on_process_terminated(WebKitWebView* view,
                           WebKitWebProcessTerminationReason reason, gpointer) {
  if (reason == WEBKIT_WEB_PROCESS_TERMINATED_BY_API) return;
  g_warning("Web process of %s ended (reason %d)", webkit_web_view_get_uri(view),
            reason);
  const gint64 now = g_get_monotonic_time() / G_USEC_PER_SEC;
  const gint64 last =
      GPOINTER_TO_SIZE(g_object_get_data(G_OBJECT(view), "aupp-reloaded"));
  if (last != 0 && now - last < 60) return;
  g_object_set_data(G_OBJECT(view), "aupp-reloaded", GSIZE_TO_POINTER(now));
  webkit_web_view_reload(view);
}

WebKitWebView* create_view(const std::string& id, const gchar* url) {
  WebKitWebView* view =
      WEBKIT_WEB_VIEW(webkit_web_view_new_with_context(web_context()));
  g_object_set_data_full(G_OBJECT(view), "aupp-id", g_strdup(id.c_str()),
                         g_free);
  GtkWidget* widget = GTK_WIDGET(view);
  gtk_widget_set_halign(widget, GTK_ALIGN_START);
  gtk_widget_set_valign(widget, GTK_ALIGN_START);
  for (const char* property :
       {"notify::title", "notify::uri", "notify::is-loading"}) {
    g_signal_connect(view, property, G_CALLBACK(on_view_changed), nullptr);
  }
  g_signal_connect(view, "create", G_CALLBACK(on_create), nullptr);
  g_signal_connect(view, "web-process-terminated",
                   G_CALLBACK(on_process_terminated), nullptr);
  gtk_overlay_add_overlay(g_overlay, widget);
  if (g_ad_filter != nullptr) block_ads(view);
  apply_dark(view);
  webkit_web_view_load_uri(view, url);
  g_views[id] = view;
  return view;
}

// GTK keeps the keyboard with a page that was clicked, even once it is hidden:
// Flutter's text fields would stop receiving keys.
void focus_flutter() { gtk_widget_grab_focus(g_flutter_view); }

gboolean on_flutter_pressed(GtkWidget*, GdkEvent*, gpointer) {
  focus_flutter();
  return FALSE;  // The click goes on to Flutter.
}

void watch_flutter_clicks(GtkWidget* widget, gpointer) {
  g_signal_connect(widget, "button-press-event",
                   G_CALLBACK(on_flutter_pressed), nullptr);
}

void hide_all() {
  for (const auto& entry : g_views) {
    gtk_widget_hide(GTK_WIDGET(entry.second));
  }
  focus_flutter();
}

const gchar* string_arg(FlValue* args, const char* key) {
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(value)
             : nullptr;
}

gint int_arg(FlValue* args, const char* key) {
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_INT
             ? static_cast<gint>(fl_value_get_int(value))
             : 0;
}

void on_method_call(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  const gchar* id = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                        ? string_arg(args, "id")
                        : nullptr;
  auto found = id != nullptr ? g_views.find(id) : g_views.end();
  WebKitWebView* view = found != g_views.end() ? found->second : nullptr;

  if (strcmp(method, "supported") == 0) {
    // Answered below.
  } else if (strcmp(method, "load") == 0 && id != nullptr) {
    // Hidden until shown: switching to it later is instant.
    const gchar* url = string_arg(args, "url");
    if (view == nullptr && url != nullptr) create_view(id, url);
  } else if (strcmp(method, "show") == 0 && id != nullptr) {
    // Created on first use: restored tabs load only when opened.
    if (view == nullptr) {
      const gchar* url = string_arg(args, "url");
      if (url != nullptr) view = create_view(id, url);
    }
    // The others only: hiding this one too would make it flicker and lose focus.
    for (const auto& entry : g_views) {
      if (entry.second != view) gtk_widget_hide(GTK_WIDGET(entry.second));
    }
    if (view != nullptr) {
      GtkWidget* widget = GTK_WIDGET(view);
      gtk_widget_set_margin_start(widget, int_arg(args, "x"));
      gtk_widget_set_margin_top(widget, int_arg(args, "y"));
      gtk_widget_set_size_request(widget, int_arg(args, "width"),
                                  int_arg(args, "height"));
      gtk_widget_show(widget);
    }
  } else if (strcmp(method, "hide") == 0) {
    hide_all();
  } else if (strcmp(method, "close") == 0) {
    if (view != nullptr) {
      g_views.erase(found);
      gtk_widget_destroy(GTK_WIDGET(view));
      focus_flutter();
    }
  } else if (strcmp(method, "back") == 0) {
    if (view != nullptr) webkit_web_view_go_back(view);
  } else if (strcmp(method, "forward") == 0) {
    if (view != nullptr) webkit_web_view_go_forward(view);
  } else if (strcmp(method, "reload") == 0) {
    if (view != nullptr) webkit_web_view_reload(view);
  } else if (strcmp(method, "darkMode") == 0) {
    FlValue* on = fl_value_lookup_string(args, "on");
    set_dark(on != nullptr && fl_value_get_bool(on));
  } else if (strcmp(method, "siteData") == 0) {
    webkit_website_data_manager_fetch(data_manager(), WEBKIT_WEBSITE_DATA_ALL,
                                      nullptr, on_sites_fetched,
                                      g_object_ref(call));
    return;
  } else if (strcmp(method, "removeSiteData") == 0) {
    webkit_website_data_manager_fetch(data_manager(), WEBKIT_WEBSITE_DATA_ALL,
                                      nullptr, on_site_to_remove_fetched,
                                      g_object_ref(call));
    return;
  } else if (strcmp(method, "clearSiteData") == 0) {
    webkit_website_data_manager_clear(data_manager(), WEBKIT_WEBSITE_DATA_ALL, 0,
                                      nullptr, on_data_changed,
                                      g_object_ref(call));
    return;
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  respond_true(call);
}

}  // namespace

void site_webviews_init(FlBinaryMessenger* messenger, GtkOverlay* overlay,
                        GtkWidget* flutter_view) {
  g_overlay = overlay;
  g_flutter_view = flutter_view;
  compile_ad_filter();
  load_dark_script();
  watch_flutter_clicks(flutter_view, nullptr);
  gtk_container_forall(GTK_CONTAINER(flutter_view), watch_flutter_clicks,
                       nullptr);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_channel = fl_method_channel_new(messenger, "aupp/sites",
                                    FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_channel, on_method_call, nullptr,
                                            nullptr);
}

#else

// Built without WebKit: the channel stays unanswered and links open in the
// browser.
void site_webviews_init(FlBinaryMessenger*, GtkOverlay*, GtkWidget*) {}

#endif  // HAS_WEBKIT
