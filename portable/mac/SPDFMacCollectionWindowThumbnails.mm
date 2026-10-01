#import "markdown/SPDFTextDocumentFormats.h"
#import "SPDFMacCollectionWindowPrivate.h"
#import "SPDFMacMarkdownPrinting.h"
#import "markdown/SPDFMarkdownDocument.h"
#import "SPDFMacCollectionThumbnail.h"
#import "SPDFMacPassword.h"
#import "SPDFMacCollectionCompanion.h"

@implementation SPDFMacCollectionWindow (Thumbnails)
- (void)initializeThumbnails {
    self.thumbnailCache = [NSCache new]; self.thumbnailCache.totalCostLimit = 24*1024*1024;
    self.pendingThumbnails = [NSMutableSet set];
    self.thumbnailQueue = [NSOperationQueue new]; self.thumbnailQueue.maxConcurrentOperationCount = 1;
    self.thumbnailQueue.qualityOfService = NSQualityOfServiceUtility;
}
- (void)requestThumbnail:(NSDictionary*)row key:(NSString*)key {
    if ([self.thumbnailCache objectForKey:key] || [self.pendingThumbnails containsObject:key]) return;
    [self.pendingThumbnails addObject:key];
    SPDFMacCollectionStore* store = self.store;
    __weak SPDFMacCollectionWindow* weakSelf = self;
    [self.thumbnailQueue addOperationWithBlock:^{
        @autoreleasepool {
            NSDictionary* version = row[@"version"];
            NSError* error = nil;
            NSURL* URL = [store materializeVersionID:version[@"id"] documentID:row[@"document"][@"id"] error:&error];
            NSImage* image = nil;
            if (URL && SPDFIsRenderedTextDocumentPath(URL.path)) {
                SPDFMarkdownDocument* markdown = [SPDFMarkdownDocument documentWithURL:URL options:nil error:&error];
                SPDFMarkdownPageConfiguration* config = markdown.authoredPageConfiguration ?: [SPDFMarkdownPageConfiguration A4PortraitConfiguration];
                SPDFMarkdownPaginationPlan* plan = [markdown paginationPlanForConfiguration:config];
                NSBitmapImageRep* bitmap = [SPDFMacMarkdownPrintAdapter imageRepForPageAtIndex:MIN(MAX(0,[row[@"selectedPage"] integerValue]-1),(NSInteger)plan.pages.count-1) paginationPlan:plan
                    attributedString:markdown.renderedDocument.attributedString scale:MIN(300/config.paperSize.width,300/config.paperSize.height)];
                if (bitmap) { image = [[NSImage alloc] initWithSize:bitmap.size]; [image addRepresentation:bitmap]; }
            } else if (URL && ![URL.pathExtension.lowercaseString isEqual:@"pdf"]) {
                image = SPDFCollectionImageThumbnail(URL,[row[@"selectedPage"] integerValue]);
            } else if (URL) {
                image = SPDFCollectionPDFThumbnail(URL,[row[@"selectedPage"] integerValue],^(PDFDocument* pdf) {
                    // Resolve lazily: standalone Collection UI tests need no core/password runtime.
                    SPDFPasswordCredentialStore* credentials = [NSClassFromString(@"SPDFPasswordCredentialStore") sharedStore];
                    for (NSString* path in @[URL.path,row[@"document"][@"path"] ?: @""]) {
                        SPDFPasswordCredential* credential = [credentials credentialForSourcePath:path];
                        [credential withUTF8Password:^(const char* password) {
                            [pdf unlockWithPassword:[NSString stringWithUTF8String:password]];
                        }];
                        if (!pdf.isLocked) break;
                    }
                    if (pdf.isLocked) {
                        SPDFCollectionCompanionRuntime* runtime=[NSClassFromString(@"SPDFCollectionCompanionRuntime") activeRuntime];
                        SPDFPasswordCredential* credential=[runtime credentialForPaths:@[URL.path,row[@"document"][@"path"] ?: @""]];
                        [credential withUTF8Password:^(const char* password) {
                            [pdf unlockWithPassword:[NSString stringWithUTF8String:password]];
                        }];
                    }
                },&error);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                SPDFMacCollectionWindow* owner = weakSelf;
                if (!owner) return;
                [owner.pendingThumbnails removeObject:key];
                if (image) [owner.thumbnailCache setObject:image forKey:key cost:260*300*4];
                for (NSInteger index = 0; index < (NSInteger)owner.rows.count; index++) {
                    NSView* cell = [owner.table viewAtColumn:0 row:index makeIfNecessary:NO];
                    for (NSView* child in cell.subviews) if ([child isKindOfClass:NSImageView.class] && [child.identifier isEqual:key]) {
                        if (image) ((NSImageView*)child).image = image;
                        else child.toolTip = error.localizedDescription ?: @"Preview unavailable; open the saved copy.";
                    }
                }
            });
        }
    }];
}
@end
