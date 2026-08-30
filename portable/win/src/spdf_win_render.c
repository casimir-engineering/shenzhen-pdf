/* spdf_win_render.c — the worker render pool. Contract and policy rationale
 * live in spdf_win_render.h; this file is the mechanism. The pthread branch is
 * not about portability of the product: it lets this exact scheduling code run
 * under ThreadSanitizer, which no MSVC build can do.
 *
 * LOCKING RULE: svc->lock covers every field of the service and of every task
 * except task.abort_flag, which is atomic precisely so a running render can
 * poll it without contending with the UI thread. Everything set in
 * spdf_win_render_service_new() is immutable thereafter and needs no lock.
 * Renders, done callbacks and the notify hook all run with the lock RELEASED. */

#include "spdf_win_render.h"

#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <process.h>
#include <windows.h>
typedef SRWLOCK spdf_mtx;
typedef CONDITION_VARIABLE spdf_cnd;
typedef HANDLE spdf_thr;
#define MTX_INIT(m) InitializeSRWLock(m)
#define MTX_LOCK(m) AcquireSRWLockExclusive(m)
#define MTX_UNLOCK(m) ReleaseSRWLockExclusive(m)
#define CND_INIT(c) InitializeConditionVariable(c)
#define CND_WAIT(c, m) ((void)SleepConditionVariableSRW((c), (m), INFINITE, 0))
#define CND_BROADCAST(c) WakeAllConditionVariable(c)
#define THR_START(out, fn, arg) (((*(out)) = (spdf_thr)_beginthreadex(NULL, 0, (fn), (arg), 0, NULL)) != NULL)
#define THR_JOIN(t) (WaitForSingleObject((t), INFINITE), (void)CloseHandle(t))
#define ATOMIC_LOAD(p) ((long)InterlockedCompareExchange((volatile LONG*)(p), 0, 0))
#define ATOMIC_STORE(p, v) ((void)InterlockedExchange((volatile LONG*)(p), (LONG)(v)))
#define SPDF_TLS __declspec(thread)
#define WORKER_ENTRY unsigned __stdcall
#define WORKER_RETURN 0
#else
#include <pthread.h>
#include <unistd.h>
typedef pthread_mutex_t spdf_mtx;
typedef pthread_cond_t spdf_cnd;
typedef pthread_t spdf_thr;
#define MTX_INIT(m) pthread_mutex_init((m), NULL)
#define MTX_LOCK(m) pthread_mutex_lock(m)
#define MTX_UNLOCK(m) pthread_mutex_unlock(m)
#define CND_INIT(c) pthread_cond_init((c), NULL)
#define CND_WAIT(c, m) pthread_cond_wait((c), (m))
#define CND_BROADCAST(c) pthread_cond_broadcast(c)
#define THR_START(out, fn, arg) (pthread_create((out), NULL, (fn), (arg)) == 0)
#define THR_JOIN(t) ((void)pthread_join((t), NULL))
#define ATOMIC_LOAD(p) __atomic_load_n((p), __ATOMIC_SEQ_CST)
#define ATOMIC_STORE(p, v) __atomic_store_n((p), (long)(v), __ATOMIC_SEQ_CST)
#define SPDF_TLS __thread
#define WORKER_ENTRY void*
#define WORKER_RETURN NULL
#endif

typedef struct waiter {
    unsigned long long token;
    spdf_win_render_done done;
    void* user_data;
} waiter;

typedef struct task {
    struct task* next; /* on svc->pending or svc->running, never both */
    spdf_win_render_key key;
    spdf_win_render_spec spec;
    int priority, waiter_count;
    unsigned long long seq;
    volatile long abort_flag;
    spdf_render_token* core_token;
    waiter waiters[SPDF_WIN_RENDER_MAX_WAITERS];
} task;

typedef struct completion {
    struct completion* next;
    spdf_win_render_result result;
    spdf_win_render_done done;
    void* user_data;
} completion;

struct spdf_win_render_service {
    char* path;
    spdf_win_render_backend backend;
    spdf_mtx lock;
    spdf_cnd wake;
    task *pending, *running;
    completion *ready_head, *ready_tail;
    int ready_count, inflight, shutdown, worker_target, worker_count;
    unsigned long long next_token, next_seq, generation, tasks_started;
    size_t max_bytes;
    spdf_thr workers[SPDF_WIN_RENDER_MAX_WORKERS];
    spdf_win_render_notify notify; /* immutable: read without the lock */
    void* notify_ctx;
};

