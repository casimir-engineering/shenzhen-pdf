/* The sidebar: the Chapters/Comments/Search segmented control, the filter
 * field, and the document's real chapter list.
 *
 * macOS (ShenzhenPDFMac.mm) -- every number below is cited, and the ones that
 * are not literals there are marked as such:
 *
 *   - Segmented control of Chapters (0), Comments (1) and Search (2), Search
 *     present only while a query is live (:3138-3144, :9603-9615), segment
 *     widths normalised to floor(max(minSeg, (sidebarWidth - 16) / segments))
 *     with minSeg 66.0 for three segments and 78.0 for two.
 *   - Filter field, "Filter Chapters" / "Filter Comments", hidden and disabled
 *     in Search mode (:3149-3157, :9641).
 *   - A headerless SPDFSidebarTableView, rowHeight 25.0, one column 230.0 wide
 *     (:3149-3213). The cell's text field is inset 8 leading, 6 trailing,
 *     vertically centred, systemFontOfSize:13, single line, truncating TAIL
 *     (:16584-16597, :16620-16624).
 *   - Nesting is level*3 SPACES prepended to the title, level clamped [0,16]
 *     (:16613-16619). Not an indented cell -- an indented string -- so it
 *     survives truncation and selection for free. This port does the same.
 *   - A row whose destination did not resolve is secondaryLabelColor rather
 *     than labelColor (:16623). The core's outline suite has three such cases
 *     (a missing target, an external URL, a dest-less entry), so this is not a
 *     hypothetical branch.
 *   - Selection follows the current page: the FIRST row whose page equals the
 *     current one (:10613-10620).
 *   - Filtering ignores case AND diacritics (:9666-9670) -- see
 *     spdf_win_sidebar_title_matches.
 *
 * NO OUTLINE, AND WHAT macOS ACTUALLY DOES. rebuildSidebar (:9813-9905)
 * computes `hasSidebar = _doc && (hasChapters || hasComments || hasSearch)` and
 * ends with `[self setSidebarActuallyVisible:hasSidebar && _sidebarPreferredVisible]`.
 * So a document with no outline, no comments and no live search does not get an
 * empty list on macOS -- IT GETS NO SIDEBAR. Windows cannot act on that yet:
 * whether the panel exists is decided by SpdfWinChromeModel.show_sidebar, which
 * belongs to another track. So this file draws the honest interim state -- one
 * centred, quiet "No Chapters" line, which is what an empty NSTableView would
 * read as if AppKit drew one -- and the change's report asks for the model bit
 * that lets Windows hide the panel exactly as macOS does. A filter that
 * excludes everything is a DIFFERENT state and says so ("No matching chapters"),
 * because on macOS the panel stays visible then.
 */
#include "spdf_win_chrome_panels.h"

#include <math.h>

