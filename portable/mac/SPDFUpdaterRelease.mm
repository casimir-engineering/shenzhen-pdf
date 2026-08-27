#import "SPDFUpdaterRelease.h"

#import <AppKit/AppKit.h>

#import "SPDFUpdater.h"

NSArray<NSNumber*>* spdf_version_components(NSString* version) {
    if (![version isKindOfClass:NSString.class] || version.length == 0) return nil;
    NSCharacterSet* seps = [NSCharacterSet characterSetWithCharactersInString:@". -"];
    NSArray<NSString*>* parts = [version componentsSeparatedByCharactersInSet:seps];
    NSMutableArray<NSNumber*>* out = [NSMutableArray array];
    for (NSString* part in parts) {
        if (part.length == 0) continue;
        NSScanner* scanner = [NSScanner scannerWithString:part];
        long long value = 0;
        if (![scanner scanLongLong:&value] || !scanner.atEnd) return nil;
        [out addObject:@(value)];
    }
    return out.count ? out : nil;
}

NSComparisonResult spdf_compare_versions(NSString* a, NSString* b) {
    NSArray<NSNumber*>* ca = spdf_version_components(a);
    NSArray<NSNumber*>* cb = spdf_version_components(b);
    if (!ca || !cb) return NSOrderedSame;
    NSUInteger count = MAX(ca.count, cb.count);
    for (NSUInteger i = 0; i < count; ++i) {
        long long va = i < ca.count ? ca[i].longLongValue : 0;
        long long vb = i < cb.count ? cb[i].longLongValue : 0;
        if (va < vb) return NSOrderedAscending;
        if (va > vb) return NSOrderedDescending;
    }
    return NSOrderedSame;
}

BOOL spdf_release_tag_matches_bundle_version(NSString* tag, NSString* shortVersion, NSString* build) {
    if (![shortVersion isKindOfClass:NSString.class] || ![build isKindOfClass:NSString.class] ||
        shortVersion.length == 0 || build.length == 0)
        return NO;
    NSString* bundleVersion = [NSString stringWithFormat:@"%@-%@", shortVersion, build];
    NSArray<NSNumber*>* tagParts = spdf_version_components(tag);
    NSArray<NSNumber*>* bundleParts = spdf_version_components(bundleVersion);
    if (tagParts.count != 4 || bundleParts.count != 4) return NO;
    for (NSUInteger i = 0; i < 4; ++i) {
        if (tagParts[i].longLongValue != bundleParts[i].longLongValue) return NO;
    }
    return YES;
}

BOOL spdf_release_tag_matches_running_version(NSString* tag, NSString* runningVersion) {
    NSArray<NSNumber*>* tagParts = spdf_version_components(tag);
    NSArray<NSNumber*>* runningParts = spdf_version_components(runningVersion);
    if (tagParts.count != 4 || runningParts.count != 4) return NO;
    for (NSUInteger i = 0; i < 4; ++i) {
        if (tagParts[i].longLongValue != runningParts[i].longLongValue) return NO;
    }
    return YES;
}

NSString* spdf_format_release_notes_for_alert(NSString* body) {
    if (![body isKindOfClass:NSString.class] || body.length == 0) return @"";
    NSCharacterSet* ws = NSCharacterSet.whitespaceCharacterSet;
    NSString* text = [body stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];

    NSMutableArray<NSString*>* lines = [NSMutableArray array];
    for (NSString* rawLine in [text componentsSeparatedByString:@"\n"]) {
        NSString* line = [rawLine stringByTrimmingCharactersInSet:ws];
        if ([line hasPrefix:@"---"] || [line hasPrefix:@"***"] || [line hasPrefix:@"___"]) break;
        while ([line hasPrefix:@"#"]) line = [line substringFromIndex:1];
        if ([line hasPrefix:@"> "]) line = [line substringFromIndex:2];
        line = [line stringByTrimmingCharactersInSet:ws];
        BOOL isBullet = NO;
        for (NSString* bullet in @[ @"- ", @"* ", @"+ " ]) {
            if ([line hasPrefix:bullet]) {
                line = [@"• " stringByAppendingString:[line substringFromIndex:2]];
                isBullet = YES;
                break;
            }
        }
        for (NSString* marker in @[ @"**", @"`", @"_" ])
            line = [line stringByReplacingOccurrencesOfString:marker withString:@""];
        BOOL continuation = !isBullet && line.length && [rawLine hasPrefix:@"  "] && lines.count &&
                            ((NSString*)lines.lastObject).length;
        if (continuation) {
            lines[lines.count - 1] = [lines.lastObject stringByAppendingFormat:@" %@", line];
        } else if (line.length) {
            [lines addObject:line];
        }
    }
    text = [lines componentsJoinedByString:@"\n"];

    NSMutableCharacterSet* strip = [NSMutableCharacterSet new];
    [strip formUnionWithCharacterSet:NSCharacterSet.controlCharacterSet];
    [strip addCharactersInRange:NSMakeRange(0x202A, 5)];
    [strip addCharactersInRange:NSMakeRange(0x2066, 4)];
    NSMutableString* cleaned = [NSMutableString stringWithCapacity:text.length];
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                             options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString* sub, NSRange range, NSRange enclosingRange, BOOL* stop) {
                            (void)range;
                            (void)enclosingRange;
                            (void)stop;
                            unichar character = sub.length ? [sub characterAtIndex:0] : 0;
                            if (sub.length == 1 && [strip characterIsMember:character] && character != '\n') return;
                            [cleaned appendString:sub];
                          }];
    text = [cleaned stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length > 500) {
        NSRange lastBreak = [[text substringToIndex:500] rangeOfString:@"\n" options:NSBackwardsSearch];
        NSUInteger cut = lastBreak.location != NSNotFound ? lastBreak.location : 500;
        text = [[[text substringToIndex:cut]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
            stringByAppendingString:@"\n…"];
    }
    return text;
}

NSAlert* spdf_make_update_available_alert(NSString* tag, NSString* runningVersion, NSString* releaseBody) {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"A new version of Shenzhen PDF is available";
    NSString* detail =
        [NSString stringWithFormat:@"Shenzhen PDF %@ is available — you have %@. Would you like to install it now?",
                                   tag, runningVersion];
    if ([releaseBody isKindOfClass:NSString.class] && releaseBody.length) {
        NSString* plain = spdf_format_release_notes_for_alert(releaseBody);
        if (plain.length) detail = [detail stringByAppendingFormat:@"\n\n%@", plain];
    }
    alert.informativeText = detail;
    [alert addButtonWithTitle:@"Install and Relaunch"];
    [alert addButtonWithTitle:@"Skip This Version"];
    [alert addButtonWithTitle:@"Later"];
    return alert;
}
