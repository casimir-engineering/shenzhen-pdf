/* The sidebar, the minimap, and the two split dividers.
 *
 * macOS (ShenzhenPDFMac.mm):
 *
 * SIDEBAR -- kDefaultSidebarWidth 240.0, min 176.0, max 320.0, search-mode min
 * 216.0, max 0.34 of the split view (:72-76, clamps :179-187). VISIBLE BY
 * DEFAULT (:836-838). Top to bottom: an NSSegmentedControl of Chapters (0),
 * Comments (1) and Search (2) -- Search present only while a query is live
 * (:3138-3144, :9603-9615), with segment widths normalised to
 * floor(max(minSeg, (sidebarWidth - 16) / segments)), minSeg 66.0 for three
 * segments and 78.0 for two; then a filter field ("Filter Chapters" / "Filter
 * Comments", hidden and disabled in Search mode); then a headerless
 * SPDFSidebarTableView, rowHeight 25.0, single column width 230.0 (:3149-3213).
 * Comment rows wrap to 3 lines with 5.0 vertical padding (:85-86).
 *
 * MINIMAP -- kDefaultMinimapWidth 126.5 (:71), clamped [72, 260] on read
 * (:1455). VISIBLE BY DEFAULT (:837-840). Background windowBackgroundColor plus
 * a 1 pt separatorColor line at x = 0 (SPDFMacMinimapView.mm:741-744). Strip
 * layout (:308-343): usable width boundsWidth - 18.0, inter-page gap 4.0, top
 * inset 8.0 when scrolled or vertically centred when the strip fits. Scale comes
 * from the MEDIAN page width with any single page capped at 2.5x the median
 * (:113, :139-147). Per page: white fill, then the thumbnail at
 * NSImageInterpolationLow, or a placeholder of grey lines
 * calibratedWhite:0.76 @0.34 (:524-536, :606-607).
 *
 * DIVIDERS -- width 5.0 (:77-78), drawn as windowBackgroundColor with a 1 pt
 * separatorColor line down the CENTRE and a resizeLeftRight cursor
 * (SPDFMacUIHelpers.mm:425-431).
 *
 * STATE OF THIS FILE: draws both panels' surfaces, the dividers exactly as
 * macOS draws them, the sidebar's segmented control and filter field, and the
 * row grid and thumbnail strip as placeholders. It is not yet fed the document's
 * outline or page thumbnails. The geometry is real, so wiring content in is
 * additive and the input router can already hit-test against it.
 */
#include "spdf_win_chrome_paint.h"

#include <math.h>

