#pragma once

#import <AppKit/AppKit.h>

#import "SPDFMarkdownLanguage.h"
#import "SPDFMarkdownHighlighter.h"
#import "SPDFMarkdownModel.h"
#import "SPDFMarkdownAsync.h"

NS_ASSUME_NONNULL_BEGIN

@class SPDFMarkdownTableRowInfo;

FOUNDATION_EXPORT NSAttributedStringKey const SPDFMarkdownBlockIndexAttribute;
FOUNDATION_EXPORT NSAttributedStringKey const SPDFMarkdownBlockKindAttribute;
FOUNDATION_EXPORT NSAttributedStringKey const SPDFMarkdownWikiLinkAttribute;
FOUNDATION_EXPORT NSAttributedStringKey const SPDFMarkdownImageTargetAttribute;
FOUNDATION_EXPORT NSAttributedStringKey const SPDFMarkdownCodeLanguageAttribute;

@interface SPDFMarkdownRenderOptions : NSObject <NSCopying>
@property(nonatomic) CGFloat textSize;
@property(nonatomic) CGFloat codeSize;
@property(nonatomic) CGFloat lineSpacing;
@property(nonatomic) CGFloat paragraphSpacing;
// Uniform typography multiplier, clamped to [0.5, 3.0] (default 1.0). Fonts and
// vertical spacing scale with it; indent constants and image budgets do not.
@property(nonatomic) CGFloat fontScale;
@property(nonatomic) CGFloat contentInset;
@property(nonatomic) CGFloat maximumImageWidth;
@property(nonatomic) CGFloat maximumImageHeight;
@property(nonatomic) NSUInteger maximumResourceBytes;
@property(nonatomic) NSUInteger maximumDecodedImagePixels;
@property(nonatomic, strong) NSColor* textColor;
@property(nonatomic, strong) NSColor* secondaryTextColor;
@property(nonatomic, strong) NSColor* linkColor;
@property(nonatomic, strong) NSColor* codeBackgroundColor;
@property(nonatomic, strong) NSColor* quoteColor;
+ (instancetype)defaultOptions;
+ (instancetype)printOptions;
@end

@interface SPDFMarkdownRenderedBlock : NSObject
@property(nonatomic, readonly) NSUInteger blockIndex;
@property(nonatomic, readonly) SPDFMarkdownBlockKind kind;
@property(nonatomic, readonly) NSRange attributedRange;
@property(nonatomic, readonly) NSUInteger level;
@property(nonatomic, readonly) NSUInteger depth;
// Non-nil only for table rows: the row's role and column geometry, recorded by
// the renderer so the pagination plan can draw the table grid decoration
// without re-deriving tab-stop math (see SPDFMarkdownTableDecorations.h).
@property(nonatomic, readonly, nullable) SPDFMarkdownTableRowInfo* tableRowInfo;
- (instancetype)initWithBlockIndex:(NSUInteger)blockIndex
                              kind:(SPDFMarkdownBlockKind)kind
                   attributedRange:(NSRange)attributedRange
                             level:(NSUInteger)level
                             depth:(NSUInteger)depth
                      tableRowInfo:(nullable SPDFMarkdownTableRowInfo*)tableRowInfo NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithBlockIndex:(NSUInteger)blockIndex
                              kind:(SPDFMarkdownBlockKind)kind
                   attributedRange:(NSRange)attributedRange
                             level:(NSUInteger)level
                             depth:(NSUInteger)depth;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface SPDFMarkdownRenderedHeading : NSObject
@property(nonatomic, readonly) NSUInteger blockIndex;
@property(nonatomic, readonly) NSUInteger level;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly) NSRange attributedRange;
@end

@interface SPDFMarkdownRenderedDocument : NSObject
@property(nonatomic, readonly, copy) NSAttributedString* attributedString;
@property(nonatomic, readonly, copy) NSArray<SPDFMarkdownRenderedBlock*>* renderedBlocks;
@property(nonatomic, readonly, copy) NSArray<SPDFMarkdownRenderedHeading*>* headings;
- (nullable SPDFMarkdownRenderedBlock*)renderedBlockWithIndex:(NSUInteger)blockIndex;
- (NSArray<SPDFMarkdownSearchMatch*>*)searchForQuery:(NSString*)query
                                       caseSensitive:(BOOL)caseSensitive;
- (NSArray<SPDFMarkdownSearchMatch*>*)searchForQuery:(NSString*)query
                                       caseSensitive:(BOOL)caseSensitive
                                   cancellationToken:(nullable SPDFMarkdownCancellationToken*)cancellationToken;
@end

@interface SPDFMarkdownRenderer : NSObject
@property(nonatomic, readonly) SPDFMarkdownLanguageCatalog* languageCatalog;
- (instancetype)initWithLanguageCatalog:(SPDFMarkdownLanguageCatalog*)languageCatalog NS_DESIGNATED_INITIALIZER;
- (instancetype)init;

// languageOverrides maps code block indexes to a supported language identifier.
- (SPDFMarkdownRenderedDocument*)renderModel:(SPDFMarkdownDocumentModel*)model
                                     options:(SPDFMarkdownRenderOptions*)options
                           languageOverrides:(nullable NSDictionary<NSNumber*, NSString*>*)languageOverrides;
- (nullable SPDFMarkdownRenderedDocument*)renderModel:(SPDFMarkdownDocumentModel*)model
                                               options:(SPDFMarkdownRenderOptions*)options
                                     languageOverrides:(nullable NSDictionary<NSNumber*, NSString*>*)languageOverrides
                                     cancellationToken:(nullable SPDFMarkdownCancellationToken*)cancellationToken;
- (NSTextView*)newSelectableTextViewForRenderedDocument:(SPDFMarkdownRenderedDocument*)document
                                                 options:(SPDFMarkdownRenderOptions*)options;
@end

NS_ASSUME_NONNULL_END
