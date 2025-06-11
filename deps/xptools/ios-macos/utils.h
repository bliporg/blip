//
//  utils.h
//  xptools
//
//  Created by Gaetan de Villele on 11/06/2025.
//  Copyright © 2025 voxowl. All rights reserved.
//

#ifdef __OBJC__

#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

///
@interface NSData (Base64UrlEncoding)
- (NSString *)base64UrlEncodedString;
@end

namespace vx {
namespace utils {
namespace ios {

/// returns the root view controller (iOS)
UIViewController* getRootUIViewController();

}
}
}

#endif