namespace {

float px(double points, float s) {
    return spdf_win_chrome_px(points, s);
}

/* The Chapters / Comments / Search segmented control, with macOS's own width
 * normalisation so the segments sit where they sit on the Mac. */
void draw_sections(const SpdfWinChromePaintCtx& ctx, SpdfWinChromeRect bar, int segments, int selected) {
    const SpdfWinChromeTheme* th = ctx.theme;
    float s = ctx.dpi_scale;
    float hair = spdf_win_chrome_stroke_px(SPDF_WIN_CT_HAIRLINE, s);
    ID2D1SolidColorBrush* fill = spdf_win_chrome_brush(ctx.target, th->control_fill);
    ID2D1SolidColorBrush* stroke = spdf_win_chrome_brush(ctx.target, th->control_stroke);
    ID2D1SolidColorBrush* sel = spdf_win_chrome_brush(ctx.target, th->accent);
    const wchar_t* titles[3] = {L"Chapters", L"Comments", L"Search"};
    int i;

    spdf_win_chrome_panel_fill_rounded(ctx.target, bar, px(4.0, s), fill, stroke, hair);

    for (i = 0; i < segments; ++i) {
        SpdfWinChromeRect cell = bar;
        cell.w = bar.w / (float)segments;
        cell.x = bar.x + cell.w * (float)i;
        if (i == selected && sel) {
            D2D1_ROUNDED_RECT rr;
            rr.rect = spdf_win_chrome_d2d_rect(cell);
            rr.radiusX = px(4.0, s);
            rr.radiusY = px(4.0, s);
            ctx.target->FillRoundedRectangle(rr, sel);
        }
        spdf_win_chrome_draw_text(ctx, titles[i], cell,
                                  (i == selected) ? spdf_win_ct_rgb(0xFFFFFFu, 1.0f) : th->label_secondary,
                                  px(SPDF_WIN_CT_FONT_SIZE_LABEL, s), DWRITE_FONT_WEIGHT_NORMAL,
                                  DWRITE_TEXT_ALIGNMENT_CENTER, 0);
        if (i > 0 && stroke && i != selected && (i - 1) != selected) {
            float x = floorf(cell.x) + 0.5f * hair;
            ctx.target->DrawLine(D2D1::Point2F(x, cell.y + hair), D2D1::Point2F(x, cell.y + cell.h - hair), stroke,
                                 hair, NULL);
        }
    }

    if (fill) fill->Release();
    if (stroke) stroke->Release();
    if (sel) sel->Release();
}

/* macOS normalises the segment width to floor(max(minSeg, (sidebarWidth - 16) /
 * segments)), so on a narrow sidebar the control can be WIDER than the panel's
 * inner width. It is clamped here rather than allowed to overhang. */
SpdfWinChromeRect normalised_sections_rect(SpdfWinChromeRect base, SpdfWinChromeRect sidebar, int segments, float s) {
    double min_seg = (segments == 3) ? 66.0 : 78.0;
    double side_pt = sidebar.w / s;
    double seg_pt = floor((side_pt - 16.0) / (double)segments);
    SpdfWinChromeRect bar = base;
    if (seg_pt < min_seg) seg_pt = min_seg;
    bar.w = px(seg_pt * (double)segments, s);
    if (bar.w > sidebar.w - px(16.0, s)) bar.w = sidebar.w - px(16.0, s);
    return bar;
}

void draw_filter_field(const SpdfWinChromePaintCtx& ctx, SpdfWinChromeRect f, int section, const wchar_t* text) {
    const SpdfWinChromeTheme* th = ctx.theme;
    float s = ctx.dpi_scale;
    float hair = spdf_win_chrome_stroke_px(SPDF_WIN_CT_HAIRLINE, s);
    ID2D1SolidColorBrush* fill = spdf_win_chrome_brush(ctx.target, th->field_fill);
    ID2D1SolidColorBrush* stroke = spdf_win_chrome_brush(ctx.target, th->field_stroke);
    int live = text && text[0];

    spdf_win_chrome_panel_fill_rounded(ctx.target, f, px(4.0, s), fill, stroke, hair);
    if (fill) fill->Release();
    if (stroke) stroke->Release();

    {
        SpdfWinChromeRect t = f;
        t.x += px(22.0, s);
        t.w -= px(28.0, s);
        spdf_win_chrome_draw_text(ctx, live ? text : (section == 1 ? L"Filter Comments" : L"Filter Chapters"), t,
                                  live ? th->label : th->field_placeholder, px(SPDF_WIN_CT_FONT_SIZE_LABEL, s),
                                  DWRITE_FONT_WEIGHT_NORMAL, DWRITE_TEXT_ALIGNMENT_LEADING, 0);
    }
    /* The search field's magnifier: a circle and a tail. */
    {
        ID2D1SolidColorBrush* g = spdf_win_chrome_brush(ctx.target, live ? th->label : th->field_placeholder);
        if (g) {
            float cx = f.x + px(12.0, s), cy = f.y + f.h * 0.5f;
            float rad = px(4.0, s);
            float lw = spdf_win_chrome_stroke_px(1.3f, s);
            D2D1_ELLIPSE e;
            e.point.x = cx;
            e.point.y = cy - px(1.0, s);
            e.radiusX = rad;
            e.radiusY = rad;
            ctx.target->DrawEllipse(e, g, lw, NULL);
            ctx.target->DrawLine(D2D1::Point2F(cx + rad * 0.7f, cy + rad * 0.7f - px(1.0, s)),
                                 D2D1::Point2F(cx + rad * 1.6f, cy + rad * 1.6f - px(1.0, s)), g, lw, NULL);
            g->Release();
        }
    }
}

void draw_empty_state(const SpdfWinChromePaintCtx& ctx, SpdfWinChromeRect list, const wchar_t* line) {
    SpdfWinChromeRect r = list;
    float s = ctx.dpi_scale;
    if (spdf_win_chrome_rect_empty(r)) return;
    r.y += px(12.0, s);
    r.h = px(SPDF_WIN_SIDEBAR_ROW_H, s);
    spdf_win_chrome_draw_text(ctx, line, r, ctx.theme->label_secondary, px(SPDF_WIN_CT_FONT_SIZE_LABEL, s),
                              DWRITE_FONT_WEIGHT_NORMAL, DWRITE_TEXT_ALIGNMENT_CENTER, 0);
}

/* The rows. Only the ones that intersect the list viewport are laid out at all,
 * so a 4000-entry outline costs the same per frame as a 20-entry one -- the
 * standing speed rule applied to the one place in this panel that could scale
 * with document size. */
void draw_rows(const SpdfWinChromePaintCtx& ctx, const SpdfWinSidebarLayout& l, const SpdfWinSidebarContent* c) {
    const SpdfWinChromeTheme* th = ctx.theme;
    float s = ctx.dpi_scale;
    int first, last, i;
    ID2D1SolidColorBrush* sel = NULL;
    ID2D1SolidColorBrush* hot = NULL;

    if (l.row_h <= 0.0f || c->row_count <= 0) return;
    first = (int)floorf(c->scroll_y / l.row_h);
    last = (int)ceilf((c->scroll_y + l.list.h) / l.row_h);
    if (first < 0) first = 0;
    if (last > c->row_count - 1) last = c->row_count - 1;

    ctx.target->PushAxisAlignedClip(spdf_win_chrome_d2d_rect(l.list), D2D1_ANTIALIAS_MODE_ALIASED);
    sel = spdf_win_chrome_brush(ctx.target, th->row_selected_fill);
    hot = spdf_win_chrome_brush(ctx.target, th->row_hot_fill);
    for (i = first; i <= last; ++i) {
        SpdfWinChromeRect row = spdf_win_sidebar_row_rect(&l, c->scroll_y, i);
        SpdfWinChromeRect text;
        if (i == c->selected_row && sel)
            ctx.target->FillRectangle(spdf_win_chrome_d2d_rect(row), sel);
        else if (i == c->hot_row && hot)
            ctx.target->FillRectangle(spdf_win_chrome_d2d_rect(row), hot);
        text = row;
        text.x += px(SPDF_WIN_SIDEBAR_CELL_LEADING, s);
        text.w -= px(SPDF_WIN_SIDEBAR_CELL_LEADING, s) + px(SPDF_WIN_SIDEBAR_CELL_TRAILING, s);
        spdf_win_chrome_draw_text(ctx, c->rows[i].title, text,
                                  c->rows[i].page_index >= 0 ? th->label : th->label_secondary,
                                  px(SPDF_WIN_SIDEBAR_FONT_SIZE, s), DWRITE_FONT_WEIGHT_NORMAL,
                                  DWRITE_TEXT_ALIGNMENT_LEADING, 0);
    }
    if (sel) sel->Release();
    if (hot) hot->Release();
    ctx.target->PopAxisAlignedClip();
}

} /* namespace */

