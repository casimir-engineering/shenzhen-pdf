#import <Cocoa/Cocoa.h>

#import "SPDFMacDelegatePrivate.h"

// Deciding whether an ocrmypdf run actually did its job.
//
// "Did any page come back with text?" is not that question. ocrmypdf skips a
// page that carries no raster image --
//   "2 page has no images - skipping all processing on this page to avoid
//    losing detail. Use --force-ocr ... to perform OCR on pages that have
//    vector content."
// -- so a datasheet whose cover is a scan and whose body pages are vector
// comes back with a text layer on page 1 and nothing on pages 2..8. Page 1
// alone satisfied the old check, the run was declared a success, and the user
// found they could not select a word past the cover.
//
// The honest test is per page: any page still without text means the pass was
// partial, and the image pass (--force-ocr) is the one that covers it.

// How many of the document's pages have no extractable text, or -1 if the file
// could not be read. A blank sheet counts as a page without text, which is why
// this arms a single retry and not a loop.
FOUNDATION_EXPORT NSInteger spdf_mac_ocr_pages_without_text(spdf_document* doc);

@interface ShenzhenMacDelegate (SPDFMacOCRValidation)
// Whether `path` has any selectable text at all: 1 yes, 0 no, -1 unreadable.
- (NSInteger)selectableTextStateForPDFAtPath:(NSString*)path errorMessage:(NSString**)errorOut;
// YES when `path` opens but leaves at least one page without text: an OCR run
// that reported success while skipping pages.
- (BOOL)ocrOutputIsPartialAtPath:(NSString*)path;
@end
