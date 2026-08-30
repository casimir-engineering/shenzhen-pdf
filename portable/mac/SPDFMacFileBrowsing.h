#pragma once

#import "SPDFMacDelegatePrivate.h"

NS_ASSUME_NONNULL_BEGIN

// The file-manager-aware open flow: Open..., the Cmd+Shift+O path prompt, and
// the shared "browse a folder for a document" decision they both route through.
@interface ShenzhenMacDelegate (SPDFMacFileBrowsing)
- (void)openDocument:(nullable id)sender;
- (void)openPathPrompt:(nullable id)sender;
- (void)openResolvedPath:(NSString*)input;
// Hands the folder to the preferred file manager, or presents the native Open
// panel rooted there when the preference resolves to the system file manager.
- (void)browseForDocumentInDirectory:(nullable NSString*)directory;
@end

NS_ASSUME_NONNULL_END
