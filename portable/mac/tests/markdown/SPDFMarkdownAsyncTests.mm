#import "SPDFMarkdownTestSupport.h"

#import "../../markdown/SPDFMarkdownDocument.h"

int main(void) {
    @autoreleasepool {
        NSError* error = nil;
        SPDFMarkdownDocument* document = [SPDFMarkdownDocument documentWithURL:SPDFFixtureURL(@"commonmark-gfm.md")
                                                                        options:nil error:&error];
        dispatch_queue_t work = dispatch_queue_create("spdf.markdown.test.work", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_t completionQueue = dispatch_queue_create("spdf.markdown.test.completion", DISPATCH_QUEUE_SERIAL);

        dispatch_semaphore_t searchDone = dispatch_semaphore_create(0);
        [document searchForQuery:@"Finished task" caseSensitive:YES workQueue:work completionQueue:completionQueue
                      completion:^(NSArray<SPDFMarkdownSearchMatch*>* matches, BOOL cancelled) {
            SPDFExpect(!cancelled && matches.count == 1, @"asynchronous search completes");
            NSString* selected = [document.renderedDocument.attributedString.string
                substringWithRange:matches.firstObject.range];
            SPDFExpect([selected isEqualToString:@"Finished task"], @"async search keeps canonical coordinates");
            dispatch_semaphore_signal(searchDone);
        }];
        SPDFExpect(dispatch_semaphore_wait(searchDone, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0,
                   @"async search does not block indefinitely");

        dispatch_queue_t suspended = dispatch_queue_create("spdf.markdown.test.cancel", DISPATCH_QUEUE_SERIAL);
        dispatch_suspend(suspended);
        dispatch_semaphore_t cancelDone = dispatch_semaphore_create(0);
        SPDFMarkdownCancellationToken* token = [document searchForQuery:@"Alpha" caseSensitive:YES
                                                               workQueue:suspended completionQueue:completionQueue
                                                              completion:^(NSArray* matches, BOOL cancelled) {
            SPDFExpect(cancelled && matches.count == 0, @"cancelled search returns no stale matches");
            dispatch_semaphore_signal(cancelDone);
        }];
        [token cancel];
        dispatch_resume(suspended);
        SPDFExpect(dispatch_semaphore_wait(cancelDone, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0,
                   @"cancelled async search completes");

        NSUInteger codeBlock = document.model.codeFences.lastObject.blockIndex;
        dispatch_semaphore_t renderDone = dispatch_semaphore_create(0);
        [document renderWithLanguageOverrides:@{@(codeBlock): @"python"}
                                    workQueue:work completionQueue:completionQueue
                                   completion:^(SPDFMarkdownRenderedDocument* rendered, BOOL cancelled) {
            SPDFMarkdownRenderedBlock* block = [rendered renderedBlockWithIndex:codeBlock];
            NSString* language = [rendered.attributedString attribute:SPDFMarkdownCodeLanguageAttribute
                                                              atIndex:block.attributedRange.location effectiveRange:nil];
            SPDFExpect(!cancelled && [language isEqualToString:@"python"],
                       @"asynchronous rerender applies language override");
            dispatch_semaphore_signal(renderDone);
        }];
        SPDFExpect(dispatch_semaphore_wait(renderDone, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0,
                   @"async rerender does not block indefinitely");

        dispatch_queue_t suspendedRender = dispatch_queue_create("spdf.markdown.test.render.cancel",
                                                                  DISPATCH_QUEUE_SERIAL);
        dispatch_suspend(suspendedRender);
        dispatch_semaphore_t renderCancelDone = dispatch_semaphore_create(0);
        SPDFMarkdownCancellationToken* renderToken =
            [document renderWithLanguageOverrides:@{@(codeBlock): @"python"}
                                        workQueue:suspendedRender completionQueue:completionQueue
                                       completion:^(SPDFMarkdownRenderedDocument* rendered, BOOL cancelled) {
            SPDFExpect(cancelled && rendered == nil, @"cancelled rerender returns no partial document");
            dispatch_semaphore_signal(renderCancelDone);
        }];
        [renderToken cancel];
        dispatch_resume(suspendedRender);
        SPDFExpect(dispatch_semaphore_wait(renderCancelDone, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0,
                   @"cancelled rerender completes");

        NSString* largeStringBody = [@"" stringByPaddingToLength:12 * 1024 * 1024
                                                      withString:@"a"
                                                 startingAtIndex:0];
        NSString* largeCode = [@"\"" stringByAppendingString:largeStringBody];
        SPDFMarkdownCancellationToken* lexerToken = [SPDFMarkdownCancellationToken new];
        dispatch_semaphore_t lexerStarted = dispatch_semaphore_create(0);
        dispatch_semaphore_t lexerDone = dispatch_semaphore_create(0);
        __block NSArray* cancelledTokens = nil;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            dispatch_semaphore_signal(lexerStarted);
            SPDFMarkdownLanguage* JavaScript =
                [SPDFMarkdownLanguageCatalog.sharedCatalog languageForFenceIdentifier:@"javascript"];
            cancelledTokens = [[SPDFMarkdownHighlighter new] tokensForCode:largeCode
                                                                   language:JavaScript
                                                          cancellationToken:lexerToken];
            dispatch_semaphore_signal(lexerDone);
        });
        dispatch_semaphore_wait(lexerStarted, DISPATCH_TIME_FOREVER);
        [lexerToken cancel];
        SPDFExpect(dispatch_semaphore_wait(lexerDone, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0 &&
                       cancelledTokens.count == 0,
                   @"in-flight lexer cancellation is observed inside a long token scan");
    }
    return SPDFFinishTests(@"SPDFMarkdownAsyncTests");
}
