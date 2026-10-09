#pragma once
#import <Cocoa/Cocoa.h>
// Model-produced Markdown never resolves an image or local resource.
NSAttributedString* SPDFMacAIChatMarkdown(NSString* text, CGFloat width, BOOL dark);
BOOL SPDFMacAIChatLinkAllowed(NSURL* URL);
