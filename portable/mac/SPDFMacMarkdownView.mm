#import "SPDFMacMarkdownView.h"

#import "markdown/SPDFMarkdown.h"

NSAttributedStringKey const SPDFMacMarkdownDestinationAttribute = @"SPDFMacMarkdownDestination";
NSAttributedStringKey const SPDFMacMarkdownWikiDestinationAttribute = @"SPDFMacMarkdownWikiDestination";

static void SPDFAddRunDestinations(SPDFMarkdownBlock* block,
                                   SPDFMarkdownRenderedDocument* rendered,
                                   NSMutableAttributedString* output) {
    SPDFMarkdownRenderedBlock* renderedBlock = [rendered renderedBlockWithIndex:block.blockIndex];
    if (renderedBlock && NSMaxRange(renderedBlock.attributedRange) <= output.length) {
        NSUInteger cursor = renderedBlock.attributedRange.location;
        NSUInteger end = NSMaxRange(renderedBlock.attributedRange);
        for (SPDFMarkdownInlineRun* run in block.runs) {
            if (!run.text.length || cursor >= end) continue;
            NSRange remaining = NSMakeRange(cursor, end - cursor);
            NSRange found = [output.string rangeOfString:run.text options:0 range:remaining];
            if (found.location == NSNotFound) continue;
            cursor = NSMaxRange(found);
            if (!(run.traits & (SPDFMarkdownInlineTraitLink | SPDFMarkdownInlineTraitWikiLink))) continue;
            NSAttributedStringKey key = (run.traits & SPDFMarkdownInlineTraitWikiLink)
                ? SPDFMacMarkdownWikiDestinationAttribute : SPDFMacMarkdownDestinationAttribute;
            [output addAttribute:key value:run.destination ?: @"" range:found];
            [output removeAttribute:NSLinkAttributeName range:found];
        }
    }
    for (SPDFMarkdownBlock* child in block.children) SPDFAddRunDestinations(child, rendered, output);
}

NSAttributedString* SPDFMacMarkdownInteractiveString(SPDFMarkdownDocumentModel* model,
                                                     SPDFMarkdownRenderedDocument* rendered) {
    NSMutableAttributedString* output = [rendered.attributedString mutableCopy];
    [output removeAttribute:NSLinkAttributeName range:NSMakeRange(0, output.length)];
    for (SPDFMarkdownBlock* block in model.blocks) SPDFAddRunDestinations(block, rendered, output);
    return output;
}

@implementation SPDFMacMarkdownTextView {
    NSPoint _mouseDownPoint;
    BOOL _mouseDragged;
}

- (void)mouseDown:(NSEvent*)event {
    _mouseDownPoint = [self convertPoint:event.locationInWindow fromView:nil];
    _mouseDragged = NO;
    [super mouseDown:event];
}

- (void)mouseDragged:(NSEvent*)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (hypot(point.x - _mouseDownPoint.x, point.y - _mouseDownPoint.y) > 3.0) _mouseDragged = YES;
    [super mouseDragged:event];
}

- (NSUInteger)characterIndexForEvent:(NSEvent*)event {
    NSLayoutManager* layout = self.layoutManager;
    NSTextContainer* container = self.textContainer;
    if (!layout || !container || self.string.length == 0) return NSNotFound;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    point.x -= self.textContainerOrigin.x;
    point.y -= self.textContainerOrigin.y;
    CGFloat fraction = 0.0;
    NSUInteger glyph = [layout glyphIndexForPoint:point inTextContainer:container fractionOfDistanceThroughGlyph:&fraction];
    if (glyph >= layout.numberOfGlyphs) return NSNotFound;
    NSUInteger character = [layout characterIndexForGlyphAtIndex:glyph];
    return character < self.textStorage.length ? character : NSNotFound;
}

- (void)mouseUp:(NSEvent*)event {
    [super mouseUp:event];
    if (_mouseDragged || event.clickCount != 1 || self.selectedRange.length != 0) return;
    NSUInteger index = [self characterIndexForEvent:event];
    if (index == NSNotFound) return;
    NSString* destination = [self.textStorage attribute:SPDFMacMarkdownDestinationAttribute
                                                atIndex:index effectiveRange:NULL];
    BOOL wiki = NO;
    if (!destination) {
        destination = [self.textStorage attribute:SPDFMacMarkdownWikiDestinationAttribute
                                          atIndex:index effectiveRange:NULL];
        wiki = destination != nil;
    }
    if (destination.length)
        [self.markdownEventDelegate markdownTextView:self activateDestination:destination wikiLink:wiki];
}

- (NSMenu*)menuForEvent:(NSEvent*)event {
    NSMenu* menu = [super menuForEvent:event] ?: [NSMenu new];
    NSUInteger index = [self characterIndexForEvent:event];
    if (index != NSNotFound) {
        NSNumber* kind = [self.textStorage attribute:SPDFMarkdownBlockKindAttribute atIndex:index effectiveRange:NULL];
        NSNumber* block = [self.textStorage attribute:SPDFMarkdownBlockIndexAttribute atIndex:index effectiveRange:NULL];
        if (kind.integerValue == SPDFMarkdownBlockKindCode && block) {
            [menu addItem:NSMenuItem.separatorItem];
            NSMenuItem* language = [[NSMenuItem alloc] initWithTitle:@"Choose Code Language..."
                                                              action:@selector(chooseCodeLanguage:)
                                                       keyEquivalent:@""];
            language.target = self;
            language.representedObject = block;
            [menu addItem:language];
        }
    }
    [menu addItem:NSMenuItem.separatorItem];
    NSArray* actions = @[
        @[ @"Show in Folder", @"showInFolder:", @"folder" ],
        @[ @"Copy Document", @"copyCurrentDocumentFile:", @"doc.on.clipboard" ],
        @[ @"Copy Path", @"copyCurrentDocumentPath:", @"doc.text" ],
    ];
    for (NSArray* action in actions) {
        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:action[0]
                                                     action:NSSelectorFromString(action[1])
                                              keyEquivalent:@""];
        item.target = NSApp.delegate;
        item.image = [NSImage imageWithSystemSymbolName:action[2] accessibilityDescription:action[0]];
        [menu addItem:item];
    }
    return menu;
}

- (void)chooseCodeLanguage:(NSMenuItem*)sender {
    NSNumber* block = sender.representedObject;
    if (block)
        [self.markdownEventDelegate markdownTextView:self chooseLanguageForCodeBlock:block.unsignedIntegerValue];
}

@end
