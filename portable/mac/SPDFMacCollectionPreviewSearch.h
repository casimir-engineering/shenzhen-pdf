#pragma once
#import <Foundation/Foundation.h>
// PDF extraction inserts line breaks absent from indexed Markdown paragraphs.
// Collapse whitespace for matching, then return ranges in the original PDF text.
NSArray<NSValue*>* SPDFCollectionPreviewMatchRanges(NSString* text, NSString* query);
