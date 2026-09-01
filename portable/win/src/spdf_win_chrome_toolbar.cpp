/* The toolbar row.
 *
 * macOS: SPDFToolbarStackView, horizontal, alignment CenterY, spacing 4.0,
 * edgeInsets (7, 6, 7, 6), height pinned to 42.0 (ShenzhenPDFMac.mm:2964-2968,
 * :3293), with 18 arranged subviews left to right (:3105-3122):
 *
 *   1 sidebar toggle ("Side Panel")            10 markdown font-size pill (A- / A+)
 *   2 OCR button (icon, 32)                    11 reading-theme button (single pill, 32)
 *   3 translate button (icon, 32)              12 search field ("Find", 88-141)
 *   4 separator (NSBox, width 1)               13 regex checkbox (68)
 *   5 page field (NSTextField, 50, right)      14 find count label (64)
 *   6 page-count label ("/ N")                 15 find pill (prev / next)
 *   7 page pill (chevron.left / .right)        16 flexible spacer
 *   8 fit-mode popup (96)                      17 overflow "..." (30)
 *   9 zoom pill (minus / plus)                 18 minimap toggle ("Map")
 *
 * Custom spacing 8.0 after the zoom pill, the reading-theme button and the
 * search field. Overflow collapses group by group (:2866-2909):
 *   [ocr, translate, separator], [findCountLabel], [findSegments],
 *   [findRegexCheckbox], [markdownFontSizeSegments, readingThemeButton],
 *   [fitModePopup, zoomSegments]
 *
 * THE PILLS ARE THE VISUAL SIGNATURE. spdf_toolbar_segments()
 * (SPDFMacSupport.mm:325-352) builds every one identically -- NSSegmentedControl,
 * NSSegmentStyleRounded, NSSegmentSwitchTrackingMomentary (no sticky selection),
 * hugging and compression resistance both Required so they are never squeezed --
 * and spdf_single_toolbar_segment() uses the SAME factory deliberately, "so a
 * single-segment control and a paired one share background, height and icon tint
 * exactly" (:324-325). Their radius and height are system-drawn on macOS, so on
 * Windows they are ours to choose; what must be reproduced is the RELATIONSHIP:
 * one rounded capsule, a hairline divider between segments, momentary press
 * feedback, and a lone button that is visibly the same object as half of a pair.
 *
 * STATE OF THIS FILE: lays out and draws the row's surface, the group geometry
 * and the pill/field/label shapes. It is not yet wired to the app's page number,
 * zoom, fit mode or find state, and the icons are drawn as primitives rather
 * than from an icon font. Everything here is geometry the input router can hit
 * test against, so wiring is additive.
 */
#include "spdf_win_chrome_paint.h"

#include <math.h>

