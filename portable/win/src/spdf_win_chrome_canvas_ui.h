#pragma once

/* spdf_win_chrome_canvas_ui.h -- what the POINTER does over the document:
 * select text, follow a link, or pan.
 *
 * Split out of spdf_win_chrome_actions.h for the reason
 * tools/file-size-limits.md gives, and along a real seam: the file next door
 * routes a point to a CONTROL, and this one is what happens once the answer is
 * "no control, this is the page". It is the shell half of the six calls
 * spdf_win_canvas.h declares under "text selection and links"; the canvas owns
 * every one of the hard questions (which glyphs, which word, which link) and
 * this file owns only the gesture and the Win32 consequences of it.
 *
 * Header-only and included from spdf_win_main.cpp after `struct app` and before
 * spdf_win_chrome_actions.h, which calls into it. Same arrangement as
 * spdf_win_chrome_tabs_ui.h beside it.
 *
 * ---------------------------------------------------------------------------
 * WHICH GESTURE A LEFT DRAG IS, AND WHY IT IS DECIDED AT THE PRESS
 *
 * This port has had left-drag-to-pan since Phase 1, and the selection track now
 * needs left-drag-to-select. They are the same gesture and cannot both own it,
 * so the press decides, ONCE, from what is under the pointer:
 *
 *   over text or a link  ->  SELECT (or follow, on a click with no movement)
 *   anywhere else        ->  PAN, exactly as before
 *
 * That is what every PDF reader on both platforms does, and it is the only split
 * that keeps drag-to-pan real: a page at fit-width has margins and whitespace
 * everywhere, so there is always somewhere to grab. MIDDLE-drag pans
 * unconditionally and is untouched, which leaves a way to pan from anywhere at
 * all, including from the middle of a paragraph.
 *
 * Decided at the PRESS and not per move, because a gesture that changed its mind
 * halfway -- panning until the pointer crossed a word, then selecting -- would be
 * unusable, and because the decision costs a structured-text pass that must not
 * be paid on every pixel of pointer travel.
 */

/* IS THERE TEXT (OR A LINK) HERE? The canvas answers in cursor terms, which is
 * exactly the question being asked: an I-beam means selectable text, a hand
 * means a link, and an arrow means neither. Reusing the cursor query rather than
 * adding a second predicate is what keeps the CURSOR the reader sees and the
 * GESTURE they get from pressing there in agreement -- the same rule
 * spdf_win_chrome.h states for hit-testing and painting. */
static int canvas_point_is_selectable(app* a, float canvas_x, float canvas_y) {
    spdf_win_canvas_cursor c;
    if (!a->canvas) return 0;
    c = spdf_win_canvas_cursor_at(a->canvas, canvas_x, canvas_y, 1);
    return c == SPDF_WIN_CANVAS_CURSOR_TEXT || c == SPDF_WIN_CANVAS_CURSOR_HAND;
}

/* OVER THE PAGE, THE DOCUMENT DECIDES WHICH CURSOR.
 *
 * The router answers SPDF_WIN_CC_ARROW for the whole canvas because it knows
 * nothing about documents; an I-beam over text and a hand over a link are things
 * only the canvas can see, so its answer overwrites the router's. Asked with the
 * SAME canvas-local point canvas_press() would use, so what the cursor promises
 * and what a press then does cannot disagree. */
static void canvas_cursor_override(app* a, spdf_win_input* in, const SpdfWinChromeLayout* l) {
    if (!a->canvas) return;
    switch (spdf_win_canvas_cursor_at(a->canvas, spdf_win_chrome_input_canvas_x(l, in->x),
                                      spdf_win_chrome_input_canvas_y(l, in->y), 1)) {
        case SPDF_WIN_CANVAS_CURSOR_TEXT: in->cursor = SPDF_WIN_CC_IBEAM; break;
        case SPDF_WIN_CANVAS_CURSOR_HAND: in->cursor = SPDF_WIN_CC_HAND; break;
        default: break;
    }
}

