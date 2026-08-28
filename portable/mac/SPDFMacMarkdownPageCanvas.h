#pragma once

#import <AppKit/AppKit.h>

@class SPDFMarkdownPaginationPlan;
@protocol SPDFMacUIReader;

NS_ASSUME_NONNULL_BEGIN

@interface SPDFMacMarkdownPageCanvas : NSView
@property(nonatomic, weak, nullable) id<SPDFMacUIReader> reader;
@property(nonatomic, readonly) NSUInteger pageCount;
@property(nonatomic) BOOL presentationMode;
@property(nonatomic) NSRange selectedRange;
@property(nonatomic, copy) NSArray<NSValue*>* searchRanges;
@property(nonatomic, copy, nullable) void (^selectionChangedHandler)(NSRange range);
@property(nonatomic, copy, nullable) void (^activateDestinationHandler)(NSString* destination, BOOL wikiLink);
@property(nonatomic, copy, nullable) void (^chooseCodeLanguageHandler)(NSUInteger blockIndex);

- (instancetype)initWithPaginationPlan:(SPDFMarkdownPaginationPlan*)plan
                      attributedString:(NSAttributedString*)attributedString NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder*)coder NS_UNAVAILABLE;
- (NSRect)frameForPageAtIndex:(NSUInteger)pageIndex;
- (void)resizeForWidth:(CGFloat)width;
- (NSInteger)pageIndexForVisibleRect:(NSRect)visibleRect;
- (NSUInteger)attributedLocationNearestToPoint:(NSPoint)point;
- (nullable NSNumber*)codeLanguageBlockAtPoint:(NSPoint)point;
- (nullable NSString*)codeLanguageLabelForBlockIndex:(NSUInteger)blockIndex;
@end

// Implemented in SPDFMacMarkdownPageCanvas+Navigation.mm.
@interface SPDFMacMarkdownPageCanvas (Navigation)
- (BOOL)scrollRangeToVisible:(NSRange)range;
- (NSUInteger)pageIndexForRange:(NSRange)range;
@end

NS_ASSUME_NONNULL_END
