#import "SPDFMacCollectionWindowPrivate.h"
#import "SPDFMacCollectionStyle.h"
#import "SPDFMacMarkdownPrinting.h"
#import "markdown/SPDFMarkdownDocument.h"
#import "SPDFMacCollectionThumbnail.h"
#import "SPDFMacPassword.h"

@interface SPDFCollectionThumbnailItem : NSCollectionViewItem
@property(nonatomic) NSButton* historyButton;
@end
@interface SPDFCollectionThumbnailGrid : NSCollectionView
@end
@implementation SPDFCollectionThumbnailGrid
- (BOOL)isAccessibilityElement { return YES; }
- (NSString*)accessibilityRole { return NSAccessibilityGridRole; }
- (NSString*)accessibilityLabel { return @"Collection thumbnails"; }
- (BOOL)isAccessibilityEnabled { return YES; }
- (NSArray*)accessibilityChildren {
    NSArray<NSCollectionViewItem*>* items = [self.visibleItems sortedArrayUsingComparator:
        ^NSComparisonResult(NSCollectionViewItem* a, NSCollectionViewItem* b) {
            return [[self indexPathForItem:a] compare:[self indexPathForItem:b]];
        }];
    NSMutableArray* children = [NSMutableArray arrayWithCapacity:items.count];
    for (NSCollectionViewItem* item in items) if (item.view.isAccessibilityElement) [children addObject:item.view];
    return children;
}
- (NSArray*)accessibilitySelectedChildren {
    NSMutableArray* children = [NSMutableArray array];
    for (NSCollectionViewItem* item in self.visibleItems) if (item.isSelected) [children addObject:item.view];
    return children;
}
@end
@interface SPDFCollectionThumbnailView : NSView
@property(nonatomic, weak) SPDFCollectionThumbnailItem* item;
@property(nonatomic, copy) NSString* caption;
@end
@implementation SPDFCollectionThumbnailView
- (BOOL)isAccessibilityElement { return YES; }
- (NSString*)accessibilityRole { return NSAccessibilityButtonRole; }
- (NSString*)accessibilityLabel { return self.caption; }
- (BOOL)isAccessibilityEnabled { return YES; }
- (BOOL)isAccessibilitySelected { return self.item.isSelected; }
- (BOOL)accessibilityPerformPress {
    NSView* ancestor = self.superview;
    while (ancestor && ![ancestor isKindOfClass:NSCollectionView.class]) ancestor = ancestor.superview;
    NSCollectionView* collection = (id)ancestor;
    NSIndexPath* path = self.item ? [collection indexPathForItem:self.item] : nil;
    if (!collection || !path) return NO;
    NSSet* paths = [NSSet setWithObject:path];
    [collection selectItemsAtIndexPaths:paths scrollPosition:NSCollectionViewScrollPositionNone];
    // Programmatic collection selection does not notify the delegate. Route
    // the accessibility action through the same table/details update as a click.
    if ([collection.delegate respondsToSelector:@selector(collectionView:didSelectItemsAtIndexPaths:)])
        [collection.delegate collectionView:collection didSelectItemsAtIndexPaths:paths];
    return YES;
}
@end
@implementation SPDFCollectionThumbnailItem
- (void)loadView {
    SPDFCollectionThumbnailView* root = [[SPDFCollectionThumbnailView alloc] initWithFrame:NSMakeRect(0,0,180,238)];
    root.item = self; self.view = root;
    self.view.wantsLayer = YES;
    self.view.layer.cornerRadius = 9;
    NSImageView* imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(9,86,162,143)];
    [self.view addSubview:imageView]; self.imageView = imageView;
    self.imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    NSTextField* caption = [NSTextField wrappingLabelWithString:@""];
    caption.frame = NSMakeRect(9,8,162,50);
    caption.font = [NSFont systemFontOfSize:11];
    caption.textColor = NSColor.labelColor;
    caption.drawsBackground = NO;
    caption.maximumNumberOfLines = 3;
    caption.lineBreakMode = NSLineBreakByTruncatingMiddle;
    caption.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:caption];
    self.historyButton = SPDFCollectionButton(@"History",nil,nil,@"normal");
    self.historyButton.frame = NSMakeRect(108,58,64,24); [self.view addSubview:self.historyButton];
    self.textField = caption; // NSCollectionViewItem outlets are weak; the view owns it first.
    [NSLayoutConstraint activateConstraints:@[
        [caption.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:9],
        [caption.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-9],
        [caption.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:8],
        [caption.heightAnchor constraintEqualToConstant:50]]];
}
- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    self.view.layer.backgroundColor = (selected ? [NSColor.controlAccentColor colorWithAlphaComponent:.16]
                                              : NSColor.controlBackgroundColor).CGColor;
    self.view.layer.borderWidth = selected ? 2 : 1;
    self.view.layer.borderColor = (selected ? NSColor.controlAccentColor : NSColor.separatorColor).CGColor;
    NSAccessibilityPostNotification(self.view,NSAccessibilityValueChangedNotification);
}
@end

