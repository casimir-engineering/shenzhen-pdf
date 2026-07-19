// Shenzhen PDF — GTK4 frontend entry point. Launch speed is a headline
// requirement (<=120 ms cold to first paint), so this file does nothing but
// mark the launch origin and hand over to AdwApplication; everything
// non-essential is deferred behind the first window map (see spdf_app.c).

#include "spdf_app.h"

int main(int argc, char** argv) {
    SpdfApp* app;
    int status;

    spdf_launch_mark("main");
    app = spdf_app_new();
    status = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return status;
}
