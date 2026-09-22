#import "SPDFMacTabGroups.h"
#import "SPDFMacModels.h"

@implementation SPDFTabGroup
+ (instancetype)generalGroup {
    SPDFTabGroup* group = [[self alloc] init];
    group.identifier = @"general";
    group.colorName = @"Gray";
    return group;
}
+ (instancetype)groupWithColor:(NSString*)color {
    SPDFTabGroup* group = [[self alloc] init];
    group.identifier = NSUUID.UUID.UUIDString;
    group.colorName = [spdf_tab_group_colors() containsObject:color] ? color : @"Purple";
    return group;
}
- (BOOL)general { return [self.identifier isEqualToString:@"general"]; }
- (NSString*)displayName { return self.name.length ? self.name : self.general ? @"General" : self.colorName; }
- (NSDictionary*)dictionary {
    return @{@"id": self.identifier ?: @"", @"name": self.name ?: @"", @"color": self.colorName ?: @"Purple",
             @"collapsed": @(self.collapsed), @"lastUsedPath": self.lastUsedPath ?: @""};
}
+ (instancetype)fromDictionary:(id)value {
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    NSString* identifier = value[@"id"];
    if (![identifier isKindOfClass:NSString.class] || !identifier.length) return nil;
    SPDFTabGroup* group = [[self alloc] init];
    group.identifier = identifier;
    NSString* color = value[@"color"];
    group.colorName = [color isKindOfClass:NSString.class] && [spdf_tab_group_colors() containsObject:color]
        ? color : @"Purple";
    if (group.general) group.colorName = @"Gray";
    if ([value[@"name"] isKindOfClass:NSString.class]) group.name = value[@"name"];
    if ([value[@"lastUsedPath"] isKindOfClass:NSString.class]) group.lastUsedPath = value[@"lastUsedPath"];
    id collapsed = value[@"collapsed"];
    group.collapsed = [collapsed respondsToSelector:@selector(boolValue)] && [collapsed boolValue];
    return group;
}
- (id)copyWithZone:(NSZone*)zone { (void)zone; return [SPDFTabGroup fromDictionary:self.dictionary]; }
@end

