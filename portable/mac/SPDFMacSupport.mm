#import "SPDFMacSupport.h"

NSArray<UTType*>* spdf_document_content_types(void) {
    NSMutableArray<UTType*>* types = [NSMutableArray arrayWithObject:UTTypePDF];
    for (NSString* extension in @[ @"xps", @"cbz", @"epub" ]) {
        UTType* type = [UTType typeWithFilenameExtension:extension];
        if (type) [types addObject:type];
    }
    return types;
}

NSString* spdf_display_label_without_extension(NSString* label) {
    if (!label.length) return @"";
    NSArray<NSString*>* extensions = @[ @".pdf", @".xps", @".cbz", @".epub" ];
    for (NSString* ext in extensions) {
        NSRange range = [label rangeOfString:ext options:NSCaseInsensitiveSearch | NSBackwardsSearch];
        if (range.location == NSNotFound) continue;
        NSUInteger end = range.location + range.length;
        BOOL atEnd = end == label.length;
        BOOL beforeSuffix = !atEnd && ([[NSCharacterSet whitespaceAndNewlineCharacterSet]
                                           characterIsMember:[label characterAtIndex:end]] ||
                                       [label characterAtIndex:end] == '-');
        if (atEnd || beforeSuffix) return [label stringByReplacingCharactersInRange:range withString:@""];
    }
    return label;
}

NSString* spdf_display_name_for_path(NSString* path) {
    NSString* name = path.lastPathComponent;
    return spdf_display_label_without_extension(name);
}

NSString* spdf_display_path_without_extension(NSString* path) {
    if (!path.length) return @"";
    NSString* stem = path.stringByDeletingPathExtension;
    return stem.length && ![stem isEqualToString:path] ? stem : path;
}

NSArray<NSDictionary<NSString*, NSString*>*>* spdf_translation_languages(void) {
    static NSArray<NSDictionary<NSString*, NSString*>*>* languages = nil;
    if (languages) return languages;
    languages = @[
        @{@"code" : @"zh", @"name" : @"Chinese (Simplified)"}, @{@"code" : @"en", @"name" : @"English"},
        @{@"code" : @"fr", @"name" : @"French"}, @{@"code" : @"de", @"name" : @"German"},
        @{@"code" : @"es", @"name" : @"Spanish"}, @{@"code" : @"it", @"name" : @"Italian"},
        @{@"code" : @"pt", @"name" : @"Portuguese"}, @{@"code" : @"ru", @"name" : @"Russian"},
        @{@"code" : @"ja", @"name" : @"Japanese"}, @{@"code" : @"ko", @"name" : @"Korean"},
        @{@"code" : @"ar", @"name" : @"Arabic"}, @{@"code" : @"hi", @"name" : @"Hindi"},
        @{@"code" : @"nl", @"name" : @"Dutch"}, @{@"code" : @"pl", @"name" : @"Polish"},
        @{@"code" : @"tr", @"name" : @"Turkish"}, @{@"code" : @"vi", @"name" : @"Vietnamese"},
        @{@"code" : @"id", @"name" : @"Indonesian"}, @{@"code" : @"uk", @"name" : @"Ukrainian"},
        @{@"code" : @"cs", @"name" : @"Czech"}
    ];
    return languages;
}

NSArray<NSDictionary<NSString*, NSString*>*>* spdf_ocr_languages(void) {
    static NSArray<NSDictionary<NSString*, NSString*>*>* languages = nil;
    if (languages) return languages;
    languages = @[
        @{@"code" : @"chi_sim+eng", @"name" : @"Chinese Simplified + English"},
        @{@"code" : @"chi_sim", @"name" : @"Chinese Simplified"},
        @{@"code" : @"chi_tra+eng", @"name" : @"Chinese Traditional + English"},
        @{@"code" : @"chi_tra", @"name" : @"Chinese Traditional"}, @{@"code" : @"eng", @"name" : @"English"}
    ];
    return languages;
}

NSArray<NSString*>* spdf_ocr_language_components(NSString* language) {
    if (!language.length) return @[];
    NSMutableArray<NSString*>* components = [NSMutableArray array];
    for (NSString* part in [language componentsSeparatedByString:@"+"]) {
        NSString* trimmed = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length) [components addObject:trimmed];
    }
    return components;
}

BOOL spdf_ocr_language_uses_extra_traineddata(NSString* language) {
    for (NSString* component in spdf_ocr_language_components(language)) {
        if (![component isEqualToString:@"eng"]) return YES;
    }
    return NO;
}

