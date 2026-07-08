#import <Cocoa/Cocoa.h>

#include "shenzhen_pdf_core.h"

// The Document Properties panel (File > Properties…, also in the document
// context menu). Each present call snapshots the active document's metadata /
// stats synchronously (all cheap core calls) and builds a fresh panel, so the
// panel always reflects the active tab at open time and remembers nothing.
// The document pointer is NOT retained past the present call: the only
// deferred work is the word/character count, which opens its own document
// from workingPath on a background queue and is cancelled when the panel
// closes. Escape and Cmd+W close the panel.
@interface SPDFPropertiesPanelController : NSObject
+ (void)presentForDocument:(spdf_document*)doc
                sourcePath:(NSString*)sourcePath
               workingPath:(NSString*)workingPath
                 pageIndex:(NSInteger)pageIndex
              outlineCount:(NSInteger)outlineCount
           annotationCount:(NSInteger)annotationCount
              parentWindow:(NSWindow*)parentWindow;
@end
