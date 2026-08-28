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

// An images-only paragraph (images are its only meaningful content, separated
// by nothing but whitespace/soft breaks) renders by its shape. A single image
// becomes a centered figure with the alt text as a centered caption line
// below the artwork. Two or more images stay the inline elements CommonMark
// says they are: they flow side by side in one center-aligned paragraph,
// separated by the source's spaces/soft breaks and wrapping when the
// printable width runs out, with no visible captions (badge rows read as one
// line). Images mixed into sentence text keep plain inline flow and show no
// visible alt text either. The roles are recorded on the affected characters
// so the leaf renderer can re-derive the centered paragraph styles after it
// applies the block's base style to the whole range.
typedef NS_ENUM(NSInteger, SPDFMarkdownImageLayoutRole) {
    SPDFMarkdownImageLayoutRoleFigure = 1,
    SPDFMarkdownImageLayoutRoleCaption = 2,
    SPDFMarkdownImageLayoutRoleImageRow = 3,
};
FOUNDATION_EXPORT NSAttributedStringKey const SPDFMarkdownImageLayoutAttribute;
void SPDFMarkdownApplyImageBlockStyles(SPDFMarkdownRenderContext* context, NSRange range,
                                       NSParagraphStyle* baseStyle);

NS_ASSUME_NONNULL_END
