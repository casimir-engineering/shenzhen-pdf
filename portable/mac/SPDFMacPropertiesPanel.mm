#import "SPDFMacPropertiesPanel.h"

#import "SPDFMacPassword.h"
#import "SPDFMacPropertiesFormat.h"

// Panel subclass so Escape and Cmd+W close the panel itself (Cmd+W would
// otherwise fall through to the File > Close menu item and close the active
// tab). sendEvent: catches Escape regardless of which field is first
// responder; performKeyEquivalent: runs before the main menu gets the event.
@interface SPDFPropertiesPanel : NSPanel
@end

@implementation SPDFPropertiesPanel

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (void)sendEvent:(NSEvent*)event {
    if (event.type == NSEventTypeKeyDown && event.keyCode == 53) {
        [self close];
        return;
    }
    [super sendEvent:event];
}

- (BOOL)performKeyEquivalent:(NSEvent*)event {
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (flags == NSEventModifierFlagCommand && [event.charactersIgnoringModifiers isEqualToString:@"w"]) {
        [self close];
        return YES;
    }
    return [super performKeyEquivalent:event];
}

@end

// Flipped host for the scroll view so the grid pins to the top.
@interface SPDFPropertiesContentView : NSView
@end

@implementation SPDFPropertiesContentView

- (BOOL)isFlipped {
    return YES;
}

@end

static const CGFloat kPropertiesPanelWidth = 560.0;
static const CGFloat kPropertiesValueMaxWidth = 360.0;
static const CGFloat kPropertiesMaxScrollHeight = 520.0;

@interface SPDFPropertiesPanelController () <NSWindowDelegate>
@property(atomic) BOOL wordCountCancelled;
@end

@implementation SPDFPropertiesPanelController {
    NSPanel* _panel;
    // Section model driving both the grid and Copy All. Each section is
    // @{@"title", @"rows"}; each row is a mutable @{@"label", @"value"} plus
    // optional @"tooltip" and @"middleTruncate". The text-stats row is mutated
    // in place when the async count lands.
    NSArray<NSDictionary*>* _sections;
    NSMutableDictionary* _textStatsRow;
    NSTextField* _textStatsField;
    NSButton* _copyAllButton;
}

// Keeps controllers alive while their panel is visible (the delegate holds no
// reference; the panel is rebuilt fresh on every open).
static NSMutableSet<SPDFPropertiesPanelController*>* spdf_properties_visible_controllers(void) {
    static NSMutableSet* controllers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controllers = [NSMutableSet set]; });
    return controllers;
}

static NSString* spdf_properties_metadata(spdf_document* doc, const char* key) {
    char buffer[4096];
    if (!spdf_lookup_metadata(doc, key, buffer, sizeof(buffer))) return @"";
    NSString* value = [NSString stringWithUTF8String:buffer] ?: @"";
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString* spdf_properties_display_date(NSDate* date) {
    if (!date) return @"";
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:date] ?: @"";
}

static NSString* spdf_properties_grouped(NSUInteger value) {
    NSNumberFormatter* formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    return [formatter stringFromNumber:@(value)] ?: [NSString stringWithFormat:@"%lu", (unsigned long)value];
}

static NSMutableDictionary* spdf_properties_row(NSString* label, NSString* value) {
    return [NSMutableDictionary dictionaryWithDictionary:@{@"label" : label, @"value" : value}];
}

+ (void)presentForDocument:(spdf_document*)doc
                sourcePath:(NSString*)sourcePath
               workingPath:(NSString*)workingPath
                 pageIndex:(NSInteger)pageIndex
              outlineCount:(NSInteger)outlineCount
           annotationCount:(NSInteger)annotationCount
              parentWindow:(NSWindow*)parentWindow {
    if (!doc) return;

    // One properties panel at a time: a fresh open replaces (and cancels) the
    // previous one so the panel always reflects the active tab at open time.
    for (SPDFPropertiesPanelController* controller in [spdf_properties_visible_controllers() copy])
        [controller close];

    SPDFPropertiesPanelController* controller = [[SPDFPropertiesPanelController alloc] init];
    [controller buildSectionsForDocument:doc
                              sourcePath:sourcePath
                               pageIndex:pageIndex
                            outlineCount:outlineCount
                         annotationCount:annotationCount];
    [controller buildPanelWithSourcePath:sourcePath parentWindow:parentWindow];
    [spdf_properties_visible_controllers() addObject:controller];
    [controller startWordCountForPath:workingPath.length ? workingPath : sourcePath sourcePath:sourcePath];
}

