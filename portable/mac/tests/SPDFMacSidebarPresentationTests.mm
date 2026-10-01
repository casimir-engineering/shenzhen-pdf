#import <Cocoa/Cocoa.h>
#import "SPDFMacSidebarPresentation.h"

static int failures;
static void Check(BOOL okay,NSString* reason) { if (!okay) { fprintf(stderr,"FAIL: %s\n",reason.UTF8String); failures++; } }
static NSTextField* Field(NSView* view,NSString* identifier) {
    for (NSView* child in view.subviews) if ([child.identifier isEqual:identifier]) return (NSTextField*)child;
    return nil;
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSTableView* table = [NSTableView new];
        NSDictionary* item = @{@"kind":@"findResult",@"title":@"Verify power sequencing and recovery before release.",
            @"subtitle":@"Page 4 · match 2 of 3",@"query":@"power"};
        NSRange hit = [item[@"title"] rangeOfString:@"power"];
        for (NSNumber* width in @[@176,@240,@400]) {
            NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,width.doubleValue,64)
                styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
            window.releasedWhenClosed = NO;
            NSTableCellView* cell = SPDFSidebarFindCell(table,item,@[[NSValue valueWithRange:hit],
                [NSValue valueWithRange:NSMakeRange(NSNotFound,NSUIntegerMax)]]);
            window.contentView = cell; [cell layoutSubtreeIfNeeded];
            NSTextField* metadata = Field(cell,@"metadata");
            Check(!window.visible,@"appearance validation never presents a reader window");
            Check(metadata.stringValue.length > 0,@"page and result position remain available");
            Check(NSMinY(metadata.frame) >= NSMaxY(cell.textField.frame)+2,
                @"metadata is above the context without overlap in AppKit bottom-up coordinates");
            NSRect textAlignment = [cell.textField alignmentRectForFrame:cell.textField.frame];
            Check(NSMinX(textAlignment)>=15 && NSMaxX(textAlignment)<=width.doubleValue-15,
                @"context retains consistent side insets at narrow and wide widths");
            Check(NSMinY(cell.textField.frame)>=5,@"two-line context remains within its row");
            Check(cell.textField.maximumNumberOfLines==2,@"context wraps rather than losing everything after one short line");
            NSAttributedString* text = cell.textField.attributedStringValue;
            Check([text attribute:NSBackgroundColorAttributeName atIndex:hit.location effectiveRange:nil] != nil,
                @"the query remains highlighted in its surrounding context");
            Check([text attribute:NSBackgroundColorAttributeName atIndex:0 effectiveRange:nil] == nil,
                @"unmatched context has no highlight");
            NSFont* body = [text attribute:NSFontAttributeName atIndex:0 effectiveRange:nil];
            NSFont* matched = [text attribute:NSFontAttributeName atIndex:hit.location effectiveRange:nil];
            Check([body isEqual:matched] && body.pointSize==12,@"highlighting does not alter weight or text geometry");
            Check([cell.toolTip containsString:item[@"title"]],@"full context remains available when visually truncated");
        }
        NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,300,200)];
        scroll.hasVerticalScroller = YES; scroll.hasHorizontalScroller = NO;
        NSTableView* resizingTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0,0,400,200)];
        resizingTable.headerView = nil; resizingTable.intercellSpacing = NSZeroSize;
        [resizingTable addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"title"]];
        scroll.documentView = resizingTable;
        for (NSNumber* width in @[@300,@176,@240]) {
            [scroll setFrameSize:NSMakeSize(width.doubleValue,200)]; [scroll tile];
            SPDFSidebarFitTableToViewport(resizingTable);
            CGFloat viewport = floor(NSWidth(scroll.contentView.bounds));
            Check(fabs(NSWidth(resizingTable.frame)-viewport)<.5 &&
                fabs(resizingTable.tableColumns.firstObject.width-viewport)<.5,
                @"table and trailing column follow the actual clip viewport when shrinking and expanding");
            Check(!SPDFSidebarFitTableToViewport(resizingTable),@"unchanged viewport skips row remeasurement");
        }
        NSTableCellView* heading = SPDFSidebarFindCell(table,@{@"kind":@"findDivider",@"title":@"Electrical interfaces"},@[]);
        Check(heading.subviews.count==1 && heading.textField.font.pointSize==10,
            @"chapter grouping stays as a quiet label without capsule or decorative rule");
        NSTableRowView* row = SPDFSidebarRowView();
        Check(row.interiorBackgroundStyle==NSBackgroundStyleNormal,
            @"selection preserves explicit readable foreground colors instead of forcing white text");
        Check(SPDFSidebarFindRowHeight(item)==64,@"context rows have space for metadata and two readable lines");
        if (!failures) puts("SPDFMacSidebarPresentationTests passed");
        return failures ? 1 : 0;
    }
}
