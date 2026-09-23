#pragma once
#import <Cocoa/Cocoa.h>
// Collection chrome only. These appearance-aware colors never enter document rendering.
NSColor* SPDFCollectionColor(NSString* token);
NSButton* SPDFCollectionButton(NSString* title, id target, SEL action, NSString* kind);
NSPopUpButton* SPDFCollectionPopUp(void);
NSSearchField* SPDFCollectionSearchField(void);
NSTextField* SPDFCollectionText(NSString* text, CGFloat size, NSFontWeight weight, BOOL secondary);
NSView* SPDFCollectionSurface(NSString* token);
NSView* SPDFCollectionDivider(void);
