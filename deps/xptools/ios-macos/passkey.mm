//
//  passkey.mm
//  xptools
//
//  Created by Gaetan de Villele on 28/03/2025.
//  Copyright © 2025 voxowl. All rights reserved.
//

#include "passkey.hpp"

// Apple
#import "Foundation/Foundation.h"
#import "AuthenticationServices/AuthenticationServices.h"

// xptools
#import "apple-utils.h"

//
// MARK: - PasskeyDelegate class -
//

// PasskeyDelegate class signature
@interface PasskeyDelegate : NSObject <ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding>

typedef void (^DidCompleteAuthorization)(NSString *credentialIDBase64,
                                         NSString *rawClientDataJSONBase64,
                                         NSString *rawAttestationObjectBase64,
                                         NSString *error);

typedef void (^DidCompleteAssertion)(NSString *credentialIDBase64,
                                     NSString *authenticatorDataBase64,
                                     NSString *rawClientDataJSONString,
                                     NSString *signatureBase64,
                                     NSString *userIDString,
                                     NSString *error);

@property (nonatomic, copy) DidCompleteAuthorization didCompleteAuthorizationHandler;
@property (nonatomic, copy) DidCompleteAssertion didCompleteAssertionHandler;

@end

// PasskeyDelegate class implementation
@implementation PasskeyDelegate

- (instancetype)initWithAuthorizationCompletionHandler:(DidCompleteAuthorization)completionHandler {
    self = [super init];
    if (self) {
        self.didCompleteAuthorizationHandler = completionHandler;
    }
    return self;
}

- (instancetype)initWithAssertionCompletionHandler:(DidCompleteAssertion)completionHandler {
    self = [super init];
    if (self) {
        self.didCompleteAssertionHandler = completionHandler;
    }
    return self;
}

/// Authorization success
- (void)authorizationController:(ASAuthorizationController *)controller didCompleteWithAuthorization:(ASAuthorization *)authorization {

    if ([authorization.credential isKindOfClass:[ASAuthorizationPlatformPublicKeyCredentialRegistration class]]) {
        // handle the registration

        // ensure the callback has been defined
        if (self.didCompleteAuthorizationHandler == nil) {
            NSLog(@"❌ Error: self.didCompleteAuthorizationHandler is nil");
            return;
        }

        ASAuthorizationPlatformPublicKeyCredentialRegistration *credentialRegistration = (ASAuthorizationPlatformPublicKeyCredentialRegistration *)authorization.credential;

        // Convert the raw attestation object to base64 string
        NSData *credentialID = credentialRegistration.credentialID;
        NSData *rawClientDataJSON = credentialRegistration.rawClientDataJSON;
        NSData *rawAttestationObject = credentialRegistration.rawAttestationObject;

        if (credentialID == nil || rawClientDataJSON == nil || rawAttestationObject == nil) {
            self.didCompleteAuthorizationHandler(nil, nil, nil, @"Error: credentialID, rawClientDataJSON, or rawAttestationObject is nil");
            return;
        }

        // encode binary values into base64
        NSString *credentialIDBase64 = [credentialID base64UrlEncodedString];
        NSString *rawClientDataJSONBase64 = [rawClientDataJSON base64UrlEncodedString];
        NSString *rawAttestationObjectBase64 = [rawAttestationObject base64UrlEncodedString];

        // Call the completion handler with the public key
        self.didCompleteAuthorizationHandler(credentialIDBase64,
                                             rawClientDataJSONBase64,
                                             rawAttestationObjectBase64,
                                             nil);

    } else if ([authorization.credential isKindOfClass:[ASAuthorizationPlatformPublicKeyCredentialAssertion class]]) {
        // verify the challenge

        // ensure the callback has been defined
        if (self.didCompleteAssertionHandler == nil) {
            NSLog(@"❌ Error: self.didCompleteAssertionHandler is nil");
            return;
        }

        ASAuthorizationPlatformPublicKeyCredentialAssertion *credentialAssertion = (ASAuthorizationPlatformPublicKeyCredentialAssertion *)authorization.credential;

        // Convert the raw attestation object to base64 string
        NSData *credentialID = credentialAssertion.credentialID;
        NSData *authenticatorData = credentialAssertion.rawAuthenticatorData;
        NSData *rawClientDataJSON = credentialAssertion.rawClientDataJSON;
        NSData *signature = credentialAssertion.signature;
        NSData *userID = credentialAssertion.userID;

        if (credentialID == nil ||
            authenticatorData == nil ||
            rawClientDataJSON == nil ||
            signature == nil ||
            userID == nil) {
            self.didCompleteAssertionHandler(nil, nil, nil, nil, nil, @"Error: credentialID, authenticatorData, rawClientDataJSON, signature, or userID is nil");
            return;
        }

        // encode binary values into base64
        NSString *credentialIDBase64 = [credentialID base64UrlEncodedString];
        NSString *authenticatorDataBase64 = [authenticatorData base64UrlEncodedString];
        NSString *rawClientDataJSONString = [[NSString alloc] initWithData:rawClientDataJSON encoding:NSUTF8StringEncoding];
        NSString *signatureBase64 = [signature base64UrlEncodedString];
        NSString *userIDString = [[NSString alloc] initWithData:userID encoding:NSUTF8StringEncoding];

        // Call the completion handler with the public key
        self.didCompleteAssertionHandler(credentialIDBase64,
                                         authenticatorDataBase64,
                                         rawClientDataJSONString,
                                         signatureBase64,
                                         userIDString,
                                         nil);

    } else {
        NSLog(@"❌ Unsupported type. This should not happen.");
    }
}

