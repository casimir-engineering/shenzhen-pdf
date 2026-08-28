#import "SPDFMacMarkdownPageCanvasPrivate.h"

#import <CoreText/CoreText.h>

#import "SPDFMacUIHelpers.h"
#import "SPDFMacMarkdownView.h"
#import "markdown/SPDFMarkdown.h"

static const CGFloat kSPDFMarkdownPageGap = 18.0;
static const CGFloat kSPDFMarkdownCanvasInset = 24.0;
static const CGFloat kSPDFMarkdownCodeControlHeight = 22.0;
static const CGFloat kSPDFMarkdownCodeControlHorizontalPadding = 9.0;

@implementation SPDFMacMarkdownPageCanvas {
    SPDFMarkdownPaginationPlan* _plan;
    NSAttributedString* _attributedString;
    NSUInteger _dragAnchor;
    BOOL _draggingSelection;
}

// Expose the plan and rendered string to the canvas categories (see
// SPDFMacMarkdownPageCanvasPrivate.h).
@synthesize plan = _plan;
@synthesize attributedString = _attributedString;

- (instancetype)initWithPaginationPlan:(SPDFMarkdownPaginationPlan*)plan
                      attributedString:(NSAttributedString*)attributedString {
    NSParameterAssert(plan);
    NSParameterAssert(attributedString);
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;
    _plan = plan;
    _attributedString = [attributedString copy];
    _selectedRange = NSMakeRange(0, 0);
    _searchRanges = @[];
    self.wantsLayer = YES;
    return self;
}

- (BOOL)isFlipped {
    return YES;
}
- (BOOL)isOpaque {
    return YES;
}
- (BOOL)acceptsFirstResponder {
    return YES;
}
- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}
- (NSUInteger)pageCount {
    return _plan.pages.count;
}

- (void)setSelectedRange:(NSRange)selectedRange {
    if (selectedRange.location == NSNotFound || NSMaxRange(selectedRange) > _attributedString.length)
        selectedRange = NSMakeRange(0, 0);
    if (NSEqualRanges(_selectedRange, selectedRange)) return;
    _selectedRange = selectedRange;
    [self setNeedsDisplay:YES];
    if (self.selectionChangedHandler) self.selectionChangedHandler(selectedRange);
}

- (void)setSearchRanges:(NSArray<NSValue*>*)searchRanges {
    _searchRanges = [searchRanges copy] ?: @[];
    [self setNeedsDisplay:YES];
}

- (SPDFMarkdownPageFragment*)codeControlFragmentOnPage:(SPDFMarkdownPage*)page blockIndex:(NSUInteger)blockIndex {
    for (SPDFMarkdownPageFragment* fragment in page.fragments) {
        if (fragment.blockIndex != blockIndex || fragment.itemIndex >= _plan.items.count) continue;
        SPDFMarkdownPaginationItem* item = _plan.items[fragment.itemIndex];
        if (item.kind == SPDFMarkdownBlockKindCode && !fragment.isContinuation) return fragment;
    }
    return nil;
}

- (NSString*)codeLanguageLabelForBlockIndex:(NSUInteger)blockIndex {
    for (SPDFMarkdownPage* page in _plan.pages) {
        for (SPDFMarkdownPageFragment* fragment in page.fragments) {
            if (fragment.blockIndex != blockIndex || !fragment.attributedRange.length ||
                NSMaxRange(fragment.attributedRange) > _attributedString.length)
                continue;
            NSString* identifier = [_attributedString attribute:SPDFMarkdownCodeLanguageAttribute
                                                        atIndex:fragment.attributedRange.location
                                                 effectiveRange:NULL];
            SPDFMarkdownLanguage* language =
                [SPDFMarkdownLanguageCatalog.sharedCatalog languageForFenceIdentifier:identifier];
            return language.displayName ?: (identifier.length ? identifier : @"Plain Text");
        }
    }
    return @"Plain Text";
}