namespace {

float px(double points, float s) { return spdf_win_chrome_px(points, s); }

void fill_rounded(ID2D1RenderTarget* target, SpdfWinChromeRect r, float radius, ID2D1Brush* fill, ID2D1Brush* stroke,
                  float stroke_w) {
    D2D1_ROUNDED_RECT rr;
    if (spdf_win_chrome_rect_empty(r)) return;
    rr.rect = stroke ? spdf_win_chrome_stroke_rect(r, stroke_w) : spdf_win_chrome_d2d_rect(r);
    rr.radiusX = radius;
    rr.radiusY = radius;
    if (fill) target->FillRoundedRectangle(rr, fill);
    if (stroke) target->DrawRoundedRectangle(rr, stroke, stroke_w, NULL);
}

/* macOS's divider: the window background, with a hairline down the CENTRE
 * rather than at an edge. Reproduced exactly -- an edge line would read as a
 * border on one panel instead of a grabbable seam between two. */
void draw_divider(const SpdfWinChromePaintCtx& ctx, SpdfWinChromeRect d) {
    const SpdfWinChromeTheme* th = ctx.theme;
    float s = ctx.dpi_scale;
    ID2D1SolidColorBrush* fill;
    ID2D1SolidColorBrush* line;
    float hw;

    if (spdf_win_chrome_rect_empty(d)) return;
    fill = spdf_win_chrome_brush(ctx.target, th->divider_fill);
    if (fill) {
        ctx.target->FillRectangle(spdf_win_chrome_d2d_rect(d), fill);
        fill->Release();
    }
    line = spdf_win_chrome_brush(ctx.target, th->separator);
    if (line) {
        hw = spdf_win_chrome_stroke_px(SPDF_WIN_CT_HAIRLINE, s);
        /* Centre the hairline, snapped so it does not straddle two columns. */
        float x = floorf(d.x + (d.w - hw) * 0.5f);
        ctx.target->FillRectangle(D2D1::RectF(x, d.y, x + hw, d.y + d.h), line);
        line->Release();
    }
}

/* The Chapters / Comments / Search segmented control, with macOS's own width
 * normalisation so the segments sit where they sit on the Mac. */
void draw_sidebar_sections(const SpdfWinChromePaintCtx& ctx, SpdfWinChromeRect bar, int segments, int selected) {
    const SpdfWinChromeTheme* th = ctx.theme;
    float s = ctx.dpi_scale;
    float hair = spdf_win_chrome_stroke_px(SPDF_WIN_CT_HAIRLINE, s);
    ID2D1SolidColorBrush* fill = spdf_win_chrome_brush(ctx.target, th->control_fill);
    ID2D1SolidColorBrush* stroke = spdf_win_chrome_brush(ctx.target, th->control_stroke);
    ID2D1SolidColorBrush* sel = spdf_win_chrome_brush(ctx.target, th->accent);
    const wchar_t* titles[3] = {L"Chapters", L"Comments", L"Search"};
    int i;

    fill_rounded(ctx.target, bar, px(4.0, s), fill, stroke, hair);

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

} /* namespace */

void spdf_win_chrome_paint_panels(const SpdfWinChromePaintCtx& ctx) {
    const SpdfWinChromeLayout* l = ctx.layout;
    const SpdfWinChromeModel* m = ctx.model;
    const SpdfWinChromeTheme* th = ctx.theme;
    float s = ctx.dpi_scale > 0.0f ? ctx.dpi_scale : 1.0f;

    if (!l || !m || !th) return;

    /* --- sidebar --------------------------------------------------------- */
    if (!spdf_win_chrome_rect_empty(l->sidebar)) {
        SpdfWinChromeRect side = l->sidebar;
        ID2D1SolidColorBrush* panel = spdf_win_chrome_brush(ctx.target, th->panel);
        float y;
        int segments = m->search_active ? 3 : 2;

        if (panel) {
            ctx.target->FillRectangle(spdf_win_chrome_d2d_rect(side), panel);
            panel->Release();
        }

        y = side.y + px(8.0, s);

        /* Segmented control. macOS normalises the segment width to
         * floor(max(minSeg, (sidebarWidth - 16) / segments)) with minSeg 66 for
         * three and 78 for two, so the control can be WIDER than the panel's
         * inner width on a narrow sidebar; it is clamped here rather than
         * allowed to overhang. */
        {
            double min_seg = (segments == 3) ? 66.0 : 78.0;
            double side_pt = side.w / s;
            double seg_pt = floor((side_pt - 16.0) / (double)segments);
            double want_pt;
            SpdfWinChromeRect bar;
            if (seg_pt < min_seg) seg_pt = min_seg;
            want_pt = seg_pt * (double)segments;
            bar.w = px(want_pt, s);
            if (bar.w > side.w - px(16.0, s)) bar.w = side.w - px(16.0, s);
            bar.x = side.x + px(8.0, s);
            bar.y = y;
            bar.h = px(24.0, s);
            if (bar.w > 0.0f) draw_sidebar_sections(ctx, bar, segments, m->sidebar_section);
            y = bar.y + bar.h + px(8.0, s);
        }

        /* Filter field -- hidden and disabled in Search mode, as on macOS. */
        if (m->sidebar_section != 2) {
            SpdfWinChromeRect f;
            ID2D1SolidColorBrush* fill = spdf_win_chrome_brush(ctx.target, th->field_fill);
            ID2D1SolidColorBrush* stroke = spdf_win_chrome_brush(ctx.target, th->field_stroke);
            float hair = spdf_win_chrome_stroke_px(SPDF_WIN_CT_HAIRLINE, s);
            f.x = side.x + px(8.0, s);
            f.w = side.w - px(16.0, s);
            f.y = y;
            f.h = px(24.0, s);
            fill_rounded(ctx.target, f, px(4.0, s), fill, stroke, hair);
            if (fill) fill->Release();
            if (stroke) stroke->Release();
            {
                SpdfWinChromeRect t = f;
                t.x += px(22.0, s);
                t.w -= px(28.0, s);
                spdf_win_chrome_draw_text(ctx,
                                          m->sidebar_section == 1 ? L"Filter Comments" : L"Filter Chapters", t,
                                          th->field_placeholder, px(SPDF_WIN_CT_FONT_SIZE_LABEL, s),
                                          DWRITE_FONT_WEIGHT_NORMAL, DWRITE_TEXT_ALIGNMENT_LEADING, 0);
            }
            /* The search field's magnifier: a circle and a tail. */
            {
                ID2D1SolidColorBrush* g = spdf_win_chrome_brush(ctx.target, th->field_placeholder);
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
            y = f.y + f.h + px(6.0, s);
        }

        /* Row grid. rowHeight 25.0, headerless. Placeholder bars stand in for
         * chapter titles until the outline is wired in; drawn at the row
         * geometry the real list will use so the panel's rhythm is already
         * right. */
        {
            ID2D1SolidColorBrush* bar = spdf_win_chrome_brush(ctx.target, th->label_secondary);
            float row_h = px(25.0, s);
            float yy = y;
            int n = 0;
            while (yy + row_h < side.y + side.h && n < 64) {
                if (bar) {
                    /* Alternating lengths so the placeholder reads as a list of
                     * titles rather than a texture. */
                    float wfrac = (n % 3 == 0) ? 0.72f : ((n % 3 == 1) ? 0.55f : 0.63f);
                    SpdfWinChromeRect line;
                    line.x = side.x + px(12.0, s);
                    line.w = (side.w - px(24.0, s)) * wfrac;
                    line.h = px(3.0, s);
                    line.y = yy + (row_h - line.h) * 0.5f;
                    /* @0.34, matching the minimap's placeholder alpha so the two
                     * empty states look like the same app. */
                    bar->SetOpacity(0.34f);
                    ctx.target->FillRectangle(spdf_win_chrome_d2d_rect(line), bar);
                    bar->SetOpacity(1.0f);
                }
                yy += row_h;
                ++n;
            }
            if (bar) bar->Release();
        }
    }

    /* --- minimap --------------------------------------------------------- */
    if (!spdf_win_chrome_rect_empty(l->minimap)) {
        SpdfWinChromeRect mm = l->minimap;
        ID2D1SolidColorBrush* panel = spdf_win_chrome_brush(ctx.target, th->panel);
        ID2D1SolidColorBrush* line = spdf_win_chrome_brush(ctx.target, th->separator);
        float usable, gap, page_w, page_h, yy;
        int n = 0;

        if (panel) {
            ctx.target->FillRectangle(spdf_win_chrome_d2d_rect(mm), panel);
            panel->Release();
        }
        /* macOS draws a 1 pt separator at x = 0 of the minimap view. */
        if (line) {
            float hw = spdf_win_chrome_stroke_px(SPDF_WIN_CT_HAIRLINE, s);
            ctx.target->FillRectangle(D2D1::RectF(mm.x, mm.y, mm.x + hw, mm.y + mm.h), line);
            line->Release();
        }

        /* Strip: usable width boundsWidth - 18.0, inter-page gap 4.0, top inset
         * 8.0. Page aspect is A4-ish until real page sizes are fed in; the
         * median-width scaling with its 2.5x cap belongs with that data. */
        usable = mm.w - px(18.0, s);
        gap = px(4.0, s);
        if (usable > 0.0f) {
            page_w = usable;
            page_h = floorf(page_w * 1.414f);
            yy = mm.y + px(8.0, s);
            while (yy < mm.y + mm.h && n < 64) {
                SpdfWinChromeRect p;
                p.x = mm.x + floorf((mm.w - page_w) * 0.5f);
                p.y = yy;
                p.w = page_w;
                p.h = page_h;
                {
                    /* White fill even in dark: a minimap thumbnail is a picture
                     * of the page, and macOS fills white before drawing it. */
                    ID2D1SolidColorBrush* white = spdf_win_chrome_brush(ctx.target, spdf_win_ct_rgb(0xFFFFFFu, 1.0f));
                    if (white) {
                        ctx.target->FillRectangle(spdf_win_chrome_d2d_rect(p), white);
                        white->Release();
                    }
                }
                {
                    /* Placeholder grey lines, calibratedWhite:0.76 @0.34. */
                    ID2D1SolidColorBrush* g =
                        spdf_win_chrome_brush(ctx.target, spdf_win_ct_rgb(0xC2C2C2u, 0.34f));
                    if (g) {
                        float ly = p.y + px(8.0, s);
                        int k = 0;
                        while (ly < p.y + p.h - px(8.0, s) && k < 24) {
                            float w = (k % 4 == 3) ? p.w * 0.45f : p.w * 0.76f;
                            ctx.target->FillRectangle(
                                D2D1::RectF(p.x + px(6.0, s), ly, p.x + px(6.0, s) + w, ly + px(2.0, s)), g);
                            ly += px(6.0, s);
                            ++k;
                        }
                        g->Release();
                    }
                }
                yy += page_h + gap;
                ++n;
            }

            /* Viewport indicator: fill calibrated(0.18, 0.55, 0.92, 0.18) at
             * radius 4, stroke controlAccentColor lineWidth 1.2, clipped to
             * NSInsetRect(bounds, 1, 1) (:776-786). Shown over the first page
             * until real scroll state is fed in. */
            {
                SpdfWinChromeRect vp;
                ID2D1SolidColorBrush* fill =
                    spdf_win_chrome_brush(ctx.target, spdf_win_ct_rgb(0x2E8CEBu, 0.18f));
                ID2D1SolidColorBrush* stroke = spdf_win_chrome_brush(ctx.target, th->accent);
                vp.x = mm.x + floorf((mm.w - page_w) * 0.5f);
                vp.y = mm.y + px(8.0, s);
                vp.w = page_w;
                vp.h = floorf(page_h * 0.42f);
                fill_rounded(ctx.target, vp, px(4.0, s), fill, stroke, spdf_win_chrome_stroke_px(1.2f, s));
                if (fill) fill->Release();
                if (stroke) stroke->Release();
            }
        }
    }

    /* --- the two dividers, last, so they sit above both panels' edges ---- */
    draw_divider(ctx, l->sidebar_divider);
    draw_divider(ctx, l->minimap_divider);
}
