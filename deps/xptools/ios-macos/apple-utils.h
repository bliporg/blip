//
//  apple-utils.h
//  xptools
//
//  Created by Gaetan de Villele on 11/06/2025.
//  Copyright © 2025 voxowl. All rights reserved.
//

// this file can only be included in Objective-C source files
#ifdef __OBJC__

// C/C++
#include <functional>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

// --------------------------------------------------
// MARK: - Objective-C utilities -
// --------------------------------------------------

//
// NSData
//

@interface NSData (Base64UrlEncoding)
- (NSString *)base64UrlEncodedString;
@end

//
//
//

enum class PickerCallbackStatus : int {
    OK = 0,
    ERROR,
    CANCELLED,
};
typedef std::function<void(PickerCallbackStatus status, std::string bytes)> PickerCallback;

//
// DocumentPickerDelegate (for iOS)
//

@interface DocumentPickerDelegate: NSObject<UIDocumentPickerDelegate>

@property (nonatomic, assign) PickerCallback callback;

+ (id)shared; // TODO: gaetan: check if this is needed

@end

//
// ImagePickerDelegate (for iOS)
//

@interface ImagePickerDelegate: NSObject<UIImagePickerControllerDelegate, UINavigationControllerDelegate>

@property (nonatomic, assign) PickerCallback callback;

+ (id)shared; // TODO: gaetan: check if this is needed

@end

// --------------------------------------------------
// MARK: - C++ utility functions -
// --------------------------------------------------

namespace vx {
namespace utils {
namespace ios {

/// returns the root view controller (iOS)
UIViewController* getRootUIViewController();

} // namespace ios
} // namespace utils
} // namespace vx

#endif
