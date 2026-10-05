#pragma once
#import <Cocoa/Cocoa.h>
@interface SPDFGroupManagementTable : NSTableView
@property(nonatomic) BOOL draggedDuringPress;
@end
NSView* SPDFGroupDocumentBadge(NSString* path);
