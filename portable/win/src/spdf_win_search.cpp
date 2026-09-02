/* The find engine. See spdf_win_chrome_find.h for the API and for why it is
 * declared there rather than in spdf_win_search.h.
 *
 * THE SHAPE, and every rule it obeys:
 *
 *   - ONE WORKER THREAD PER SEARCH, with its own spdf_document. The core allows
 *     one document per thread, so the app's handle is never touched off-thread;
 *     this is the same model as the GTK4 controller (spdf_search.c
 *     search_worker) and the macOS startFindForCurrentQuery. Results arrive as
 *     generation-checked batches of 128, so a long document highlights and
 *     counts as it goes rather than after.
 *
 *   - NOTHING ON THE PAINT PATH OR THE LAUNCH PATH. The session allocates one
 *     struct and starts no thread until a non-empty query arrives, so a document
 *     nobody searches, every --render-png and the probe all pay exactly nothing.
 *     Everything the UI thread calls (set with an unchanged query, poll,
 *     step, marks, apply_overlays) is O(1)-ish and cannot block.
 *
 *   - CANCELLATION IS A COUNTER. spdf_win_find_set bumps `generation`; the worker
 *     polls it once per page and stops, and any batch it already posted is
 *     discarded because it carries the old generation. Deliberately not a thread
 *     join: a join on the UI thread is a stall of exactly the length of the
 *     search that is being abandoned, which is the wrong end of the trade.
 *
 *   - THE PORTED LOGIC IS CALLED, NOT REIMPLEMENTED. Every decision below that
 *     has a GTK4 original -- the match list and its 20000 cap, the query byte
 *     cap, the snippet, chapter attribution, the marker fractions -- goes through
 *     spdf_win_search.h, which is differentially tested against that original.
 *
 * The CHROME-FACING half -- the process-wide session, the temporary query bridge
 * and spdf_win_find_fill_model() -- is in spdf_win_chrome_find.cpp, so this file
 * stays the engine and the session struct below stays private to it.
 */
#include "spdf_win_chrome_find.h"

#include "spdf_win_d2d.h" /* spdf_win_scene, spdf_win_overlay */
#include "spdf_win_layout.h"

#include <process.h>
#include <stdlib.h>
#include <string.h>

#define SPDF_FIND_PAGE_RECT_MAX 256 /* GTK3's per-page rect cap (SEARCH_PAGE_RECT_MAX) */
#define SPDF_FIND_BATCH_MATCHES 128 /* GTK4's worker->main delivery granularity */
#define SPDF_FIND_DEFAULT_LANE_H 800.0f

struct SpdfWinFindSession {
    CRITICAL_SECTION lock;

    /* --- UI thread only ------------------------------------------------- */
    char* path;
    char* query;
    int regex;
    SpdfWinSearchMatchList list;
    int current;
    int started;
    char error[512];

    float* marks;
    int mark_count;
    int active_mark;
    float* raw_marks;
    int raw_capacity;
    float lane_h;    /* device px of the scroller trough, from the last frame */
    float dpi_scale; /* device px per logical px, likewise */

    spdf_win_overlay* overlays;
    int overlay_capacity;
    int overlay_count;

    /* --- shared, under `lock` ------------------------------------------- */
    SpdfWinSearchMatchList pending;
    long pending_gen;
    char pending_error[512];
    int pending_has_error;
    SpdfWinPageSizePt* sizes;
    int size_count;

    /* --- interlocked ---------------------------------------------------- */
    volatile long generation;
    volatile long finished_gen;
    volatile long live_workers;

    /* Repaint side channel, exactly the shape and the justification of
     * spdf_win_thumbs_note_paint_thread: a batch lands on a worker thread
     * milliseconds to seconds after the frame that asked for it, and without
     * this the highlights and the counter would not appear until the next mouse
     * move. spdf_win_paint() still needs no HWND -- this is the session's side
     * channel, not the painter's. */
    HWND windows[8];
    int window_count;
    int noted_paint_thread;
};