/// Authorization failure
- (void)authorizationController:(ASAuthorizationController *)controller didCompleteWithError:(NSError *)error {

    // get error message
    NSString *errorMessage = [NSString stringWithFormat:@"%@", error.localizedDescription];

    // call callback
    if (self.didCompleteAuthorizationHandler) {
        // Call the completion handler with the error
        self.didCompleteAuthorizationHandler(nil, nil, nil, errorMessage);
    } else if (self.didCompleteAssertionHandler) {
        self.didCompleteAssertionHandler(nil, nil, nil, nil, nil, errorMessage);
    } else {
        NSLog(@"❌ Error: no completion handler defined");
    }
}

- (nonnull ASPresentationAnchor)presentationAnchorForAuthorizationController:(nonnull ASAuthorizationController *)controller {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // if we are on iOS, return the current window
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] &&
                scene.activationState == UISceneActivationStateForegroundActive) {

                UIWindowScene *windowScene = (UIWindowScene *)scene;

                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        return window;
                    }
                }
            }
        }

        // If no key window found, return any visible window as fallback
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                if (windowScene.windows.count > 0) {
                    return windowScene.windows.firstObject;
                }
            }
        }

        // Absolute fallback to avoid returning nil
        return [[UIWindow alloc] initWithFrame:CGRectZero];
#elif TARGET_OS_MAC
    // if we are on macOS, return the current window
    return [[NSApplication sharedApplication] keyWindow];
#endif
}

@end

PasskeyDelegate *passkeyDelegate = nil;

//
// MARK: - C++ implementation -
//

bool vx::auth::PassKey::IsAvailable() {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    if (@available(iOS 16.0, *)) {
        return true;
    }
#elif TARGET_OS_MAC
    if (@available(macOS 13.0, *)) {
        return true;
    }
#endif
    return false;
}

