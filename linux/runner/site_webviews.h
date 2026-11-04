#ifndef RUNNER_SITE_WEBVIEWS_H_
#define RUNNER_SITE_WEBVIEWS_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Fork: sites inside the app. Flutter has no web view on Linux, so these are
// WebKit views placed over the part of the window the Dart side reserves for
// them (lib/desktop/asset-workspaces.dart), through the channel "aupp/sites".
void site_webviews_init(FlBinaryMessenger* messenger, GtkOverlay* overlay,
                        GtkWidget* flutter_view);

#endif  // RUNNER_SITE_WEBVIEWS_H_
