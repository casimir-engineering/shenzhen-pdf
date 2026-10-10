#pragma once
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <LocalAuthentication/LocalAuthentication.h>
#include <mutex>

// LAContext covers data-protection items, but legacy login-Keychain ACLs can
// still display UI. Keep both policies; never relax an item's access control.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
inline void SPDFKeychainDisallowAuthenticationUI(NSMutableDictionary* query) {
    LAContext* context=[LAContext new]; context.interactionNotAllowed=YES;
    query[(__bridge id)kSecUseAuthenticationContext]=context;
    query[(__bridge id)kSecUseAuthenticationUI]=(__bridge id)kSecUseAuthenticationUIFail;
}

// The legacy switch is process-wide. One inline-function static mutex is shared
// across translation units so AI and Collection cannot restore UI under each
// other's operation. Construction does no Keychain work; failure is closed.
inline OSStatus SPDFKeychainWithoutInteraction(OSStatus (^operation)(void),
    OSStatus (*getAllowed)(Boolean*)=SecKeychainGetUserInteractionAllowed,
    OSStatus (*setAllowed)(Boolean)=SecKeychainSetUserInteractionAllowed) {
    static std::recursive_mutex mutex;
    std::lock_guard<std::recursive_mutex> lock(mutex);
    Boolean previous=false;
    OSStatus status=getAllowed(&previous);
    if(status!=errSecSuccess)return status;
    status=setAllowed(false);
    if(status!=errSecSuccess)return status;
    @try { status=operation(); }
    @finally {
        OSStatus restored=setAllowed(previous);
        if(status==errSecSuccess && restored!=errSecSuccess)status=restored;
    }
    return status;
}
#pragma clang diagnostic pop
