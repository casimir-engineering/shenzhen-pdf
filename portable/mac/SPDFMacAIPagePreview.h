#pragma once
#import <Foundation/Foundation.h>
// Generates one bounded, light-theme page image in a private owned directory.
// The caller owns cleanup, including cancellation and deleted conversations.
NSDictionary* SPDFAIPagePreview(NSString* path, BOOL landscape, NSUInteger page,
    NSProgress* progress, NSError** error);

NSDictionary* SPDFAIPagePreviewForCandidate(NSDictionary* candidate, NSUInteger page,
    NSProgress* progress, NSError** error);