NSArray<NSString*>* spdf_tab_group_colors(void) {
    // Function-local initialization is intentional: an ungrouped launch never
    // constructs the palette or generates an identifier.
    static NSArray* colors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ colors = @[@"Purple", @"Green", @"Blue", @"Teal", @"Rose", @"Coral",
                                      @"Amber", @"Indigo", @"Plum", @"Slate"]; });
    return colors;
}
static NSColor* RGB(unsigned rgb) {
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0
                              blue:(rgb & 255) / 255.0 alpha:1];
}
NSColor* spdf_tab_group_accent(NSString* color) {
    NSArray* names = spdf_tab_group_colors();
    NSUInteger index = [names indexOfObject:color ?: @""];
    const unsigned values[] = {0xbca1dc, 0x95c8b4, 0x9bbfe0, 0x87c7cc, 0xdaa2bd,
                               0xe4ad98, 0xd8bf86, 0xa5afe1, 0xc0a0c4, 0xa8bbc8};
    return RGB(index < names.count ? values[index] : 0xb5b5be);
}
NSImage* spdf_tab_group_swatch_image(NSString* color) {
    NSString* label = color.length ? color : @"Gray";
    return [NSImage imageWithSize:NSMakeSize(12, 12) flipped:NO drawingHandler:^BOOL(NSRect rect) {
      [spdf_tab_group_accent(label) setFill];
      [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 1, 1)] fill];
      return YES;
    }];
}
NSColor* spdf_tab_group_selected_fill(NSString* color, BOOL dark) {
    if (!color.length || [color isEqualToString:@"Gray"]) return RGB(dark ? 0x16161b : 0xe3e3e9);
    NSUInteger index = [spdf_tab_group_colors() indexOfObject:color ?: @""];
    // Aqua uses labelColor (black) for every tab title, so selected fills are
    // pale tints. Dark Aqua keeps the deep fills below for white labelColor.
    const unsigned light[] = {0xe8dbf6, 0xd8eee5, 0xdbeaf7, 0xd6edef, 0xf3dce7,
                              0xf5e0d8, 0xefe6ce, 0xdfe2f7, 0xeadceb, 0xdde7ed};
    const unsigned night[] = {0x30203f, 0x153b2c, 0x1d334c, 0x17393e, 0x482337,
                              0x492a1e, 0x443412, 0x292d4f, 0x402944, 0x283844};
    return RGB(index < spdf_tab_group_colors().count ? (dark ? night[index] : light[index])
                                                    : (dark ? 0x16161b : 0x41414a));
}
NSString* spdf_tab_group_unused_color(NSArray<SPDFDocumentTab*>* tabs) {
    NSMutableArray* available = [spdf_tab_group_colors() mutableCopy];
    for (SPDFDocumentTab* tab in tabs) if (tab.group.colorName) [available removeObject:tab.group.colorName];
    if (!available.count) available = [spdf_tab_group_colors() mutableCopy];
    return available[arc4random_uniform((uint32_t)available.count)];
}
NSArray<SPDFDocumentTab*>* spdf_tab_group_members(NSArray<SPDFDocumentTab*>* tabs, SPDFTabGroup* group) {
    NSMutableArray* members = [NSMutableArray array];
    if (!group) return members;
    for (SPDFDocumentTab* tab in tabs)
        if ([tab.group.identifier isEqualToString:group.identifier]) [members addObject:tab];
    return members;
}
void spdf_tab_groups_normalize(NSMutableArray<SPDFDocumentTab*>* tabs) {
    BOOL hasCustom = NO;
    BOOL hasAny = NO;
    for (SPDFDocumentTab* tab in tabs) {
        if (tab.group) hasAny = YES;
        if (tab.group && !tab.group.general) { hasCustom = YES; break; }
    }
    if (!hasAny) return;
    if (!hasCustom) { for (SPDFDocumentTab* tab in tabs) tab.group = nil; return; }
    // Strip refreshes also happen while reading. Already canonical, contiguous
    // groups need no buckets, arrays, or identity dictionaries on that path.
    BOOL needsNormalization = NO;
    SPDFTabGroup* previous = nil;
    for (NSUInteger i = 0; i < tabs.count && !needsNormalization; ++i) {
        SPDFTabGroup* group = tabs[i].group;
        if (!group) { needsNormalization = YES; break; }
        if (group == previous) continue;
        for (NSUInteger j = 0; j < i; ++j)
            if ([tabs[j].group.identifier isEqualToString:group.identifier]) { needsNormalization = YES; break; }
        previous = group;
    }
    if (!needsNormalization) return;
    NSMutableDictionary<NSString*, SPDFTabGroup*>* canonical = [NSMutableDictionary dictionary];
    NSMutableArray<NSString*>* order = [NSMutableArray array];
    NSMutableDictionary<NSString*, NSMutableArray*>* buckets = [NSMutableDictionary dictionary];
    for (SPDFDocumentTab* tab in tabs) {
        NSString* identifier = tab.group.identifier ?: @"general";
        if (!canonical[identifier]) {
            canonical[identifier] = tab.group ?: SPDFTabGroup.generalGroup;
            buckets[identifier] = [NSMutableArray array];
            [order addObject:identifier];
        }
        tab.group = canonical[identifier];
        [buckets[identifier] addObject:tab];
    }
    [tabs removeAllObjects];
    for (NSString* identifier in order) [tabs addObjectsFromArray:buckets[identifier]];
}
void spdf_tab_groups_activate(NSArray<SPDFDocumentTab*>* tabs, SPDFDocumentTab* selected) {
    if (!selected.group) return;
    for (SPDFDocumentTab* tab in tabs)
        if (!tab.group.general) tab.group.collapsed = tab.group != selected.group;
    selected.group.collapsed = NO;
    selected.group.lastUsedPath = selected.path;
}