int spdf_win_render_aborted(const spdf_win_render_abort* abort) {
    return abort && abort->flag && ATOMIC_LOAD(abort->flag) != 0;
}

static char* dup_str(const char* s) {
    size_t n = s ? strlen(s) + 1 : 0;
    char* out = n ? (char*)malloc(n) : NULL;
    if (out) memcpy(out, s, n);
    return out;
}
/* --- completions and waiters. Every function here needs the lock held. --- */
static completion* queue_completion(spdf_win_render_service* svc, const task* t, const waiter* w, int status,
                                    unsigned long long primary, const char* err) {
    completion* c = (completion*)calloc(1, sizeof(*c));
    if (!c) return NULL; /* nothing useful is possible here; dropping beats crashing */
    c->result.token = w->token;
    c->result.primary_token = primary;
    c->result.spec = t->spec;
    c->result.status = status;
    c->result.render_zoom = t->spec.zoom;
    c->done = w->done;
    c->user_data = w->user_data;
    if (err && *err) {
        strncpy(c->result.err, err, sizeof(c->result.err) - 1);
        c->result.err[sizeof(c->result.err) - 1] = '\0';
    }
    if (svc->ready_tail)
        svc->ready_tail->next = c;
    else
        svc->ready_head = c;
    svc->ready_tail = c;
    svc->ready_count++;
    svc->inflight--;
    return c;
}

/* Detach waiter `i` and queue its one callback. Losing the last waiter aborts
 * the render: that is what stops superseded work instead of letting it run. */
static void retire_waiter(spdf_win_render_service* svc, task* t, int i, int status, const char* err) {
    (void)queue_completion(svc, t, &t->waiters[i], status, 0, err);
    t->waiters[i] = t->waiters[t->waiter_count - 1];
    if (--t->waiter_count == 0) {
        ATOMIC_STORE(&t->abort_flag, 1);
        if (t->core_token) spdf_render_token_cancel(t->core_token);
    }
}

static void unlink_task(task** list, task* t) {
    for (; *list; list = &(*list)->next)
        if (*list == t) {
            *list = t->next;
            return;
        }
}

static void retire_pending(spdf_win_render_service* svc, task* t, int status) {
    while (t->waiter_count > 0) retire_waiter(svc, t, t->waiter_count - 1, status, NULL);
    unlink_task(&svc->pending, t);
    if (t->core_token) spdf_render_token_free(t->core_token);
    free(t);
}

/* Lowest (priority, seq) wins: the visible page before its neighbours, FIFO
 * inside a band. Linear scan, on a worker, never on the UI thread. */
static task* pick_pending(spdf_win_render_service* svc) {
    task *best = NULL, *t;
    for (t = svc->pending; t; t = t->next)
        if (!best || t->priority < best->priority || (t->priority == best->priority && t->seq < best->seq)) best = t;
    if (best) unlink_task(&svc->pending, best);
    return best;
}

/* Same generation and identity, still able to take a waiter. */
static task* find_open_task(spdf_win_render_service* svc, const spdf_win_render_key* key, unsigned long long gen) {
    task* t;
    int pass;
    for (pass = 0; pass < 2; pass++)
        for (t = pass == 0 ? svc->pending : svc->running; t; t = t->next)
            if (t->spec.generation == gen && t->waiter_count > 0 && t->waiter_count < SPDF_WIN_RENDER_MAX_WAITERS &&
                spdf_win_render_key_equal(&t->key, key))
                return t;
    return NULL;
}
/* --- the worker -------------------------------------------------------- */
/* On success the first waiter gets the pixels and the rest are told which token
 * did, so nothing is copied and each request still gets exactly one callback. */
static void finish_task(spdf_win_render_service* svc, task* t, spdf_bitmap* bitmap, int status, const char* err,
                        float render_zoom) {
    completion* c = NULL;
    int i;
    unlink_task(&svc->running, t);
    if (status == SPDF_WIN_RENDER_OK && !bitmap->rgba) status = SPDF_WIN_RENDER_ERROR;
    if (svc->shutdown && status != SPDF_WIN_RENDER_OK) status = SPDF_WIN_RENDER_SHUTDOWN;
    if (status == SPDF_WIN_RENDER_OK && t->waiter_count > 0)
        c = queue_completion(svc, t, &t->waiters[0], SPDF_WIN_RENDER_OK, 0, "");
    if (c) {
        c->result.width = bitmap->width;
        c->result.height = bitmap->height;
        c->result.stride = bitmap->stride;
        c->result.rgba = bitmap->rgba;
        c->result.render_zoom = render_zoom;
        for (i = 1; i < t->waiter_count; i++)
            (void)queue_completion(svc, t, &t->waiters[i], SPDF_WIN_RENDER_COALESCED, t->waiters[0].token, "");
        t->waiter_count = 0;
    } else {
        spdf_free_bitmap(bitmap);
        while (t->waiter_count > 0) retire_waiter(svc, t, t->waiter_count - 1, status, err);
    }
    if (t->core_token) spdf_render_token_free(t->core_token);
    free(t);
}

