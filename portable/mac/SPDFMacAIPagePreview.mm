#import "SPDFMacAIPagePreview.h"
#import "SPDFMacSearchFileCache.h"
#import "SPDFMacMarkdownPrinting.h"
#import "markdown/SPDFTextDocumentFormats.h"
#import "markdown/SPDFMarkdownDocument.h"
#import <ImageIO/ImageIO.h>
#include "shenzhen_pdf_core.h"
#include <sys/stat.h>
static id PreviewError(NSError** error, NSString* message) {
    if (error) *error=[NSError errorWithDomain:@"ShenzhenPDF.AI.Preview" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
    return nil;
}
static NSDictionary* Preview(NSString* path, BOOL landscape, NSUInteger page, NSDictionary* candidate, NSProgress* progress, NSError** error) {
    NSString* stamp=SPDFSearchFileStamp(path);
    if (!page || !stamp || progress.cancelled) return PreviewError(error,@"Page unavailable or request cancelled.");
    NSData* png=nil;
    if (SPDFIsRenderedTextDocumentPath(path)) {
        if (candidate && (![candidate[@"sourceRevision"] isEqual:candidate[@"revision"]] ||
            ![candidate[@"revision"] isEqual:stamp]))
            return PreviewError(error,@"This text snapshot is stale. Wait for the reader to reload it.");
        SPDFMarkdownPaginationPlan* plan=candidate[@"paginationPlan"];
        SPDFMarkdownRenderedDocument* rendered=candidate[@"renderedDocument"];
        if (candidate && (!plan || !rendered)) return PreviewError(error,@"Open this text document before rendering a page preview.");
        if (!candidate) {
            SPDFMarkdownDocument* doc=[SPDFMarkdownDocument documentWithURL:[NSURL fileURLWithPath:path] options:nil error:error];
            if (!doc) return nil;
            SPDFMarkdownPageConfiguration* paper=landscape ? [SPDFMarkdownPageConfiguration A4LandscapeConfiguration] :
                [SPDFMarkdownPageConfiguration A4PortraitConfiguration];
            plan=[doc paginationPlanForConfiguration:doc.authoredPageConfiguration ?: paper]; rendered=doc.renderedDocument;
        }
        if (page>plan.pages.count) return PreviewError(error,@"Page is outside the document.");
        NSSize size=plan.configuration.paperSize;
        if (size.width<=0 || size.height<=0 || !isfinite(size.width) || !isfinite(size.height))
            return PreviewError(error,@"Invalid paper dimensions.");
        CGFloat scale=MIN(2.0,1600.0/MAX(size.width,size.height));
        NSBitmapImageRep* rep=[SPDFMacMarkdownPrintAdapter imageRepForPageAtIndex:page-1 paginationPlan:plan
            attributedString:rendered.attributedString scale:scale];
        png=[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    } else {
        char message[1024]={}; spdf_document* doc=spdf_open(path.fileSystemRepresentation,message,sizeof(message));
        if (!doc) return PreviewError(error,@"Document is locked or unavailable.");
        float width=0,height=0;
        if (page>(NSUInteger)spdf_page_count(doc) ||
            !spdf_page_size(doc,(int)page-1,&width,&height,message,sizeof(message)) ||
            width<=0 || height<=0 || !isfinite(width) || !isfinite(height)) {
            spdf_close(doc); return PreviewError(error,@"Page is outside the document or has invalid dimensions.");
        }
        spdf_bitmap bitmap={}; float scale=MIN(2.0f,1600.0f/MAX(width,height));
        BOOL rendered=spdf_render_page_rgba_opts(doc,(int)page-1,scale,SPDF_RENDER_DEFAULT,NULL,&bitmap,message,sizeof(message));
        spdf_close(doc);
        if (!rendered) return PreviewError(error,@"Page could not be rendered.");
        CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,bitmap.rgba,(size_t)bitmap.stride*bitmap.height,NULL);
        CGImageRef image=CGImageCreate(bitmap.width,bitmap.height,8,32,bitmap.stride,space,
            kCGImageAlphaLast|kCGBitmapByteOrder32Big,provider,NULL,false,kCGRenderingIntentDefault);
        CGColorSpaceRelease(space); CGDataProviderRelease(provider);
        NSMutableData* data=[NSMutableData data];
        CGImageDestinationRef destination=image ? CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,CFSTR("public.png"),1,NULL) : NULL;
        if (destination) { CGImageDestinationAddImage(destination,image,NULL); if (CGImageDestinationFinalize(destination)) png=data; CFRelease(destination); }
        if (image) CGImageRelease(image); spdf_free_bitmap(&bitmap);
    }
    if (!png || png.length>8*1024*1024) return PreviewError(error,@"Page preview exceeds its image budget.");
    if (progress.cancelled || ![stamp isEqual:SPDFSearchFileStamp(path)]) return PreviewError(error,@"Page changed or request cancelled.");
    NSString* root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"ShenzhenPDF-AI-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    if (![NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:NO
        attributes:@{NSFilePosixPermissions:@0700} error:error]) return nil;
    NSString* output=[root stringByAppendingPathComponent:@"page.png"];
    if (![png writeToFile:output options:NSDataWritingAtomic error:error]) { [NSFileManager.defaultManager removeItemAtPath:root error:nil]; return nil; }
    chmod(output.fileSystemRepresentation,0600);
    return @{@"path":output,@"revision":stamp,@"page":@(page)};
}

NSDictionary* SPDFAIPagePreview(NSString* path, BOOL landscape, NSUInteger page, NSProgress* progress, NSError** error) {
    return Preview(path,landscape,page,nil,progress,error);
}
NSDictionary* SPDFAIPagePreviewForCandidate(NSDictionary* candidate, NSUInteger page, NSProgress* progress, NSError** error) {
    return Preview(candidate[@"readPath"] ?: candidate[@"path"],[candidate[@"landscape"] boolValue],page,candidate,progress,error);
}