- (void)buildSectionsForDocument:(spdf_document*)doc
                      sourcePath:(NSString*)sourcePath
                       pageIndex:(NSInteger)pageIndex
                    outlineCount:(NSInteger)outlineCount
                 annotationCount:(NSInteger)annotationCount {
    NSMutableArray<NSDictionary*>* sections = [NSMutableArray array];

    // Document metadata (rows with empty values are omitted).
    NSMutableArray* documentRows = [NSMutableArray array];
    NSDictionary<NSString*, NSString*>* metadataRows = @{
        @"Title" : @"info:Title",
        @"Author" : @"info:Author",
        @"Subject" : @"info:Subject",
        @"Keywords" : @"info:Keywords",
        @"Creator" : @"info:Creator",
        @"Producer" : @"info:Producer",
    };
    for (NSString* label in @[ @"Title", @"Author", @"Subject", @"Keywords", @"Creator", @"Producer" ]) {
        NSString* value = spdf_properties_metadata(doc, metadataRows[label].UTF8String);
        if (value.length) [documentRows addObject:spdf_properties_row(label, value)];
    }
    NSString* encryption = spdf_properties_metadata(doc, "encryption");
    if ([encryption isEqualToString:@"None"]) encryption = @"";
    if (encryption.length && spdf_is_password_protected(doc))
        encryption = [encryption stringByAppendingString:@" (password protected)"];
    NSString* security =
        spdf_properties_security_summary(encryption, spdf_has_permission(doc, 'p'), spdf_has_permission(doc, 'c'),
                                         spdf_has_permission(doc, 'e'), spdf_has_permission(doc, 'n'));
    [documentRows addObject:spdf_properties_row(@"Security", security)];
    [sections addObject:@{@"title" : @"Document", @"rows" : documentRows}];

    // Dates: PDF metadata dates first; on-disk dates appear when there is no
    // PDF counterpart or when they differ meaningfully (> 60 s).
    NSDictionary* fileAttributes = sourcePath.length
                                       ? [NSFileManager.defaultManager attributesOfItemAtPath:sourcePath error:nil]
                                       : nil;
    NSMutableArray* dateRows = [NSMutableArray array];
    NSString* rawCreated = spdf_properties_metadata(doc, "info:CreationDate");
    NSString* rawModified = spdf_properties_metadata(doc, "info:ModDate");
    NSDate* pdfCreated = spdf_properties_parse_pdf_date(rawCreated);
    NSDate* pdfModified = spdf_properties_parse_pdf_date(rawModified);
    if (pdfCreated) {
        NSMutableDictionary* row = spdf_properties_row(@"Created", spdf_properties_display_date(pdfCreated));
        row[@"tooltip"] = rawCreated;
        [dateRows addObject:row];
    } else if (rawCreated.length) {
        [dateRows addObject:spdf_properties_row(@"Created", rawCreated)];  // unparseable: show verbatim
    }
    if (pdfModified) {
        NSMutableDictionary* row = spdf_properties_row(@"Modified", spdf_properties_display_date(pdfModified));
        row[@"tooltip"] = rawModified;
        [dateRows addObject:row];
    } else if (rawModified.length) {
        [dateRows addObject:spdf_properties_row(@"Modified", rawModified)];
    }
    NSDate* fileCreated = fileAttributes[NSFileCreationDate];
    NSDate* fileModified = fileAttributes[NSFileModificationDate];
    if (fileCreated && (!pdfCreated || fabs([fileCreated timeIntervalSinceDate:pdfCreated]) > 60.0))
        [dateRows addObject:spdf_properties_row(@"Created (on disk)", spdf_properties_display_date(fileCreated))];
    if (fileModified && (!pdfModified || fabs([fileModified timeIntervalSinceDate:pdfModified]) > 60.0))
        [dateRows addObject:spdf_properties_row(@"Modified (on disk)", spdf_properties_display_date(fileModified))];
    if (dateRows.count) [sections addObject:@{@"title" : @"Dates", @"rows" : dateRows}];

    // File.
    NSMutableArray* fileRows = [NSMutableArray array];
    if (sourcePath.length) {
        NSMutableDictionary* pathRow = spdf_properties_row(@"Location", sourcePath);
        pathRow[@"tooltip"] = sourcePath;
        pathRow[@"middleTruncate"] = @YES;
        [fileRows addObject:pathRow];
    }
    unsigned long long fileSize = [fileAttributes[NSFileSize] unsignedLongLongValue];
    if (fileAttributes) [fileRows addObject:spdf_properties_row(@"Size", spdf_properties_format_file_size(fileSize))];
    NSString* format = spdf_properties_metadata(doc, "format");
    if (!format.length) format = sourcePath.pathExtension.uppercaseString;
    if (format.length) [fileRows addObject:spdf_properties_row(@"Format", format)];
    if (fileRows.count) [sections addObject:@{@"title" : @"File", @"rows" : fileRows}];

    // Statistics.
    NSMutableArray* statsRows = [NSMutableArray array];
    NSInteger pageCount = spdf_page_count(doc);
    [statsRows addObject:spdf_properties_row(@"Pages", spdf_properties_grouped((NSUInteger)MAX(0, pageCount)))];
    if (pageIndex >= 0 && pageIndex < pageCount) {
        float pageWidth = 0, pageHeight = 0;
        char err[256];
        if (spdf_page_size(doc, (int)pageIndex, &pageWidth, &pageHeight, err, sizeof(err))) {
            NSString* size = spdf_properties_format_page_size_pt(pageWidth, pageHeight);
            if (size.length) {
                NSString* label = [NSString stringWithFormat:@"Page %ld size", (long)pageIndex + 1];
                [statsRows addObject:spdf_properties_row(label, size)];
            }
        }
    }
    NSString* toc = outlineCount > 0
                        ? [NSString stringWithFormat:@"%@ entries", spdf_properties_grouped((NSUInteger)outlineCount)]
                        : @"None";
    [statsRows addObject:spdf_properties_row(@"Table of contents", toc)];
    NSString* annotations =
        annotationCount > 0 ? spdf_properties_grouped((NSUInteger)annotationCount) : @"None";
    [statsRows addObject:spdf_properties_row(@"Annotations", annotations)];
    _textStatsRow = spdf_properties_row(@"Text", @"Counting…");
    [statsRows addObject:_textStatsRow];
    [sections addObject:@{@"title" : @"Statistics", @"rows" : statsRows}];

    _sections = sections;
}

