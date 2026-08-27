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

NS_ASSUME_NONNULL_END
