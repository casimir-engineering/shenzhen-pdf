#pragma once

/* spdf_win_chrome_toolbar_route.h -- what a mouse event over the TOOLBAR means:
 * which of the row's eighteen controls, and for a pill which half.
 *
 * The toolbar case of spdf_win_chrome_input_route(), extracted when the
 * Markdown A−/A＋ pill took the router past the repo's 500-line cap
 * (tools/file-size-limits.md asks for a file, not a raised cap) -- the same
 * move, for the same reason, as spdf_win_sidebar_input.h beside it, and
 * included from the same place: spdf_win_chrome_input.h only, after the action
 * enum and the hit struct this fills are complete.
 *
 * Same rules as its caller: pure, header-only, no app state, and the row's
 * geometry comes from spdf_win_toolbar_layout() -- the function the painter
 * draws with, called here with the SAME model field -- so a click lands on what
 * was drawn. That last clause is the whole reason this file is not allowed to
 * decide anything about the row for itself: `m->markdown` adds a 64 pt pill in
 * the middle of the toolbar, and a router that assumed either answer would
 * hit-test every control after the zoom pill in the wrong place on half the
 * documents this app opens.
 */

static SPDF_WIN_CI_INLINE void spdf_win_toolbar_route(const SpdfWinChromeLayout* l, const SpdfWinChromeModel* m,
                                                      float x, float y, int button, float s, SpdfWinChromeHit* out) {
    SpdfWinToolbarLayout tb;
    int segment = 0;
    spdf_win_toolbar_item item;

    if (button != SPDF_WIN_CB_LEFT) return;
    spdf_win_toolbar_layout(l->toolbar, s, m->markdown, &tb);
    item = spdf_win_toolbar_hit(&tb, x, y, &segment);
    switch (item) {
        case SPDF_WIN_TB_SIDEBAR_TOGGLE: out->action = SPDF_WIN_CA_TOGGLE_SIDEBAR; return;
        case SPDF_WIN_TB_MINIMAP_TOGGLE: out->action = SPDF_WIN_CA_TOGGLE_MINIMAP; return;
        case SPDF_WIN_TB_READING_THEME: out->action = SPDF_WIN_CA_TOGGLE_THEME; return;
        case SPDF_WIN_TB_PAGE_PILL:
            /* chevron.left / chevron.right, in that order (:2996-3000). */
            out->action = segment == 0 ? SPDF_WIN_CA_PREV_PAGE : SPDF_WIN_CA_NEXT_PAGE;
            return;
        case SPDF_WIN_TB_ZOOM_PILL:
            /* minus / plus, in that order (:3026-3030). */
            out->action = segment == 0 ? SPDF_WIN_CA_ZOOM_OUT : SPDF_WIN_CA_ZOOM_IN;
            return;
        case SPDF_WIN_TB_MD_TEXT_PILL:
            /* A− / A＋, in that order, and the pill is in the row only on a
             * Markdown tab -- so this arm is unreachable on a PDF rather than
             * inert on one. The caller posts the command, as the two power
             * tools below do. */
            out->action = segment == 0 ? SPDF_WIN_CA_MD_TEXT_SMALLER : SPDF_WIN_CA_MD_TEXT_LARGER;
            return;
        case SPDF_WIN_TB_FIT_POPUP: out->action = SPDF_WIN_CA_CYCLE_FIT; return;
        case SPDF_WIN_TB_OVERFLOW: out->action = SPDF_WIN_CA_APP_MENU; return;
        /* The two power tools. Their handlers belong to another track; the
         * caller posts the command (spdf_win_chrome_field_ui.h
         * chrome_post_command). */
        case SPDF_WIN_TB_OCR: out->action = SPDF_WIN_CA_OCR; return;
        case SPDF_WIN_TB_TRANSLATE: out->action = SPDF_WIN_CA_TRANSLATE_SELECTION; return;
        /* The two text fields and the two find controls. All four were drawn and
         * inert while the query and the page number could only be changed from
         * outside the app. */
        case SPDF_WIN_TB_FIND_FIELD: out->action = SPDF_WIN_CA_FOCUS_FIND; return;
        case SPDF_WIN_TB_PAGE_FIELD: out->action = SPDF_WIN_CA_FOCUS_PAGE; return;
        case SPDF_WIN_TB_FIND_REGEX: out->action = SPDF_WIN_CA_TOGGLE_REGEX; return;
        case SPDF_WIN_TB_FIND_PILL:
            /* chevron.up / chevron.down -- previous match, then next, the order
             * macOS's find segments use (:3073-3079). */
            out->action = segment == 0 ? SPDF_WIN_CA_FIND_PREV : SPDF_WIN_CA_FIND_NEXT;
            return;
        default: return;
    }
}
