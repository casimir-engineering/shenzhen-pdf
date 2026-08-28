#import "SPDFMacMarkdownPageCanvasPrivate.h"

// Image-aware selection copy backing the Markdown tab's Cmd+C / Copy chain
// (the canvas's copy: fallback and the reader's copySelection:). An
// image-only selection writes the attachment's image itself, a mixed
// selection writes the plain text plus an RTFD rendition that keeps the
// attachments, and a plain-text selection writes the string exactly as the
// pre-image copy path did.

// The image an attachment can put on the pasteboard: its natural decoded
// image when present, else a decode of the attachment's file-wrapper bytes.
static NSImage* SPDFMarkdownAttachmentImage(NSTextAttachment* attachment) {
    if (![attachment isKindOfClass:NSTextAttachment.class]) return nil;
    if (attachment.image) return attachment.image;
    NSData* contents = attachment.fileWrapper.regularFileContents;
    return contents.length ? [[NSImage alloc] initWithData:contents] : nil;
}

@implementation SPDFMacMarkdownPageCanvas (Copy)

- (NSArray<NSImage*>*)spdf_imagesInSelection {
    NSRange range = self.selectedRange;
    if (!range.length || NSMaxRange(range) > self.attributedString.length) return @[];
    NSMutableArray<NSImage*>* images = [NSMutableArray array];
    [self.attributedString enumerateAttribute:NSAttachmentAttributeName
                                      inRange:range
                                      options:0
                                   usingBlock:^(NSTextAttachment* attachment, NSRange attachmentRange, BOOL* stop) {
                                     (void)attachmentRange;
                                     (void)stop;
                                     NSImage* image = SPDFMarkdownAttachmentImage(attachment);
                                     if (image) [images addObject:image];
                                   }];
    return images;
}

- (BOOL)selectionContainsImageAttachment {
    return [self spdf_imagesInSelection].count > 0;
}

// RTFD serialization needs file-wrapper-backed attachments, so image-backed
// attachments are rewrapped around a PNG (TIFF fallback) of their natural-size
// image while keeping the original display bounds.
- (NSData*)spdf_RTFDDataForSelectionRange:(NSRange)range {
    NSMutableAttributedString* substring = [[self.attributedString attributedSubstringFromRange:range] mutableCopy];
    __block NSUInteger imageNumber = 0;
    [substring enumerateAttribute:NSAttachmentAttributeName
                          inRange:NSMakeRange(0, substring.length)
                          options:0
                       usingBlock:^(NSTextAttachment* attachment, NSRange attachmentRange, BOOL* stop) {
                         (void)stop;
                         if (![attachment isKindOfClass:NSTextAttachment.class]) return;
                         if (attachment.fileWrapper.regularFileContents.length) return;
                         NSData* tiff = attachment.image.TIFFRepresentation;
                         if (!tiff) return;
                         NSData* png = [[NSBitmapImageRep imageRepWithData:tiff]
                             representationUsingType:NSBitmapImageFileTypePNG
                                          properties:@{}];
                         NSFileWrapper* wrapper = [[NSFileWrapper alloc] initRegularFileWithContents:png ?: tiff];
                         wrapper.preferredFilename = [NSString stringWithFormat:@"image %lu.%@",
                                                                                (unsigned long)++imageNumber,
                                                                                png ? @"png" : @"tiff"];
                         NSTextAttachment* serializable = [NSTextAttachment new];
                         serializable.fileWrapper = wrapper;
                         serializable.image = attachment.image;
                         serializable.bounds = attachment.bounds;
                         [substring addAttribute:NSAttachmentAttributeName value:serializable range:attachmentRange];
                       }];
    return [substring RTFDFromRange:NSMakeRange(0, substring.length)
                 documentAttributes:@{NSDocumentTypeDocumentAttribute : NSRTFDTextDocumentType}];
}

- (BOOL)writeSelectionToPasteboard:(NSPasteboard*)pasteboard
                plainTextTransform:(NSString* (^)(NSString* text))transform {
    NSRange range = self.selectedRange;
    if (!pasteboard || !range.length || NSMaxRange(range) > self.attributedString.length) return NO;
    NSString* plain = [self.attributedString.string substringWithRange:range];
    NSArray<NSImage*>* images = [self spdf_imagesInSelection];
    if (!images.count) {
        [pasteboard clearContents];
        return [pasteboard setString:transform ? transform(plain) : plain forType:NSPasteboardTypeString];
    }
    // Exactly one image and nothing but its attachment character (plus
    // surrounding whitespace) selected: the pasteboard gets the image itself
    // at its natural decoded size — the Copy Page Image convention.
    NSString* trimmed = [plain stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (images.count == 1 && trimmed.length == 1 && [trimmed characterAtIndex:0] == NSAttachmentCharacter) {
        [pasteboard clearContents];
        return [pasteboard writeObjects:@[ images.firstObject ]];
    }
    // Mixed selection: the plain text exactly as a text-only copy writes it,
    // plus an RTFD rendition carrying the selected attachments.
    NSPasteboardItem* item = [NSPasteboardItem new];
    [item setString:transform ? transform(plain) : plain forType:NSPasteboardTypeString];
    NSData* rtfd = [self spdf_RTFDDataForSelectionRange:range];
    if (rtfd.length) [item setData:rtfd forType:NSPasteboardTypeRTFD];
    [pasteboard clearContents];
    return [pasteboard writeObjects:@[ item ]];
}

@end
