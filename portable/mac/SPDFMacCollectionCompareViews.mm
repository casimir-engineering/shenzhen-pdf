#import "SPDFMacCollectionCompareViews.h"

@implementation SPDFCollectionCompareRail
- (BOOL)isFlipped { return YES; }
- (BOOL)isAccessibilityElement { return YES; }
- (NSString*)accessibilityRole { return NSAccessibilityGroupRole; }
- (NSString*)accessibilityLabel { return @"Change markers. Use Previous change and Next change to navigate."; }
- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor separatorColor] setFill];
    NSRectFill(NSInsetRect(self.bounds, 5, 0));
    [self.markerColor setFill];
    for (NSNumber* slot in self.slots) {
        CGFloat y = slot.doubleValue / MAX((NSUInteger)1, self.slotCount) * self.bounds.size.height;
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(2, y-2, self.bounds.size.width-4, 4)
                                       xRadius:2 yRadius:2] fill];
    }
}
- (void)mouseDown:(NSEvent*)event {
    if (!self.slots.count) return;
    CGFloat fraction = [self convertPoint:event.locationInWindow fromView:nil].y / MAX(1,self.bounds.size.height);
    CGFloat nearest = 0;
    CGFloat distance = CGFLOAT_MAX;
    for (NSNumber* slot in self.slots) {
        CGFloat delta = fabs(slot.doubleValue/MAX((NSUInteger)1,self.slotCount)-fraction);
        if (delta < distance) { nearest = slot.doubleValue; distance = delta; }
    }
    if (self.jump) self.jump(nearest);
}
@end

static NSButton* button(NSString* title, id target, SEL action) {
    NSButton* control = [NSButton buttonWithTitle:title target:target action:action];
    control.bezelStyle = NSBezelStyleRounded;
    return control;
}