// What we need from the server:
// - std::string challenge
// - std::string userID
// - std::string username
// Return value:
// - std::string error string if something went wrong (empty string on success)
// TODO: review arguments order where it is called
std::string vx::auth::PassKey::createPasskey(const std::string& relyingPartyIdentifier,
                                             const std::string& challenge,
                                             const std::string& userID,
                                             const std::string& username,
                                             CreatePasskeyCallbackFunc callback) {

    NSLog(@"Creating a PassKey! challenge: %s, userID: %s, username: %s",
          challenge.c_str(), userID.c_str(), username.c_str());

    // validate arguments
    if (relyingPartyIdentifier.empty()) {
        return "relyingPartyIdentifier argument is empty";
    }
    if (challenge.empty()) {
        return "challenge argument is empty";
    }
    if (userID.empty()) {
        return "userID argument is empty";
    }
    if (username.empty()) {
        return "username argument is empty";
    }

    NSString *kRelyingPartyIdentifier = [NSString stringWithUTF8String:relyingPartyIdentifier.c_str()];

    // Assuming these are obtained from the server
    NSData *challengeData = [NSData dataWithBytes:challenge.c_str() length:challenge.size()];
    NSData *userIDData = [NSData dataWithBytes:userID.c_str() length:userID.size()];
    NSString *userNameStr = [NSString stringWithUTF8String:username.c_str()];

    ASAuthorizationPlatformPublicKeyCredentialProvider *platformProvider =
    [[ASAuthorizationPlatformPublicKeyCredentialProvider alloc]
     initWithRelyingPartyIdentifier:kRelyingPartyIdentifier];

    ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest *platformKeyRequest =
    [platformProvider createCredentialRegistrationRequestWithChallenge:challengeData
                                                                  name:userNameStr
                                                                userID:userIDData];

    ASAuthorizationController *authController = [[ASAuthorizationController alloc] initWithAuthorizationRequests:@[platformKeyRequest]];

    // Create a delegate instance
    passkeyDelegate = [[PasskeyDelegate alloc] initWithAuthorizationCompletionHandler:^(NSString *credentialIDBase64,
                                                                                        NSString *rawClientDataJSONBase64,
                                                                                        NSString *rawAttestationObjectBase64,
                                                                                        NSString *error) {
        if (callback == nil) {
            NSLog(@"❌ [vx::device::createPasskey] Error: callback is nil");
            return;
        }

        if (error != nil) {
            // error
            callback(PassKey::CreateResponse{}, std::string([error UTF8String]));
            return;
        }

        // success
        PassKey::CreateResponse resp = PassKey::CreateResponse(std::string([credentialIDBase64 UTF8String]),
                                                               std::string([rawClientDataJSONBase64 UTF8String]),
                                                               std::string([rawAttestationObjectBase64 UTF8String]));
        callback(resp, "");
    }];

    authController.delegate = passkeyDelegate;
    authController.presentationContextProvider = passkeyDelegate;

    [authController performRequests];

    return ""; // success, no error
}

/// Returns an empty string on success or an error message on failure
std::string vx::auth::PassKey::loginWithPasskey(const std::string& relyingPartyIdentifier,
                                                const std::string& challengeBytes,
                                                LoginWithPasskeyCallbackFunc callback) {
    NSLog(@"Logging in with  a PassKey! RP ID: %s", relyingPartyIdentifier.c_str());

    // validate arguments
    if (relyingPartyIdentifier.empty()) {
        return "relying party identifier argument is empty"; // error
    }

    NSString *kRelyingPartyIdentifier = [NSString stringWithUTF8String:relyingPartyIdentifier.c_str()];
    NSData *challengeData = [NSData dataWithBytes:challengeBytes.c_str() length:challengeBytes.size()];

    ASAuthorizationPlatformPublicKeyCredentialProvider *platformProvider = [[ASAuthorizationPlatformPublicKeyCredentialProvider alloc] initWithRelyingPartyIdentifier:kRelyingPartyIdentifier];

    ASAuthorizationPlatformPublicKeyCredentialAssertionRequest *assertionRequest = [platformProvider createCredentialAssertionRequestWithChallenge:challengeData];

    ASAuthorizationController *authController = [[ASAuthorizationController alloc] initWithAuthorizationRequests:@[assertionRequest]];

    // Create a delegate instance
    passkeyDelegate = [[PasskeyDelegate alloc] initWithAssertionCompletionHandler:^(NSString *credentialIDBase64,
                                                                                    NSString *authenticatorDataBase64,
                                                                                    NSString *rawClientDataJSONString,
                                                                                    NSString *signatureBase64,
                                                                                    NSString *userIDString,
                                                                                    NSString *error) {
        if (callback == nil) {
            NSLog(@"❌ [vx::device::loginWithPasskey] Error: callback is nil");
            return;
        }

        if (error != nil) {
            // error
            callback(nullptr, std::string([error UTF8String]));
            return;
        }

        // success
        PassKey::LoginResponse_SharedPtr resp = PassKey::LoginResponse::fromComponents(std::string([credentialIDBase64 UTF8String]),
                                                                                       std::string([authenticatorDataBase64 UTF8String]),
                                                                                       std::string([rawClientDataJSONString UTF8String]),
                                                                                       std::string([signatureBase64 UTF8String]),
                                                                                       std::string([userIDString UTF8String]));
        callback(resp, "");
    }];

    authController.delegate = passkeyDelegate;
    authController.presentationContextProvider = passkeyDelegate;

    [authController performRequests];

    return ""; // success
}
