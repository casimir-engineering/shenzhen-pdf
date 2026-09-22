#import "SPDFMacCollectionCompareViews.h"
#import <CoreText/CoreText.h>
#import <objc/runtime.h>
#include <atomic>

@interface SPDFCollectionCompareController : NSWindowController
- (instancetype)initWithOldLabel:(NSString*)oldLabel newLabel:(NSString*)newLabel;
- (void)loadOld:(NSURL*)oldURL new:(NSURL*)newURL;
- (void)nextChange:(id)sender;
@end

static int failures;
static std::atomic<unsigned> serializations(0);
static std::atomic<bool> serializedOnMain(false);
static IMP originalSerialization;
static NSData* CountSerialization(id document, SEL selector) {
    serializations++;
    if (NSThread.isMainThread) serializedOnMain = true;
    return ((NSData* (*)(id,SEL))originalSerialization)(document,selector);
}
static void Expect(NSString* name, BOOL pass) {
    if (!pass) { fprintf(stderr,"FAIL: %s\n",name.UTF8String); failures++; }
}
static void WriteFixture(NSURL* URL, BOOL updated) {
    NSMutableData* data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box = CGRectMake(0,0,420,595);
    CGContextRef context = CGPDFContextCreate(consumer,&box,NULL);
    CGDataConsumerRelease(consumer);
    NSArray* pages = updated ? @[@"Orchid shipment approved",@"New inspection page",@"Stable appendix"]
                             : @[@"Orchid shipment pending",@"Stable appendix"];
    for (NSString* text in pages) {
        CGPDFContextBeginPage(context,NULL);
        CGPDFContextBeginTag(context,CGPDFTagTypeParagraph,NULL);
        NSAttributedString* string = [[NSAttributedString alloc] initWithString:text
            attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:18]}];
        CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)string);
        CGContextSetTextPosition(context,34,500); CTLineDraw(line,context); CFRelease(line);
        CGPDFContextEndTag(context);
        CGPDFContextEndPage(context);
    }
    CGPDFContextClose(context); CGContextRelease(context);
    PDFDocument* document = [[PDFDocument alloc] initWithData:data];
    PDFAnnotation* note = [[PDFAnnotation alloc] initWithBounds:NSMakeRect(20,440,30,30)
        forType:PDFAnnotationSubtypeText withProperties:nil];
    note.contents = @"Original review note";
    [[document pageAtIndex:0] addAnnotation:note];
    [document writeToURL:URL];
}
static void FindPanes(NSView* view, NSMutableArray* panes) {
    if ([view isKindOfClass:SPDFCollectionComparePane.class]) [panes addObject:view];
    for (NSView* child in view.subviews) FindPanes(child,panes);
}
static NSView* FindControl(NSView* view, NSString* label, BOOL button) {
    if (button && [view isKindOfClass:NSButton.class] && [[(NSButton*)view title] isEqual:label]) return view;
    if (!button && [view isKindOfClass:NSTextField.class] &&
        ([view.accessibilityLabel isEqual:label] || [[(NSTextField*)view stringValue] isEqual:label])) return view;
    for (NSView* child in view.subviews) {
        NSView* match = FindControl(child,label,button);
        if (match) return match;
    }
    return nil;
}
static BOOL ShowsPage(SPDFCollectionComparePane* pane, NSString* pair, NSString* source) {
    NSTextField* field = (id)FindControl(pane,@"Comparison page",NO);
    return [field.stringValue isEqual:pair] && FindControl(pane,source,NO) != nil;
}
static void DrainNavigation(void) {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
}
static void CheckNavigation(SPDFCollectionCompareController* controller, NSArray<SPDFCollectionComparePane*>* panes) {
    SPDFCollectionComparePane* old = panes.firstObject;
    SPDFCollectionComparePane* updated = panes.lastObject;
    [controller nextChange:nil]; [controller nextChange:nil];
    Expect(@"next change identifies the inserted counterpart in both panes",
        ShowsPage(old,@"2",@"/ 3 · No counterpart") && ShowsPage(updated,@"2",@"/ 3 · source 2"));
    // PDFKit does not guarantee a page notification for destination jumps.
    // Remove only the pane's observer to exercise that real event omission.
    [NSNotificationCenter.defaultCenter removeObserver:updated name:PDFViewPageChangedNotification object:updated.reader];
    [(NSButton*)FindControl(old,@"›",YES) performClick:nil];
    Expect(@"linked next from inserted page updates pair and both source numbers",
        ShowsPage(old,@"3",@"/ 3 · source 2") && ShowsPage(updated,@"3",@"/ 3 · source 3"));
    DrainNavigation();
    Expect(@"linked counters remain aligned after PDFKit settles",
        ShowsPage(old,@"3",@"/ 3 · source 2") && ShowsPage(updated,@"3",@"/ 3 · source 3"));
    Expect(@"linked readers actually display the stable appendix",
        [old.reader.document indexForPage:old.reader.currentPage] == 2 &&
        [updated.reader.document indexForPage:updated.reader.currentPage] == 2);
    NSButton* linked = (id)FindControl(controller.window.contentView,@"Link scrolling and zoom",YES);
    [linked performClick:nil];
    [(NSButton*)FindControl(updated,@"‹",YES) performClick:nil];
    Expect(@"unlinked previous updates only its own counter without page notifications",
        ShowsPage(old,@"3",@"/ 3 · source 2") && ShowsPage(updated,@"2",@"/ 3 · source 2"));
    [(NSButton*)FindControl(updated,@"›",YES) performClick:nil];
    Expect(@"unlinked next reaches final aligned page with source three",
        ShowsPage(updated,@"3",@"/ 3 · source 3"));
    [updated goToSlot:0];
    PDFPage* last = [updated.reader.document pageAtIndex:2];
    [updated.reader goToDestination:[[PDFDestination alloc] initWithPage:last atPoint:NSMakePoint(0,595)]];
    DrainNavigation();
    Expect(@"scroll observation refreshes counters without page notifications",
        ShowsPage(updated,@"3",@"/ 3 · source 3"));
}
static void WalkAccessibility(id element, NSHashTable* visited, NSUInteger* pages, NSUInteger* textNodes) {
    if (!element || [visited containsObject:element]) return;
    [visited addObject:element];
    NSString* type = NSStringFromClass([element class]);
    if ([type isEqual:@"PDFAccessibilityNodePage"]) (*pages)++;
    if ([type isEqual:@"PDFAccessibilityNodeText"]) (*textNodes)++;
    if ([element respondsToSelector:@selector(accessibilityChildren)]) {
        // This reaches PDFKit's actual tagged page tree, including each blank
        // counterpart. The original crash happened in this children getter.
        for (id child in [element accessibilityChildren]) WalkAccessibility(child,visited,pages,textNodes);
    }
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSURL* root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
        [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL* oldURL = [root URLByAppendingPathComponent:@"old.pdf"];
        NSURL* newURL = [root URLByAppendingPathComponent:@"new.pdf"];
        WriteFixture(oldURL,NO); WriteFixture(newURL,YES);
        NSData* oldBytes = [NSData dataWithContentsOfURL:oldURL];
        NSData* newBytes = [NSData dataWithContentsOfURL:newURL];
        Method method = class_getInstanceMethod(PDFDocument.class,@selector(dataRepresentation));
        originalSerialization = method_setImplementation(method,(IMP)CountSerialization);
        SPDFCollectionCompareController* controller = [[SPDFCollectionCompareController alloc]
            initWithOldLabel:@"Old fixture" newLabel:@"New fixture"];
        [controller.window.contentView layoutSubtreeIfNeeded];
        NSMutableArray<SPDFCollectionComparePane*>* panes = [NSMutableArray array];
        FindPanes(controller.window.contentView,panes);
        Expect(@"constructing empty comparison starts no serialization",serializations == 0);
        Expect(@"comparison has two native readers",panes.count == 2);
        [controller loadOld:oldURL new:newURL];
        NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:15];
        while (!panes.lastObject.reader.document && deadline.timeIntervalSinceNow > 0) {
            @autoreleasepool {
                [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                    beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
            }
        }
        [controller.window.contentView layoutSubtreeIfNeeded];
        Expect(@"comparison serialization runs on its worker",serializations >= 2 && !serializedOnMain);
        for (NSUInteger side = 0; side < panes.count; side++) {
            SPDFCollectionComparePane* pane = panes[side];
            PDFDocument* document = pane.reader.document;
            Expect(@"aligned reader contains all three page pairs",document.pageCount == 3);
            Expect(@"aligned reader owns a durable PDF backing",document.documentRef != NULL);
            for (NSUInteger index = 0; index < document.pageCount; index++) {
                PDFPage* page = [document pageAtIndex:index];
                Expect(@"every page belongs to displayed Core Graphics document",
                    page.pageRef && CGPDFPageGetDocument(page.pageRef) == document.documentRef);
                Expect(@"every page belongs to displayed PDFKit document",page.document == document);
            }
            Expect(@"selectable text survives presentation",[document.string containsString:
                side ? @"Orchid shipment approved" : @"Orchid shipment pending"]);
            Expect(@"search still finds original content",[document findString:@"Stable appendix"
                withOptions:NSCaseInsensitiveSearch].count == 1);
            BOOL note = NO, mark = NO;
            for (PDFAnnotation* annotation in [document pageAtIndex:0].annotations) {
                note |= [annotation.contents isEqual:@"Original review note"];
                mark |= [annotation.contents isEqual:side ? @"Added content" : @"Removed content"];
            }
            Expect(@"original annotations and comparison marks survive",note && mark);
            NSUInteger pageNodes = 0, textNodes = 0;
            for (NSUInteger slot = 0; slot < document.pageCount; slot++) [pane goToSlot:slot];
            WalkAccessibility(pane.reader,[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality],
                &pageNodes,&textNodes);
            Expect(@"native PDF accessibility exposes every aligned page",pageNodes == 3);
            Expect(@"native tagged PDF accessibility retains text children",textNodes >= (side ? 3 : 2));
        }
        CheckNavigation(controller,panes);
        Expect(@"added page receives an explicit empty counterpart",[panes.firstObject.sourcePages isEqual:@[@0,@-1,@1]]);
        Expect(@"comparison never shows a headless window",!controller.window.visible);
        Expect(@"comparison leaves source PDFs unchanged",[oldBytes isEqual:[NSData dataWithContentsOfURL:oldURL]] &&
            [newBytes isEqual:[NSData dataWithContentsOfURL:newURL]]);
        method_setImplementation(method,originalSerialization);
        [controller.window close];
        [NSFileManager.defaultManager removeItemAtURL:root error:nil];
        if (!failures) puts("SPDFMacCollectionComparePresentationTests passed");
    }
    return failures ? 1 : 0;
}
