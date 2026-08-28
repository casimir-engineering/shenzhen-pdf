#import <AppKit/AppKit.h>

#import "../SPDFMacMarkdownSession.h"
#import "../SPDFMacMarkdownPagedView.h"
#import "../markdown/SPDFMarkdown.h"

#include <assert.h>
#include <stdio.h>

static BOOL SpinUntil(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return condition();
}

static NSString* WriteMarkdown(NSString* text) {
    NSString* path = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"md"]];
    assert([text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    return path;
}

@interface SPDFMacMarkdownSession (SPDFMacMarkdownSessionTests)
- (void)applyLanguageIdentifier:(NSString*)identifier toCodeBlock:(NSUInteger)blockIndex;
@end

int main(void) {
    @autoreleasepool {
        (void)NSApplication.sharedApplication;
        NSString* path = WriteMarkdown(@"# Introduction\nAlpha beta alpha.\n\n# Finish\nOmega.\n\n"
                                        "```unknown\nlet value = 1\n```\n");
        NSView* host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 640, 480)];
        dispatch_queue_t sessionQueue = dispatch_queue_create("markdown.session.test", DISPATCH_QUEUE_CONCURRENT);
        SPDFMacMarkdownSession* session =
            [[SPDFMacMarkdownSession alloc] initWithDocumentURL:[NSURL fileURLWithPath:path]];
        NSObject* reader = [NSObject new];
        session.reader = (id<SPDFMacUIReader>)reader;
        assert(session.reader == (id<SPDFMacUIReader>)reader);
        __block BOOL loaded = NO;
        [session activateInHostView:host
                          workQueue:sessionQueue
                       scrollOrigin:NSZeroPoint
                      selectedRange:NSMakeRange(0, 0)
                          pageIndex:0
                               zoom:1.0
                            fitMode:SPDFMacMarkdownPageFitPage
                             anchor:nil
                         completion:^(BOOL success, NSError* error) {
                           assert(success && !error);
                           loaded = YES;
                         }];
        assert(SpinUntil(
            ^BOOL {
              return loaded;
            },
            5.0));
        assert(session.state == SPDFMacMarkdownSessionReady);
        assert(session.pageCount > 0);
        assert([session.renderedDocument.attributedString.string containsString:@"Alpha beta alpha"]);

        __block NSUInteger count = NSNotFound;
        __block NSInteger index = -1;
        session.searchUpdateHandler = ^(NSUInteger resultCount, NSInteger resultIndex, BOOL searching) {
          if (!searching) {
              count = resultCount;
              index = resultIndex;
          }
        };
        [session searchForQuery:@"alpha" preferredIndex:0];
        assert(SpinUntil(
            ^BOOL {
              return count != NSNotFound;
            },
            5.0));
        assert(count == 2 && index == 0);
        [session moveToNextMatch:YES];
        assert(session.currentMatchIndex == 1);
        assert([session scrollToHeadingAnchor:@"finish"]);
        SPDFMacMarkdownPagedView* pagedView = nil;
        for (NSView* view in session.rootView.subviews)
            if ([view isKindOfClass:SPDFMacMarkdownPagedView.class]) pagedView = (id)view;
        assert(pagedView != nil);
        assert(pagedView.reader == session.reader);
        assert(session.visibleAttributedLocation == pagedView.visibleAttributedLocation);
        assert(session.visibleAttributedLocation != NSNotFound);
        NSObject* replacementReader = [NSObject new];
        session.reader = (id<SPDFMacUIReader>)replacementReader;
        assert(pagedView.reader == (id<SPDFMacUIReader>)replacementReader);
        pagedView.selectedRange = NSMakeRange(0, 5);
        assert([session.selectedText isEqualToString:@"Intro"]);

        // A language rerender must not invalidate an overlapping Find. Suspending
        // the shared worker queue makes the overlap deterministic and reproduces
        // the old shared-generation failure every time.
        __block BOOL overlapSearchFinished = NO;
        __block BOOL overlapRenderFinished = NO;
        session.searchUpdateHandler = ^(NSUInteger resultCount, NSInteger resultIndex, BOOL searching) {
          (void)resultIndex;
          if (!searching && resultCount == 2) overlapSearchFinished = YES;
        };
        session.statusHandler = ^(NSString* status) {
          if ([status isEqualToString:@"Code language updated."]) overlapRenderFinished = YES;
        };
        NSUInteger codeBlock = session.document.model.codeFences.firstObject.blockIndex;
        dispatch_suspend(sessionQueue);
        [session searchForQuery:@"alpha" preferredIndex:0];
        [session applyLanguageIdentifier:@"python" toCodeBlock:codeBlock];
        dispatch_resume(sessionQueue);
        assert(SpinUntil(
            ^BOOL {
              return overlapSearchFinished && overlapRenderFinished;
            },
            5.0));
        assert(session.searchMatches.count == 2);

        // Replacing an in-flight search must only publish the latest query.
        __block NSUInteger latestCount = NSNotFound;
        session.searchUpdateHandler = ^(NSUInteger resultCount, NSInteger resultIndex, BOOL searching) {
          (void)resultIndex;
          if (!searching) latestCount = resultCount;
        };
        dispatch_suspend(sessionQueue);
        [session searchForQuery:@"alpha" preferredIndex:0];
        [session searchForQuery:@"omega" preferredIndex:0];
        dispatch_resume(sessionQueue);
        assert(SpinUntil(
            ^BOOL {
              return latestCount == 1;
            },
            5.0));
        assert(session.searchMatches.count == 1);

        // Replacing a queued language render must not let its stale completion
        // overwrite the newer override.
        __block NSUInteger renderCompletions = 0;
        session.statusHandler = ^(NSString* status) {
          if ([status isEqualToString:@"Code language updated."]) renderCompletions++;
        };
        dispatch_suspend(sessionQueue);
        [session applyLanguageIdentifier:@"python" toCodeBlock:codeBlock];
        [session applyLanguageIdentifier:@"swift" toCodeBlock:codeBlock];
        dispatch_resume(sessionQueue);
        assert(SpinUntil(
            ^BOOL {
              return renderCompletions == 1;
            },
            5.0));
        SPDFMarkdownRenderedBlock* renderedCode = [session.renderedDocument renderedBlockWithIndex:codeBlock];
        NSString* language = [session.renderedDocument.attributedString attribute:SPDFMarkdownCodeLanguageAttribute
                                                                          atIndex:renderedCode.attributedRange.location
                                                                   effectiveRange:nil];
        assert([language isEqualToString:@"swift"]);
        SPDFMacMarkdownPagedView* replacedPagedView = nil;
        for (NSView* view in session.rootView.subviews)
            if ([view isKindOfClass:SPDFMacMarkdownPagedView.class]) replacedPagedView = (id)view;
        assert(replacedPagedView != nil && replacedPagedView != pagedView);
        assert(replacedPagedView.reader == session.reader);

        // applyFontScale: rerenders with scaled typography, preserves the
        // current custom zoom, survives a later language rerender, clamps to
        // [0.5, 3.0], and no-ops on an equal value.
        NSRange bodyRange = [session.renderedDocument.attributedString.string rangeOfString:@"Alpha beta alpha"];
        assert(bodyRange.location != NSNotFound);
        NSFont* baseFont = [session.renderedDocument.attributedString attribute:NSFontAttributeName
                                                                        atIndex:bodyRange.location
                                                                 effectiveRange:nil];
        assert(baseFont != nil && session.fontScale == 1.0);
        // Drain the earlier installs' queued viewport restores before adopting
        // a custom zoom so they cannot overwrite it.
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        [session setZoom:1.6];
        assert(session.fitMode == SPDFMacMarkdownPageFitCustom);
        __block NSUInteger fontScaleRenders = 0;
        session.statusHandler = ^(NSString* status) {
          if ([status isEqualToString:@"Markdown text size updated."]) fontScaleRenders++;
        };
        [session applyFontScale:1.5];
        assert(session.fontScale == 1.5);
        assert(SpinUntil(
            ^BOOL {
              return fontScaleRenders == 1;
            },
            5.0));
        NSRange scaledRange = [session.renderedDocument.attributedString.string rangeOfString:@"Alpha beta alpha"];
        assert(scaledRange.location != NSNotFound);
        NSFont* scaledFont = [session.renderedDocument.attributedString attribute:NSFontAttributeName
                                                                          atIndex:scaledRange.location
                                                                   effectiveRange:nil];
        assert(fabs(scaledFont.pointSize - baseFont.pointSize * 1.5) < 0.01);
        assert(SpinUntil(
            ^BOOL {
              return session.fitMode == SPDFMacMarkdownPageFitCustom && fabs(session.zoom - 1.6) < 0.01;
            },
            5.0));

        // A language rerender after the scale change keeps the scaled fonts.
        __block NSUInteger scaledLanguageRenders = 0;
        session.statusHandler = ^(NSString* status) {
          if ([status isEqualToString:@"Code language updated."]) scaledLanguageRenders++;
        };
        [session applyLanguageIdentifier:@"python" toCodeBlock:codeBlock];
        assert(SpinUntil(
            ^BOOL {
              return scaledLanguageRenders == 1;
            },
            5.0));
        NSRange rescaledRange = [session.renderedDocument.attributedString.string rangeOfString:@"Alpha beta alpha"];
        NSFont* rescaledFont = [session.renderedDocument.attributedString attribute:NSFontAttributeName
                                                                            atIndex:rescaledRange.location
                                                                     effectiveRange:nil];
        assert(fabs(rescaledFont.pointSize - baseFont.pointSize * 1.5) < 0.01);
        SPDFMarkdownRenderedBlock* rescaledCode = [session.renderedDocument renderedBlockWithIndex:codeBlock];
        NSString* rescaledLanguage =
            [session.renderedDocument.attributedString attribute:SPDFMarkdownCodeLanguageAttribute
                                                         atIndex:rescaledCode.attributedRange.location
                                                  effectiveRange:nil];
        assert([rescaledLanguage isEqualToString:@"python"]);

        // Clamping, then equal-value applications must not rerender.
        session.statusHandler = ^(NSString* status) {
          if ([status isEqualToString:@"Markdown text size updated."]) fontScaleRenders++;
        };
        [session applyFontScale:10.0];
        assert(session.fontScale == 3.0);
        assert(SpinUntil(
            ^BOOL {
              return fontScaleRenders == 2;
            },
            5.0));
        SPDFMarkdownRenderedDocument* renderedBeforeNoop = session.renderedDocument;
        [session applyFontScale:3.0];
        [session applyFontScale:47.0]; // clamps to the same 3.0
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
        assert(fontScaleRenders == 2 && session.renderedDocument == renderedBeforeNoop);

        // Print/export stays at scale 1.0 while keeping the language override.
        SPDFMarkdownRenderedDocument* exportRendered = [session renderedDocumentForExport];
        assert(exportRendered != nil && exportRendered != session.renderedDocument);
        NSRange exportRange = [exportRendered.attributedString.string rangeOfString:@"Alpha beta alpha"];
        NSFont* exportFont = [exportRendered.attributedString attribute:NSFontAttributeName
                                                                atIndex:exportRange.location
                                                         effectiveRange:nil];
        assert(fabs(exportFont.pointSize - baseFont.pointSize) < 0.01);
        SPDFMarkdownRenderedBlock* exportCode = [exportRendered renderedBlockWithIndex:codeBlock];
        NSString* exportLanguage = [exportRendered.attributedString attribute:SPDFMarkdownCodeLanguageAttribute
                                                                      atIndex:exportCode.attributedRange.location
                                                               effectiveRange:nil];
        assert([exportLanguage isEqualToString:@"python"]);

        // A session created with an initial font scale renders scaled from the
        // first pass, and a pending anchor no longer discards the restored zoom.
        SPDFMacMarkdownSession* scaledSession =
            [[SPDFMacMarkdownSession alloc] initWithDocumentURL:[NSURL fileURLWithPath:path] fontScale:2.0];
        __block BOOL scaledLoaded = NO;
        [scaledSession activateInHostView:host
                                workQueue:sessionQueue
                             scrollOrigin:NSZeroPoint
                            selectedRange:NSMakeRange(0, 0)
                                pageIndex:0
                                     zoom:1.4
                                  fitMode:SPDFMacMarkdownPageFitCustom
                                   anchor:@"finish"
                               completion:^(BOOL success, NSError* error) {
                                 assert(success && !error);
                                 scaledLoaded = YES;
                               }];
        assert(SpinUntil(
            ^BOOL {
              return scaledLoaded;
            },
            5.0));
        assert(scaledSession.fontScale == 2.0);
        NSRange scaledBodyRange =
            [scaledSession.renderedDocument.attributedString.string rangeOfString:@"Alpha beta alpha"];
        NSFont* initialScaledFont = [scaledSession.renderedDocument.attributedString attribute:NSFontAttributeName
                                                                                       atIndex:scaledBodyRange.location
                                                                                effectiveRange:nil];
        assert(fabs(initialScaledFont.pointSize - baseFont.pointSize * 2.0) < 0.01);
        assert(SpinUntil(
            ^BOOL {
              return scaledSession.fitMode == SPDFMacMarkdownPageFitCustom && fabs(scaledSession.zoom - 1.4) < 0.01;
            },
            5.0));
        [scaledSession deactivate];
        assert(scaledSession.rootView.superview == nil);

        // Block the worker before activation, switch away, then release it.
        // The stale completion must never attach or call back.
        dispatch_queue_t blockedQueue = dispatch_queue_create("markdown.stale.test", DISPATCH_QUEUE_SERIAL);
        dispatch_semaphore_t gate = dispatch_semaphore_create(0);
        dispatch_async(blockedQueue, ^{
          dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER);
        });
        SPDFMacMarkdownSession* stale =
            [[SPDFMacMarkdownSession alloc] initWithDocumentURL:[NSURL fileURLWithPath:path]];
        __block BOOL staleCompletion = NO;
        [stale activateInHostView:host
                        workQueue:blockedQueue
                     scrollOrigin:NSZeroPoint
                    selectedRange:NSMakeRange(0, 0)
                        pageIndex:0
                             zoom:1.0
                          fitMode:SPDFMacMarkdownPageFitPage
                           anchor:nil
                       completion:^(BOOL success, NSError* error) {
                         (void)success;
                         (void)error;
                         staleCompletion = YES;
                       }];
        [stale deactivate];
        dispatch_semaphore_signal(gate);
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
        assert(!staleCompletion);
        assert(stale.rootView.superview == nil);

        [session deactivate];
        assert(session.rootView.superview == nil);
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        puts("SPDFMacMarkdownSessionTests passed");
    }
    return 0;
}