NSImage* spdf_translate_toolbar_image(void) {
    static NSImage* image = nil;
    if (image) return image;

    if (@available(macOS 11.0, *)) {
        image = [NSImage imageWithSystemSymbolName:@"translate" accessibilityDescription:@"Translate"];
        if (image) {
            [image setTemplate:YES];
            return image;
        }
    }

    image = [[NSImage alloc] initWithSize:NSMakeSize(18.0, 18.0)];
    [image lockFocus];
    CGContextRef ctx = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, 0.0, 18.0);
    CGContextScaleCTM(ctx, 18.0 / 24.0, -18.0 / 24.0);
    CGContextSetLineWidth(ctx, 1.9);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    CGContextSetStrokeColorWithColor(ctx, NSColor.blackColor.CGColor);

    CGContextSetLineWidth(ctx, 2.1);
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, 5.2, 17.8);
    CGContextAddLineToPoint(ctx, 8.0, 7.2);
    CGContextAddLineToPoint(ctx, 10.8, 17.8);
    CGContextMoveToPoint(ctx, 6.2, 14.0);
    CGContextAddLineToPoint(ctx, 9.8, 14.0);
    CGContextStrokePath(ctx);

    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, 13.5, 5.3);
    CGContextAddLineToPoint(ctx, 21.2, 5.3);
    CGContextMoveToPoint(ctx, 17.4, 3.0);
    CGContextAddLineToPoint(ctx, 17.4, 5.3);
    CGContextMoveToPoint(ctx, 15.1, 7.0);
    CGContextAddQuadCurveToPoint(ctx, 17.4, 10.7, 20.0, 7.0);
    CGContextMoveToPoint(ctx, 16.5, 8.8);
    CGContextAddLineToPoint(ctx, 19.8, 12.2);
    CGContextStrokePath(ctx);

    CGContextSetLineWidth(ctx, 1.7);
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, 14.7, 15.8);
    CGContextAddLineToPoint(ctx, 18.7, 15.8);
    CGContextAddLineToPoint(ctx, 17.0, 14.1);
    CGContextMoveToPoint(ctx, 18.7, 15.8);
    CGContextAddLineToPoint(ctx, 17.0, 17.5);
    CGContextMoveToPoint(ctx, 9.3, 8.1);
    CGContextAddLineToPoint(ctx, 5.3, 8.1);
    CGContextAddLineToPoint(ctx, 7.0, 6.4);
    CGContextMoveToPoint(ctx, 5.3, 8.1);
    CGContextAddLineToPoint(ctx, 7.0, 9.8);
    CGContextStrokePath(ctx);
    CGContextRestoreGState(ctx);

    [image unlockFocus];
    [image setTemplate:YES];
    return image;
}

NSImage* spdf_ocr_toolbar_image(void) {
    static NSImage* image = nil;
    if (image) return image;

    if (@available(macOS 11.0, *)) {
        image = [NSImage imageWithSystemSymbolName:@"doc.text.viewfinder" accessibilityDescription:@"OCR"];
        if (!image) image = [NSImage imageWithSystemSymbolName:@"text.viewfinder" accessibilityDescription:@"OCR"];
        if (image) {
            [image setTemplate:YES];
            return image;
        }
    }

    image = [[NSImage alloc] initWithSize:NSMakeSize(18.0, 18.0)];
    [image lockFocus];
    CGContextRef ctx = NSGraphicsContext.currentContext.CGContext;
    CGContextSetLineWidth(ctx, 1.8);
    CGContextSetStrokeColorWithColor(ctx, NSColor.blackColor.CGColor);
    CGContextStrokeRect(ctx, CGRectMake(2.5, 3.0, 13.0, 12.0));
    CGContextMoveToPoint(ctx, 5.0, 7.0);
    CGContextAddLineToPoint(ctx, 13.0, 7.0);
    CGContextMoveToPoint(ctx, 5.0, 10.0);
    CGContextAddLineToPoint(ctx, 13.0, 10.0);
    CGContextStrokePath(ctx);
    [image unlockFocus];
    [image setTemplate:YES];
    return image;
}

BOOL spdf_is_allowed_external_url(NSURL* url) {
    NSString* scheme = url.scheme.lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] ||
           [scheme isEqualToString:@"mailto"] || [scheme isEqualToString:@"file"];
}
