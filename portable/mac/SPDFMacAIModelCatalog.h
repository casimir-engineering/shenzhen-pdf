#pragma once
#import <Foundation/Foundation.h>
NSDictionary* SPDFMacAIModelFromCatalog(NSData* data, NSString* identifier, NSError** error);
// Only invoked by an explicit connection/model setting change; no startup fetch.
NSURLSessionDataTask* SPDFMacAIValidateModel(NSString* identifier, void (^completion)(NSDictionary*,NSError*));
