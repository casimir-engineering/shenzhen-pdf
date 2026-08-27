#pragma once

#import <AppKit/AppKit.h>

@class SPDFMarkdownDocument;
@class SPDFMarkdownRenderedDocument;
@class SPDFMarkdownSearchMatch;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPDFMacMarkdownSessionState) {
    SPDFMacMarkdownSessionIdle,
    SPDFMacMarkdownSessionLoading,
    SPDFMacMarkdownSessionReady,
    SPDFMacMarkdownSessionFailed,
};

@interface SPDFMacMarkdownSession : NSObject
@property(nonatomic, readonly, copy) NSURL* documentURL;
@property(nonatomic, readonly) NSView* rootView;
@property(nonatomic, readonly, nullable) NSTextView* textView;
@property(nonatomic, readonly, nullable) SPDFMarkdownDocument* document;
@property(nonatomic, readonly, nullable) SPDFMarkdownRenderedDocument* renderedDocument;
@property(nonatomic, readonly) SPDFMacMarkdownSessionState state;
@property(nonatomic, readonly, copy) NSArray<SPDFMarkdownSearchMatch*>* searchMatches;
@property(nonatomic, readonly) NSInteger currentMatchIndex;
@property(nonatomic, readonly) NSPoint scrollOrigin;
@property(nonatomic, readonly) NSRange selectedRange;
@property(nonatomic, readonly, copy) NSString* selectedText;
@property(nonatomic, copy, nullable) void (^openDocumentHandler)(NSURL* URL, NSString* _Nullable anchor);
@property(nonatomic, copy, nullable) void (^openExternalURLHandler)(NSURL* URL);
@property(nonatomic, copy, nullable) void (^statusHandler)(NSString* status);
@property(nonatomic, copy, nullable) void (^searchUpdateHandler)(NSUInteger count,
                                                                    NSInteger currentIndex,
                                                                    BOOL searching);

- (instancetype)initWithDocumentURL:(NSURL*)URL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)activateInHostView:(NSView*)hostView
                 workQueue:(dispatch_queue_t)workQueue
              scrollOrigin:(NSPoint)scrollOrigin
             selectedRange:(NSRange)selectedRange
                    anchor:(nullable NSString*)anchor
                completion:(void (^)(BOOL success, NSError* _Nullable error))completion;
- (void)deactivate;
- (void)cancelAllOperations;
- (void)searchForQuery:(NSString*)query preferredIndex:(NSInteger)preferredIndex;
- (void)clearSearch;
- (void)moveToNextMatch:(BOOL)forward;
- (BOOL)scrollToHeadingAnchor:(NSString*)anchor;
- (void)navigateToAnchorWhenReady:(NSString*)anchor;
- (void)showLanguagePickerForCodeBlock:(NSUInteger)blockIndex parentWindow:(NSWindow*)window;
@end

NS_ASSUME_NONNULL_END
