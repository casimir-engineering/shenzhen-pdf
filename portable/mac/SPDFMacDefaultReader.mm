#import "SPDFMacDefaultReader.h"

#import <CoreServices/CoreServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString* spdf_pdf_content_type_identifier(void) {
    if (@available(macOS 11.0, *)) {
        NSString* identifier = UTTypePDF.identifier;
        if (identifier.length > 0) return identifier;
    }
    return @"com.adobe.pdf";
}

static NSString* spdf_app_bundle_identifier(void) {
    NSString* identifier = NSBundle.mainBundle.bundleIdentifier;
    return identifier.length > 0 ? identifier : @"com.intuition.shenzhenpdf";
}

BOOL SPDFMacIsDefaultPDFReader(void) {
    CFStringRef handler = LSCopyDefaultRoleHandlerForContentType(
        (__bridge CFStringRef)spdf_pdf_content_type_identifier(), kLSRolesViewer);
    NSString* currentHandler = CFBridgingRelease(handler);
    return [currentHandler isEqualToString:spdf_app_bundle_identifier()];
}

BOOL SPDFMacMakeDefaultPDFReader(NSError** error) {
    NSString* contentType = spdf_pdf_content_type_identifier();
    NSString* bundleIdentifier = spdf_app_bundle_identifier();
    OSStatus status = LSSetDefaultRoleHandlerForContentType((__bridge CFStringRef)contentType, kLSRolesViewer,
                                                            (__bridge CFStringRef)bundleIdentifier);
    if (status == noErr) return YES;

    if (error) {
        *error = [NSError
            errorWithDomain:@"com.intuition.shenzhenpdf.default-reader"
                       code:status
                   userInfo:@{
                       NSLocalizedDescriptionKey : @"macOS did not accept Shenzhen PDF as the default PDF reader.",
                       NSLocalizedRecoverySuggestionErrorKey :
                           @"Open Finder, select a PDF, choose File > Get Info, then set Open With to "
                           @"Shenzhen PDF and click Change All."
                   }];
    }
    return NO;
}
