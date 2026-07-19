// Internal module seams for the GTK4 frontend. Every module includes this.
// Contract file: agents extend their own module's section; the tab/view/render
// seams below change only by integrator decision.
#pragma once

#include <adwaita.h>
#include <gtk/gtk.h>

#include "shenzhen_pdf_core.h"

G_BEGIN_DECLS

typedef struct _SpdfTab SpdfTab;
typedef struct _SpdfWindow SpdfWindow;

// ---------------------------------------------------------------------------
// spdf_launch.c — launch profiling (SPDF_LAUNCH_PROFILE=1, same as Mac).
void spdf_launch_mark(const char *stage); // no-op unless profiling enabled
gboolean spdf_launch_profile_enabled(void);

// ---------------------------------------------------------------------------
// spdf_render.c — worker render pipeline (ported semantics from GTK3 file:
// persistent worker docs, display-list cache, render tokens, 96MB byte cap).
typedef struct _SpdfRenderService SpdfRenderService;
typedef struct {
    int page;
    double scale;            // device pixels per PDF point
    GdkRectangle crop;       // page-space crop in device px; {0,0,0,0} = full
    guint64 token;           // request generation; stale results dropped
} SpdfRenderSpec;
// Fires exactly once per token, always on the main thread; texture is NULL on
// cancel/error/shutdown — the deterministic release point for user_data.
// texture is owned by callee after return.
typedef void (*SpdfRenderDone)(GdkTexture *texture, const SpdfRenderSpec *spec,
                               gpointer user_data);
SpdfRenderService *spdf_render_service_new(const char *path, char **error);
void spdf_render_service_free(SpdfRenderService *svc);
guint64 spdf_render_request(SpdfRenderService *svc, const SpdfRenderSpec *spec,
                            int priority /*0=visible,1=near,2=warm*/,
                            SpdfRenderDone done, gpointer user_data);
void spdf_render_cancel(SpdfRenderService *svc, guint64 token);
void spdf_render_set_byte_cap(SpdfRenderService *svc, gsize bytes);
// Drop every cached texture/list (rotation/OCR/save rewrote the file; worker
// docs re-open by themselves, keyed on path+mtime+size).
void spdf_render_service_invalidate(SpdfRenderService *svc);

// ---------------------------------------------------------------------------
// spdf_docview.c — the page canvas (custom GtkWidget, snapshot + GdkTexture).
#define SPDF_TYPE_DOC_VIEW (spdf_doc_view_get_type())
G_DECLARE_FINAL_TYPE(SpdfDocView, spdf_doc_view, SPDF, DOC_VIEW, GtkWidget)
SpdfDocView *spdf_doc_view_new(SpdfTab *tab);
void spdf_doc_view_goto_page(SpdfDocView *v, int page);
int spdf_doc_view_current_page(SpdfDocView *v);
void spdf_doc_view_set_zoom(SpdfDocView *v, double zoom, gboolean anchored,
                            double anchor_x, double anchor_y);
double spdf_doc_view_get_zoom(SpdfDocView *v);
typedef enum { SPDF_FIT_PAGE, SPDF_FIT_WIDTH, SPDF_FIT_CUSTOM } SpdfFitMode;
void spdf_doc_view_set_fit(SpdfDocView *v, SpdfFitMode m);
SpdfFitMode spdf_doc_view_get_fit(SpdfDocView *v);
void spdf_doc_view_get_scroll(SpdfDocView *v, double *x, double *y);
void spdf_doc_view_set_scroll(SpdfDocView *v, double x, double y);
char *spdf_doc_view_copy_selection(SpdfDocView *v); // NULL if none
// Kick the first-page render before the window maps (launch-speed budget);
// renders at the restored zoom, settle pass corrects fit after first allocate.
void spdf_doc_view_prime_first_page(SpdfDocView *v);
// "page-changed", "zoom-changed", "selection-changed" signals emitted.

// ---------------------------------------------------------------------------
// spdf_tab.c (owned by spdf_window.c agent) — per-document model.
struct _SpdfTab {
    char *path;
    spdf_document *doc;          // main-thread core doc (metadata/search)
    SpdfRenderService *render;
    SpdfDocView *view;
    AdwTabPage *page;            // owning AdwTabView page
    SpdfWindow *win;
    char *search_text;           // persisted per-tab query
    gboolean read_only_shadow;   // orange-dot shadow copy tab
    // agents may append fields; never reorder existing ones mid-wave
};
SpdfTab *spdf_tab_open(SpdfWindow *win, const char *path, char **error);
void spdf_tab_close(SpdfTab *tab);

// ---------------------------------------------------------------------------
// spdf_state.c — JSON state, schema-compatible with the Mac app.
typedef struct _SpdfState SpdfState; // settings + session + favorites + recents
SpdfState *spdf_state_load(void);    // cheap; must stay off the hot launch path
void spdf_state_save_session(SpdfState *s); // coalesced, async write
void spdf_state_flush(SpdfState *s);

G_END_DECLS