@interface SPDFMacCollectionWindow (GridProtocols) <NSCollectionViewDataSource, NSCollectionViewDelegate>
@end
@implementation SPDFMacCollectionWindow (Grid)
- (void)installGridInView:(NSView*)host {
    self.thumbnailCache = [NSCache new]; self.thumbnailCache.totalCostLimit = 24*1024*1024;
    self.pendingThumbnails = [NSMutableSet set];
    self.thumbnailQueue = [NSOperationQueue new]; self.thumbnailQueue.maxConcurrentOperationCount = 1;
    self.thumbnailQueue.qualityOfService = NSQualityOfServiceUtility;
    self.grid = [SPDFCollectionThumbnailGrid new];
    self.grid.dataSource = self; self.grid.delegate = self;
    self.grid.selectable = YES; self.grid.allowsMultipleSelection = YES;
    self.grid.backgroundColors = @[SPDFCollectionColor(@"window")];
    NSCollectionViewFlowLayout* flow = [NSCollectionViewFlowLayout new];
    flow.itemSize = NSMakeSize(180,238); flow.minimumInteritemSpacing = 10; flow.minimumLineSpacing = 12;
    flow.sectionInset = NSEdgeInsetsMake(12,12,12,12); self.grid.collectionViewLayout = flow;
    [self.grid registerClass:SPDFCollectionThumbnailItem.class forItemWithIdentifier:@"thumbnail"];
    NSClickGestureRecognizer* doubleClick = [[NSClickGestureRecognizer alloc] initWithTarget:self action:@selector(preview:)];
    doubleClick.numberOfClicksRequired = 2; [self.grid addGestureRecognizer:doubleClick];
    self.gridScroll = [NSScrollView new]; self.gridScroll.hasVerticalScroller = YES;
    self.gridScroll.documentView = self.grid; self.gridScroll.borderType = NSNoBorder;
    self.gridScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:self.gridScroll];
    [NSLayoutConstraint activateConstraints:@[
        [self.gridScroll.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [self.gridScroll.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [self.gridScroll.topAnchor constraintEqualToAnchor:host.topAnchor],
        [self.gridScroll.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]]];
}
- (void)reloadGrid {
    BOOL grid = self.layoutPicker.indexOfSelectedItem == 1 && !self.search.stringValue.length;
    self.listScroll.hidden = grid; self.gridScroll.hidden = !grid;
    [self.grid reloadData];
    [self synchronizeGridSelection];
    NSAccessibilityPostNotification(self.grid,NSAccessibilityLayoutChangedNotification);
}
- (NSInteger)collectionView:(NSCollectionView*)view numberOfItemsInSection:(NSInteger)section {
    (void)view; (void)section; return self.rows.count;
}
- (NSCollectionViewItem*)collectionView:(NSCollectionView*)view itemForRepresentedObjectAtIndexPath:(NSIndexPath*)indexPath {
    SPDFCollectionThumbnailItem* item = (id)[view makeItemWithIdentifier:@"thumbnail" forIndexPath:indexPath];
    // Registered collection items can reach the data source before AppKit asks
    // for their view. Load it here so the first caption is not sent to nil.
    (void)item.view;
    NSDictionary* row = self.rows[indexPath.item];
    NSDictionary* doc = row[@"document"], *version = row[@"version"];
    NSString* key = [NSString stringWithFormat:@"%@/%@",doc[@"id"],version[@"id"] ?: @""];
    item.representedObject = key;
    item.historyButton.target = self; item.historyButton.action = @selector(historyForRow:);
    item.historyButton.tag = indexPath.item;
    NSString* date = version[@"capturedAt"] ? [NSDateFormatter localizedStringFromDate:
        [NSDate dateWithTimeIntervalSince1970:[version[@"capturedAt"] doubleValue]]
        dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle] : @"No protected copy";
    NSString* filename = [doc[@"path"] lastPathComponent];
    if (!filename.length) filename = doc[@"title"] ?: @"Document";
    NSString* caption = [NSString stringWithFormat:@"%@%@\n%@",[version[@"keep"] boolValue] ? @"★ " : @"",
        filename,date];
    item.textField.stringValue = caption;
    item.view.toolTip = doc[@"path"];
    SPDFCollectionThumbnailView* itemView = (id)item.view;
    itemView.caption = caption;
    itemView.accessibilityHelp = doc[@"path"];
    item.imageView.image = [self.thumbnailCache objectForKey:key] ?: [NSImage imageWithSystemSymbolName:
        @"doc" accessibilityDescription:@"Document preview"];
    if (self.layoutPicker.indexOfSelectedItem == 1 && version[@"id"]) [self requestThumbnail:row key:key];
    return item;
}
- (void)requestThumbnail:(NSDictionary*)row key:(NSString*)key {
    if ([self.thumbnailCache objectForKey:key] || [self.pendingThumbnails containsObject:key]) return;
    [self.pendingThumbnails addObject:key];
    SPDFMacCollectionStore* store = self.store;
    __weak SPDFMacCollectionWindow* weakSelf = self;
    [self.thumbnailQueue addOperationWithBlock:^{
        @autoreleasepool {
            NSDictionary* version = row[@"version"];
            NSError* error = nil;
            NSURL* URL = [store materializeVersionID:version[@"id"] documentID:row[@"document"][@"id"] error:&error];
            NSImage* image = nil;
            if (URL && [@[@"md",@"markdown",@"mdown"] containsObject:URL.pathExtension.lowercaseString]) {
                SPDFMarkdownDocument* markdown = [SPDFMarkdownDocument documentWithURL:URL options:nil error:&error];
                SPDFMarkdownPageConfiguration* config = markdown.authoredPageConfiguration ?: [SPDFMarkdownPageConfiguration A4PortraitConfiguration];
                SPDFMarkdownPaginationPlan* plan = [markdown paginationPlanForConfiguration:config];
                NSBitmapImageRep* bitmap = [SPDFMacMarkdownPrintAdapter imageRepForPageAtIndex:MIN(MAX(0,[row[@"selectedPage"] integerValue]-1),(NSInteger)plan.pages.count-1) paginationPlan:plan
                    attributedString:markdown.renderedDocument.attributedString scale:MIN(300/config.paperSize.width,300/config.paperSize.height)];
                if (bitmap) { image = [[NSImage alloc] initWithSize:bitmap.size]; [image addRepresentation:bitmap]; }
            } else if (URL) {
                image = SPDFCollectionPDFThumbnail(URL,[row[@"selectedPage"] integerValue],^(PDFDocument* pdf) {
                    // Resolve lazily: standalone Collection UI tests need no core/password runtime.
                    SPDFPasswordCredentialStore* credentials = [NSClassFromString(@"SPDFPasswordCredentialStore") sharedStore];
                    for (NSString* path in @[URL.path,row[@"document"][@"path"] ?: @""]) {
                        SPDFPasswordCredential* credential = [credentials credentialForSourcePath:path];
                        [credential withUTF8Password:^(const char* password) {
                            [pdf unlockWithPassword:[NSString stringWithUTF8String:password]];
                        }];
                        if (!pdf.isLocked) break;
                    }
                },&error);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                SPDFMacCollectionWindow* owner = weakSelf;
                if (!owner) return;
                [owner.pendingThumbnails removeObject:key];
                if (image) [owner.thumbnailCache setObject:image forKey:key cost:260*300*4];
                for (NSInteger index = 0; index < (NSInteger)owner.rows.count; index++) {
                    NSView* cell = [owner.table viewAtColumn:0 row:index makeIfNecessary:NO];
                    for (NSView* child in cell.subviews) if ([child isKindOfClass:NSImageView.class] && [child.identifier isEqual:key]) {
                        if (image) ((NSImageView*)child).image = image;
                        else child.toolTip = error.localizedDescription ?: @"Preview unavailable; open the saved copy.";
                    }
                }
                for (NSCollectionViewItem* item in owner.grid.visibleItems) if ([item.representedObject isEqual:key]) {
                    if (image) item.imageView.image = image;
                    else item.imageView.toolTip = error.localizedDescription ?: @"Preview unavailable; the archived copy can still be opened.";
                }
            });
        }
    }];
}
- (void)collectionView:(NSCollectionView*)view didSelectItemsAtIndexPaths:(NSSet<NSIndexPath*>*)paths {
    (void)paths; [self selectGridRows:view];
}
- (void)collectionView:(NSCollectionView*)view didDeselectItemsAtIndexPaths:(NSSet<NSIndexPath*>*)paths {
    (void)paths; [self selectGridRows:view];
}
- (void)selectGridRows:(NSCollectionView*)view {
    NSMutableIndexSet* rows = [NSMutableIndexSet indexSet];
    for (NSIndexPath* index in view.selectionIndexPaths) [rows addIndex:index.item];
    if (![rows isEqual:self.table.selectedRowIndexes]) [self.table selectRowIndexes:rows byExtendingSelection:NO];
    NSAccessibilityPostNotification(view,NSAccessibilitySelectedChildrenChangedNotification);
    [self updateDetails];
}
- (void)synchronizeGridSelection {
    NSMutableSet* paths = [NSMutableSet set];
    [self.table.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL* stop) {
        (void)stop; if (index < self.rows.count) [paths addObject:[NSIndexPath indexPathForItem:index inSection:0]];
    }];
    if (![paths isEqual:self.grid.selectionIndexPaths]) self.grid.selectionIndexPaths = paths;
}
@end
