// Focused tab-strip layout regressions; included by the interaction test TU.
static void check_group_overflow(void) {
    for (NSNumber* count in @[@50, @100]) for (NSNumber* customFirst in @[@NO, @YES])
        for (NSNumber* width in @[@700, @900]) {
            SPDFTabGroup* general = SPDFTabGroup.generalGroup;
            SPDFTabGroup* custom = [SPDFTabGroup groupWithColor:@"Purple"];
            SPDFGroupTestStrip* crowded = [[SPDFGroupTestStrip alloc] initWithFrame:NSMakeRect(0,0,width.doubleValue,42)];
            NSMutableArray* fixture = [NSMutableArray array];
            for (NSInteger i = 0; i < count.integerValue; ++i) [fixture addObject:tab(@"General",general)];
            NSIndexSet* pair = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(customFirst.boolValue ? 0 : fixture.count,2)];
            [fixture insertObjects:@[tab(@"Grouped A",custom),tab(@"Grouped B",custom)] atIndexes:pair];
            crowded.tabs = (id)fixture;
            for (NSNumber* selectGeneral in @[@NO, @YES]) {
                crowded.selectedIndex = selectGeneral.boolValue ? (customFirst.boolValue ? 2 : count.integerValue-1) : pair.lastIndex;
                NSArray* visible = crowded.groupedVisibleTabIndexes;
                expect([visible containsObject:@(pair.firstIndex)] && [visible containsObject:@(pair.lastIndex)],
                       @"General tabs consumed space needed by the newly grouped pair");
                expect([visible containsObject:@(crowded.selectedIndex)], @"General selection became hidden during prioritized overflow");
                NSRect previous = NSZeroRect;
                for (id layout in crowded.groupLayouts) {
                    NSRect frame = [[layout valueForKey:@"frame"] rectValue];
                    if (NSIsEmptyRect(frame)) continue;
                    expect(NSMinX(frame) >= NSMaxX(previous) && NSMaxX(frame) <= [crowded tabAreaRightWithOverflow:YES],
                           @"prioritized group layout overlapped another group or overflow controls");
                    previous = frame;
                }
                if (count.integerValue == 100 && width.integerValue == 900 && !selectGeneral.boolValue)
                    render_strip(crowded, [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua],
                        customFirst.boolValue ? @"/tmp/spdf-group-overflow-left.png" : @"/tmp/spdf-group-overflow-right.png");
            }
        }
}

static void check_group_creation_side(void) {
    for (NSNumber* grouped in @[@NO,@YES]) {
        SPDFGroupTestStrip* strip = [[SPDFGroupTestStrip alloc] initWithFrame:NSMakeRect(0,0,900,42)];
        SPDFGroupFakeReader* reader = [SPDFGroupFakeReader new];
        strip.reader = (id)reader;
        SPDFTabGroup* general = grouped.boolValue ? SPDFTabGroup.generalGroup : nil;
        NSMutableArray* tabs = [NSMutableArray array];
        for (NSInteger i=0;i<66;i++) [tabs addObject:tab(@"Crowded General",general)];
        strip.tabs = (id)tabs;
        strip.selectedIndex = 65;
        NSArray<NSNumber*>* visible = strip.visibleTabIndexes;
        expect(visible.firstObject.integerValue > 33 && visible.count > 1,
               @"placement fixture must show only the trailing half of document indexes");
        expect([strip newGroupGoesBeforeTargetAtIndex:visible.firstObject.integerValue],
               @"leftmost visible tab was positioned using its hidden model index");
        expect(![strip newGroupGoesBeforeTargetAtIndex:visible.lastObject.integerValue],
               @"rightmost visible tab did not keep the new group on the right");
        for (NSNumber* index in @[visible.firstObject,visible.lastObject]) {
            NSMenuItem* item = [NSMenuItem new];
            item.representedObject = index;
            [strip tabContextNewGroup:item];
            expect(reader.createdBeforeTarget == [index isEqual:visible.firstObject],
                   @"context group creation lost its visible-side placement");
            if (grouped.boolValue) continue; // Existing-group sibling drags intentionally reorder.
            NSRect rect = [strip rectForTabAtIndex:index.integerValue];
            NSPoint point = NSMakePoint(NSMidX(rect),NSMidY(rect));
            NSInteger source = [index isEqual:visible.firstObject] ? visible.lastObject.integerValue : visible.firstObject.integerValue;
            [strip updateGroupDropForPoint:point sourceIndex:source];
            [strip setValue:@(NSDate.timeIntervalSinceReferenceDate-1) forKey:@"groupHoverBegan"];
            [strip updateGroupDropForPoint:point sourceIndex:source];
            expect([strip performGroupDropWithTab:(id)tabs[(NSUInteger)source] sourceIndex:source atPoint:point],
                   @"pair creation drop was not recognized");
            expect(reader.createdBeforeTarget == [index isEqual:visible.firstObject],
                   @"pair drop lost its visible-side placement");
        }
    }
}

static void check_hidden_groups(void) {
    SPDFGroupTestStrip* strip=[[SPDFGroupTestStrip alloc] initWithFrame:NSMakeRect(0,0,900,42)];
    SPDFTabGroup* general=SPDFTabGroup.generalGroup;
    SPDFTabGroup* custom=[SPDFTabGroup groupWithColor:@"Blue"];
    strip.tabs=(id)@[tab(@"General one",general),tab(@"General two",general),tab(@"Hidden one",custom),tab(@"Hidden two",custom)];
    custom.hidden=YES; strip.selectedIndex=3;
    expect([strip.groupedVisibleTabIndexes isEqual:@[@0,@1]],@"hidden custom tabs consume strip space");
    expect(!strip.groupedHasOverflow && !strip.hiddenTabIndexes.count,@"hidden group leaks into overflow");
    for (id child in strip.accessibilityChildren)
        expect(![[child accessibilityLabel] hasPrefix:@"Hidden"],@"hidden group leaks into strip accessibility");
    general.hidden=YES; strip.tabs=strip.tabs;
    expect(!strip.groupLayouts.count && !strip.visibleTabIndexes.count && !strip.groupedHasOverflow,
        @"all hidden groups leave only controls in the strip");
    expect(strip.tabs.count==4 && strip.selectedIndex==3,@"hiding groups removes tabs or changes selection");
    general.hidden=NO; strip.tabs=strip.tabs;
    expect([strip.groupedVisibleTabIndexes isEqual:@[@0,@1]],@"showing General does not restore its original member order");
}
