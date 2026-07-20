// Shenzhen PDF — GTK4 frontend entry point. Launch speed is a headline
// requirement (<=120 ms cold to first paint), so this file does nothing but
// mark the launch origin and hand over to AdwApplication; everything
// non-essential is deferred behind the first window map (see spdf_app.c).

#include "spdf_app.h"
#include "spdf_updater.h"

int main(int argc, char** argv) {
    SpdfApp* app;
    int status;

    // Updater CLI flags (--check-updates-now / --install-update /
    // --updater-health-probe) run headless and exit before GApplication is
    // constructed; for every normal launch this is a handful of strcmps.
    status = spdf_updater_handle_cli(argc, argv);
    if (status >= 0) return status;

    // Cold-path trim (Wave D): force the measured-fastest GSK renderer
    // before GTK/adwaita initialize. On the dev machine (2026-07-19,
    // GTK 4.20/GNOME 49/Wayland) "gl" cut startup 370→238 ms and
    // invoke-to-present 692→455 ms vs the default renderer. Default-only
    // (overwrite=FALSE): a user's own GSK_RENDERER always wins.
    g_setenv("GSK_RENDERER", "gl", FALSE);

    spdf_launch_mark("main");
    app = spdf_app_new();
    status = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return status;
}