/* Defined in spdf_win_search_geometry.h, which is included at the BOTTOM of this
 * file so it sees the complete struct above. Forward-declared here because the
 * UI-thread API below rebuilds the ticks whenever the match list or the current
 * match moves. */
static void rebuild_marks(SpdfWinFindSession* s);

namespace {

char* dup_str(const char* s) {
    size_t n;
    char* out;
    if (!s) return NULL;
    n = strlen(s);
    out = (char*)malloc(n + 1);
    if (out) memcpy(out, s, n + 1);
    return out;
}

int same_str(const char* a, const char* b) {
    if (!a) a = "";
    if (!b) b = "";
    return strcmp(a, b) == 0;
}

BOOL CALLBACK collect_window(HWND hwnd, LPARAM param) {
    SpdfWinFindSession* s = (SpdfWinFindSession*)param;
    if (s->window_count < (int)(sizeof(s->windows) / sizeof(s->windows[0]))) s->windows[s->window_count++] = hwnd;
    return TRUE;
}

void invalidate_windows(SpdfWinFindSession* s) {
    int i;
    EnterCriticalSection(&s->lock);
    for (i = 0; i < s->window_count; ++i) InvalidateRect(s->windows[i], NULL, FALSE);
    LeaveCriticalSection(&s->lock);
}

struct Job {
    SpdfWinFindSession* session;
    long generation;
    char* path;
    char* query;
    int regex;
};

/* One page's worth of snippets, from the page's own text lines. The GTK4 worker
 * does exactly this and for the same reason: the snippet is the sidebar's row
 * text, and extracting lines is only worth it on a page that actually matched. */
void snippets_for_page(spdf_document* doc, int page, const spdf_rect* rects, int hits, int chapter,
                       SpdfWinSearchMatchList* batch, int* total) {
    char err[256] = {0};
    spdf_text_lines lines;
    const char** texts = NULL;
    spdf_rect* bounds = NULL;
    int has_lines, i;

    memset(&lines, 0, sizeof(lines));
    has_lines = spdf_extract_page_text_lines(doc, page, &lines, err, sizeof(err)) && lines.count > 0;
    if (has_lines) {
        texts = (const char**)malloc(sizeof(*texts) * (size_t)lines.count);
        bounds = (spdf_rect*)malloc(sizeof(*bounds) * (size_t)lines.count);
        if (!texts || !bounds) has_lines = 0;
    }
    if (has_lines) {
        for (i = 0; i < lines.count; ++i) {
            texts[i] = lines.items[i].text;
            bounds[i] = lines.items[i].bounds;
        }
    }
    for (i = 0; i < hits && *total < SPDF_WIN_SEARCH_MAX_MATCHES; ++i) {
        char* snippet = has_lines ? spdf_win_search_snippet(texts, bounds, lines.count, rects[i])
                                  : spdf_win_search_dup_bytes("", 0);
        spdf_win_search_match_list_append(batch, page, rects[i], snippet, chapter);
        (*total)++;
    }
    free(texts);
    free(bounds);
    if (lines.count > 0 || lines.items) spdf_free_text_lines(&lines);
}

/* Hands a batch to the UI thread. Discards it if the generation has moved on,
 * and RESETS whatever an older generation left behind -- otherwise a fast
 * retype would deliver the tail of the previous query's results. */
void post_batch(SpdfWinFindSession* s, long gen, SpdfWinSearchMatchList* batch, const char* error) {
    EnterCriticalSection(&s->lock);
    if (s->pending_gen != gen) {
        spdf_win_search_match_list_clear(&s->pending);
        s->pending_gen = gen;
        s->pending_has_error = 0;
        s->pending_error[0] = 0;
    }
    spdf_win_search_match_list_steal_into(&s->pending, batch);
    if (error && error[0]) {
        /* A failed search shows NO matches (GTK3 semantics, inherited by the
         * mac app), so the error arrives having thrown the rest away. */
        spdf_win_search_match_list_clear(&s->pending);
        s->pending_has_error = 1;
        strncpy(s->pending_error, error, sizeof(s->pending_error) - 1);
        s->pending_error[sizeof(s->pending_error) - 1] = 0;
    }
    LeaveCriticalSection(&s->lock);
    invalidate_windows(s);
}

unsigned __stdcall search_worker(void* arg) {
    Job* job = (Job*)arg;
    SpdfWinFindSession* s = job->session;
    char err[512] = {0};
    const char* error = NULL;
    SpdfWinSearchMatchList batch;
    int* chapter_pages = NULL;
    int chapter_count = 0;
    int total = 0;
    int page, page_count = 0;
    spdf_document* doc;

    spdf_win_search_match_list_init(&batch);
    doc = spdf_open(job->path, err, sizeof(err));
    if (!doc) {
        error = err[0] ? err : "Could not open the document for search.";
    } else {
        spdf_outline outline;
        memset(&outline, 0, sizeof(outline));
        page_count = spdf_page_count(doc);
        if (spdf_load_outline(doc, &outline, err, sizeof(err)) && outline.count > 0) {
            chapter_count = outline.count;
            chapter_pages = (int*)malloc(sizeof(int) * (size_t)chapter_count);
            if (chapter_pages)
                for (int i = 0; i < chapter_count; ++i) chapter_pages[i] = outline.items[i].page_index;
            else
                chapter_count = 0;
        }
        spdf_free_outline(&outline);

        /* The mark layout needs every page's height, and the overlay mapping
         * needs the width of any page that matched. Both are published as the
         * sweep reaches them; an unmeasured page borrows page 0's size, which is
         * macOS's own placeholder geometry pass. */
        EnterCriticalSection(&s->lock);
        free(s->sizes);
        s->sizes = page_count > 0 ? (SpdfWinPageSizePt*)calloc((size_t)page_count, sizeof(SpdfWinPageSizePt)) : NULL;
        s->size_count = s->sizes ? page_count : 0;
        LeaveCriticalSection(&s->lock);

        for (page = 0; page < page_count && total < SPDF_WIN_SEARCH_MAX_MATCHES; ++page) {
            spdf_rect rects[SPDF_FIND_PAGE_RECT_MAX];
            int hits;
            float pw = 0.0f, ph = 0.0f;

            if (InterlockedCompareExchange(&s->generation, 0, 0) != job->generation) break;

            if (spdf_page_size(doc, page, &pw, &ph, err, sizeof(err)) && pw > 0.0f && ph > 0.0f) {
                EnterCriticalSection(&s->lock);
                if (s->sizes && page < s->size_count) {
                    s->sizes[page].width = (double)pw;
                    s->sizes[page].height = (double)ph;
                }
                LeaveCriticalSection(&s->lock);
            }

            hits = spdf_search_page_rects_options(doc, page, job->query, job->regex, 0, rects,
                                                 SPDF_FIND_PAGE_RECT_MAX, err, sizeof(err));
            if (hits < 0) {
                /* Graceful invalid-pattern failure: the first error wins. */
                error = err[0] ? err : (job->regex ? "Invalid regular expression." : "Search failed.");
                break;
            }
            if (hits == 0) continue;

            snippets_for_page(doc, page, rects, hits, spdf_win_search_chapter_for_page(chapter_pages, chapter_count, page),
                              &batch, &total);
            if (spdf_win_search_match_list_count(&batch) >= SPDF_FIND_BATCH_MATCHES)
                post_batch(s, job->generation, &batch, NULL);
        }
        spdf_close(doc);
    }

    post_batch(s, job->generation, &batch, error);
    spdf_win_search_match_list_deinit(&batch);
    free(chapter_pages);
    InterlockedExchange(&s->finished_gen, job->generation);
    InterlockedDecrement(&s->live_workers);
    free(job->path);
    free(job->query);
    free(job);
    return 0;
}

} /* namespace */