- (NSRect)codeLanguageControlRectForFragment:(SPDFMarkdownPageFragment*)fragment pageFrame:(NSRect)pageFrame {
    NSString* label = [[self codeLanguageLabelForBlockIndex:fragment.blockIndex] stringByAppendingString:@"  ▾"];
    NSDictionary* attributes = @{NSFontAttributeName : [NSFont systemFontOfSize:11 weight:NSFontWeightMedium]};
    CGFloat width = ceil([label sizeWithAttributes:attributes].width) + kSPDFMarkdownCodeControlHorizontalPadding * 2.0;
    NSRect printable = _plan.configuration.printableRect;
    return NSMakeRect(NSMinX(pageFrame) + NSMinX(printable),
                      NSMinY(pageFrame) + NSMinY(printable) + fragment.pageYOffset + 2.0,
                      MIN(MAX(82.0, width), NSWidth(printable)), kSPDFMarkdownCodeControlHeight);
}

- (void)drawCodeLanguageControlsOnPage:(SPDFMarkdownPage*)page pageFrame:(NSRect)pageFrame {
    for (SPDFMarkdownPageFragment* fragment in page.fragments) {
        if (fragment.itemIndex >= _plan.items.count) continue;
        SPDFMarkdownPaginationItem* item = _plan.items[fragment.itemIndex];
        if (item.kind != SPDFMarkdownBlockKindCode || fragment.isContinuation) continue;
        NSRect controlRect = [self codeLanguageControlRectForFragment:fragment pageFrame:pageFrame];
        NSBezierPath* background = [NSBezierPath bezierPathWithRoundedRect:controlRect xRadius:6.0 yRadius:6.0];
        [NSColor.controlBackgroundColor setFill];
        [background fill];
        [NSColor.separatorColor setStroke];
        background.lineWidth = 0.75;
        [background stroke];
        NSString* label = [[self codeLanguageLabelForBlockIndex:fragment.blockIndex] stringByAppendingString:@"  ▾"];
        NSDictionary* attributes = @{
            NSFontAttributeName : [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName : NSColor.labelColor,
        };
        NSSize labelSize = [label sizeWithAttributes:attributes];
        NSPoint origin = NSMakePoint(NSMinX(controlRect) + kSPDFMarkdownCodeControlHorizontalPadding,
                                     floor(NSMidY(controlRect) - labelSize.height * 0.5));
        [label drawAtPoint:origin withAttributes:attributes];
    }
}

- (NSRect)frameForPageAtIndex:(NSUInteger)pageIndex {
    if (pageIndex >= self.pageCount) return NSZeroRect;
    NSSize paper = _plan.configuration.paperSize;
    CGFloat x = floor(MAX(kSPDFMarkdownCanvasInset, (NSWidth(self.bounds) - paper.width) * 0.5));
    CGFloat y = kSPDFMarkdownCanvasInset + pageIndex * (paper.height + kSPDFMarkdownPageGap);
    return NSMakeRect(x, y, paper.width, paper.height);
}

- (void)resizeForWidth:(CGFloat)width {
    NSSize paper = _plan.configuration.paperSize;
    CGFloat height = kSPDFMarkdownCanvasInset * 2.0 + self.pageCount * paper.height +
                     (self.pageCount ? self.pageCount - 1 : 0) * kSPDFMarkdownPageGap;
    self.frame = NSMakeRect(0, 0, MAX(width, paper.width + kSPDFMarkdownCanvasInset * 2.0), height);
}

- (NSInteger)pageIndexForVisibleRect:(NSRect)visibleRect {
    if (!self.pageCount) return -1;
    NSInteger first = MAX(0, (NSInteger)floor((NSMinY(visibleRect) - kSPDFMarkdownCanvasInset) /
                                              (_plan.configuration.paperSize.height + kSPDFMarkdownPageGap)));
    NSInteger last = MIN((NSInteger)self.pageCount - 1,
                         (NSInteger)ceil((NSMaxY(visibleRect) - kSPDFMarkdownCanvasInset) /
                                         (_plan.configuration.paperSize.height + kSPDFMarkdownPageGap)));
    NSInteger best = first;
    CGFloat bestArea = -1.0;
    for (NSInteger page = first; page <= last; ++page) {
        NSRect intersection = NSIntersectionRect(visibleRect, [self frameForPageAtIndex:(NSUInteger)page]);
        CGFloat area = NSWidth(intersection) * NSHeight(intersection);
        if (area > bestArea) {
            bestArea = area;
            best = page;
        }
    }
    return best;
}

- (void)drawRanges:(NSArray<NSValue*>*)ranges
             color:(NSColor*)color
            onPage:(SPDFMarkdownPage*)page
         pageFrame:(NSRect)pageFrame {
    if (!ranges.count) return;
    NSRect printable = _plan.configuration.printableRect;
    [color setFill];
    for (SPDFMarkdownPageFragment* fragment in page.fragments) {
        if (!fragment.attributedRange.length || NSMaxRange(fragment.attributedRange) > _attributedString.length)
            continue;
        NSAttributedString* lineString = [_attributedString attributedSubstringFromRange:fragment.attributedRange];
        CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)lineString);
        for (NSValue* value in ranges) {
            NSRange intersection = NSIntersectionRange(fragment.attributedRange, value.rangeValue);
            if (!intersection.length) continue;
            CFIndex start = (CFIndex)(intersection.location - fragment.attributedRange.location);
            CFIndex end = (CFIndex)(NSMaxRange(intersection) - fragment.attributedRange.location);
            CGFloat x0 = CTLineGetOffsetForStringIndex(line, start, NULL) * fragment.scale;
            CGFloat x1 = CTLineGetOffsetForStringIndex(line, end, NULL) * fragment.scale;
            NSRect highlight = NSMakeRect(NSMinX(pageFrame) + NSMinX(printable) + fragment.xOffset + MIN(x0, x1),
                                          NSMinY(pageFrame) + NSMinY(printable) + fragment.pageYOffset,
                                          MAX(2.0, fabs(x1 - x0)), fragment.height);
            NSRectFillUsingOperation(highlight, NSCompositingOperationSourceOver);
        }
        CFRelease(line);
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [(self.presentationMode ? NSColor.blackColor : NSColor.windowBackgroundColor) setFill];
    NSRectFill(dirtyRect);
    if (!self.pageCount) return;
    NSSize paper = _plan.configuration.paperSize;
    NSInteger first = MAX(
        0, (NSInteger)floor((NSMinY(dirtyRect) - kSPDFMarkdownCanvasInset) / (paper.height + kSPDFMarkdownPageGap)));
    NSInteger last = MIN((NSInteger)self.pageCount - 1, (NSInteger)ceil((NSMaxY(dirtyRect) - kSPDFMarkdownCanvasInset) /
                                                                        (paper.height + kSPDFMarkdownPageGap)));
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    for (NSInteger pageIndex = first; pageIndex <= last; ++pageIndex) {
        NSRect pageFrame = [self frameForPageAtIndex:(NSUInteger)pageIndex];
        if (!NSIntersectsRect(pageFrame, dirtyRect)) continue;
        NSShadow* shadow = [NSShadow new];
        shadow.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.22];
        shadow.shadowBlurRadius = 4.0;
        shadow.shadowOffset = NSMakeSize(0, -1);
        [NSGraphicsContext saveGraphicsState];
        [shadow set];
        [NSColor.whiteColor setFill];
        NSRectFill(pageFrame);
        [NSGraphicsContext restoreGraphicsState];
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, NSMinX(pageFrame), NSMaxY(pageFrame));
        CGContextScaleCTM(context, 1, -1);
        [_plan drawPageAtIndex:(NSUInteger)pageIndex attributedString:_attributedString inContext:context];
        CGContextRestoreGState(context);
        SPDFMarkdownPage* page = _plan.pages[(NSUInteger)pageIndex];
        [self drawRanges:_searchRanges
                   color:[NSColor.systemYellowColor colorWithAlphaComponent:0.32]
                  onPage:page
               pageFrame:pageFrame];
        if (_selectedRange.length)
            [self drawRanges:@[ [NSValue valueWithRange:_selectedRange] ]
                       color:[NSColor.selectedTextBackgroundColor colorWithAlphaComponent:0.42]
                      onPage:page
                   pageFrame:pageFrame];
        [self drawCodeLanguageControlsOnPage:page pageFrame:pageFrame];
    }
}

