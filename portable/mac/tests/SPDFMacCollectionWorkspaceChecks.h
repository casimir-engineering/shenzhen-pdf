// Real PDF fixture: search, latest-version identity and lazy thumbnail presentation
// are exercised together, without opening a reader or putting a window on screen.
static NSData* CollectionWorkspacePDF(void) {
    NSMutableData* data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect paper = CGRectMake(0,0,595,842);
    CGContextRef pdf = CGPDFContextCreate(consumer,&paper,NULL);
    CGPDFContextBeginPage(pdf,NULL);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithCGContext:pdf flipped:NO];
    [NSColor.whiteColor setFill]; NSRectFill(paper);
    [@"Interface specification" drawAtPoint:NSMakePoint(45,765)
        withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:24 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:NSColor.blackColor}];
    [@"1. System overview" drawAtPoint:NSMakePoint(45,710)
        withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:16 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:NSColor.blackColor}];
    [@"The controller coordinates power sequencing and host communication.\nEach transition is verified during cold-start and recovery tests."
        drawInRect:NSMakeRect(45,625,505,60) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13],NSForegroundColorAttributeName:NSColor.blackColor}];
    [@"Operating conditions" drawAtPoint:NSMakePoint(45,580)
        withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:16 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:NSColor.blackColor}];
    [@"Supply voltage           3.3 V ± 5%\nStartup delay            25 ms minimum\nInterface state          High impedance until ready"
        drawInRect:NSMakeRect(45,480,505,80) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13],NSForegroundColorAttributeName:NSColor.blackColor}];
    [NSGraphicsContext restoreGraphicsState];
    CGPDFContextEndPage(pdf); CGPDFContextClose(pdf); CGContextRelease(pdf); CGDataConsumerRelease(consumer);
    return data;
}
static void CheckCollectionPDFWorkspace(SPDFMacCollectionWindow* manager, SPDFMacCollectionStore* store) {
    NSString* directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString* path = [directory stringByAppendingPathComponent:@"Interface specification.pdf"];
    [CollectionWorkspacePDF() writeToFile:path atomically:YES];
    NSDictionary* document = [store capturePath:path reason:@"Opened" error:nil];
    Expect(@"workspace PDF fixture captures a latest version",[document[@"latestVersionID"] length]>0);
    [manager showDestination:@"Documents"]; [manager.layoutPicker selectItemAtIndex:0]; [manager.viewPicker selectItemWithTag:0];
    manager.search.stringValue = @"power";
    NSArray* previous = manager.rows; [manager reload:nil];
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (manager.rows == previous && deadline.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    Expect(@"Collection PDF search returns its live latest history and highlighted context",manager.rows.count==1 &&
        [manager.rows[0][@"version"][@"id"] isEqual:document[@"latestVersionID"]] && [manager.rows[0][@"matches"] count]>0);
    Layout(manager.window,NSMakeSize(850,590));
    NSView* cell = [manager.table viewAtColumn:0 row:0 makeIfNecessary:YES];
    [cell layoutSubtreeIfNeeded];
    NSImageView* preview = (id)Descendant(cell,NSImageView.class);
    deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (![manager.thumbnailCache objectForKey:preview.identifier] && deadline.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    Expect(@"readable saved PDF produces an actual lazy page preview",[manager.thumbnailCache objectForKey:preview.identifier] != nil);
    NSString* evidence = NSProcessInfo.processInfo.environment[@"SPDF_COLLECTION_WINDOW_EVIDENCE"];
    if (evidence.length) for (NSString* appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) {
        manager.window.appearance = [NSAppearance appearanceNamed:appearance];
        [manager.window.contentView layoutSubtreeIfNeeded];
        NSBitmapImageRep* bitmap = [manager.window.contentView bitmapImageRepForCachingDisplayInRect:manager.window.contentView.bounds];
        [manager.window.contentView cacheDisplayInRect:manager.window.contentView.bounds toBitmapImageRep:bitmap];
        NSString* output = [evidence.stringByDeletingPathExtension stringByAppendingFormat:@"-pdf-%@.png",appearance];
        [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:output atomically:YES];
    }
    [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
}

static void CheckCollectionSettingsApplyPlacement(SPDFMacCollectionWindow* manager) {
    [manager showDestination:@"Settings"];
    NSAppearance* previousAppearance = manager.window.appearance;
    NSInteger previousLimitMode = manager.limitPicker.indexOfSelectedItem;
    NSString* evidence = NSProcessInfo.processInfo.environment[@"SPDF_COLLECTION_WINDOW_EVIDENCE"];
    for (NSString* appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) {
        manager.window.appearance = [NSAppearance appearanceNamed:appearance];
        for (NSInteger mode=0;mode<2;mode++) {
            [manager.limitPicker selectItemAtIndex:mode];
            [manager performSelector:@selector(changeLimitMode:) withObject:manager.limitPicker];
            Layout(manager.window,NSMakeSize(850,590));
            NSView* cap = Identified(manager.settingsPane,@"CollectionStorageCap");
            NSButton* apply = (id)Identified(manager.settingsPane,@"CollectionStorageApply");
            NSView* stack = cap.superview;
            NSRect capRect = [cap convertRect:cap.bounds toView:stack];
            NSRect applyRect = [apply convertRect:apply.bounds toView:stack];
            NSRect helpRect = [Label(manager.settingsPane,@"Unlimited by default. Set 0 to keep all saved copies.")
                convertRect:Label(manager.settingsPane,@"Unlimited by default. Set 0 to keep all saved copies.").bounds toView:stack];
            NSRect locationRect = [manager.locationField convertRect:manager.locationField.bounds toView:stack];
            Expect(@"Apply sits directly below the cap, before help and Location in both limit modes",
                cap && apply && NSMinY(applyRect)>=NSMaxY(capRect) && NSMinY(applyRect)-NSMaxY(capRect)<=12 &&
                NSMaxY(applyRect)<=NSMinY(helpRect) && NSMaxY(applyRect)<NSMinY(locationRect));
            Expect(@"Apply describes its storage-only action to accessibility",[apply.accessibilityLabel isEqual:@"Apply storage limit"] &&
                apply.action == @selector(changeLimit:) && apply.target == manager);
            if (evidence.length) {
                NSBitmapImageRep* bitmap = [manager.window.contentView bitmapImageRepForCachingDisplayInRect:manager.window.contentView.bounds];
                [manager.window.contentView cacheDisplayInRect:manager.window.contentView.bounds toBitmapImageRep:bitmap];
                NSString* output = [evidence.stringByDeletingPathExtension stringByAppendingFormat:@"-settings-%@-%ld.png",appearance,(long)mode];
                [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:output atomically:YES];
            }
        }
    }
    [manager.limitPicker selectItemAtIndex:previousLimitMode]; [manager performSelector:@selector(changeLimitMode:) withObject:manager.limitPicker];
    manager.window.appearance = previousAppearance;
}