namespace {

float px(double points, float s) { return spdf_win_chrome_px(points, s); }

/* macOS's toolbar metrics, transcribed. */
const double kInsetX = 6.0;      /* edgeInsets left/right */
const double kInsetY = 7.0;      /* edgeInsets top/bottom */
const double kSpacing = 4.0;     /* stack view spacing */
const double kWideSpacing = 8.0; /* the three custom gaps */
const double kControlH = 28.0;   /* what a 42 pt row with 7 pt insets leaves */
const double kIconW = 32.0;
const double kPageFieldW = 50.0;
const double kFitPopupW = 96.0;
const double kSearchFieldW = 141.0;
const double kSegmentW = 32.0; /* one half of a pill */

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

/* A capsule of `segments` equal cells with hairline dividers between them. One
 * function for both the paired and the single form, which is the whole point of
 * macOS routing both through spdf_toolbar_segments(). */
void draw_pill(const SpdfWinChromePaintCtx& ctx, SpdfWinChromeRect r, int segments) {
    const SpdfWinChromeTheme* th = ctx.theme;
    float s = ctx.dpi_scale;
    float hair = spdf_win_chrome_stroke_px(SPDF_WIN_CT_HAIRLINE, s);
    ID2D1SolidColorBrush* fill = spdf_win_chrome_brush(ctx.target, th->control_fill);
    ID2D1SolidColorBrush* stroke = spdf_win_chrome_brush(ctx.target, th->control_stroke);
    int i;

    /* Fully rounded: radius half the height makes a capsule, which is what
     * NSSegmentStyleRounded looks like at 28 pt. */
    fill_rounded(ctx.target, r, r.h * 0.5f, fill, stroke, hair);

    if (stroke && segments > 1) {
        for (i = 1; i < segments; ++i) {
            float x = floorf(r.x + r.w * (float)i / (float)segments) + 0.5f * hair;
            ctx.target->DrawLine(D2D1::Point2F(x, r.y + hair), D2D1::Point2F(x, r.y + r.h - hair), stroke, hair, NULL);
        }
    }
    if (fill) fill->Release();
    if (stroke) stroke->Release();
}

/* Chevron, minus, plus and the letter-ish marks are drawn as strokes so they
 * stay crisp at any DPI and need no icon font. */
void draw_chevron(const SpdfWinChromePaintCtx& ctx, SpdfWinChromeRect cell, int pointing_left, ID2D1Brush* brush) {
    float s = ctx.dpi_scale;
    float cx = cell.x + cell.w * 0.5f;
    float cy = cell.y + cell.h * 0.5f;
    float a = px(3.5, s);
    float lw = spdf_win_chrome_stroke_px(1.5f, s);
    float dir = pointing_left ? -1.0f : 1.0f;
    if (!brush) return;
    ctx.target->DrawLine(D2D1::Point2F(cx - dir * a * 0.5f, cy - a), D2D1::Point2F(cx + dir * a * 0.5f, cy), brush, lw,
                         NULL);
    ctx.target->DrawLine(D2D1::Point2F(cx + dir * a * 0.5f, cy), D2D1::Point2F(cx - dir * a * 0.5f, cy + a), brush, lw,
                         NULL);
}

void draw_plus_minus(const SpdfWinChromePaintCtx& ctx, SpdfWinChromeRect cell, int plus, ID2D1Brush* brush) {
    float s = ctx.dpi_scale;
    float cx = cell.x + cell.w * 0.5f;
    float cy = cell.y + cell.h * 0.5f;
    float a = px(5.0, s);
    float lw = spdf_win_chrome_stroke_px(1.5f, s);
    if (!brush) return;
    ctx.target->DrawLine(D2D1::Point2F(cx - a, cy), D2D1::Point2F(cx + a, cy), brush, lw, NULL);
    if (plus) ctx.target->DrawLine(D2D1::Point2F(cx, cy - a), D2D1::Point2F(cx, cy + a), brush, lw, NULL);
}

SpdfWinChromeRect cell_of(SpdfWinChromeRect pill, int index, int segments) {
    SpdfWinChromeRect c = pill;
    c.w = pill.w / (float)segments;
    c.x = pill.x + c.w * (float)index;
    return c;
}

/* A text field: rounded, filled, hairline outline, with a Windows 11-ish
 * 4 pt corner rather than a capsule, so it reads as editable. */
void draw_field(const SpdfWinChromePaintCtx& ctx, SpdfWinChromeRect r, const wchar_t* text, int placeholder,
                DWRITE_TEXT_ALIGNMENT align) {
    const SpdfWinChromeTheme* th = ctx.theme;
    float s = ctx.dpi_scale;
    float hair = spdf_win_chrome_stroke_px(SPDF_WIN_CT_HAIRLINE, s);
    ID2D1SolidColorBrush* fill = spdf_win_chrome_brush(ctx.target, th->field_fill);
    ID2D1SolidColorBrush* stroke = spdf_win_chrome_brush(ctx.target, th->field_stroke);
    SpdfWinChromeRect text_rect = r;

    fill_rounded(ctx.target, r, px(4.0, s), fill, stroke, hair);
    if (fill) fill->Release();
    if (stroke) stroke->Release();

    text_rect.x += px(6.0, s);
    text_rect.w -= px(12.0, s);
    spdf_win_chrome_draw_text(ctx, text, text_rect, placeholder ? th->field_placeholder : th->label,
                              px(SPDF_WIN_CT_FONT_SIZE_FIELD, s), DWRITE_FONT_WEIGHT_NORMAL, align, 0);
}

/* The "Side Panel" / "Map" toggles. macOS custom-draws these
 * (SPDFToolbarToggleButton, SPDFMacUIHelpers.mm:144-246), so its numbers
 * transfer directly: intrinsic width titleWidth + 50.0, height 28.0, title at
 * systemFontOfSize:12 Light, switch track 32.0 x 18.0 anchored 5 pt from maxX,
 * fully rounded, knob 14.0 inset 2 pt. */
void draw_toggle(const SpdfWinChromePaintCtx& ctx, SpdfWinChromeRect r, const wchar_t* title, int on) {
    const SpdfWinChromeTheme* th = ctx.theme;
    float s = ctx.dpi_scale;
    float hair = spdf_win_chrome_stroke_px(SPDF_WIN_CT_HAIRLINE, s);
    SpdfWinChromeRect track, knob, label;

    track.w = px(32.0, s);
    track.h = px(18.0, s);
    track.x = r.x + r.w - px(5.0, s) - track.w;
    track.y = r.y + (r.h - track.h) * 0.5f;

    label = r;
    label.w = track.x - r.x - px(4.0, s);
    spdf_win_chrome_draw_text(ctx, title, label, th->label, px(SPDF_WIN_CT_FONT_SIZE_LABEL, s),
                              DWRITE_FONT_WEIGHT_NORMAL, DWRITE_TEXT_ALIGNMENT_LEADING, 0);

    {
        ID2D1SolidColorBrush* tf =
            spdf_win_chrome_brush(ctx.target, on ? th->accent : th->control_fill_pressed);
        ID2D1SolidColorBrush* ts = spdf_win_chrome_brush(ctx.target, th->control_stroke);
        fill_rounded(ctx.target, track, track.h * 0.5f, tf, ts, hair);
        if (tf) tf->Release();
        if (ts) ts->Release();
    }

    knob.w = px(14.0, s);
    knob.h = knob.w;
    knob.y = track.y + (track.h - knob.h) * 0.5f;
    knob.x = on ? (track.x + track.w - knob.w - px(2.0, s)) : (track.x + px(2.0, s));
    {
        /* macOS: fill calibratedWhite:0.14 when on, white @0.96 when off -- a
         * DARK knob on a light track, which is the opposite of the Windows
         * convention. Windows' own switch keeps the knob light on an accent
         * track, so that is what is used here; the toggle's meaning is carried
         * by the track colour either way. */
        SpdfWinChromeColor c = on ? spdf_win_ct_rgb(0xFFFFFFu, 1.0f) : ctx.theme->label_secondary;
        ID2D1SolidColorBrush* kb = spdf_win_chrome_brush(ctx.target, c);
        D2D1_ELLIPSE e;
        e.point.x = knob.x + knob.w * 0.5f;
        e.point.y = knob.y + knob.h * 0.5f;
        e.radiusX = knob.w * 0.5f;
        e.radiusY = knob.h * 0.5f;
        if (kb) {
            ctx.target->FillEllipse(e, kb);
            kb->Release();
        }
    }
}

} /* namespace */

