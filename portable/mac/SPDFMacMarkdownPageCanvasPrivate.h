#pragma once

#import "SPDFMacMarkdownPageCanvas.h"

@class SPDFMarkdownPaginationPlan;

@class SPDFMarkdownPage;
@class SPDFMarkdownPageFragment;

// Shared between SPDFMacMarkdownPageCanvas.mm and its categories
// (SPDFMacMarkdownPageCanvas+Navigation.mm); not part of the public canvas API.
@interface SPDFMacMarkdownPageCanvas ()
@property(nonatomic, readonly) SPDFMarkdownPaginationPlan* plan;
@property(nonatomic, readonly) NSAttributedString* attributedString;
@end

// Drawing/geometry internals implemented alongside the public (Decorations)
// category in SPDFMacMarkdownPageCanvas+Decorations.mm.
@interface SPDFMacMarkdownPageCanvas (DecorationsInternal)
- (SPDFMarkdownPageFragment*)codeControlFragmentOnPage:(SPDFMarkdownPage*)page blockIndex:(NSUInteger)blockIndex;
- (NSRect)codeLanguageControlRectForFragment:(SPDFMarkdownPageFragment*)fragment pageFrame:(NSRect)pageFrame;
- (NSRect)codeLanguageControlHitRectForFragment:(SPDFMarkdownPageFragment*)fragment pageFrame:(NSRect)pageFrame;
- (void)drawDecorationsForPageAtIndex:(NSUInteger)pageIndex pageFrame:(NSRect)pageFrame;
- (void)drawCodeLanguageControlsOnPage:(SPDFMarkdownPage*)page pageFrame:(NSRect)pageFrame;
@end
