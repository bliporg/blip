//
//  apple-utils.mm
//  xptools
//
//  Created by Gaetan de Villele on 12/05/2025.
//  Copyright © 2025 voxowl. All rights reserved.
//

#include "apple-utils.h"

//#import <Foundation/Foundation.h>
//#import <UIKit/UIKit.h>
//#import <Photos/Photos.h>

// --------------------------------------------------
// MARK: - Objective-C utilities -
// --------------------------------------------------

//
// NSData
//

/// add function to type NSData
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
// DocumentPickerDelegate (for iOS)
//

@implementation DocumentPickerDelegate

@synthesize callback;

+ (id)shared {
    static DocumentPickerDelegate *sharedDelegate = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedDelegate = [[DocumentPickerDelegate alloc] init];
    });
    return sharedDelegate;
}

- (id)init {
    if ((self = [super init])) {
        // someProperty = [[NSString alloc] initWithString:@"Default Property Value"];
    }
    return self;
}

- (void)dealloc {}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    // static_cast<DocumentPickerDelegate*>([DocumentPickerDelegate shared]).callback(FilePickerCallbackStatus::CANCELLED, std::string());
    [self callback](PickerCallbackStatus::CANCELLED, std::string());
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL* fileURL = [urls objectAtIndex:0];
    NSError* error = nil;
    NSData* data = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingUncached error:&error];
    if (error) {
        // static_cast<DocumentPickerDelegate*>([DocumentPickerDelegate shared]).callback(FilePickerCallbackStatus::ERROR, std::string());
        [self callback](PickerCallbackStatus::ERROR, std::string());

    } else {
        std::string bytes(static_cast<const char*>(data.bytes), data.length); // performs a copy of the data
        // static_cast<DocumentPickerDelegate*>([DocumentPickerDelegate shared]).callback(FilePickerCallbackStatus::OK, std::move(bytes));
        [self callback](PickerCallbackStatus::OK, std::move(bytes));
    }
}

@end

//
// ImagePickerDelegate (for iOS)
//

@implementation ImagePickerDelegate

@synthesize callback;

+ (id)shared {
    static ImagePickerDelegate *sharedDelegate = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedDelegate = [[ImagePickerDelegate alloc] init];
    });
    return sharedDelegate;
}

- (id)init {
    if ((self = [super init])) {
        // someProperty = [[NSString alloc] initWithString:@"Default Property Value"];
    }
    return self;
}

- (void)dealloc {}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:nil];

    if (image == nil) {
        // static_cast<ImagePickerDelegate*>([ImagePickerDelegate shared]).callback(nullptr, 0, FilePickerCallbackStatus::ERROR);
        [self callback](PickerCallbackStatus::ERROR, std::string());
        return;
    }

    NSData *imageData = UIImagePNGRepresentation(image);
    if (imageData == nil) {
        // Try JPEG if PNG fails
        imageData = UIImageJPEGRepresentation(image, 0.9);
    }

    if (imageData == nil) {
        // static_cast<ImagePickerDelegate*>([ImagePickerDelegate shared]).callback(nullptr, 0, FilePickerCallbackStatus::ERROR);
        [self callback](PickerCallbackStatus::ERROR, std::string());
        return;
    }

    // static_cast<ImagePickerDelegate*>([ImagePickerDelegate shared]).callback(bytes, imageData.length, FilePickerCallbackStatus::OK);
    std::string bytes(static_cast<const char*>(imageData.bytes), imageData.length);
    [self callback](PickerCallbackStatus::OK, std::move(bytes));
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
    // static_cast<ImagePickerDelegate*>([ImagePickerDelegate shared]).callback(nullptr, 0, FilePickerCallbackStatus::CANCELLED);
    [self callback](PickerCallbackStatus::CANCELLED, std::string());
}

@end

// --------------------------------------------------
// MARK: - C++ utility functions -
// --------------------------------------------------

namespace vx {
namespace utils {
namespace ios {

#if TARGET_OS_IPHONE

// Helper function to get the root view controller in a modern way
UIViewController* getRootUIViewController() {
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

} // namespace ios

#endif

#if TARGET_OS_MAC

namespace macos {

// ...

} // namespace macos

#endif

} // namespace utils
} // namespace vx
