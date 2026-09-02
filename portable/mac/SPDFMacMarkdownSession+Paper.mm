#import "SPDFMacMarkdownSessionPrivate.h"

// The PAPER half of the session: which sheet the document is laid out on.
//
// A Markdown document has no pages of its own — it is text that we choose to
// pour onto A4. So "rotate" here cannot mean what it means for a PDF, where the
// rendered pixels of a fixed page really do turn. It means TURNING THE PAPER:
// the sheet becomes A4 landscape, the printable rect keeps the same four
// margins, and the document re-flows onto wider, shorter pages with every glyph
// still upright and readable.
//
// Because the orientation travels on the pagination plan (via the single
// SPDFMacMarkdownPlanForRendition seam), the screen, print, Save as PDF, Copy
// Page and Copy Page Image paths all follow it without knowing it exists — they
// already read their paper size off plan.configuration.

@implementation SPDFMacMarkdownSession (Paper)

// Mirrors applyThemeVariant: exactly: an active session re-paginates in place
// preserving its viewport, an inactive one adopts the paper and catches up on
// activation (renderTrailsPreferences).
//
// The one difference is the viewport. A font-scale or theme rerender keeps the
// live scroll ORIGIN, because the canvas keeps roughly the same shape. Turning
// the paper re-flows the whole document onto a different number of differently
// shaped pages, so an absolute Y offset points at unrelated content afterwards.
// The top of the viewport is therefore remembered as an attributed LOCATION and
// the install lands on whichever page now holds it (see
// -installRenderedDocument:paginationPlan:interactiveString:preserveCurrentState:).
- (void)applyPageOrientation:(SPDFMarkdownPageOrientation)orientation {
    if (orientation == _pageOrientation) return;
    _pageOrientation = orientation;
    if (!_active || !self.document) return;
    _pendingReanchorLocation = self.visibleAttributedLocation;
    [self rerenderDocumentWithStatus:orientation == SPDFMarkdownPageOrientationLandscape
                                         ? @"Markdown pages are now landscape."
                                         : @"Markdown pages are now portrait."];
}

@end