- (NSNumber*)codeLanguageBlockAtPoint:(NSPoint)point {
    NSSize paper = _plan.configuration.paperSize;
    NSInteger pageIndex =
        (NSInteger)floor((point.y - kSPDFMarkdownCanvasInset) / (paper.height + kSPDFMarkdownPageGap));
    if (pageIndex < 0 || pageIndex >= (NSInteger)self.pageCount) return nil;
    SPDFMarkdownPage* page = _plan.pages[(NSUInteger)pageIndex];
    NSRect pageFrame = [self frameForPageAtIndex:(NSUInteger)pageIndex];
    for (SPDFMarkdownPageFragment* fragment in page.fragments) {
        if (fragment.itemIndex >= _plan.items.count) continue;
        SPDFMarkdownPaginationItem* item = _plan.items[fragment.itemIndex];
        if (item.kind != SPDFMarkdownBlockKindCode || fragment.isContinuation) continue;
        if (NSPointInRect(point, [self codeLanguageControlRectForFragment:fragment pageFrame:pageFrame]))
            return @(fragment.blockIndex);
    }
    return nil;
}

- (NSUInteger)characterIndexAtPoint:(NSPoint)point {
    NSSize paper = _plan.configuration.paperSize;
    NSInteger pageIndex =
        (NSInteger)floor((point.y - kSPDFMarkdownCanvasInset) / (paper.height + kSPDFMarkdownPageGap));
    if (pageIndex < 0 || pageIndex >= (NSInteger)self.pageCount) return NSNotFound;
    NSRect pageFrame = [self frameForPageAtIndex:(NSUInteger)pageIndex];
    if (!NSPointInRect(point, pageFrame)) return NSNotFound;
    NSRect printable = _plan.configuration.printableRect;
    CGFloat localY = point.y - NSMinY(pageFrame) - NSMinY(printable);
    SPDFMarkdownPage* page = _plan.pages[(NSUInteger)pageIndex];
    for (SPDFMarkdownPageFragment* fragment in page.fragments) {
        if (localY < fragment.pageYOffset || localY > fragment.pageYOffset + fragment.height) continue;
        if (NSMaxRange(fragment.attributedRange) > _attributedString.length) continue;
        NSAttributedString* lineString = [_attributedString attributedSubstringFromRange:fragment.attributedRange];
        CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)lineString);
        CGFloat localX =
            (point.x - NSMinX(pageFrame) - NSMinX(printable) - fragment.xOffset) / MAX(fragment.scale, 0.001);
        CFIndex index = CTLineGetStringIndexForPosition(line, CGPointMake(localX, 0));
        CFRelease(line);
        if (index == kCFNotFound) return NSNotFound;
        return MIN(NSMaxRange(fragment.attributedRange), fragment.attributedRange.location + (NSUInteger)index);
    }
    return NSNotFound;
}