/* Lock RELEASED. *zoom comes back as what was rendered at, which the byte cap
 * can reduce below the requested zoom. */
static int run_task(spdf_win_render_service* svc, task* t, spdf_bitmap* bitmap, double* zoom, char* err, size_t n) {
    spdf_win_render_abort ab;
    float pw = 0.0f, ph = 0.0f;
    ab.token = t->core_token;
    ab.flag = &t->abort_flag;
    *zoom = (double)t->spec.zoom;
    if (ATOMIC_LOAD(&t->abort_flag)) return SPDF_WIN_RENDER_CANCELED; /* cancelled before it ever started */
    if (svc->backend.page_size) {
        if (!svc->backend.page_size(svc->backend.ctx, svc->path, t->spec.page, &pw, &ph, err, n))
            return SPDF_WIN_RENDER_ERROR;
        *zoom = spdf_win_render_capped_zoom(*zoom, pw, ph, svc->max_bytes);
    }
    if (!svc->backend.render(svc->backend.ctx, svc->path, t->spec.page, (float)*zoom, t->spec.flags, &ab, bitmap, err,
                             n))
        return ATOMIC_LOAD(&t->abort_flag) ? SPDF_WIN_RENDER_CANCELED : SPDF_WIN_RENDER_ERROR;
    return SPDF_WIN_RENDER_OK;
}

static void worker_body(spdf_win_render_service* svc) {
    for (;;) {
        task* t = NULL;
        spdf_bitmap bitmap;
        char err[256];
        double zoom = 0.0;
        int status;
        MTX_LOCK(&svc->lock);
        while (!svc->shutdown && (t = pick_pending(svc)) == NULL) CND_WAIT(&svc->wake, &svc->lock);
        if (svc->shutdown) {
            MTX_UNLOCK(&svc->lock);
            break;
        }
        t->next = svc->running;
        svc->running = t;
        svc->tasks_started++;
        MTX_UNLOCK(&svc->lock);
        err[0] = '\0';
        memset(&bitmap, 0, sizeof(bitmap));
        status = run_task(svc, t, &bitmap, &zoom, err, sizeof(err));
        MTX_LOCK(&svc->lock);
        /* The generation may have moved while this ran; stale pixels must
         * never reach the view. */
        if (status == SPDF_WIN_RENDER_OK && t->spec.generation != svc->generation)
            status = SPDF_WIN_RENDER_SUPERSEDED;
        finish_task(svc, t, &bitmap, status, err, (float)zoom);
        MTX_UNLOCK(&svc->lock);
        if (svc->notify) svc->notify(svc->notify_ctx);
    }
    if (svc->backend.thread_exit) svc->backend.thread_exit(svc->backend.ctx);
}

static WORKER_ENTRY worker_entry(void* arg) {
    worker_body((spdf_win_render_service*)arg);
    return WORKER_RETURN;
}
/* --- the default backend: the shipping core ----------------------------
 * One spdf_document per worker thread, per the core's one-document-per-thread
 * contract (shenzhen_pdf_core.c:40-43). Kept across renders so the core's
 * per-page display-list cache stays warm; released when the worker exits. */
static SPDF_TLS spdf_document* g_slot_doc;
static SPDF_TLS char* g_slot_path;

static void core_thread_exit(void* ctx) {
    (void)ctx;
    if (g_slot_doc) spdf_close(g_slot_doc);
    free(g_slot_path);
    g_slot_doc = NULL;
    g_slot_path = NULL;
}

static spdf_document* core_doc(const char* path, char* err, size_t err_len) {
    if (g_slot_doc && g_slot_path && path && strcmp(g_slot_path, path) == 0) return g_slot_doc;
    core_thread_exit(NULL);
    if (!path) return NULL;
    g_slot_doc = spdf_open(path, err, err_len);
    if (g_slot_doc) g_slot_path = dup_str(path);
    return g_slot_doc;
}

static int core_page_size(void* ctx, const char* path, int page, float* w, float* h, char* err, size_t err_len) {
    spdf_document* doc = core_doc(path, err, err_len);
    (void)ctx;
    return doc ? spdf_page_size(doc, page, w, h, err, err_len) : 0;
}

