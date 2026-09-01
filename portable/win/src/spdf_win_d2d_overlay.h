#pragma once

/* Internal to spdf_win_d2d.cpp -- included by it, not by anyone else.
 *
 * Search highlights and the text selection: marks drawn OVER the pages, inside
 * the canvas clip, after every page and before the chrome. Split out of
 * spdf_win_d2d.cpp to keep that file inside the size ratchet
 * (tools/file-size-limits.md) with room left for the next change, the same move
 * spdf_win_d2d_png.h made.
 *
 * WHY THE COLOURS ARE HERE AND NOT IN THE CHROME THEME. These are
 * theme-independent and hard-coded on macOS, in both canvases, and
 * windows-port-handoff.md sec 3.3 says not to route them through the palette.
 * They are not surfaces; they are marks ON a surface, and the same values have
 * to read over white paper and over a recoloured #1E1E1E page. Chrome, which
 * SHOULD look native, lives in spdf_win_chrome_theme.h instead.
 *
 * Transcribed from portable/mac/SPDFMacDocumentView.mm:467-485 and :11.
 */

static void draw_overlays(ID2D1RenderTarget* target, const spdf_win_scene* scene) {
    if (!scene->overlays || scene->overlay_count <= 0) return;
    float s = scene->dpi_scale > 0.0f ? scene->dpi_scale : 1.0f;
    ID2D1SolidColorBrush* brush = NULL;
    if (SUCCEEDED(target->CreateSolidColorBrush(D2D1::ColorF(0, 0, 0, 1.0f), &brush))) {
        for (int i = 0; i < scene->overlay_count; ++i) {
            const spdf_win_overlay* o = &scene->overlays[i];
            float a = o->alpha > 0.0f ? o->alpha : 1.0f;
            D2D1_RECT_F r = D2D1::RectF(o->x, o->y, o->x + o->w, o->y + o->h);
            if (!(o->w > 0.0f && o->h > 0.0f)) continue;
            switch (o->kind) {
                case SPDF_WIN_OVERLAY_SEARCH_MATCH: {
                    /* calibrated(1.0, 0.84, 0.12, 0.38), radius 2.0 */
                    D2D1_ROUNDED_RECT rr;
                    rr.rect = r;
                    rr.radiusX = 2.0f * s;
                    rr.radiusY = 2.0f * s;
                    brush->SetColor(D2D1::ColorF(1.0f, 0.84f, 0.12f, 0.38f * a));
                    target->FillRoundedRectangle(rr, brush);
                    break;
                }
                case SPDF_WIN_OVERLAY_SEARCH_ACTIVE: {
                    /* stroke calibrated(0.94, 0.03, 0.02, a), inset -2,-2,
                     * lineWidth 1.2. The inset is OUTWARD -- macOS's
                     * NSInsetRect with negative deltas grows the rect -- so
                     * the outline sits just clear of the glyphs rather than
                     * on them. */
                    float grow = 2.0f * s;
                    float lw = 1.2f * s;
                    D2D1_RECT_F ring = D2D1::RectF(r.left - grow, r.top - grow, r.right + grow, r.bottom + grow);
                    brush->SetColor(D2D1::ColorF(0.94f, 0.03f, 0.02f, a));
                    target->DrawRectangle(ring, brush, lw, NULL);
                    break;
                }
                case SPDF_WIN_OVERLAY_SELECTION:
                default:
                    /* calibrated(0.40, 0.62, 0.86, 0.20), square fill --
                     * macOS does not round the PDF selection. */
                    brush->SetColor(D2D1::ColorF(0.40f, 0.62f, 0.86f, 0.20f * a));
                    target->FillRectangle(r, brush);
                    break;
            }
        }
        brush->Release();
    }
}