void spdf_win_chrome_paint_toolbar(const SpdfWinChromePaintCtx& ctx) {
    const SpdfWinChromeLayout* l = ctx.layout;
    const SpdfWinChromeTheme* th = ctx.theme;
    SpdfWinChromeRect bar;
    float s = ctx.dpi_scale > 0.0f ? ctx.dpi_scale : 1.0f;
    float x, y, h, right;
    ID2D1SolidColorBrush* band = NULL;
    ID2D1SolidColorBrush* glyph = NULL;

    if (!l || !th || !ctx.model) return;
    bar = l->toolbar;
    if (spdf_win_chrome_rect_empty(bar)) return;

    band = spdf_win_chrome_brush(ctx.target, th->band);
    if (band) {
        ctx.target->FillRectangle(spdf_win_chrome_d2d_rect(bar), band);
        band->Release();
    }
    glyph = spdf_win_chrome_brush(ctx.target, th->control_glyph);

    y = bar.y + px(kInsetY, s);
    h = px(kControlH, s);
    x = bar.x + px(kInsetX, s);
    right = bar.x + bar.w - px(kInsetX, s);

    /* 1. Side Panel toggle. Width is macOS's titleWidth + 50, approximated with
     * a measured-free constant so the row does not need a text metric pass
     * before it can lay itself out. */
    {
        SpdfWinChromeRect r;
        r.x = x;
        r.y = y;
        r.w = px(112.0, s);
        r.h = h;
        draw_toggle(ctx, r, L"Side Panel", ctx.model->show_sidebar);
        x = r.x + r.w + px(kSpacing, s);
    }

    /* 2-3. OCR and translate, icon buttons 32 wide. Drawn as capsule singles so
     * they match half a pill, per the shared-factory rule. */
    {
        int i;
        for (i = 0; i < 2; ++i) {
            SpdfWinChromeRect r;
            r.x = x;
            r.y = y;
            r.w = px(kIconW, s);
            r.h = h;
            draw_pill(ctx, r, 1);
            /* Placeholder marks: a document-ish box for OCR, two bars for
             * translate. Replaced when an icon source lands. */
            if (glyph) {
                float cx = r.x + r.w * 0.5f, cy = r.y + r.h * 0.5f;
                float a = px(4.0, s);
                float lw = spdf_win_chrome_stroke_px(1.4f, s);
                if (i == 0) {
                    ctx.target->DrawRectangle(D2D1::RectF(cx - a, cy - a, cx + a, cy + a), glyph, lw, NULL);
                } else {
                    ctx.target->DrawLine(D2D1::Point2F(cx - a, cy - a * 0.5f), D2D1::Point2F(cx + a, cy - a * 0.5f),
                                         glyph, lw, NULL);
                    ctx.target->DrawLine(D2D1::Point2F(cx - a, cy + a * 0.5f), D2D1::Point2F(cx + a, cy + a * 0.5f),
                                         glyph, lw, NULL);
                }
            }
            x = r.x + r.w + px(kSpacing, s);
        }
    }

    /* 4. Separator: an NSBox of width 1, full control height. */
    {
        ID2D1SolidColorBrush* sep = spdf_win_chrome_brush(ctx.target, th->separator);
        if (sep) {
            float w = spdf_win_chrome_stroke_px(SPDF_WIN_CT_HAIRLINE, s);
            ctx.target->FillRectangle(D2D1::RectF(x, y + px(4.0, s), x + w, y + h - px(4.0, s)), sep);
            sep->Release();
        }
        x += px(1.0, s) + px(kSpacing, s);
    }

    /* 5-6. Page field and "/ N". */
    {
        SpdfWinChromeRect r;
        r.x = x;
        r.y = y;
        r.w = px(kPageFieldW, s);
        r.h = h;
        draw_field(ctx, r, L"1", 0, DWRITE_TEXT_ALIGNMENT_TRAILING);
        x = r.x + r.w + px(kSpacing, s);

        r.x = x;
        r.w = px(44.0, s);
        spdf_win_chrome_draw_text(ctx, L"/ 1", r, th->label_secondary, px(SPDF_WIN_CT_FONT_SIZE_FIELD, s),
                                  DWRITE_FONT_WEIGHT_NORMAL, DWRITE_TEXT_ALIGNMENT_LEADING, 0);
        x = r.x + r.w + px(kSpacing, s);
    }

    /* 7. Page pill: chevron.left / chevron.right. */
    {
        SpdfWinChromeRect r;
        r.x = x;
        r.y = y;
        r.w = px(kSegmentW * 2.0, s);
        r.h = h;
        draw_pill(ctx, r, 2);
        draw_chevron(ctx, cell_of(r, 0, 2), 1, glyph);
        draw_chevron(ctx, cell_of(r, 1, 2), 0, glyph);
        x = r.x + r.w + px(kSpacing, s);
    }

    /* 8. Fit-mode popup. */
    {
        SpdfWinChromeRect r;
        r.x = x;
        r.y = y;
        r.w = px(kFitPopupW, s);
        r.h = h;
        draw_pill(ctx, r, 1);
        {
            SpdfWinChromeRect t = r;
            t.x += px(8.0, s);
            t.w -= px(24.0, s);
            spdf_win_chrome_draw_text(ctx, L"Fit Width", t, th->label, px(SPDF_WIN_CT_FONT_SIZE_LABEL, s),
                                      DWRITE_FONT_WEIGHT_NORMAL, DWRITE_TEXT_ALIGNMENT_LEADING, 0);
        }
        /* The popup's disclosure chevron, pointing down. */
        if (glyph) {
            float cx = r.x + r.w - px(11.0, s);
            float cy = r.y + r.h * 0.5f;
            float a = px(3.0, s);
            float lw = spdf_win_chrome_stroke_px(1.4f, s);
            ctx.target->DrawLine(D2D1::Point2F(cx - a, cy - a * 0.5f), D2D1::Point2F(cx, cy + a * 0.5f), glyph, lw,
                                 NULL);
            ctx.target->DrawLine(D2D1::Point2F(cx, cy + a * 0.5f), D2D1::Point2F(cx + a, cy - a * 0.5f), glyph, lw,
                                 NULL);
        }
        x = r.x + r.w + px(kSpacing, s);
    }

    /* 9. Zoom pill: minus / plus, then a wide gap. */
    {
        SpdfWinChromeRect r;
        r.x = x;
        r.y = y;
        r.w = px(kSegmentW * 2.0, s);
        r.h = h;
        draw_pill(ctx, r, 2);
        draw_plus_minus(ctx, cell_of(r, 0, 2), 0, glyph);
        draw_plus_minus(ctx, cell_of(r, 1, 2), 1, glyph);
        x = r.x + r.w + px(kWideSpacing, s);
    }

    /* 11. Reading-theme button: a SINGLE-segment pill, 32 wide -- deliberately
     * the same object as half of a pair. moon.stars in light, sun.max in dark. */
    {
        SpdfWinChromeRect r;
        r.x = x;
        r.y = y;
        r.w = px(kIconW, s);
        r.h = h;
        draw_pill(ctx, r, 1);
        if (glyph) {
            float cx = r.x + r.w * 0.5f, cy = r.y + r.h * 0.5f;
            float rad = px(5.0, s);
            float lw = spdf_win_chrome_stroke_px(1.4f, s);
            D2D1_ELLIPSE e;
            e.point.x = cx;
            e.point.y = cy;
            e.radiusX = rad;
            e.radiusY = rad;
            ctx.target->DrawEllipse(e, glyph, lw, NULL);
            if (ctx.model->dark) {
                /* sun: four short rays */
                float o = rad + px(3.0, s);
                ctx.target->DrawLine(D2D1::Point2F(cx - o, cy), D2D1::Point2F(cx - rad - px(1.0, s), cy), glyph, lw,
                                     NULL);
                ctx.target->DrawLine(D2D1::Point2F(cx + rad + px(1.0, s), cy), D2D1::Point2F(cx + o, cy), glyph, lw,
                                     NULL);
                ctx.target->DrawLine(D2D1::Point2F(cx, cy - o), D2D1::Point2F(cx, cy - rad - px(1.0, s)), glyph, lw,
                                     NULL);
                ctx.target->DrawLine(D2D1::Point2F(cx, cy + rad + px(1.0, s)), D2D1::Point2F(cx, cy + o), glyph, lw,
                                     NULL);
            } else {
                /* moon: bite the circle with a band-coloured disc */
                ID2D1SolidColorBrush* band2 = spdf_win_chrome_brush(ctx.target, th->control_fill);
                if (band2) {
                    D2D1_ELLIPSE bite;
                    bite.point.x = cx + rad * 0.55f;
                    bite.point.y = cy - rad * 0.45f;
                    bite.radiusX = rad * 0.95f;
                    bite.radiusY = rad * 0.95f;
                    ctx.target->FillEllipse(bite, band2);
                    band2->Release();
                }
            }
        }
        x = r.x + r.w + px(kWideSpacing, s);
    }

    /* 18. Minimap toggle, from the trailing edge. 17. Overflow next to it. */
    {
        SpdfWinChromeRect r;
        r.w = px(74.0, s);
        r.h = h;
        r.x = right - r.w;
        r.y = y;
        draw_toggle(ctx, r, L"Map", ctx.model->show_minimap);
        right = r.x - px(kSpacing, s);

        r.w = px(30.0, s);
        r.x = right - r.w;
        draw_pill(ctx, r, 1);
        if (glyph) {
            float d = px(3.0, s);
            float gap = px(3.0, s);
            float total = 3.0f * d + 2.0f * gap;
            float gx = r.x + (r.w - total) * 0.5f;
            float gy = r.y + (r.h - d) * 0.5f;
            int i;
            for (i = 0; i < 3; ++i) {
                D2D1_ELLIPSE e;
                e.point.x = gx + (float)i * (d + gap) + d * 0.5f;
                e.point.y = gy + d * 0.5f;
                e.radiusX = d * 0.5f;
                e.radiusY = d * 0.5f;
                ctx.target->FillEllipse(e, glyph);
            }
        }
        right = r.x - px(kSpacing, s);
    }

    /* 12-15. Find field, then the regex checkbox and the find pill, laid out
     * from the trailing side so the flexible spacer sits between them and the
     * zoom pill exactly as the stack view puts it. Drawn only when there is room,
     * which is this row's stand-in for macOS's group-by-group overflow. */
    if (right - x > px(kSearchFieldW + 2.0 * kSegmentW + 3.0 * kSpacing, s)) {
        SpdfWinChromeRect r;
        r.w = px(kSegmentW * 2.0, s);
        r.h = h;
        r.x = right - r.w;
        r.y = y;
        draw_pill(ctx, r, 2);
        draw_chevron(ctx, cell_of(r, 0, 2), 1, glyph);
        draw_chevron(ctx, cell_of(r, 1, 2), 0, glyph);
        right = r.x - px(kSpacing, s);

        r.w = px(kSearchFieldW, s);
        r.x = right - r.w;
        draw_field(ctx, r, L"Find", 1, DWRITE_TEXT_ALIGNMENT_LEADING);
    }

    if (glyph) glyph->Release();

    /* Hairline under the toolbar: the boundary between chrome and document. */
    {
        ID2D1SolidColorBrush* sep = spdf_win_chrome_brush(ctx.target, th->separator);
        if (sep) {
            float hw = spdf_win_chrome_stroke_px(SPDF_WIN_CT_HAIRLINE, s);
            ctx.target->FillRectangle(D2D1::RectF(bar.x, bar.y + bar.h - hw, bar.x + bar.w, bar.y + bar.h), sep);
            sep->Release();
        }
    }
}