/* DARK_THEME / PRESERVE_IMAGES arrive in `flags` and are part of the request's
 * identity; nothing here decides the theme. USE_PAGE_LIST is ours. */
static int core_render(void* ctx, const char* path, int page, float zoom, unsigned flags,
                       const spdf_win_render_abort* abort, spdf_bitmap* out, char* err, size_t err_len) {
    spdf_document* doc = core_doc(path, err, err_len);
    (void)ctx;
    return doc ? spdf_render_page_rgba_opts(doc, page, zoom, flags | SPDF_RENDER_USE_PAGE_LIST,
                                            abort ? abort->token : NULL, out, err, err_len)
               : 0;
}

const spdf_win_render_backend* spdf_win_render_core_backend(void) {
    static const spdf_win_render_backend backend = {NULL, core_page_size, core_render, core_thread_exit};
    return &backend;
}
/* --- the service ------------------------------------------------------- */
static int worker_target(void) {
    const char* forced = getenv("SPDF_RENDER_WORKERS");
    int n;
#ifdef _WIN32
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    n = (int)info.dwNumberOfProcessors / 2;
#else
    n = (int)sysconf(_SC_NPROCESSORS_ONLN) / 2;
#endif
    if (forced && *forced && atoi(forced) > 0) n = atoi(forced);
    if (n < 1) n = 1;
    return n > SPDF_WIN_RENDER_MAX_WORKERS ? SPDF_WIN_RENDER_MAX_WORKERS : n;
}

spdf_win_render_service* spdf_win_render_service_new(const char* path, const spdf_win_render_backend* backend,
                                                     size_t max_bytes, spdf_win_render_notify notify, void* ctx) {
    spdf_win_render_service* svc = path && *path ? (spdf_win_render_service*)calloc(1, sizeof(*svc)) : NULL;
    if (!svc) return NULL;
    svc->path = dup_str(path);
    svc->notify = notify;
    svc->notify_ctx = ctx;
    svc->backend = *(backend ? backend : spdf_win_render_core_backend());
    if (!svc->path || !svc->backend.render) {
        free(svc->path);
        free(svc);
        return NULL;
    }
    MTX_INIT(&svc->lock);
    CND_INIT(&svc->wake);
    svc->next_token = 1;
    svc->generation = 1;
    svc->max_bytes = max_bytes ? max_bytes : SPDF_WIN_RENDER_MAX_BYTES;
    svc->worker_target = worker_target();
    return svc;
}

void spdf_win_render_service_free(spdf_win_render_service* svc) {
    task* t;
    int i;
    if (!svc) return;
    MTX_LOCK(&svc->lock);
    svc->shutdown = 1;
    for (t = svc->running; t; t = t->next) {
        ATOMIC_STORE(&t->abort_flag, 1);
        if (t->core_token) spdf_render_token_cancel(t->core_token);
    }
    CND_BROADCAST(&svc->wake);
    MTX_UNLOCK(&svc->lock);
    /* svc->workers is only ever written under the lock we just released, and
     * shutdown bars any further request, so reading it here is ordered. */
    for (i = 0; i < svc->worker_count; i++) THR_JOIN(svc->workers[i]);
    /* Single-threaded from here. Everything queued is still delivered, so
     * per-request user_data always has its one release point. */
    MTX_LOCK(&svc->lock);
    while (svc->pending) retire_pending(svc, svc->pending, SPDF_WIN_RENDER_SHUTDOWN);
    MTX_UNLOCK(&svc->lock);
    (void)spdf_win_render_drain(svc, 0);
#ifndef _WIN32
    pthread_mutex_destroy(&svc->lock);
    pthread_cond_destroy(&svc->wake);
#endif
    free(svc->path);
    free(svc);
}

/* Everything older stops now: a running render loses its waiters (which aborts
 * it), a queued one never starts. */
unsigned long long spdf_win_render_service_bump_generation(spdf_win_render_service* svc) {
    unsigned long long gen;
    task *t, *next;
    if (!svc) return 0;
    MTX_LOCK(&svc->lock);
    gen = ++svc->generation;
    for (t = svc->running; t; t = t->next)
        while (t->spec.generation != gen && t->waiter_count > 0)
            retire_waiter(svc, t, t->waiter_count - 1, SPDF_WIN_RENDER_SUPERSEDED, NULL);
    for (t = svc->pending; t; t = next) {
        next = t->next;
        if (t->spec.generation != gen) retire_pending(svc, t, SPDF_WIN_RENDER_SUPERSEDED);
    }
    MTX_UNLOCK(&svc->lock);
    return gen;
}

