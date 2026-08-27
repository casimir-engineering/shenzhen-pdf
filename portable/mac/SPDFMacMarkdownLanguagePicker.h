#pragma once

#import <AppKit/AppKit.h>

@class SPDFMarkdownLanguage;

NS_ASSUME_NONNULL_BEGIN

@interface SPDFMacMarkdownLanguagePickerController : NSWindowController
@property(nonatomic, readonly) NSSearchField* searchField;
@property(nonatomic, readonly) NSTableView* tableView;
@property(nonatomic, readonly, copy) NSArray<SPDFMarkdownLanguage*>* visibleLanguages;
@property(nonatomic, readonly) NSInteger selectedIndex;

- (void)presentForWindow:(NSWindow*)window
              completion:(void (^)(SPDFMarkdownLanguage* _Nullable language))completion;
- (BOOL)handleCommandSelector:(SEL)selector;
- (void)updateQuery:(NSString*)query;
@end

NS_ASSUME_NONNULL_END
