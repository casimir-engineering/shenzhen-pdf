#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#import "SPDFMacCollectionHistoryDetail.h"
#import "SPDFMacCollectionStore.h"
#import "SPDFMacCollectionUsage.h"
#import "SPDFMacCollectionPreviewSearch.h"
#import "SPDFMacCollectionWindowPrivate.h"
#import "SPDFMacCollectionWindowHistory.h"

static int failures;
static void Expect(NSString* label, BOOL result) {
    if (!result) { fprintf(stderr,"FAIL: %s\n",label.UTF8String); failures++; }
}
static BOOL Await(BOOL (^ready)(void)) {
    NSDate* end = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!ready() && end.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    return ready();
}
static void CheckHistoryBounds(NSView* view, NSView* host) {
    if ([view isKindOfClass:NSButton.class] && !view.hidden) {
        NSButton* button=(NSButton*)view;
        if ([button.title hasPrefix:@"Actions"] || [button.title hasPrefix:@"Save a Copy"] ||
            [button.title containsString:@"Back to Documents"]) {
            NSRect rect=[view convertRect:view.bounds toView:host];
            Expect([@"History action fits real minimum manager: " stringByAppendingString:button.title],
                NSContainsRect(NSInsetRect(host.bounds,-1,-1),rect));
        }
    }
    for (NSView* child in view.subviews) CheckHistoryBounds(child,host);
}
static NSData* TwoPages(void) {
    NSMutableData* data=[NSMutableData data];
    CGDataConsumerRef consumer=CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box=CGRectMake(0,0,320,440); CGContextRef context=CGPDFContextCreate(consumer,&box,NULL);
    CGDataConsumerRelease(consumer);
    for (NSString* text in @[@"First orchid café page",@"Second orchid café page"]) {
        CGPDFContextBeginPage(context,NULL);
        NSAttributedString* title=[[NSAttributedString alloc] initWithString:text
            attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:16]}];
        CTLineRef line=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)title);
        CGContextSetTextPosition(context,30,380); CTLineDraw(line,context); CFRelease(line);
        CGPDFContextEndPage(context);
    }
    CGPDFContextClose(context); CGContextRelease(context);
    PDFDocument* pdf=[[PDFDocument alloc] initWithData:data];
    PDFAnnotation* field=[[PDFAnnotation alloc] initWithBounds:NSMakeRect(30,320,180,25)
        forType:PDFAnnotationSubtypeWidget withProperties:nil];
    field.widgetFieldType=PDFAnnotationWidgetSubtypeText; field.widgetStringValue=@"Saved value";
    [[pdf pageAtIndex:0] addAnnotation:field]; return pdf.dataRepresentation;
}
@interface DelayedHistoryStore : SPDFMacCollectionStore
@property(nonatomic,copy) NSString* delayedID;
@property dispatch_semaphore_t entered;
@property dispatch_semaphore_t releaseGate;
@property dispatch_semaphore_t finished;
@end
@implementation DelayedHistoryStore
- (NSURL*)materializeVersionID:(NSString*)version documentID:(NSString*)document error:(NSError**)error {
    BOOL delayed=[document isEqual:self.delayedID];
    if (delayed) {
        dispatch_semaphore_signal(self.entered);
        dispatch_semaphore_wait(self.releaseGate,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC));
    }
    NSURL* result=[super materializeVersionID:version documentID:document error:error];
    if (delayed) dispatch_semaphore_signal(self.finished);
    return result;
}
@end
int main(void) {
    @autoreleasepool {
        NSString* wrapped=@"Prefix café\n  and flowers suffix";
        NSArray* matches=SPDFCollectionPreviewMatchRanges(wrapped,@" cafe and ");
        Expect(@"wrapped PDF matches map to exact original text",matches.count==1 &&
            [[wrapped substringWithRange:[matches.firstObject rangeValue]] isEqual:@"café\n  and"]);
        Expect(@"combining-mark-only search stays bounded",SPDFCollectionPreviewMatchRanges(@"plain text",@"\u0301").count==0);
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSString* sourceDirectory=[@(__FILE__) stringByDeletingLastPathComponent];
        NSString* hostSource=[NSString stringWithContentsOfFile:[sourceDirectory stringByAppendingPathComponent:@"../ShenzhenPDFMac.mm"] encoding:NSUTF8StringEncoding error:nil];
        NSString* captureSource=[NSString stringWithContentsOfFile:[sourceDirectory stringByAppendingPathComponent:@"../SPDFMacCollectionIntegration.mm"] encoding:NSUTF8StringEncoding error:nil];
        NSString* usageSource=[NSString stringWithContentsOfFile:[sourceDirectory stringByAppendingPathComponent:@"../SPDFMacCollectionUsageIntegration.mm"] encoding:NSUTF8StringEncoding error:nil];
        Expect(@"explicit open requests reach the intent ledger",[hostSource containsString:@"[self collectionWillOpenPaths:paths]"]);
        Expect(@"capture receives open counts before cleanup, with exactly-once fallback",
            [captureSource containsString:@"userOpenCount:userOpenCount"] && [captureSource containsString:@"if (!userOpenCountRecorded)"]);
        Expect(@"detached and restored launch paths do not create user-open intents",
            [usageSource containsString:@"_startupDocumentWorkInProgress && (self.detachedTabLaunch || self.restoreWindowID.length)"]);
        NSURL* directory=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
        [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL* root=[directory URLByAppendingPathComponent:@"Collection"];
        SPDFMacCollectionStore* store=[[SPDFMacCollectionStore alloc] initWithRootURL:root];
        SPDFCollectionOpenIntents* intents=[SPDFCollectionOpenIntents new];
        Expect(@"restore/watch success without user intent never counts",![intents consumePath:@"/tmp/a.pdf"]);
        [intents requestPaths:@[@"/tmp/a.pdf",@"/tmp/a.pdf"]];
        Expect(@"explicit successful open counts once",[intents consumePath:@"/tmp/a.pdf"] && ![intents consumePath:@"/tmp/a.pdf"]);
        [intents requestPaths:@[@"/tmp/a.pdf"]]; [intents requestPaths:@[@"/tmp/a.pdf"]];
        Expect(@"separate pending opens both count",[intents consumePath:@"/tmp/a.pdf"]==2 && ![intents consumePath:@"/tmp/a.pdf"]);
        Expect(@"open intent tracking does not create Collection",![NSFileManager.defaultManager fileExistsAtPath:root.path]);
        [store updateSettings:@{@"choice":@"enabled"} error:nil];
        NSURL* source=[directory URLByAppendingPathComponent:@"Orchid.pdf"];
        NSData* original=TwoPages(); [original writeToURL:source atomically:YES];
        NSDictionary* doc=[store capturePath:source.path reason:@"First opened" error:nil];
        NSDictionary* version=[doc[@"versions"] lastObject];
        SPDFMacCollectionHistoryDetailController* history=[[SPDFMacCollectionHistoryDetailController alloc]
            initWithStore:store document:doc version:version page:2 actionTarget:nil];
        history.searchQuery=@" cafe ";
        NSWindow* host=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,820,630)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        host.releasedWhenClosed=NO; host.contentViewController=history;
        [host.contentView layoutSubtreeIfNeeded];
        Expect(@"History lazily loads actual PDF pages",Await(^BOOL{ return history.reader.document.pageCount==2; }));
        Expect(@"saved form widgets are read-only in History",[history.reader.document pageAtIndex:0].annotations.firstObject.readOnly);
        Expect(@"requested matching page survives PDF installation",
            [history.reader.document indexForPage:history.reader.currentPage]==1);
        Expect(@"saved preview trims and folds accents like contextual search",history.reader.highlightedSelections.count==1);
        Expect(@"preview and version table have real viewports",history.reader.bounds.size.width>350 &&
            history.reader.bounds.size.height>180 && history.table.enclosingScrollView.bounds.size.height>300);
        Expect(@"headless construction never orders a window",!host.visible);
        [host setContentSize:NSMakeSize(750,560)]; [host.contentView layoutSubtreeIfNeeded];
        PDFSelection* highlighted=history.reader.highlightedSelections.firstObject;
        PDFPage* highlightedPage=highlighted.pages.firstObject;
        NSRect highlightRect=[history.reader convertRect:[highlighted boundsForPage:highlightedPage] fromPage:highlightedPage];
        Expect(@"resizing keeps selected search match visible",NSIntersectsRect(highlightRect,history.reader.bounds));
        [history.keepButton performClick:nil];
        Expect(@"Keep persists to the store",Await(^BOOL{ return [history.selectedVersion[@"keep"] boolValue]; }));
        Expect(@"Keep effect is described at the accessible control",
            [history.keepButton.accessibilityHelp containsString:@"entire history"] &&
            [history.protection.stringValue containsString:@"entire history"]);
        Expect(@"preview never modifies original bytes",[[NSData dataWithContentsOfURL:source] isEqual:original]);
        NSString* evidence=NSProcessInfo.processInfo.environment[@"SPDF_COLLECTION_HISTORY_EVIDENCE"];
        if (evidence.length) {
            [host.contentView layoutSubtreeIfNeeded];
            NSBitmapImageRep* bitmap=[host.contentView bitmapImageRepForCachingDisplayInRect:host.contentView.bounds];
            [host.contentView cacheDisplayInRect:host.contentView.bounds toBitmapImageRep:bitmap];
            [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:evidence atomically:YES];
        }
        NSURL* markdown=[directory URLByAppendingPathComponent:@"Notes.md"];
        [@"# Older version\nAn orchid in the garden.\n" writeToURL:markdown atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSDictionary* first=[store capturePath:markdown.path reason:@"First opened" error:nil];
        NSString* firstID=[first[@"versions"] lastObject][@"id"];
        [@"# Latest version\nThe orchid now has two flowers.\n" writeToURL:markdown atomically:YES encoding:NSUTF8StringEncoding error:nil];
        // Atomic writes replace the file identity. An observed edit must name
        // the existing document, just as the live watcher does; a generic open
        // deliberately starts a separate history for an unrelated replacement.
        NSDictionary* latest=[store capturePath:markdown.path reason:@"Observed change"
            continuingDocumentID:first[@"id"] error:nil];
        Expect(@"observed Markdown edit retains both versions in one history",
            [latest[@"id"] isEqual:first[@"id"]] && [latest[@"versions"] count]==2);
        SPDFMacCollectionHistoryDetailController* markdownHistory=[[SPDFMacCollectionHistoryDetailController alloc]
            initWithStore:store document:latest version:[latest[@"versions"] lastObject] page:1 actionTarget:nil];
        NSView* view=markdownHistory.view; (void)view;
        Expect(@"Markdown History initially renders the actual latest revision",Await(^BOOL{
            NSString* text=markdownHistory.reader.document.string;
            return markdownHistory.reader.document.pageCount>0 && [text containsString:@"Latest version"] &&
                [text containsString:@"two flowers"] && ![text containsString:@"Older version"];
        }));
        [markdownHistory selectVersionID:firstID];
        Expect(@"selecting older Markdown replaces the actual preview",Await(^BOOL{
            NSString* text=markdownHistory.reader.document.string;
            return [markdownHistory.selectedVersion[@"id"] isEqual:firstID] &&
                [text containsString:@"Older version"] && [text containsString:@"orchid in the garden"] &&
                ![text containsString:@"Latest version"] && ![text containsString:@"two flowers"];
        }));
        SPDFMacCollectionHistoryDetailController* directOlder=[[SPDFMacCollectionHistoryDetailController alloc]
            initWithStore:store document:latest version:[latest[@"versions"] firstObject] page:1 actionTarget:nil];
        NSView* directView=directOlder.view; (void)directView;
        Expect(@"entering History on an older search hit keeps that exact version",Await(^BOOL{
            return [directOlder.selectedVersion[@"id"] isEqual:firstID] &&
                [directOlder.reader.document.string containsString:@"Older version"];
        }));
        Expect(@"History preview does not increment document opens",[[store documentForPath:markdown.path][@"openCount"] integerValue]==0);
        SPDFMacCollectionWindow* manager=[[SPDFMacCollectionWindow alloc] initWithStore:store open:nil];
        [manager.window setFrame:NSMakeRect(0,0,940,560) display:NO];
        [manager showHistoryForDocument:latest version:[latest[@"versions"] lastObject]];
        [manager.window.contentView layoutSubtreeIfNeeded];
        CheckHistoryBounds(manager.historyPane,manager.window.contentView);
        NSEvent* find=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
            modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:manager.window.windowNumber
            context:nil characters:@"f" charactersIgnoringModifiers:@"f" isARepeat:NO keyCode:3];
        Expect(@"Cmd F returns from History to Collection search",[manager.window performKeyEquivalent:find] &&
            [manager.destination isEqual:@"Documents"] && manager.search.currentEditor!=nil);
        Expect(@"History manager remains headless",!manager.window.visible);
        [manager.window close];
        DelayedHistoryStore* delayed=[[DelayedHistoryStore alloc] initWithRootURL:root];
        delayed.delayedID=doc[@"id"]; delayed.entered=dispatch_semaphore_create(0);
        delayed.releaseGate=dispatch_semaphore_create(0); delayed.finished=dispatch_semaphore_create(0);
        SPDFMacCollectionWindow* navigation=[[SPDFMacCollectionWindow alloc] initWithStore:delayed open:nil];
        [navigation showHistoryForDocument:doc version:version];
        Expect(@"older preview entered delayed materialization",
            !dispatch_semaphore_wait(delayed.entered,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC)));
        [navigation showHistoryForDocument:latest version:[latest[@"versions"] lastObject]];
        Expect(@"newer History selection persists first",Await(^BOOL{
            return [delayed.settings[@"managerHistoryDocumentID"] isEqual:latest[@"id"]];
        }));
        dispatch_semaphore_signal(delayed.releaseGate);
        Expect(@"obsolete preview completes safely",
            !dispatch_semaphore_wait(delayed.finished,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC)));
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
        Expect(@"obsolete preview cannot overwrite current History context",
            [delayed.settings[@"managerHistoryDocumentID"] isEqual:latest[@"id"]]);
        [navigation.window close];
        [host close];
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
        [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
        if (!failures) puts("SPDFMacCollectionHistoryDetailTests passed");
    }
    return failures?1:0;
}