SpdfWinFindSession* spdf_win_find_session_new(void) {
    SpdfWinFindSession* s = (SpdfWinFindSession*)calloc(1, sizeof(SpdfWinFindSession));
    if (!s) return NULL;
    InitializeCriticalSection(&s->lock);
    spdf_win_search_match_list_init(&s->list);
    spdf_win_search_match_list_init(&s->pending);
    s->current = -1;
    s->active_mark = -1;
    s->pending_gen = -1;
    s->finished_gen = 0;
    s->lane_h = SPDF_FIND_DEFAULT_LANE_H;
    s->dpi_scale = 1.0f;
    return s;
}

void spdf_win_find_session_free(SpdfWinFindSession* s) {
    if (!s) return;
    /* Bump first so every worker stops at its next page boundary, then wait for
     * them: they hold a pointer to this struct. The wait is bounded by one page
     * search, and it is the only blocking wait in the file. */
    InterlockedIncrement(&s->generation);
    while (InterlockedCompareExchange(&s->live_workers, 0, 0) != 0) Sleep(1);
    spdf_win_search_match_list_deinit(&s->list);
    spdf_win_search_match_list_deinit(&s->pending);
    free(s->sizes);
    free(s->marks);
    free(s->raw_marks);
    free(s->overlays);
    free(s->path);
    free(s->query);
    DeleteCriticalSection(&s->lock);
    free(s);
}

