#pragma once

#import "SPDFMacMarkdownPageCanvas.h"

@class SPDFMarkdownPaginationPlan;

// Shared between SPDFMacMarkdownPageCanvas.mm and its categories
// (SPDFMacMarkdownPageCanvas+Navigation.mm); not part of the public canvas API.
@interface SPDFMacMarkdownPageCanvas ()
@property(nonatomic, readonly) SPDFMarkdownPaginationPlan* plan;
@property(nonatomic, readonly) NSAttributedString* attributedString;
@end
