static void CheckEditableCollection(void) {
    NSString* sandbox=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:sandbox withIntermediateDirectories:YES attributes:nil error:nil];
    SPDFMacCollectionStore* store=[[SPDFMacCollectionStore alloc] initWithRootURL:
        [NSURL fileURLWithPath:[sandbox stringByAppendingPathComponent:@"Collection"]]];
    Expect(@"editable lookup is lazy",![store editableInfoForPath:@"/ordinary.pdf"] &&
        ![NSFileManager.defaultManager fileExistsAtPath:store.rootURL.path]);
    [store updateSettings:@{@"choice":@"enabled"} error:nil];
    NSString* source=[sandbox stringByAppendingPathComponent:@"Notes.md"]; Write(source,@"# First revision");
    NSDictionary* doc=Capture(store,source,@"Opened"); NSString* identifier=doc[@"id"], *first=doc[@"latestVersionID"];
    NSURL* copy=[store editableVersionID:first documentID:identifier error:nil];
    Expect(@"Collection documents are writable independent files",copy &&
        [NSFileManager.defaultManager isWritableFileAtPath:copy.path] && ![store isArchivePath:copy.path]);
    Expect(@"edit protection works on managed document",[store ensureProtectedPath:copy.path reason:@"Before edit" error:nil]);
    Write(copy.path,@"# Edited in Collection");
    NSError* error=nil;
    NSDictionary* edited=[store capturePath:copy.path reason:@"Saved" error:&error];
    Expect([NSString stringWithFormat:@"edit remains in the same history: %@",error],
        [edited[@"id"] isEqual:identifier] && [edited[@"versions"] count]==2 && [edited[@"path"] isEqual:source]);
    NSURL* originalVersion=[store materializeVersionID:first documentID:identifier error:nil];
    Expect(@"editing never alters retained snapshot bytes",[[NSString stringWithContentsOfURL:originalVersion encoding:NSUTF8StringEncoding error:nil] isEqual:@"# First revision"]);
    Expect(@"editable current copy is reused",[[store editableVersionID:nil documentID:identifier error:nil] isEqual:copy]);
    Expect(@"same bytes do not add a version",[[store capturePath:copy.path reason:@"Opened" error:nil][@"versions"] count]==2);
    NSURL* historical=[store editableVersionID:first documentID:identifier error:nil];
    NSDictionary* consulted=[store capturePath:historical.path reason:@"Opened" error:nil];
    Expect(@"opening an older version never promotes it or adds a snapshot",[consulted[@"versions"] count]==2 &&
        [consulted[@"latestVersionID"] isEqual:edited[@"latestVersionID"]]);
    Expect(@"older editable version is protectable",[store ensureProtectedPath:historical.path reason:@"Before edit" error:nil]);
    [NSFileManager.defaultManager removeItemAtPath:source error:nil];
    Expect(@"missing original does not prevent editing",[store ensureProtectedPath:copy.path reason:@"Before edit" error:nil]);
    NSURL* renamed=[store renameEditablePath:copy.path filename:@"Renamed.md" error:nil];
    Expect(@"rename updates Collection title and writable file",renamed &&
        [[store documentForPath:renamed.path][@"title"] isEqual:@"Renamed.md"] &&
        ![NSFileManager.defaultManager fileExistsAtPath:copy.path] &&
        [[store documentForPath:copy.path][@"id"] isEqual:identifier]);
    Expect(@"rename retains the missing source binding",[[store documentForPath:renamed.path][@"path"] isEqual:source]);
    Expect(@"automatic cleanup cannot discard an editable document",![[store previewStorageLimit:1][@"canApply"] boolValue]);
    // Exercise the same working-file isolation with real PDF and raster bytes.
    NSMutableData* pdfBytes=[NSMutableData data];
    CGDataConsumerRef consumer=CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)pdfBytes);
    CGRect pageBounds=CGRectMake(0,0,120,160);
    CGContextRef context=CGPDFContextCreate(consumer,&pageBounds,NULL);
    CGContextBeginPage(context,&pageBounds); CGContextSetRGBFillColor(context,1,0,0,1);
    CGContextFillRect(context,CGRectMake(10,10,30,40)); CGContextEndPage(context);
    CGContextRelease(context); CGDataConsumerRelease(consumer);
    NSString* pdfPath=[sandbox stringByAppendingPathComponent:@"Drawing.pdf"];
    [pdfBytes writeToFile:pdfPath atomically:YES];
    NSDictionary* pdfRow=Capture(store,pdfPath,@"Opened");
    NSURL* pdfCopy=[store editableVersionID:nil documentID:pdfRow[@"id"] error:nil];
    Expect(@"PDF working file supports edit protection",[store ensureProtectedPath:pdfCopy.path reason:@"Rotate" error:nil]);
    PDFDocument* pdf=[[PDFDocument alloc] initWithURL:pdfCopy]; [pdf pageAtIndex:0].rotation=90;
    Expect(@"PDF edit writes to Collection",[pdf writeToURL:pdfCopy]);
    NSDictionary* pdfEdited=[store capturePath:pdfCopy.path reason:@"Saved" error:nil];
    PDFDocument* pdfOriginal=[[PDFDocument alloc] initWithURL:[store materializeVersionID:pdfRow[@"latestVersionID"] documentID:pdfRow[@"id"] error:nil]];
    Expect(@"PDF edit retains earlier orientation and one history",[pdfEdited[@"versions"] count]==2 && [pdfOriginal pageAtIndex:0].rotation==0);
    NSDictionary* reopenedOriginal=[store capturePath:pdfPath reason:@"Opened" error:nil];
    Expect(@"original capture cannot reuse working-copy revision fingerprints",
        [[reopenedOriginal[@"versions"] lastObject][@"hash"] isEqual:[pdfRow[@"versions"] firstObject][@"hash"]]);
    NSBitmapImageRep* bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:2 pixelsHigh:2
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    memset(bitmap.bitmapData,255,bitmap.bytesPerRow*bitmap.pixelsHigh);
    NSData* png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSString* imagePath=[sandbox stringByAppendingPathComponent:@"Image.png"]; [png writeToFile:imagePath atomically:YES];
    NSDictionary* imageRow=Capture(store,imagePath,@"Opened");
    NSURL* imageCopy=[store editableVersionID:nil documentID:imageRow[@"id"] error:nil];
    bitmap.bitmapData[0]=0;
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToURL:imageCopy atomically:YES];
    NSDictionary* imageEdited=[store capturePath:imageCopy.path reason:@"Saved" error:nil];
    NSURL* imageSnapshot=[store materializeVersionID:imageRow[@"latestVersionID"] documentID:imageRow[@"id"] error:nil];
    Expect(@"raster edits retain the original pixels and history",[imageEdited[@"versions"] count]==2 &&
        [[NSData dataWithContentsOfURL:imageSnapshot] isEqual:png]);
    NSURL* destination=[NSURL fileURLWithPath:[sandbox stringByAppendingPathComponent:@"Moved"]];
    Expect(@"move Collection retains editable copies",[store relocateToURL:destination error:nil] &&
        [NSFileManager.defaultManager isWritableFileAtPath:renamed.path] &&
        [[store documentForPath:renamed.path][@"id"] isEqual:identifier]);
    NSURL* movedRename=[store renameEditablePath:renamed.path filename:@"After move.md" error:nil];
    Expect(@"rename works through a restored pre-relocation path",movedRename &&
        [[store documentForPath:movedRename.path][@"title"] isEqual:@"After move.md"]);
    [NSFileManager.defaultManager removeItemAtPath:sandbox error:nil];
}