/* --- UI-thread API ------------------------------------------------------- */

static void reset_results(SpdfWinFindSession* s) {
    spdf_win_search_match_list_clear(&s->list);
    s->current = -1;
    s->mark_count = 0;
    s->active_mark = -1;
    s->error[0] = 0;
    s->started = 0;
    EnterCriticalSection(&s->lock);
    spdf_win_search_match_list_clear(&s->pending);
    s->pending_has_error = 0;
    s->pending_error[0] = 0;
    LeaveCriticalSection(&s->lock);
}

void spdf_win_find_set(SpdfWinFindSession* s, const char* utf8_path, const char* utf8_query, int regex) {
    Job* job;
    char* capped;
    HANDLE thread;

    if (!s) return;
    regex = regex ? 1 : 0;
    if (same_str(s->path, utf8_path) && same_str(s->query, utf8_query) && s->regex == regex) return;

    free(s->path);
    free(s->query);
    s->path = dup_str(utf8_path);
    s->query = dup_str(utf8_query);
    s->regex = regex;

    InterlockedIncrement(&s->generation);
    reset_results(s);
    if (!s->path || !s->query || !s->query[0]) {
        InterlockedExchange(&s->finished_gen, InterlockedCompareExchange(&s->generation, 0, 0));
        return;
    }

    capped = spdf_win_search_dup_query(s->query);
    job = (Job*)calloc(1, sizeof(Job));
    if (!job || !capped) {
        free(capped);
        free(job);
        return;
    }
    job->session = s;
    job->generation = InterlockedCompareExchange(&s->generation, 0, 0);
    job->path = dup_str(s->path);
    job->query = capped;
    job->regex = regex;
    if (!job->path) {
        free(job->query);
        free(job);
        return;
    }
    s->started = 1;
    InterlockedIncrement(&s->live_workers);
    thread = (HANDLE)_beginthreadex(NULL, 0, search_worker, job, 0, NULL);
    if (!thread) {
        InterlockedDecrement(&s->live_workers);
        s->started = 0;
        free(job->path);
        free(job->query);
        free(job);
        return;
    }
    CloseHandle(thread); /* detached: the generation counter is the join */
}