/* THE SHELL'S HALF OF A LINK.
 *
 * spdf_win_canvas.h is explicit that an INTERNAL target has already been
 * scrolled to and that a URI is deliberately NOT opened by the canvas, because
 * "launching a browser is a shell decision with a shell's security questions".
 * Here are the answers to those questions.
 *
 * ONLY http, https and mailto ARE LAUNCHED. A URI in a PDF is untrusted input
 * from a file the reader may have been sent, and ShellExecuteW will happily
 * launch anything the shell has a handler for -- file:, ms-msdt:, a UNC path, a
 * registered custom scheme belonging to some other installed application. A
 * reader clicking a footnote in a document has not consented to any of that. The
 * three schemes below are the ones a document link plausibly means and the ones
 * whose handler is a browser or a mail client; everything else is ignored
 * silently rather than opened or reported, because a dialog about a link is
 * itself a thing a hostile document could make appear.
 *
 * Case-insensitively, because a scheme is case-insensitive (RFC 3986 3.1) and
 * "HTTPS://" is a link, not an attack. */
static int canvas_scheme_is_safe(const char* uri) {
    static const char* allowed[] = {"http://", "https://", "mailto:"};
    size_t i;
    if (!uri) return 0;
    for (i = 0; i < sizeof(allowed) / sizeof(allowed[0]); ++i)
        if (_strnicmp(uri, allowed[i], strlen(allowed[i])) == 0) return 1;
    return 0;
}

static void canvas_open_uri(app* a, const char* utf8_uri) {
    wchar_t wide[2048];
    if (!canvas_scheme_is_safe(utf8_uri)) return;
    /* MB_ERR_INVALID_CHARS: a malformed URI is not opened at all rather than
     * opened with U+FFFD substituted into it, which would be a different URI
     * from the one the document contained. */
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8_uri, -1, wide,
                            (int)(sizeof(wide) / sizeof(wide[0]))) <= 0)
        return;
    ShellExecuteW(a->window ? (HWND)spdf_win_window_native_handle(a->window) : NULL, L"open", wide, NULL, NULL,
                  SW_SHOWNORMAL);
}

/* A LEFT PRESS ON THE PAGE. Returns 1 when the view changed.
 *
 * Sets a->drag to whichever of the two canvas gestures this is, which is what
 * every later move and the release read. */
static int canvas_press(app* a, const spdf_win_input* in, const SpdfWinChromeLayout* l) {
    float cx = spdf_win_chrome_input_canvas_x(l, in->x);
    float cy = spdf_win_chrome_input_canvas_y(l, in->y);

    if (in->button != SPDF_WIN_CB_LEFT || !canvas_point_is_selectable(a, cx, cy)) {
        a->drag = SPDF_WIN_CA_CANVAS; /* pan, exactly as before */
        return 0;
    }
    a->drag = SPDF_WIN_CA_CANVAS_SELECT;
    /* click_count is the ROUTER's accumulation (spdf_win_window.h): 1 places a
     * caret, 2 selects a word, 3 or more selects the block. A press that
     * reported 0 -- which nothing does -- is still a single click. */
    return spdf_win_canvas_pointer_press(a->canvas, cx, cy, in->click_count ? in->click_count : 1u);
}

static int canvas_drag(app* a, const spdf_win_input* in, const SpdfWinChromeLayout* l) {
    if (!a->canvas) return 0;
    return spdf_win_canvas_pointer_drag(a->canvas, spdf_win_chrome_input_canvas_x(l, in->x),
                                        spdf_win_chrome_input_canvas_y(l, in->y));
}

/* THE RELEASE, WHICH IS ALSO WHERE A LINK IS FOLLOWED.
 *
 * `cancelled` is a button-up whose button is SPDF_WIN_CB_NONE -- the capture was
 * taken away by an Alt+Tab or a system modal, which spdf_win_window.h documents
 * as a CANCELLED drag rather than a release. A cancel must not follow a link:
 * the reader never let go over it. */
static int canvas_release(app* a, int cancelled) {
    spdf_win_canvas_link_nav nav;
    int changed;
    if (!a->canvas) return 0;
    if (cancelled) {
        spdf_win_canvas_pointer_cancel(a->canvas);
        return 0;
    }
    memset(&nav, 0, sizeof(nav));
    changed = spdf_win_canvas_pointer_release(a->canvas, &nav);
    /* INTERNAL has already been scrolled to by the canvas; there is genuinely
     * nothing to do for it, and forwarding it back would scroll twice. */
    if (nav.kind == SPDF_LINK_URI) canvas_open_uri(a, nav.uri);
    else if (nav.kind == SPDF_LINK_INTERNAL) changed = 1;
    return changed;
}
