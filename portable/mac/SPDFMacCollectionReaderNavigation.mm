#import "SPDFMacCollectionReaderNavigation.h"
#import "SPDFMacCollectionAvailability.h"
#import "SPDFMacCollectionPalette.h"
#import "SPDFMacCollectionStore.h"
#import "SPDFMacCollectionWindow.h"
#import "SPDFMacCollectionStyle.h"
#import <objc/runtime.h>

static char versionInfoKey, versionIndicatorKey, navigationGenerationKey;
@interface SPDFCollectionVersionPill : NSButton
@end
@implementation SPDFCollectionVersionPill
- (NSSize)intrinsicContentSize {
    return NSMakeSize(MIN(330,ceil([self.title sizeWithAttributes:@{NSFontAttributeName:self.font}].width)+22),24);
}
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    NSRect bounds = NSInsetRect(self.bounds,.5,.5);
    NSBezierPath* shape = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:NSHeight(bounds)/2 yRadius:NSHeight(bounds)/2];
    [[NSColor.controlAccentColor colorWithAlphaComponent:self.highlighted ? .22 : .10] setFill]; [shape fill];
    [[NSColor.controlAccentColor colorWithAlphaComponent:.45] setStroke]; [shape stroke];
    NSMutableParagraphStyle* style = [NSMutableParagraphStyle new];
    style.alignment = NSTextAlignmentCenter; style.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSDictionary* attributes = @{NSFontAttributeName:self.font,NSForegroundColorAttributeName:NSColor.labelColor,
                                 NSParagraphStyleAttributeName:style};
    CGFloat height = [self.title sizeWithAttributes:attributes].height;
    [self.title drawInRect:NSMakeRect(10,(NSHeight(self.bounds)-height)/2,MAX(0,NSWidth(self.bounds)-20),height)
        withAttributes:attributes];
}
- (NSRect)focusRingMaskBounds { return self.bounds; }
- (void)drawFocusRingMask {
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:NSHeight(self.bounds)/2 yRadius:NSHeight(self.bounds)/2] fill];
}
@end
@implementation ShenzhenMacDelegate (SPDFMacCollectionReaderNavigation)
- (void)collectionNavigateDocument:(NSDictionary*)document version:(NSDictionary*)version
                             page:(NSUInteger)page query:(NSString*)query history:(BOOL)history {
    SPDFMacCollectionStore* store = SPDFMacCollectionStore.defaultStore;
    NSUInteger generation = [objc_getAssociatedObject(self,&navigationGenerationKey) unsignedIntegerValue]+1;
    objc_setAssociatedObject(self,&navigationGenerationKey,@(generation),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (history) {
        version = [document[@"versions"] lastObject];
        for (NSDictionary* candidate in document[@"versions"])
            if ([candidate[@"id"] isEqual:document[@"latestVersionID"]]) { version = candidate; break; }
    }
    // Latest is always the live document. Earlier indexed matches retain their immutable copy.
    BOOL original = (history || SPDFCollectionVersionIsLatest(document,version)) && SPDFCollectionOriginalAvailable(document);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSError* error = nil;
        NSURL* URL = original ? [NSURL fileURLWithPath:document[@"path"]] :
            [store materializeVersionID:version[@"id"] documentID:document[@"id"] error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([objc_getAssociatedObject(self,&navigationGenerationKey) unsignedIntegerValue] != generation) return;
            if (!URL) { if (error) [self->_window presentError:error]; return; }
            [self collectionOpenPath:URL.path archived:!original];
            if (![[self selectedTab].path isEqual:URL.path]) return;
            [self->_window makeKeyAndOrderFront:nil];
            if (history) [self showCollectionHistory:nil];
            else [self collectionNavigateResult:@{@"page":@(page ? page-1 : 0),@"query":query ?: @""}
                path:URL.path attempts:100];
        });
    });
}
- (void)collectionSetVersionInfo:(NSDictionary*)info forTab:(SPDFDocumentTab*)tab {
    if (!tab) return;
    objc_setAssociatedObject(tab,&versionInfoKey,info,OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self collectionUpdateVersionIndicator];
}
- (void)collectionRefreshVersionInfoForDocument:(NSDictionary*)document {
    if (![document[@"id"] length]) return;
    for (SPDFDocumentTab* tab in _tabs) {
        NSDictionary* info = objc_getAssociatedObject(tab,&versionInfoKey);
        if (![info[@"document"][@"id"] isEqual:document[@"id"]]) continue;
        NSDictionary* version = info[@"version"];
        for (NSDictionary* candidate in document[@"versions"])
            if ([candidate[@"id"] isEqual:version[@"id"]]) { version = candidate; break; }
        objc_setAssociatedObject(tab,&versionInfoKey,@{@"document":document,@"version":version ?: @{}},OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    [self collectionUpdateVersionIndicator];
}
- (void)collectionUpdateVersionIndicator {
    NSDictionary* info = objc_getAssociatedObject([self selectedTab],&versionInfoKey);
    NSButton* pill = objc_getAssociatedObject(self,&versionIndicatorKey);
    if (!info || !_toolbar || !_findRegexCheckbox) { pill.hidden = YES; return; }
    if (!pill) {
        pill = [SPDFCollectionVersionPill new]; pill.bordered = NO;
        pill.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        pill.target = self; pill.action = @selector(collectionLocateFromIndicator:);
        pill.identifier = @"CollectionVersionIndicator";
        pill.translatesAutoresizingMaskIntoConstraints = NO;
        [pill.widthAnchor constraintLessThanOrEqualToConstant:330].active = YES;
        pill.lineBreakMode = NSLineBreakByTruncatingMiddle;
        NSUInteger index = [_toolbar.arrangedSubviews indexOfObjectIdenticalTo:_findRegexCheckbox];
        if (index == NSNotFound) return;
        [_toolbar insertArrangedSubview:pill atIndex:index+1];
        objc_setAssociatedObject(self,&versionIndicatorKey,pill,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSDictionary* doc = info[@"document"], *version = info[@"version"];
    BOOL missing = !SPDFCollectionOriginalAvailable(doc);
    BOOL older = !SPDFCollectionVersionIsLatest(doc,version);
    NSDateFormatter* format = [NSDateFormatter new]; format.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    format.dateFormat = @"yyyy.MM.dd";
    NSString* date = [version[@"capturedAt"] isKindOfClass:NSNumber.class] ?
        [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:[version[@"capturedAt"] doubleValue]]] : @"date unavailable";
    NSString* title = older ? [@"Older version — " stringByAppendingString:date] : @"Collected copy";
    if (missing) title = [title stringByAppendingString:@" · Original missing"];
    pill.title = title; [pill invalidateIntrinsicContentSize]; pill.accessibilityLabel = title; pill.hidden = NO;
    pill.enabled = missing;
    pill.toolTip = missing ? @"This saved copy has no available original. Click to locate it." : @"Read-only saved version";
}
- (void)collectionLocateFromIndicator:(id)sender {
    (void)sender;
    NSDictionary* info = objc_getAssociatedObject([self selectedTab],&versionInfoKey);
    NSDictionary* doc = info[@"document"];
    if (!doc || SPDFCollectionOriginalAvailable(doc)) return;
    SPDFMacCollectionStore* store = SPDFMacCollectionStore.defaultStore;
    SPDFDocumentTab* tab = [self selectedTab];
    SPDFMacLocateCollectionOriginal(store,doc[@"id"],_window, ^(NSString* path) {
        [self collectionOpenPath:path archived:NO];
    }, ^(NSString* path) {
        NSDictionary* updated = [store documentForPath:path];
        if (updated) [self collectionSetVersionInfo:@{@"document":updated,@"version":info[@"version"]} forTab:tab];
        [self collectionRefreshHistory];
    });
}
@end
