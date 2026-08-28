#pragma once

#import "SPDFMarkdownRenderer.h"
#import "SPDFMarkdownResources.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPDFMarkdownRenderContext : NSObject
@property(nonatomic) NSMutableAttributedString* output;
@property(nonatomic) NSMutableArray<SPDFMarkdownRenderedBlock*>* blocks;
@property(nonatomic) SPDFMarkdownRenderOptions* options;
@property(nonatomic) SPDFMarkdownLanguageCatalog* catalog;
@property(nonatomic) SPDFMarkdownHighlighter* highlighter;
@property(nonatomic, nullable) SPDFMarkdownCancellationToken* cancellationToken;
@property(nonatomic) NSDictionary<NSNumber*, NSString*>* overrides;
@property(nonatomic, nullable) NSURL* sourceURL;
@property(nonatomic, nullable) SPDFMarkdownResourceStore* resourceStore;
@property(nonatomic) NSFont* bodyFont;
@property(nonatomic) NSFont* codeFont;
@end

void SPDFRenderMarkdownBlocks(SPDFMarkdownRenderContext* context, NSArray<SPDFMarkdownBlock*>* blocks);

// Shared string-building primitives (SPDFMarkdownInlineRenderer.mm) used by
// both the block renderer and the inline-run renderer.
NSFont* SPDFMarkdownFontWithTraits(NSFont* font, NSFontTraitMask traits);
void SPDFMarkdownAppend(SPDFMarkdownRenderContext* context, NSString* string,
                        NSDictionary<NSAttributedStringKey, id>* attributes);
CGFloat SPDFMarkdownRenderScale(SPDFMarkdownRenderContext* context);

// Renders a block's inline runs, including image attachments and their
// alt-text captions (SPDFMarkdownInlineRenderer.mm).
void SPDFMarkdownRenderInlineRuns(SPDFMarkdownRenderContext* context, SPDFMarkdownBlock* block);

// A standalone image paragraph (an image that is its paragraph's only
// meaningful content) renders GitHub-style as a centered figure with the alt
// text as a centered caption line below the artwork. The roles are recorded on
// the affected characters so the leaf renderer can re-derive the centered
// paragraph styles after it applies the block's base style to the whole range.
typedef NS_ENUM(NSInteger, SPDFMarkdownImageLayoutRole) {
    SPDFMarkdownImageLayoutRoleFigure = 1,
    SPDFMarkdownImageLayoutRoleCaption = 2,
};
FOUNDATION_EXPORT NSAttributedStringKey const SPDFMarkdownImageLayoutAttribute;
void SPDFMarkdownApplyImageBlockStyles(SPDFMarkdownRenderContext* context, NSRange range,
                                       NSParagraphStyle* baseStyle);

NS_ASSUME_NONNULL_END
