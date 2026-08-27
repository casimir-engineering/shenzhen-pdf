#pragma once

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

#import "SPDFMarkdownRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPDFMarkdownPageConfiguration : NSObject <NSCopying>
@property(nonatomic) NSSize paperSize;
@property(nonatomic) NSRect printableRect;
@property(nonatomic) CGFloat headingKeepThreshold;
// Screen pagination can reserve space for its interactive code-language control.
// Print and export configurations intentionally default to NO.
@property(nonatomic) BOOL includesCodeLanguageControlSpacing;
+ (instancetype)A4PortraitConfiguration;
+ (instancetype)configurationForPaperSize:(NSSize)paperSize printableRect:(NSRect)printableRect;
@end

@interface SPDFMarkdownTextLine : NSObject
@property(nonatomic, readonly) NSRange attributedRange;
@property(nonatomic, readonly) CGFloat height;
@property(nonatomic, readonly) CGFloat xOffset;
@property(nonatomic, readonly) CGFloat baselineOffset;
- (instancetype)initWithAttributedRange:(NSRange)attributedRange
                                 height:(CGFloat)height
                                xOffset:(CGFloat)xOffset
                         baselineOffset:(CGFloat)baselineOffset NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface SPDFMarkdownPaginationItem : NSObject
@property(nonatomic, readonly) NSUInteger blockIndex;
@property(nonatomic, readonly) SPDFMarkdownBlockKind kind;
@property(nonatomic, readonly) NSUInteger headingLevel;
@property(nonatomic, readonly, copy) NSArray<SPDFMarkdownTextLine*>* lines;
@property(nonatomic, readonly) CGFloat measuredHeight;
- (instancetype)initWithBlockIndex:(NSUInteger)blockIndex
                              kind:(SPDFMarkdownBlockKind)kind
                      headingLevel:(NSUInteger)headingLevel
                             lines:(NSArray<SPDFMarkdownTextLine*>*)lines NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface SPDFMarkdownPageFragment : NSObject
@property(nonatomic, readonly) NSUInteger itemIndex;
@property(nonatomic, readonly) NSUInteger blockIndex;
@property(nonatomic, readonly) NSRange attributedRange;
@property(nonatomic, readonly) CGFloat pageYOffset;
@property(nonatomic, readonly) CGFloat height;
@property(nonatomic, readonly) CGFloat xOffset;
@property(nonatomic, readonly) CGFloat baselineOffset;
@property(nonatomic, readonly) CGFloat scale;
@property(nonatomic, readonly, getter=isContinuation) BOOL continuation;
@end

@interface SPDFMarkdownPage : NSObject
@property(nonatomic, readonly) NSUInteger pageIndex;
@property(nonatomic, readonly, copy) NSArray<SPDFMarkdownPageFragment*>* fragments;
@property(nonatomic, readonly) CGFloat usedHeight;
@end

@interface SPDFMarkdownPaginationPlan : NSObject
@property(nonatomic, readonly, copy) SPDFMarkdownPageConfiguration* configuration;
@property(nonatomic, readonly, copy) NSArray<SPDFMarkdownPaginationItem*>* items;
@property(nonatomic, readonly, copy) NSArray<SPDFMarkdownPage*>* pages;

// Draws the same exact line-fragment plan used by print preview/pagination.
- (BOOL)drawPageAtIndex:(NSUInteger)pageIndex
       attributedString:(NSAttributedString*)attributedString
              inContext:(CGContextRef)context;
@end

@interface SPDFMarkdownPaginator : NSObject
- (SPDFMarkdownPaginationPlan*)paginateItems:(NSArray<SPDFMarkdownPaginationItem*>*)items
                               configuration:(SPDFMarkdownPageConfiguration*)configuration;
- (NSArray<SPDFMarkdownPaginationItem*>*)measureRenderedDocument:(SPDFMarkdownRenderedDocument*)document
                                                  containerWidth:(CGFloat)containerWidth;
@end

NS_ASSUME_NONNULL_END
