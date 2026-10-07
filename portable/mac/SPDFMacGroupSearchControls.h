#pragma once
#import <Cocoa/Cocoa.h>

@interface SPDFGroupSearchCell : NSSearchFieldCell
@end
@implementation SPDFGroupSearchCell
- (NSRect)searchTextRectForBounds:(NSRect)bounds {
    NSRect rect=[super searchTextRectForBounds:bounds];
    // An empty search has no cancel action. Give its placeholder that space.
    if (!self.stringValue.length) rect.size.width=MAX(0,NSMaxX(bounds)-8-NSMinX(rect));
    return rect;
}
@end

static void SPDFUpdateGroupSearchPlaceholder(NSSearchField* field) {
    if (field.stringValue.length) return;
    CGFloat width=NSWidth([(NSSearchFieldCell*)field.cell searchTextRectForBounds:field.bounds])-2;
    NSDictionary* attributes=@{NSFontAttributeName:field.font ?: [NSFont systemFontOfSize:13]};
    for (NSString* text in @[@"Search groups and documents",@"Search groups and docs",@"Groups & docs",@"Search…"]) {
        if ([text sizeWithAttributes:attributes].width<=width) { field.placeholderString=text; return; }
    }
    field.placeholderString=@"";
}

static NSImage* SPDFGroupExpansionImage(BOOL collapse) {
    static NSImage* images[2]; static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (NSUInteger index=0;index<2;index++) {
            BOOL inward=index==1;
            images[index]=[NSImage imageWithSize:NSMakeSize(20,20) flipped:NO drawingHandler:^BOOL(NSRect rect) {
                (void)rect; [NSColor.blackColor setStroke];
                NSBezierPath* outline=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1,1,18,18) xRadius:4 yRadius:4];
                outline.lineWidth=1.4; [outline stroke];
                NSBezierPath* arrows=[NSBezierPath bezierPath]; arrows.lineWidth=1.4;
                arrows.lineCapStyle=NSLineCapStyleRound; arrows.lineJoinStyle=NSLineJoinStyleRound;
                if (inward) {
                    [arrows moveToPoint:NSMakePoint(15,15)]; [arrows lineToPoint:NSMakePoint(11.5,11.5)];
                    [arrows moveToPoint:NSMakePoint(11.5,15)]; [arrows lineToPoint:NSMakePoint(11.5,11.5)]; [arrows lineToPoint:NSMakePoint(15,11.5)];
                    [arrows moveToPoint:NSMakePoint(5,5)]; [arrows lineToPoint:NSMakePoint(8.5,8.5)];
                    [arrows moveToPoint:NSMakePoint(5,8.5)]; [arrows lineToPoint:NSMakePoint(8.5,8.5)]; [arrows lineToPoint:NSMakePoint(8.5,5)];
                } else {
                    [arrows moveToPoint:NSMakePoint(11,11)]; [arrows lineToPoint:NSMakePoint(15,15)];
                    [arrows moveToPoint:NSMakePoint(11,15)]; [arrows lineToPoint:NSMakePoint(15,15)]; [arrows lineToPoint:NSMakePoint(15,11)];
                    [arrows moveToPoint:NSMakePoint(9,9)]; [arrows lineToPoint:NSMakePoint(5,5)];
                    [arrows moveToPoint:NSMakePoint(5,9)]; [arrows lineToPoint:NSMakePoint(5,5)]; [arrows lineToPoint:NSMakePoint(9,5)];
                }
                [arrows stroke]; return YES;
            }];
            // Match the adjacent scope symbol visually; keep the 26-point hit target.
            images[index].size=NSMakeSize(16,16);
            [images[index] setTemplate:YES];
        }
    });
    return images[collapse ? 1 : 0];
}
