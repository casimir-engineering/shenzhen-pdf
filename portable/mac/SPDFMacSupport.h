#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

NSArray<UTType*>* spdf_document_content_types(void);
NSString* spdf_display_label_without_extension(NSString* label);
NSString* spdf_display_name_for_path(NSString* path);
NSString* spdf_display_path_without_extension(NSString* path);
NSArray<NSDictionary<NSString*, NSString*>*>* spdf_translation_languages(void);
NSArray<NSDictionary<NSString*, NSString*>*>* spdf_ocr_languages(void);
NSArray<NSString*>* spdf_ocr_language_components(NSString* language);
BOOL spdf_ocr_language_uses_extra_traineddata(NSString* language);
NSImage* spdf_translate_toolbar_image(void);
NSImage* spdf_ocr_toolbar_image(void);
BOOL spdf_is_allowed_external_url(NSURL* url);
