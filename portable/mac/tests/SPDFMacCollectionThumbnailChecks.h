#import "SPDFMacCollectionThumbnail.h"

static void CheckCollectionThumbnails(void) {
    NSString* directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSFileManager* fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableData* data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box = CGRectMake(0,0,200,200);
    CGContextRef context = CGPDFContextCreate(consumer,&box,NULL);
    CGPDFContextBeginPage(context,NULL); CGContextSetRGBFillColor(context,.1,.3,.8,1);
    CGContextFillRect(context,CGRectMake(20,20,160,160)); CGPDFContextEndPage(context);
    CGPDFContextClose(context); CGContextRelease(context); CGDataConsumerRelease(consumer);
    PDFDocument* plain = [[PDFDocument alloc] initWithData:data];
    NSURL* restricted = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"Restricted.pdf"]];
    Expect(@"write owner-restricted PDF",[plain writeToURL:restricted withOptions:@{
        PDFDocumentOwnerPasswordOption:@"owner-secret",PDFDocumentUserPasswordOption:@""}]);
    PDFDocument* ownerRestricted = [[PDFDocument alloc] initWithURL:restricted];
    Expect(@"fixture encrypted but readable without a user password",ownerRestricted.isEncrypted && !ownerRestricted.isLocked);
    __block BOOL prompted = NO;
    NSImage* image = SPDFCollectionPDFThumbnail(restricted,1,^(PDFDocument* pdf) { (void)pdf; prompted = YES; },nil);
    Expect(@"encrypted readable PDF gets a real page thumbnail without prompting",image != nil && !prompted);
    NSURL* locked = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"Locked.pdf"]];
    Expect(@"write locked PDF",[plain writeToURL:locked withOptions:@{
        PDFDocumentOwnerPasswordOption:@"owner-secret",PDFDocumentUserPasswordOption:@"reader-secret"}]);
    NSError* error = nil;
    Expect(@"locked copy remains private without a credential",SPDFCollectionPDFThumbnail(locked,1,nil,&error)==nil && error.code==2);
    image = SPDFCollectionPDFThumbnail(locked,1,^(PDFDocument* pdf) { [pdf unlockWithPassword:@"reader-secret"]; },nil);
    Expect(@"already authenticated copy can render using a memory credential",image != nil);
    Expect(@"rendering does not decrypt or rewrite archived bytes",[[[PDFDocument alloc] initWithURL:locked] isLocked]);
    Expect(@"out of bounds result pages clamp to a real page",SPDFCollectionPDFThumbnail(restricted,999,nil,nil)!=nil);
    [fm removeItemAtPath:directory error:nil];
}
