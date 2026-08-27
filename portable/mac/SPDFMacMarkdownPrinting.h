#pragma once

#import <AppKit/AppKit.h>

@class SPDFMarkdownPaginationPlan;
@class SPDFMarkdownRenderedDocument;

NS_ASSUME_NONNULL_BEGIN

@interface SPDFMacMarkdownPrintView : NSView
@property(nonatomic, readonly) SPDFMarkdownPaginationPlan* paginationPlan;
@property(nonatomic, readonly) SPDFMarkdownRenderedDocument* renderedDocument;
- (instancetype)initWithRenderedDocument:(SPDFMarkdownRenderedDocument*)document
                                printInfo:(NSPrintInfo*)printInfo NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder*)coder NS_UNAVAILABLE;
@end

@interface SPDFMacMarkdownPrintAdapter : NSObject
+ (NSPrintOperation*)printOperationForRenderedDocument:(SPDFMarkdownRenderedDocument*)document
                                             printInfo:(NSPrintInfo*)printInfo;
+ (BOOL)writeRenderedDocument:(SPDFMarkdownRenderedDocument*)document
                        toURL:(NSURL*)URL
                    printInfo:(NSPrintInfo*)printInfo
                        error:(NSError**)error;
+ (SPDFMarkdownPaginationPlan*)paginationPlanForRenderedDocument:(SPDFMarkdownRenderedDocument*)document
                                                       printInfo:(NSPrintInfo*)printInfo;
@end

NS_ASSUME_NONNULL_END