- (NSUInteger)attributedLocationNearestToPoint:(NSPoint)point {
    if (!self.pageCount || !_attributedString.length) return NSNotFound;
    NSSize paper = _plan.configuration.paperSize;
    NSInteger pageIndex =
        (NSInteger)floor((point.y - kSPDFMarkdownCanvasInset) / (paper.height + kSPDFMarkdownPageGap));
    pageIndex = MAX(0, MIN(pageIndex, (NSInteger)self.pageCount - 1));
    if (pageIndex + 1 < (NSInteger)self.pageCount) {
        NSRect currentPage = [self frameForPageAtIndex:(NSUInteger)pageIndex];
        NSRect nextPage = [self frameForPageAtIndex:(NSUInteger)pageIndex + 1];
        if (point.y > NSMaxY(currentPage) && fabs(point.y - NSMinY(nextPage)) < fabs(point.y - NSMaxY(currentPage)))
            pageIndex++;
    }

    SPDFMarkdownPageFragment* nearest = nil;
    CGFloat nearestDistance = CGFLOAT_MAX;
    SPDFMarkdownPage* page = _plan.pages[(NSUInteger)pageIndex];
    NSRect pageFrame = [self frameForPageAtIndex:(NSUInteger)pageIndex];
    NSRect printable = _plan.configuration.printableRect;
    for (SPDFMarkdownPageFragment* fragment in page.fragments) {
        if (!fragment.attributedRange.length || NSMaxRange(fragment.attributedRange) > _attributedString.length)
            continue;
        CGFloat fragmentY = NSMinY(pageFrame) + NSMinY(printable) + fragment.pageYOffset;
        CGFloat distance =
            point.y < fragmentY ? fragmentY - point.y : MAX(0.0, point.y - (fragmentY + fragment.height));
        if (distance < nearestDistance) {
            nearest = fragment;
            nearestDistance = distance;
        }
    }
    if (!nearest) return NSNotFound;

    NSAttributedString* lineString = [_attributedString attributedSubstringFromRange:nearest.attributedRange];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)lineString);
    CGFloat localX = (point.x - NSMinX(pageFrame) - NSMinX(printable) - nearest.xOffset) / MAX(nearest.scale, 0.001);
    CFIndex lineIndex = CTLineGetStringIndexForPosition(line, CGPointMake(localX, 0));
    CFRelease(line);
    if (lineIndex == kCFNotFound) lineIndex = localX <= 0.0 ? 0 : (CFIndex)nearest.attributedRange.length;
    return MIN(NSMaxRange(nearest.attributedRange), nearest.attributedRange.location + (NSUInteger)lineIndex);
}

