#import <AppKit/AppKit.h>

#import "../SPDFMacMarkdownSession.h"
#import "../markdown/SPDFMarkdown.h"

#include <assert.h>
#include <stdio.h>

static BOOL SpinUntil(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                              beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return condition();
}

static NSString* WriteMarkdown(NSString* text) {
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"md"]];
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
        dispatch_queue_t sessionQueue =
            dispatch_queue_create("markdown.session.test", DISPATCH_QUEUE_CONCURRENT);
        SPDFMacMarkdownSession* session = [[SPDFMacMarkdownSession alloc]
            initWithDocumentURL:[NSURL fileURLWithPath:path]];
        __block BOOL loaded = NO;
        [session activateInHostView:host
                          workQueue:sessionQueue
                       scrollOrigin:NSZeroPoint
                      selectedRange:NSMakeRange(0, 0)
                             anchor:nil
                         completion:^(BOOL success, NSError* error) {
                           assert(success && !error);
                           loaded = YES;
                         }];
        assert(SpinUntil(^BOOL { return loaded; }, 5.0));
        assert(session.state == SPDFMacMarkdownSessionReady);
        assert(session.textView.selectable && !session.textView.editable);
        assert([session.textView.string containsString:@"Alpha beta alpha"]);

        __block NSUInteger count = NSNotFound;
        __block NSInteger index = -1;
        session.searchUpdateHandler = ^(NSUInteger resultCount, NSInteger resultIndex, BOOL searching) {
          if (!searching) {
              count = resultCount;
              index = resultIndex;
          }
        };
        [session searchForQuery:@"alpha" preferredIndex:0];
        assert(SpinUntil(^BOOL { return count != NSNotFound; }, 5.0));
        assert(count == 2 && index == 0);
        [session moveToNextMatch:YES];
        assert(session.currentMatchIndex == 1);
        assert([session scrollToHeadingAnchor:@"finish"]);
        session.textView.selectedRange = NSMakeRange(0, 5);
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
        assert(SpinUntil(^BOOL { return overlapSearchFinished && overlapRenderFinished; }, 5.0));
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
        assert(SpinUntil(^BOOL { return latestCount == 1; }, 5.0));
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
        assert(SpinUntil(^BOOL { return renderCompletions == 1; }, 5.0));
        SPDFMarkdownRenderedBlock* renderedCode =
            [session.renderedDocument renderedBlockWithIndex:codeBlock];
        NSString* language = [session.renderedDocument.attributedString
            attribute:SPDFMarkdownCodeLanguageAttribute
              atIndex:renderedCode.attributedRange.location
       effectiveRange:nil];
        assert([language isEqualToString:@"swift"]);

        // Block the worker before activation, switch away, then release it.
        // The stale completion must never attach or call back.
        dispatch_queue_t blockedQueue = dispatch_queue_create("markdown.stale.test", DISPATCH_QUEUE_SERIAL);
        dispatch_semaphore_t gate = dispatch_semaphore_create(0);
        dispatch_async(blockedQueue, ^{ dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER); });
        SPDFMacMarkdownSession* stale = [[SPDFMacMarkdownSession alloc]
            initWithDocumentURL:[NSURL fileURLWithPath:path]];
        __block BOOL staleCompletion = NO;
        [stale activateInHostView:host workQueue:blockedQueue scrollOrigin:NSZeroPoint
                    selectedRange:NSMakeRange(0, 0) anchor:nil
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
