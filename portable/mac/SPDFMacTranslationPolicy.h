#pragma once

#import <Foundation/Foundation.h>

// Where the Translate entry points are allowed to act, per tab kind.
//
// SELECTION translation only needs text, so it works on any tab that has a
// selection it may copy — a Markdown tab included, since Markdown has no
// copy-permission concept at all. WHOLE-DOCUMENT translation rewrites a
// rendered PDF in place (translated lines are drawn back at each source line's
// position, page by page, through the mupdf render path), so it stays
// PDF-only: a Markdown tab has no page raster and no per-line geometry to
// write into. That limit is surfaced in the UI as an explicit "select some
// text" message rather than a silently greyed-out button.
typedef struct {
    bool markdownActive;             // the active tab is a Markdown document
    bool pdfDocumentOpen;            // a mupdf document is loaded (PDF/XPS/EPUB/CBZ path)
    bool contentCopyAllowed;         // PDF 'c' permission; always true for Markdown
    bool hasSelection;               // trimmed selected text is non-empty
    bool translationRunning;         // a translation job is in flight
    bool translationInstallRunning;  // the Argos installer panel is running
} spdf_translation_context;

// The Translate toolbar button and its overflow-menu twin. A PDF tab behaves
// exactly as before — enabled whenever a document is open and no translation
// job is running, with a copy-locked PDF explained on click rather than greyed
// out. A Markdown tab is enabled only while a selection exists, since there is
// nothing else Translate could do there. The File-menu item additionally
// requires contentCopyAllowed, which is also unchanged.
bool spdf_translation_command_enabled(spdf_translation_context context);

// The selection-translation panel (toolbar with a selection, context menu,
// Services-style menu item).
bool spdf_translation_selection_enabled(spdf_translation_context context);

// Whole-document translation, the PDF-render-path feature. Copy permission is
// deliberately NOT part of this: a copy-locked PDF still reaches the command
// and gets the explicit "Translation is not allowed" sheet.
bool spdf_translation_whole_document_available(spdf_translation_context context);
