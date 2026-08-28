#pragma once

#import <AppKit/AppKit.h>

@class SPDFMarkdownPaginationPlan;

NS_ASSUME_NONNULL_BEGIN

// Print/export never repaginates: both consume the session's live pagination
// plan (current font scale, language overrides, and the reserved language
// control band), so output is page-for-page identical to the on-screen render.
@interface SPDFMacMarkdownPrintView : NSView
@property(nonatomic, readonly) SPDFMarkdownPaginationPlan* paginationPlan;
@property(nonatomic, readonly) NSAttributedString* attributedString;
- (instancetype)initWithPaginationPlan:(SPDFMarkdownPaginationPlan*)plan
                      attributedString:(NSAttributedString*)attributedString NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder*)coder NS_UNAVAILABLE;
@end

@interface SPDFMacMarkdownPrintAdapter : NSObject
+ (NSPrintOperation*)printOperationForPaginationPlan:(SPDFMarkdownPaginationPlan*)plan
                                    attributedString:(NSAttributedString*)attributedString
                                           printInfo:(NSPrintInfo*)printInfo;
+ (BOOL)writePaginationPlan:(SPDFMarkdownPaginationPlan*)plan
           attributedString:(NSAttributedString*)attributedString
                      toURL:(NSURL*)URL
                      error:(NSError**)error;
@end

NS_ASSUME_NONNULL_END
