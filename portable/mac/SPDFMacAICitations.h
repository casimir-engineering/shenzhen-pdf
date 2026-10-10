#pragma once
#import <Foundation/Foundation.h>
// A clickable document citation must have been issued by a tool in this chat.
NSDictionary* SPDFMacAICitationArguments(NSURL* URL);
BOOL SPDFMacAIChatContainsCitation(NSDictionary* chat, NSDictionary* arguments);
