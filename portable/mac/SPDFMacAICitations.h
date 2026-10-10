#pragma once
#import <Foundation/Foundation.h>
// A clickable document citation must have been issued by a tool in this chat.
NSDictionary* SPDFMacAICitationArguments(NSURL* URL);
BOOL SPDFMacAIChatContainsCitation(NSDictionary* chat, NSDictionary* arguments);
// Drop an invented highlight only when the exact page/revision has a retrieved page citation.
NSDictionary* SPDFMacAIResolveCitation(NSDictionary* chat, NSDictionary* arguments);
NSString* SPDFMacAIRepairCitationLinks(NSString* text, NSDictionary* chat);
