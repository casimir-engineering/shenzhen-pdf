#import <AppKit/AppKit.h>

#import "../SPDFMacMarkdownCache.h"
#import "../SPDFMacMarkdownRouting.h"
#import "../SPDFMacMarkdownView.h"
#import "../markdown/SPDFMarkdown.h"

#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>

static void WriteText(NSString* text, NSString* path) {
    NSError* error = nil;
    assert([text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]);
    assert(error == nil);
}

int main(void) {
    @autoreleasepool {
        assert(spdf_mac_path_is_markdown(@"README.md"));
        assert(spdf_mac_path_is_markdown(@"NOTES.MARKDOWN"));
        assert(!spdf_mac_path_is_markdown(@"manual.pdf"));
        UTType* markdown = [UTType typeWithIdentifier:@"net.daringfireball.markdown"];
        assert(spdf_mac_type_is_markdown(markdown));
        assert([spdf_mac_markdown_heading_slug(@"Caf\u00e9 & Build Notes") isEqualToString:@"cafe-build-notes"]);

        NSString* root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString* outside = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        assert([NSFileManager.defaultManager createDirectoryAtPath:root
                                      withIntermediateDirectories:YES attributes:nil error:nil]);
        assert([NSFileManager.defaultManager createDirectoryAtPath:outside
                                      withIntermediateDirectories:YES attributes:nil error:nil]);
        NSString* source = [root stringByAppendingPathComponent:@"source.md"];
        NSString* child = [root stringByAppendingPathComponent:@"Child.md"];
        NSString* escaped = [outside stringByAppendingPathComponent:@"Escape.md"];
        WriteText(@"# Source\nplain foo [foo](Child.md), [Child](Child.md) and [[Child]].\n", source);
        WriteText(@"# Child\n", child);
        WriteText(@"# Escape\n", escaped);
        NSURL* sourceURL = [NSURL fileURLWithPath:source];

        SPDFMacMarkdownLinkResolution* local = spdf_mac_resolve_markdown_link(@"Child.md#Title", sourceURL, NO);
        assert(local.kind == SPDFMacMarkdownLinkDocument);
        id localIdentifier = nil;
        id childIdentifier = nil;
        [local.URL getResourceValue:&localIdentifier forKey:NSURLFileResourceIdentifierKey error:nil];
        [[NSURL fileURLWithPath:child] getResourceValue:&childIdentifier
                                                forKey:NSURLFileResourceIdentifierKey error:nil];
        assert(localIdentifier && [localIdentifier isEqual:childIdentifier]);
        assert([local.anchor isEqualToString:@"title"]);
        SPDFMacMarkdownLinkResolution* wiki = spdf_mac_resolve_markdown_link(@"Child", sourceURL, YES);
        assert(wiki.kind == SPDFMacMarkdownLinkDocument);
        SPDFMacMarkdownLinkResolution* anchor = spdf_mac_resolve_markdown_link(@"#Source", sourceURL, NO);
        assert(anchor.kind == SPDFMacMarkdownLinkAnchor);
        assert([anchor.anchor isEqualToString:@"source"]);
        assert(spdf_mac_resolve_markdown_link(@"https://example.com", sourceURL, NO).kind ==
               SPDFMacMarkdownLinkExternal);
        assert(spdf_mac_resolve_markdown_link(@"javascript:alert(1)", sourceURL, NO).kind ==
               SPDFMacMarkdownLinkRejected);
        assert(spdf_mac_resolve_markdown_link(@"../Escape.md", sourceURL, NO).kind ==
               SPDFMacMarkdownLinkRejected);
        NSString* symlink = [root stringByAppendingPathComponent:@"Linked.md"];
        assert([NSFileManager.defaultManager createSymbolicLinkAtPath:symlink withDestinationPath:escaped error:nil]);
        assert(spdf_mac_resolve_markdown_link(@"Linked.md", sourceURL, NO).kind == SPDFMacMarkdownLinkRejected);

        NSError* error = nil;
        SPDFMarkdownDocument* document = [SPDFMarkdownDocument documentWithURL:sourceURL options:nil error:&error];
        assert(document && !error);
        NSAttributedString* interactive = SPDFMacMarkdownInteractiveString(document.model,
                                                                           document.renderedDocument);
        NSRange plainFoo = [interactive.string rangeOfString:@"foo"];
        NSRange linkedFoo = [interactive.string rangeOfString:@"foo"
                                                       options:0
                                                         range:NSMakeRange(NSMaxRange(plainFoo),
                                                                           interactive.length -
                                                                               NSMaxRange(plainFoo))];
        assert(plainFoo.location != NSNotFound && linkedFoo.location != NSNotFound);
        assert([interactive attribute:SPDFMacMarkdownDestinationAttribute
                            atIndex:plainFoo.location effectiveRange:NULL] == nil);
        assert([[interactive attribute:SPDFMacMarkdownDestinationAttribute
                             atIndex:linkedFoo.location effectiveRange:NULL] isEqualToString:@"Child.md"]);
        NSRange childRange = [interactive.string rangeOfString:@"Child"];
        assert(childRange.location != NSNotFound);
        assert([[interactive attribute:SPDFMacMarkdownDestinationAttribute
                              atIndex:childRange.location effectiveRange:NULL] isEqualToString:@"Child.md"]);
        NSRange wikiRange = [interactive.string rangeOfString:@"Child" options:0
                                                       range:NSMakeRange(NSMaxRange(childRange),
                                                                         interactive.length - NSMaxRange(childRange))];
        assert(wikiRange.location != NSNotFound);
        assert([[interactive attribute:SPDFMacMarkdownWikiDestinationAttribute
                              atIndex:wikiRange.location effectiveRange:NULL] isEqualToString:@"Child"]);

        // Atomic replacement can preserve both size and mtime. The inode-based
        // identity must still invalidate the cached rendered Markdown.
        NSString* replacePath = [root stringByAppendingPathComponent:@"replace.md"];
        NSString* replacementPath = [root stringByAppendingPathComponent:@"replacement.md"];
        WriteText(@"before\n", replacePath);
        struct stat beforeStat;
        assert(stat(replacePath.fileSystemRepresentation, &beforeStat) == 0);
        NSDictionary* beforeAttributes = [NSFileManager.defaultManager attributesOfItemAtPath:replacePath error:nil];
        NSString* beforeIdentity = spdf_mac_markdown_file_identity(replacePath);
        WriteText(@"after!\n", replacementPath);
        assert(rename(replacementPath.fileSystemRepresentation, replacePath.fileSystemRepresentation) == 0);
        struct timespec preservedTimes[2] = {beforeStat.st_atimespec, beforeStat.st_mtimespec};
        assert(utimensat(AT_FDCWD, replacePath.fileSystemRepresentation, preservedTimes, 0) == 0);
        NSDictionary* afterAttributes = [NSFileManager.defaultManager attributesOfItemAtPath:replacePath error:nil];
        NSString* afterIdentity = spdf_mac_markdown_file_identity(replacePath);
        assert([beforeAttributes[NSFileSize] isEqual:afterAttributes[NSFileSize]]);
        assert([beforeAttributes[NSFileModificationDate] isEqual:afterAttributes[NSFileModificationDate]]);
        assert(beforeIdentity.length && afterIdentity.length && ![beforeIdentity isEqualToString:afterIdentity]);
        assert(!spdf_mac_markdown_cache_matches(beforeAttributes[NSFileModificationDate],
                                                [beforeAttributes[NSFileSize] unsignedLongLongValue],
                                                beforeIdentity, afterAttributes, afterIdentity));

        [NSFileManager.defaultManager removeItemAtPath:root error:nil];
        [NSFileManager.defaultManager removeItemAtPath:outside error:nil];
        puts("SPDFMacMarkdownRoutingTests passed");
    }
    return 0;
}