@implementation SPDFCollectionComparePane {
    NSTextField* _pageField;
    NSTextField* _pageCount;
    NSTextField* _searchCount;
    NSSearchField* _search;
    NSMutableArray<PDFSelection*>* _matches;
    BOOL _finding;
    NSInteger _matchIndex;
    NSString* _lastQuery;
    NSScrollView* _observedScroll;
    BOOL _navigating;
    NSUInteger _navigationGeneration;
    PDFDestination* _explicitDestination;
}
- (instancetype)initWithLabel:(NSString*)label removed:(BOOL)removed {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    NSTextField* title = [NSTextField labelWithString:label];
    title.font = [NSFont boldSystemFontOfSize:13];
    title.lineBreakMode = NSLineBreakByTruncatingMiddle;
    title.toolTip = label;
    NSTextField* badge = [NSTextField labelWithString:removed ? @"OLD · Read-only · − Removed" : @"NEW · Read-only · + Added"];
    badge.textColor = removed ? [NSColor colorWithSRGBRed:.72 green:.17 blue:.18 alpha:1]
                             : [NSColor colorWithSRGBRed:.08 green:.43 blue:.22 alpha:1];
    _pageField = [NSTextField textFieldWithString:@"1"];
    _pageField.target = self; _pageField.action = @selector(pageEntered:);
    _pageField.alignment = NSTextAlignmentCenter;
    [_pageField setAccessibilityLabel:@"Comparison page"];
    [_pageField.widthAnchor constraintEqualToConstant:42].active = YES;
    _pageCount = [NSTextField labelWithString:@"/ —"];
    NSStackView* navigation = [NSStackView stackViewWithViews:@[
        button(@"‹", self, @selector(previous:)), _pageField, _pageCount,
        button(@"›", self, @selector(next:)), button(@"−", self, @selector(zoomOut:)),
        button(@"+", self, @selector(zoomIn:)), button(@"Fit", self, @selector(fit:))]];
    navigation.spacing = 4;
    navigation.detachesHiddenViews = NO;
    _search = [NSSearchField new];
    _search.placeholderString = @"Find in this version";
    _search.target = self; _search.action = @selector(search:);
    _search.sendsSearchStringImmediately = NO;
    _search.sendsWholeSearchString = YES;
    [_search.widthAnchor constraintGreaterThanOrEqualToConstant:120].active = YES;
    _searchCount = [NSTextField labelWithString:@""];
    NSStackView* searchRow = [NSStackView stackViewWithViews:@[_search, _searchCount]];
    self.reader = [PDFView new];
    self.reader.displayMode = kPDFDisplaySinglePageContinuous;
    self.reader.displayBox = kPDFDisplayBoxMediaBox;
    self.reader.autoScales = YES;
    self.reader.minScaleFactor = .15;
    self.reader.maxScaleFactor = 6;
    self.reader.backgroundColor = [NSColor windowBackgroundColor];
    self.reader.displaysPageBreaks = YES;
    self.rail = [SPDFCollectionCompareRail new];
    self.rail.markerColor = badge.textColor;
    self.rail.toolTip = removed ? @"Removed content — click a marker" : @"Added content — click a marker";
    __weak SPDFCollectionComparePane* weakSelf = self;
    self.rail.jump = ^(CGFloat slot) { [weakSelf goToSlot:(NSUInteger)slot]; };
    NSStackView* pageRow = [NSStackView stackViewWithViews:@[self.reader, self.rail]];
    pageRow.distribution = NSStackViewDistributionFill;
    pageRow.alignment = NSLayoutAttributeHeight;
    pageRow.spacing = 0;
    [self.rail.widthAnchor constraintEqualToConstant:14].active = YES;
    NSStackView* stack = [NSStackView stackViewWithViews:@[title,badge,navigation,searchRow,pageRow]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 7;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [title.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [searchRow.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [pageRow.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [self.reader.heightAnchor constraintEqualToAnchor:pageRow.heightAnchor],
        [self.rail.heightAnchor constraintEqualToAnchor:pageRow.heightAnchor]]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(pageChanged:)
                                               name:PDFViewPageChangedNotification object:self.reader];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scaleChanged:)
                                               name:PDFViewScaleChangedNotification object:self.reader];
    return self;
}
- (void)dealloc { [self.reader.document cancelFindString]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)installDocument:(PDFDocument*)document {
    self.reader.document = document;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(foundMatch:)
                                               name:PDFDocumentDidFindMatchNotification object:document];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(searchFinished:)
                                               name:PDFDocumentDidEndFindNotification object:document];
    _observedScroll = self.reader.documentView.enclosingScrollView;
    _observedScroll.contentView.postsBoundsChangedNotifications = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scrolled:)
                                               name:NSViewBoundsDidChangeNotification object:_observedScroll.contentView];
    [self pageChanged:nil];
}
- (NSUInteger)currentSlot { return MAX(1,_pageField.integerValue)-1; }
- (PDFDestination*)navigationDestination {
    if (_explicitDestination) return _explicitDestination;
    PDFDestination* current = self.reader.currentDestination;
    PDFPage* page = self.reader.currentPage;
    if (!current || !page) return current;
    // PDFKit's top-left destination can name the preceding, partly visible
    // page. Link the page represented by the counter while preserving position.
    NSPoint point = [self.reader convertPoint:current.point fromPage:current.page];
    point = [self.reader convertPoint:point toPage:page];
    return [[PDFDestination alloc] initWithPage:page atPoint:point];
}
- (void)updateCounterForSlot:(NSUInteger)slot {
    if (slot == NSNotFound) slot = 0;
    _pageField.stringValue = [NSString stringWithFormat:@"%lu",slot+1];
    NSInteger source = slot < self.sourcePages.count ? self.sourcePages[slot].integerValue : (NSInteger)slot;
    _pageCount.stringValue = [NSString stringWithFormat:@"/ %lu · %@",self.reader.document.pageCount,
        source < 0 ? @"No counterpart" : [NSString stringWithFormat:@"source %ld",source+1]];
}
- (void)pageChanged:(NSNotification*)note {
    if (_navigating) return;
    [self updateCounterForSlot:[self.reader.document indexForPage:self.reader.currentPage]];
    if (note && self.navigationChanged) self.navigationChanged(self);
}
- (void)scrolled:(NSNotification*)note {
    if (_navigating) return;
    NSUInteger generation = ++_navigationGeneration;
    // Bounds notifications arrive before PDFKit settles currentPage. Coalesce
    // wheel/trackpad updates and read it on the next main-queue turn instead.
    __weak SPDFCollectionComparePane* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        SPDFCollectionComparePane* pane = weakSelf;
        if (!pane || generation != pane->_navigationGeneration) return;
        [pane pageChanged:nil];
        if (pane.navigationChanged) pane.navigationChanged(pane);
    });
}
- (void)scaleChanged:(NSNotification*)note { if (self.zoomChanged) self.zoomChanged(self); }
- (void)goToDestination:(PDFDestination*)destination {
    NSUInteger slot = [self.reader.document indexForPage:destination.page];
    if (slot == NSNotFound) return;
    ++_navigationGeneration;
    _navigating = YES;
    [self.reader goToDestination:destination];
    _navigating = NO;
    // A destination jump need not emit PDFViewPageChangedNotification. Publish
    // the requested aligned slot explicitly for both its counter and its peer.
    [self updateCounterForSlot:slot];
    _explicitDestination = destination;
    if (self.navigationChanged) self.navigationChanged(self);
    _explicitDestination = nil;
}
- (void)goToSlot:(NSUInteger)slot {
    if (!self.reader.document.pageCount) return;
    PDFPage* page = [self.reader.document pageAtIndex:MIN(slot,self.reader.document.pageCount-1)];
    NSRect box = [page boundsForBox:self.reader.displayBox];
    [self goToDestination:[[PDFDestination alloc] initWithPage:page atPoint:NSMakePoint(NSMinX(box),NSMaxY(box))]];
}
- (void)previous:(id)sender { [self goToSlot:self.currentSlot ? self.currentSlot-1 : 0]; }
- (void)next:(id)sender { [self goToSlot:self.currentSlot+1]; }
- (void)pageEntered:(id)sender { [self goToSlot:MAX(1,_pageField.integerValue)-1]; }
- (void)zoomOut:(id)sender { [self.reader zoomOut:sender]; }
- (void)zoomIn:(id)sender { [self.reader zoomIn:sender]; }
- (void)fit:(id)sender { self.reader.autoScales = YES; }
- (void)search:(id)sender {
    NSString* query = _search.stringValue;
    if (![query isEqual:_lastQuery]) {
        _finding = NO;
        [self.reader.document cancelFindString];
        _lastQuery = query.copy;
        _matches = [NSMutableArray array];
        _matchIndex = -1;
        [self.reader clearSelection];
        if (query.length) {
            _finding = YES;
            _searchCount.stringValue = @"Searching…";
            [self.reader.document beginFindString:query withOptions:NSCaseInsensitiveSearch];
        } else _searchCount.stringValue = @"";
        return;
    }
    [self selectNextMatch];
}
- (void)foundMatch:(NSNotification*)note {
    if (!_finding) return;
    PDFSelection* match = note.userInfo[PDFDocumentFoundSelectionKey];
    if (match && _matches.count < 2000) [_matches addObject:match];
    if (_matches.count == 2000) [self.reader.document cancelFindString];
}
- (void)searchFinished:(NSNotification*)note {
    if (!_finding) return;
    _finding = NO;
    [self selectNextMatch];
}
- (void)selectNextMatch {
    if (_matches.count) {
        _matchIndex = (_matchIndex + 1) % _matches.count;
        PDFSelection* match = _matches[_matchIndex];
        match.color = NSColor.systemYellowColor;
        [self.reader setCurrentSelection:match animate:YES];
        [self.reader scrollSelectionToVisible:self];
        _searchCount.stringValue = [NSString stringWithFormat:@"%ld / %lu%@",_matchIndex+1,_matches.count,
            _matches.count == 2000 ? @"+" : @""];
    } else if (!_finding) {
        [self.reader clearSelection];
        _searchCount.stringValue = _lastQuery.length ? @"No matches" : @"";
    }
}
@end