void spdf_win_chrome_paint_sidebar(const SpdfWinChromePaintCtx& ctx, const SpdfWinSidebarContent* content) {
    const SpdfWinChromeModel* m = ctx.model;
    SpdfWinChromeRect side = ctx.layout->sidebar;
    float s = ctx.dpi_scale > 0.0f ? ctx.dpi_scale : 1.0f;
    int segments = m->search_active ? 3 : 2;
    SpdfWinSidebarLayout l;
    ID2D1SolidColorBrush* panel;

    if (spdf_win_chrome_rect_empty(side)) return;
    panel = spdf_win_chrome_brush(ctx.target, ctx.theme->panel);
    if (panel) {
        ctx.target->FillRectangle(spdf_win_chrome_d2d_rect(side), panel);
        panel->Release();
    }

    spdf_win_sidebar_layout(side, m->sidebar_section, s, &l);
    {
        SpdfWinChromeRect bar = normalised_sections_rect(l.sections, side, segments, s);
        if (bar.w > 0.0f) draw_sections(ctx, bar, segments, m->sidebar_section);
    }
    if (!spdf_win_chrome_rect_empty(l.filter))
        draw_filter_field(ctx, l.filter, m->sidebar_section, content ? content->filter : NULL);

    /* Chapters is the only section with content on Windows so far. The rows
     * below ARE chapters, so drawing them under the Comments or Search heading
     * would be a lie about what the list is; each of those says what it is
     * instead, and gets its own content when its own track lands. */
    if (m->sidebar_section == 1) {
        draw_empty_state(ctx, l.list, L"No Comments");
        return;
    }
    if (m->sidebar_section == 2) {
        draw_empty_state(ctx, l.list, L"No Results");
        return;
    }

    if (!content || !content->loaded) return; /* nothing known yet; never block */
    if (content->row_count > 0) {
        draw_rows(ctx, l, content);
        return;
    }
    /* The two empty states are genuinely different and macOS treats them
     * differently -- see this file's header. */
    draw_empty_state(ctx, l.list, content->total_count > 0 ? L"No matching chapters" : L"No Chapters");
}
