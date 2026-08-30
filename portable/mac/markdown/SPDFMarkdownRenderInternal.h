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

// A fenced code block whose language names a native diagram (mermaid /
// sequence / flow) renders as a centered figure attachment instead of a code
// box (SPDFMarkdownDiagramFigure.mm). Returns NO — having emitted nothing —
// when the fence is not a diagram or the diagram seam declines it (malformed,
// unsupported sub-type, over budget); the caller must then run the unchanged
// code-box path, which is the degradation contract.
BOOL SPDFMarkdownRenderDiagramFigureBlock(SPDFMarkdownRenderContext* context, SPDFMarkdownBlock* block,
                                          NSUInteger depth, BOOL record);

// An images-only paragraph (images are its only meaningful content, separated
// by nothing but whitespace/soft breaks) renders by its shape. A single image
// becomes a centered figure with a centered caption line below the artwork —
// the caption is the image's markdown TITLE (`![alt](src "title")`) when one
// is present, falling back to the alt text (the title stays a tooltip too).
// Two or more images stay the inline elements CommonMark says they are: they
// flow side by side in one center-aligned paragraph, separated by the
// source's spaces/soft breaks and wrapping when the printable width runs out
// (badge rows read as one line). A row whose capped images would overflow the
// width budget (maximumImageWidth) scales them all down by one common factor
// — never below 0.45x — so typical two-image rows fit a single line instead
// of stacking. Row images caption too: each attachment-rendered image shows
// its title-or-alt caption BELOW ITSELF, centered under that image's own
// horizontal span. The captions live once in the canonical string as one
// trailing caption paragraph (searchable, exact canonical ranges); each
// caption span and its image span share an SPDFMarkdownImageRowIndexAttribute
// ordinal so the paginator's measurement pass can emit the caption as a
// custom-positioned line under its image (see SPDFMarkdownPaginator.mm). An
// image with neither title nor alt gets no caption; its neighbors keep
// theirs. Images mixed into sentence text keep plain inline flow and show no
// visible alt text. The roles are recorded on the affected characters so the
// leaf renderer can re-derive the centered paragraph styles after it applies
// the block's base style to the whole range.
typedef NS_ENUM(NSInteger, SPDFMarkdownImageLayoutRole) {
    SPDFMarkdownImageLayoutRoleFigure = 1,
    SPDFMarkdownImageLayoutRoleCaption = 2,
    SPDFMarkdownImageLayoutRoleImageRow = 3,
};
FOUNDATION_EXPORT NSAttributedStringKey const SPDFMarkdownImageLayoutAttribute;
// NSNumber ordinal linking a row image's rendered span to its caption span.
FOUNDATION_EXPORT NSAttributedStringKey const SPDFMarkdownImageRowIndexAttribute;
void SPDFMarkdownApplyImageBlockStyles(SPDFMarkdownRenderContext* context, NSRange range,
                                       NSParagraphStyle* baseStyle);

NS_ASSUME_NONNULL_END
