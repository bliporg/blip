//
//  passkey.mm
//  xptools
//
//  Created by Gaetan de Villele on 28/03/2025.
//  Copyright © 2025 voxowl. All rights reserved.
//

#include "passkey.hpp"

#import "Foundation/Foundation.h"
#import "AuthenticationServices/AuthenticationServices.h"

@interface PassKeyObjc : NSObject <ASAuthorizationControllerDelegate>
- (void)saveWithChallenge:(const std::string&)challenge
                  userID:(const std::string&)userID
                 domain:(const std::string&)domain
               username:(const std::string&)username;
@end

@implementation PassKeyObjc

- (void)authorizationController:(ASAuthorizationController *)controller didCompleteWithAuthorization:(ASAuthorization *)authorization {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    if (@available(iOS 16.0, *)) {
//        if ([authorization.credential isKindOfClass:[ASAuthorizationPlatformPublicKeyCredentialRegistration class]]) {
//            ASAuthorizationPlatformPublicKeyCredentialRegistration *credential = (ASAuthorizationPlatformPublicKeyCredentialRegistration *)authorization.credential;
//            // Handle successful registration
//            NSLog(@"Passkey registration successful");
//        }
    }
#endif
}

- (void)authorizationController:(ASAuthorizationController *)controller didCompleteWithError:(NSError *)error {
    NSLog(@"Passkey registration failed: %@", error.localizedDescription);
}

- (void)saveWithChallenge:(const std::string&)challenge
                  userID:(const std::string&)userID
                 domain:(const std::string&)domain
               username:(const std::string&)username {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    if (@available(iOS 16.0, *)) {
        // Obtain these from the server
        NSData *challengeData = [NSData dataWithBytes:challenge.c_str() length:challenge.length()];
        NSData *userIDData = [NSData dataWithBytes:userID.c_str() length:userID.length()];
        NSString *domainStr = [NSString stringWithUTF8String:domain.c_str()];
        NSString *usernameStr = [NSString stringWithUTF8String:username.c_str()];

        ASAuthorizationPlatformPublicKeyCredentialProvider *platformProvider = [[ASAuthorizationPlatformPublicKeyCredentialProvider alloc] initWithRelyingPartyIdentifier:domainStr];
        ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest *platformKeyRequest = [platformProvider createCredentialRegistrationRequestWithChallenge:challengeData name:usernameStr userID:userIDData];

        ASAuthorizationController *authController = [[ASAuthorizationController alloc] initWithAuthorizationRequests:@[platformKeyRequest]];
        authController.delegate = self;
        [authController performRequests];
    }
#endif
}

@end

bool vx::auth::PassKey::IsAvailable() {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    if (@available(iOS 16.0, *)) {
        return true;
    }
#elif TARGET_OS_MAC
    // Not available on macOS for now
    //        if (@available(macOS 13.0, *)) {
    //            return true;
    //        }
#endif
    return false;
}

void vx::auth::PassKey::initPlatformImpl() {
    PassKeyObjc *passKeyObjc = [[PassKeyObjc alloc] init];
    _platformImpl = (__bridge void *)passKeyObjc;
}

void vx::auth::PassKey::save() {
    PassKeyObjc *passKeyObjc = (__bridge PassKeyObjc *)_platformImpl;
    [passKeyObjc saveWithChallenge:_challenge userID:_userID domain:_domain username:_username];
}