- (NSRange)wordRangeAtIndex:(NSUInteger)index {
    if (index >= _attributedString.length) return NSMakeRange(index, 0);
    __block NSRange found = NSMakeRange(index, 0);
    [_attributedString.string
        enumerateSubstringsInRange:NSMakeRange(0, _attributedString.length)
                           options:NSStringEnumerationByWords
                        usingBlock:^(NSString* substring, NSRange substringRange, NSRange enclosingRange, BOOL* stop) {
                          (void)substring;
                          (void)enclosingRange;
                          if (NSLocationInRange(index, substringRange)) {
                              found = substringRange;
                              *stop = YES;
                          }
                        }];
    return found;
}

- (void)mouseDown:(NSEvent*)event {
    if (!NSApp.active) [NSApp activateIgnoringOtherApps:YES];
    if (!self.window.keyWindow) [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self];
    if (event.modifierFlags & NSEventModifierFlagControl) {
        [NSMenu popUpContextMenu:[self menuForEvent:event] withEvent:event forView:self];
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSNumber* languageBlock = [self codeLanguageBlockAtPoint:point];
    if (languageBlock) {
        _draggingSelection = NO;
        if (self.chooseCodeLanguageHandler) self.chooseCodeLanguageHandler(languageBlock.unsignedIntegerValue);
        return;
    }
    NSUInteger index = [self characterIndexAtPoint:point];
    if (index == NSNotFound) {
        self.selectedRange = NSMakeRange(0, 0);
        return;
    }
    _dragAnchor = index;
    _draggingSelection = YES;
    if (event.clickCount >= 3) {
        NSRange line = NSMakeRange(index, 0);
        [_attributedString.string getLineStart:&line.location end:&line.length contentsEnd:NULL forRange:line];
        line.length -= line.location;
        self.selectedRange = line;
        _draggingSelection = NO;
    } else if (event.clickCount == 2) {
        self.selectedRange = [self wordRangeAtIndex:index];
        _draggingSelection = NO;
    } else
        self.selectedRange = NSMakeRange(index, 0);
}

- (void)resetCursorRects {
    [super resetCursorRects];
    NSRect visible = self.visibleRect;
    if (!self.pageCount || NSIsEmptyRect(visible)) return;
    NSSize paper = _plan.configuration.paperSize;
    NSInteger first =
        MAX(0, (NSInteger)floor((NSMinY(visible) - kSPDFMarkdownCanvasInset) / (paper.height + kSPDFMarkdownPageGap)));
    NSInteger last = MIN((NSInteger)self.pageCount - 1, (NSInteger)ceil((NSMaxY(visible) - kSPDFMarkdownCanvasInset) /
                                                                        (paper.height + kSPDFMarkdownPageGap)));
    for (NSInteger pageIndex = first; pageIndex <= last; ++pageIndex) {
        SPDFMarkdownPage* page = _plan.pages[(NSUInteger)pageIndex];
        NSRect pageFrame = [self frameForPageAtIndex:(NSUInteger)pageIndex];
        for (SPDFMarkdownPageFragment* fragment in page.fragments) {
            if (fragment.itemIndex >= _plan.items.count) continue;
            SPDFMarkdownPaginationItem* item = _plan.items[fragment.itemIndex];
            if (item.kind == SPDFMarkdownBlockKindCode && !fragment.isContinuation)
                [self addCursorRect:[self codeLanguageControlRectForFragment:fragment pageFrame:pageFrame]
                             cursor:NSCursor.pointingHandCursor];
        }
    }
}

- (void)mouseDragged:(NSEvent*)event {
    if (!_draggingSelection) return;
    NSUInteger index = [self characterIndexAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (index == NSNotFound) return;
    NSUInteger start = MIN(_dragAnchor, index);
    self.selectedRange = NSMakeRange(start, MAX(_dragAnchor, index) - start);
    [self autoscroll:event];
}

- (void)mouseUp:(NSEvent*)event {
    BOOL activateLink = _draggingSelection && _selectedRange.length == 0 && event.clickCount == 1;
    _draggingSelection = NO;
    if (!activateLink) return;
    NSUInteger index = [self characterIndexAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (index == NSNotFound || index >= _attributedString.length) return;
    NSString* destination = [_attributedString attribute:SPDFMacMarkdownDestinationAttribute
                                                 atIndex:index
                                          effectiveRange:NULL];
    BOOL wiki = NO;
    if (!destination) {
        destination = [_attributedString attribute:SPDFMacMarkdownWikiDestinationAttribute
                                           atIndex:index
                                    effectiveRange:NULL];
        wiki = destination != nil;
    }
    if (destination.length && self.activateDestinationHandler) self.activateDestinationHandler(destination, wiki);
}

- (void)keyDown:(NSEvent*)event {
    NSScrollView* scrollView = self.enclosingScrollView;
    if (scrollView) {
        [scrollView keyDown:event];
        return;
    }
    [super keyDown:event];
}

- (void)copy:(id)sender {
    (void)sender;
    if (!_selectedRange.length || NSMaxRange(_selectedRange) > _attributedString.length) {
        NSBeep();
        return;
    }
    if (self.reader) {
        [self.reader copySelection:self];
        return;
    }
    NSPasteboard* pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:[_attributedString.string substringWithRange:_selectedRange] forType:NSPasteboardTypeString];
}

- (NSMenu*)menuForEvent:(NSEvent*)event {
    NSMenu* menu = self.reader ? [self.reader contextMenuForDocumentView:self event:event] : [NSMenu new];
    if (!self.reader) {
        NSMenuItem* copy = [[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@""];
        copy.target = self;
        copy.enabled = _selectedRange.length > 0;
        [menu addItem:copy];
    }
    NSUInteger index = [self characterIndexAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (index != NSNotFound && index < _attributedString.length) {
        NSNumber* kind = [_attributedString attribute:SPDFMarkdownBlockKindAttribute atIndex:index effectiveRange:NULL];
        NSNumber* block = [_attributedString attribute:SPDFMarkdownBlockIndexAttribute
                                               atIndex:index
                                        effectiveRange:NULL];
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
    return menu;
}

- (void)chooseCodeLanguage:(NSMenuItem*)sender {
    NSNumber* block = sender.representedObject;
    if (block && self.chooseCodeLanguageHandler) self.chooseCodeLanguageHandler(block.unsignedIntegerValue);
}

@end
