// Exercises production layout, including its per-item lookup and viewport query.
static void CheckCompactCollectionGrid(SPDFMacCollectionWindow* manager, NSDictionary* row, NSString* evidence) {
    NSArray* saved = manager.rows; NSMutableArray* rows = [NSMutableArray array];
    for (NSUInteger index=0;index<12;index++) [rows addObject:row];
    manager.rows = rows; [manager.table reloadData]; [manager reloadGrid];
    for (NSNumber* width in @[@640,@940,@1100,@760]) {
        Layout(manager.window,NSMakeSize(width.doubleValue,680));
        [manager.grid.collectionViewLayout invalidateLayout]; [manager.grid layoutSubtreeIfNeeded];
        NSCollectionViewLayout* layout = manager.grid.collectionViewLayout;
        NSMutableArray* frames = [NSMutableArray array];
        CGFloat clip = NSWidth(manager.gridScroll.contentView.bounds), horizontal = -1, vertical = -1;
        for (NSUInteger index=0;index<rows.count;index++) {
            NSCollectionViewLayoutAttributes* item = [layout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:index inSection:0]];
            NSRect frame = item.frame;
            Expect(@"compact card is smaller without reducing preview height",NSWidth(frame)<180 && NSHeight(frame)<238);
            Expect(@"grid item stays inside actual viewport width",NSMinX(frame)>=0 && NSMaxX(frame)<=clip);
            for(NSValue* value in frames) Expect(@"thumbnail cards never overlap",!NSIntersectsRect(value.rectValue,frame));
            if(index) {
                NSRect previous = [frames.lastObject rectValue];
                if(fabs(NSMinY(frame)-NSMinY(previous))<.5) horizontal = NSMinX(frame)-NSMaxX(previous);
                else { vertical = NSMinY(frame)-NSMaxY(previous); Expect(@"each row is left aligned",fabs(NSMinX(frame)-12)<.5); }
            }
            [frames addObject:[NSValue valueWithRect:frame]];
        }
        Expect(@"x and y gutters stay equal and compact after resize",fabs(horizontal-8)<.5 && fabs(vertical-horizontal)<.5);
        NSRect visible = NSMakeRect(0,0,clip,NSHeight(manager.gridScroll.contentView.bounds));
        for(NSCollectionViewLayoutAttributes* item in [layout layoutAttributesForElementsInRect:visible])
            Expect(@"viewport and direct item queries agree",NSEqualRects(item.frame,[layout layoutAttributesForItemAtIndexPath:item.indexPath].frame));
        Expect(@"scrolling reaches the last complete row",layout.collectionViewContentSize.height>=NSMaxY([frames.lastObject rectValue]));
        if(evidence.length && width.integerValue==940) for(NSString* appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) {
            manager.window.appearance = [NSAppearance appearanceNamed:appearance];
            [manager.window.contentView layoutSubtreeIfNeeded];
            NSBitmapImageRep* bitmap = [manager.window.contentView bitmapImageRepForCachingDisplayInRect:manager.window.contentView.bounds];
            [manager.window.contentView cacheDisplayInRect:manager.window.contentView.bounds toBitmapImageRep:bitmap];
            [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                writeToFile:[evidence.stringByDeletingPathExtension stringByAppendingFormat:@"-grid-%@.png",appearance] atomically:YES];
        }
    }
    manager.window.appearance=nil; manager.rows=saved; [manager.table reloadData]; [manager reloadGrid];
    Layout(manager.window,NSMakeSize(940,560)); [manager.grid layoutSubtreeIfNeeded];
}
