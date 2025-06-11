//
//  utils.mm
//  xptools
//
//  Created by Gaetan de Villele on 12/05/2025.
//  Copyright © 2025 voxowl. All rights reserved.
//

#include "utils.h"

@implementation NSData (Base64UrlEncoding)

- (NSString *)base64UrlEncodedString {
    // First, get the regular base64 encoded string
    NSString *base64String = [self base64EncodedStringWithOptions:0];
    
    // Then make it URL-safe by replacing characters and removing padding
    NSString *base64UrlString = [base64String stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64UrlString = [base64UrlString stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64UrlString = [base64UrlString stringByReplacingOccurrencesOfString:@"=" withString:@""];
    
    return base64UrlString;
}

@end

//
// MARK: - iOS utility functions -
//

#if TARGET_OS_IPHONE

// Helper function to get the root view controller in a modern way
UIViewController* vx::utils::ios::getRootUIViewController() {
    if (@available(iOS 13.0, *)) {
        // iOS 13+ scene-based approach
        UIWindow *window = nil;
        for (UIWindowScene* windowScene in [UIApplication sharedApplication].connectedScenes) {
            if (windowScene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in windowScene.windows) {
                    if (w.isKeyWindow) {
                        window = w;
                        break;
                    }
                }
                if (window) break;
            }
        }
        if (window) {
            return window.rootViewController;
        }
    }

    // Fallback for iOS 12 and earlier, or if scene approach fails
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].keyWindow.rootViewController;
#pragma clang diagnostic pop
}

#endif