- (NSTextField*)valueFieldForRow:(NSDictionary*)row {
    NSString* value = row[@"value"] ?: @"";
    NSTextField* field;
    if ([row[@"middleTruncate"] boolValue]) {
        field = [NSTextField labelWithString:value];
        field.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
    } else {
        field = [NSTextField wrappingLabelWithString:value];
        field.preferredMaxLayoutWidth = kPropertiesValueMaxWidth;
        field.maximumNumberOfLines = 6;
        field.cell.truncatesLastVisibleLine = YES;
    }
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.selectable = YES;
    field.editable = NO;
    field.font = [NSFont systemFontOfSize:13];
    field.textColor = NSColor.labelColor;
    NSString* tooltip = row[@"tooltip"];
    field.toolTip = tooltip.length ? tooltip : nil;
    [field.widthAnchor constraintLessThanOrEqualToConstant:kPropertiesValueMaxWidth].active = YES;
    return field;
}

- (void)buildPanelWithSourcePath:(NSString*)sourcePath parentWindow:(NSWindow*)parentWindow {
    _panel = [[SPDFPropertiesPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, kPropertiesPanelWidth, 400)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    _panel.title = @"Document Properties";
    _panel.releasedWhenClosed = NO;
    _panel.floatingPanel = YES;
    _panel.hidesOnDeactivate = YES;
    _panel.level = NSModalPanelWindowLevel;
    _panel.collectionBehavior =
        NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorFullScreenAuxiliary;
    _panel.delegate = self;

    NSView* content = [[NSView alloc] initWithFrame:NSZeroRect];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    _panel.contentView = content;

    // Header: file icon, display name, short format/size subtitle.
    NSImageView* iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.image = sourcePath.length ? [NSWorkspace.sharedWorkspace iconForFile:sourcePath]
                                       : [NSImage imageNamed:NSImageNameMultipleDocuments];
    iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [content addSubview:iconView];

    NSString* displayName = sourcePath.lastPathComponent;
    if (!displayName.length) displayName = @"Untitled";
    NSTextField* nameField = [NSTextField labelWithString:displayName];
    nameField.translatesAutoresizingMaskIntoConstraints = NO;
    nameField.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    nameField.textColor = NSColor.labelColor;
    nameField.lineBreakMode = NSLineBreakByTruncatingMiddle;
    nameField.selectable = YES;
    nameField.toolTip = sourcePath.length ? sourcePath : nil;
    [nameField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                        forOrientation:NSLayoutConstraintOrientationHorizontal];
    [content addSubview:nameField];

    NSTextField* subtitleField = [NSTextField labelWithString:[self headerSubtitle]];
    subtitleField.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleField.font = [NSFont systemFontOfSize:12];
    subtitleField.textColor = NSColor.secondaryLabelColor;
    [content addSubview:subtitleField];

    NSBox* headerSeparator = [[NSBox alloc] initWithFrame:NSZeroRect];
    headerSeparator.translatesAutoresizingMaskIntoConstraints = NO;
    headerSeparator.boxType = NSBoxSeparator;
    [content addSubview:headerSeparator];

    // Sections grid inside a scroll view (tall metadata sets stay usable on
    // small screens).
    NSGridView* grid = [NSGridView gridViewWithNumberOfColumns:2 rows:0];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.rowSpacing = 5.0;
    grid.columnSpacing = 12.0;
    grid.rowAlignment = NSGridRowAlignmentFirstBaseline;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;

    BOOL firstSection = YES;
    for (NSDictionary* section in _sections) {
        NSTextField* header = [NSTextField labelWithString:[section[@"title"] uppercaseString]];
        header.translatesAutoresizingMaskIntoConstraints = NO;
        header.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        header.textColor = NSColor.secondaryLabelColor;
        NSGridRow* headerRow = [grid addRowWithViews:@[ header ]];
        [headerRow mergeCellsInRange:NSMakeRange(0, 2)];
        // The merged cell inherits the label column's trailing placement.
        [grid cellForView:header].xPlacement = NSGridCellPlacementLeading;
        headerRow.topPadding = firstSection ? 0.0 : 18.0;
        headerRow.bottomPadding = 2.0;
        firstSection = NO;

        for (NSDictionary* row in section[@"rows"]) {
            NSTextField* label = [NSTextField labelWithString:row[@"label"] ?: @""];
            label.translatesAutoresizingMaskIntoConstraints = NO;
            label.font = [NSFont systemFontOfSize:13];
            label.textColor = NSColor.secondaryLabelColor;
            label.alignment = NSTextAlignmentRight;
            NSTextField* value = [self valueFieldForRow:row];
            if (row == _textStatsRow) _textStatsField = value;
            [grid addRowWithViews:@[ label, value ]];
        }
    }

    SPDFPropertiesContentView* gridHost = [[SPDFPropertiesContentView alloc] initWithFrame:NSZeroRect];
    gridHost.translatesAutoresizingMaskIntoConstraints = NO;
    [gridHost addSubview:grid];

    NSScrollView* scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.borderType = NSNoBorder;
    scrollView.drawsBackground = NO;
    scrollView.documentView = gridHost;
    [content addSubview:scrollView];

    NSBox* footerSeparator = [[NSBox alloc] initWithFrame:NSZeroRect];
    footerSeparator.translatesAutoresizingMaskIntoConstraints = NO;
    footerSeparator.boxType = NSBoxSeparator;
    [content addSubview:footerSeparator];

    _copyAllButton = [NSButton buttonWithTitle:@"Copy All" target:self action:@selector(copyAll:)];
    _copyAllButton.translatesAutoresizingMaskIntoConstraints = NO;
    _copyAllButton.bezelStyle = NSBezelStyleRounded;
    [content addSubview:_copyAllButton];

    NSButton* doneButton = [NSButton buttonWithTitle:@"Done" target:self action:@selector(closePanel:)];
    doneButton.translatesAutoresizingMaskIntoConstraints = NO;
    doneButton.bezelStyle = NSBezelStyleRounded;
    doneButton.keyEquivalent = @"\r";
    [content addSubview:doneButton];

    // Fit the panel to its content, capped so huge metadata scrolls.
    CGFloat gridHeight = grid.fittingSize.height;
    CGFloat scrollHeight = MIN(gridHeight + 4.0, kPropertiesMaxScrollHeight);

    [NSLayoutConstraint activateConstraints:@[
        [content.widthAnchor constraintEqualToConstant:kPropertiesPanelWidth],
        [iconView.topAnchor constraintEqualToAnchor:content.topAnchor constant:18],
        [iconView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [iconView.widthAnchor constraintEqualToConstant:36],
        [iconView.heightAnchor constraintEqualToConstant:36],
        [nameField.topAnchor constraintEqualToAnchor:content.topAnchor constant:19],
        [nameField.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:12],
        [nameField.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-20],
        [subtitleField.topAnchor constraintEqualToAnchor:nameField.bottomAnchor constant:1],
        [subtitleField.leadingAnchor constraintEqualToAnchor:nameField.leadingAnchor],
        [subtitleField.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-20],
        [headerSeparator.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:14],
        [headerSeparator.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [headerSeparator.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [scrollView.topAnchor constraintEqualToAnchor:headerSeparator.bottomAnchor constant:14],
        [scrollView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [scrollView.heightAnchor constraintEqualToConstant:scrollHeight],
        [gridHost.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor],
        [grid.topAnchor constraintEqualToAnchor:gridHost.topAnchor],
        [grid.leadingAnchor constraintEqualToAnchor:gridHost.leadingAnchor constant:20],
        [grid.trailingAnchor constraintLessThanOrEqualToAnchor:gridHost.trailingAnchor constant:-20],
        [grid.bottomAnchor constraintEqualToAnchor:gridHost.bottomAnchor],
        [footerSeparator.topAnchor constraintEqualToAnchor:scrollView.bottomAnchor constant:12],
        [footerSeparator.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [footerSeparator.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [_copyAllButton.topAnchor constraintEqualToAnchor:footerSeparator.bottomAnchor constant:12],
        [_copyAllButton.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [_copyAllButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-14],
        [doneButton.centerYAnchor constraintEqualToAnchor:_copyAllButton.centerYAnchor],
        [doneButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [doneButton.widthAnchor constraintGreaterThanOrEqualToConstant:76],
    ]];

    [content layoutSubtreeIfNeeded];
    [_panel setContentSize:content.fittingSize];

    if (parentWindow) {
        [parentWindow addChildWindow:_panel ordered:NSWindowAbove];
        NSRect windowFrame = parentWindow.frame;
        NSRect panelFrame = _panel.frame;
        panelFrame.origin.x = NSMidX(windowFrame) - NSWidth(panelFrame) * 0.5;
        panelFrame.origin.y = NSMidY(windowFrame) - NSHeight(panelFrame) * 0.5;
        [_panel setFrame:panelFrame display:NO];
    } else {
        [_panel center];
    }
    [_panel makeKeyAndOrderFront:nil];
}

- (NSString*)headerSubtitle {
    NSMutableArray<NSString*>* parts = [NSMutableArray array];
    for (NSDictionary* section in _sections) {
        if (![section[@"title"] isEqualToString:@"File"]) continue;
        for (NSDictionary* row in section[@"rows"]) {
            NSString* label = row[@"label"];
            if ([label isEqualToString:@"Format"]) [parts insertObject:row[@"value"] atIndex:0];
            if ([label isEqualToString:@"Size"]) {
                // "2.4 MB (2,437,120 bytes)" -> "2.4 MB" for the compact header.
                NSString* size = row[@"value"];
                NSRange parenthesis = [size rangeOfString:@" ("];
                if (parenthesis.location != NSNotFound) size = [size substringToIndex:parenthesis.location];
                [parts addObject:size];
            }
        }
    }
    for (NSDictionary* section in _sections) {
        if (![section[@"title"] isEqualToString:@"Statistics"]) continue;
        for (NSDictionary* row in section[@"rows"]) {
            if (![row[@"label"] isEqualToString:@"Pages"]) continue;
            NSString* pages = row[@"value"];
            [parts addObject:[pages isEqualToString:@"1"] ? @"1 page"
                                                          : [NSString stringWithFormat:@"%@ pages", pages]];
        }
    }
    return [parts componentsJoinedByString:@" · "];
}

// Word/character count runs on its own document instance opened from the
// working path (the core's one-thread-per-document contract), checking the
// cancellation flag between pages so closing the panel stops the walk quickly
// even on 1000-page documents.
- (void)startWordCountForPath:(NSString*)path sourcePath:(NSString*)sourcePath {
    if (!path.length || !sourcePath.length || !_textStatsField) {
        [self finishWordCountWithValue:@"Unavailable"];
        return;
    }
    __weak SPDFPropertiesPanelController* weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
      @autoreleasepool {
          char err[1024];
          spdf_document* doc = SPDFOpenDocumentWithStoredCredential(path, sourcePath, NULL, NULL, err, sizeof(err));
          if (!doc) {
              dispatch_async(dispatch_get_main_queue(),
                             ^{ [weakSelf finishWordCountWithValue:@"Unavailable"]; });
              return;
          }
          NSUInteger words = 0;
          NSUInteger chars = 0;
          BOOL cancelled = NO;
          NSInteger pageCount = spdf_page_count(doc);
          for (NSInteger page = 0; page < pageCount; ++page) {
              SPDFPropertiesPanelController* strongSelf = weakSelf;
              if (!strongSelf || strongSelf.wordCountCancelled) {
                  cancelled = YES;
                  break;
              }
              @autoreleasepool {
                  spdf_text_lines lines;
                  memset(&lines, 0, sizeof(lines));
                  if (spdf_extract_page_text_lines(doc, (int)page, &lines, err, sizeof(err))) {
                      for (int i = 0; i < lines.count; ++i) {
                          if (!lines.items[i].text) continue;
                          NSString* text = [NSString stringWithUTF8String:lines.items[i].text];
                          spdf_properties_count_text(text, &words, &chars);
                      }
                  }
                  spdf_free_text_lines(&lines);
              }
          }
          spdf_close(doc);
          if (cancelled) return;
          NSString* value = words == 0 && chars == 0
                                ? @"No text"
                                : [NSString stringWithFormat:@"%@ words · %@ characters",
                                                             spdf_properties_grouped(words),
                                                             spdf_properties_grouped(chars)];
          dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf finishWordCountWithValue:value]; });
      }
    });
}

- (void)finishWordCountWithValue:(NSString*)value {
    if (self.wordCountCancelled) return;
    _textStatsRow[@"value"] = value;
    _textStatsField.stringValue = value;
}

- (void)copyAll:(id)sender {
    (void)sender;
    NSMutableString* text = [NSMutableString string];
    for (NSDictionary* section in _sections) {
        if (text.length) [text appendString:@"\n"];
        [text appendFormat:@"%@\n", section[@"title"]];
        for (NSDictionary* row in section[@"rows"])
            [text appendFormat:@"  %@: %@\n", row[@"label"], row[@"value"]];
    }
    NSPasteboard* pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];

    _copyAllButton.title = @"Copied";
    __weak SPDFPropertiesPanelController* weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      SPDFPropertiesPanelController* strongSelf = weakSelf;
      if (strongSelf) strongSelf->_copyAllButton.title = @"Copy All";
    });
}

- (void)closePanel:(id)sender {
    (void)sender;
    [self close];
}

- (void)close {
    [_panel close];
}

- (void)windowWillClose:(NSNotification*)notification {
    (void)notification;
    self.wordCountCancelled = YES;
    [_panel.parentWindow removeChildWindow:_panel];
    [spdf_properties_visible_controllers() removeObject:self];
}

@end