unsigned long long spdf_win_render_request(spdf_win_render_service* svc, const spdf_win_render_spec* spec,
                                           int priority, spdf_win_render_done done, void* user_data) {
    spdf_win_render_key key;
    spdf_win_render_spec assigned;
    unsigned long long token;
    task* t;
    if (!svc || !spec) return 0;
    if (priority < SPDF_WIN_RENDER_VISIBLE) priority = SPDF_WIN_RENDER_VISIBLE;
    if (priority > SPDF_WIN_RENDER_WARM) priority = SPDF_WIN_RENDER_WARM;
    MTX_LOCK(&svc->lock);
    if (svc->shutdown) {
        MTX_UNLOCK(&svc->lock);
        return 0;
    }
    assigned = *spec;
    if (assigned.generation == 0) assigned.generation = svc->generation;
    key = spdf_win_render_key_for(&assigned);
    token = svc->next_token++;
    svc->inflight++;
    t = assigned.generation == svc->generation ? find_open_task(svc, &key, assigned.generation) : NULL;
    if (t) {
        /* Coalesced -- the macOS _queuedRenderOperations behaviour, except the
         * second asker still gets its own callback. */
        if (priority < t->priority) t->priority = priority;
    } else {
        t = (task*)calloc(1, sizeof(*t));
        if (!t) {
            svc->inflight--;
            MTX_UNLOCK(&svc->lock);
            return 0;
        }
        t->key = key;
        t->spec = assigned;
        t->priority = priority;
        t->seq = svc->next_seq++;
        t->core_token = spdf_render_token_new();
        t->next = svc->pending;
        svc->pending = t;
    }
    t->waiters[t->waiter_count].token = token;
    t->waiters[t->waiter_count].done = done;
    t->waiters[t->waiter_count].user_data = user_data;
    t->waiter_count++;
    if (assigned.generation != svc->generation) {
        retire_pending(svc, t, SPDF_WIN_RENDER_SUPERSEDED); /* born stale: still gets its one callback */
    } else {
        /* Threads start only once there is work. */
        while (svc->worker_count < svc->worker_target && THR_START(&svc->workers[svc->worker_count], worker_entry, svc))
            svc->worker_count++;
        CND_BROADCAST(&svc->wake);
    }
    MTX_UNLOCK(&svc->lock);
    return token;
}

void spdf_win_render_cancel(spdf_win_render_service* svc, unsigned long long token) {
    task* t;
    int pass, i;
    if (!svc || token == 0) return;
    MTX_LOCK(&svc->lock);
    for (pass = 0; pass < 2; pass++)
        for (t = pass == 0 ? svc->pending : svc->running; t; t = t->next)
            for (i = 0; i < t->waiter_count; i++) {
                if (t->waiters[i].token != token) continue;
                retire_waiter(svc, t, i, SPDF_WIN_RENDER_CANCELED, NULL);
                if (pass == 0 && t->waiter_count == 0) retire_pending(svc, t, SPDF_WIN_RENDER_CANCELED);
                MTX_UNLOCK(&svc->lock);
                return;
            }
    MTX_UNLOCK(&svc->lock);
}

int spdf_win_render_drain(spdf_win_render_service* svc, int max_items) {
    int delivered = 0;
    if (!svc) return 0;
    while (max_items <= 0 || delivered < max_items) {
        completion* c;
        MTX_LOCK(&svc->lock);
        c = svc->ready_head;
        if (c) {
            svc->ready_head = c->next;
            if (!svc->ready_head) svc->ready_tail = NULL;
            svc->ready_count--;
        }
        MTX_UNLOCK(&svc->lock);
        if (!c) break;
        if (c->done) c->done(&c->result, c->user_data);
        free(c->result.rgba); /* spdf_free_bitmap() minus a pointless memset */
        free(c);
        delivered++;
    }
    return delivered;
}

unsigned long long spdf_win_render_stat(spdf_win_render_service* svc, int which) {
    unsigned long long v;
    if (!svc) return 0;
    MTX_LOCK(&svc->lock);
    v = which == SPDF_WIN_RENDER_STAT_WORKERS        ? (unsigned long long)svc->worker_count
        : which == SPDF_WIN_RENDER_STAT_TASKS_STARTED ? svc->tasks_started
        : which == SPDF_WIN_RENDER_STAT_GENERATION    ? svc->generation
                                                      : (unsigned long long)svc->inflight;
    MTX_UNLOCK(&svc->lock);
    return v;
}