int spdf_win_find_poll(SpdfWinFindSession* s) {
    long gen;
    int changed = 0;
    if (!s) return 0;
    gen = InterlockedCompareExchange(&s->generation, 0, 0);
    EnterCriticalSection(&s->lock);
    if (s->pending_gen == gen) {
        if (spdf_win_search_match_list_count(&s->pending) > 0) {
            spdf_win_search_match_list_steal_into(&s->list, &s->pending);
            changed = 1;
        }
        if (s->pending_has_error) {
            s->pending_has_error = 0;
            strncpy(s->error, s->pending_error, sizeof(s->error) - 1);
            s->error[sizeof(s->error) - 1] = 0;
            spdf_win_search_match_list_clear(&s->list);
            s->current = -1;
            changed = 1;
        }
    }
    LeaveCriticalSection(&s->lock);
    if (changed) {
        /* Only pick a current match if the reader has not already stepped to
         * one: indices are stable because batches only append, so recomputing
         * would yank the view away from their choice (GTK4 deliver_idle). */
        if (s->current < 0 && spdf_win_search_match_list_count(&s->list) > 0) s->current = 0;
        rebuild_marks(s);
    }
    return changed;
}

int spdf_win_find_searching(const SpdfWinFindSession* s) {
    if (!s || !s->started) return 0;
    return InterlockedCompareExchange((volatile long*)&s->finished_gen, 0, 0) !=
           InterlockedCompareExchange((volatile long*)&s->generation, 0, 0);
}

int spdf_win_find_match_count(const SpdfWinFindSession* s) {
    return s ? (int)spdf_win_search_match_list_count(&s->list) : 0;
}

int spdf_win_find_match_index(const SpdfWinFindSession* s) { return s ? s->current : -1; }

const char* spdf_win_find_error(const SpdfWinFindSession* s) { return s && s->error[0] ? s->error : NULL; }

int spdf_win_find_step(SpdfWinFindSession* s, int delta) {
    int count;
    if (!s) return -1;
    count = (int)spdf_win_search_match_list_count(&s->list);
    if (count <= 0) return s->current = -1;
    if (s->current < 0) s->current = delta >= 0 ? 0 : count - 1;
    else {
        /* Wraparound, as GTK3 find_step does. The modulo is written so a
         * negative delta larger than count still lands in range. */
        s->current = ((s->current + delta) % count + count) % count;
    }
    rebuild_marks(s);
    return s->current;
}

int spdf_win_find_current_target(const SpdfWinFindSession* s, int* out_page, spdf_rect* out_rect) {
    const SpdfWinSearchMatch* m;
    if (!s || s->current < 0) return 0;
    m = spdf_win_search_match_list_get(&s->list, (unsigned)s->current);
    if (!m) return 0;
    if (out_page) *out_page = m->page;
    if (out_rect) *out_rect = m->rect;
    return 1;
}

const float* spdf_win_find_marks(const SpdfWinFindSession* s, int* out_count, int* out_active) {
    if (out_count) *out_count = s ? s->mark_count : 0;
    if (out_active) *out_active = s ? s->active_mark : -1;
    return s ? s->marks : NULL;
}

/* The paint thread's windows, for the repaint side channel described on the
 * `windows` field. Exported rather than done inline in the model builder so the
 * session's internals stay inside this translation unit. Idempotent, and a
 * no-op in a headless process, where the painting thread owns no windows. */
void spdf_win_find_note_paint_thread(SpdfWinFindSession* s) {
    if (!s || s->noted_paint_thread) return;
    s->noted_paint_thread = 1;
    EnterCriticalSection(&s->lock);
    s->window_count = 0;
    EnumThreadWindows(GetCurrentThreadId(), collect_window, (LPARAM)s);
    LeaveCriticalSection(&s->lock);
}

/* The two mappings from matches to pixels. Included HERE, at the bottom, so it
 * sees the complete session struct; see its own header comment. */
#include "spdf_win_search_geometry.h"
