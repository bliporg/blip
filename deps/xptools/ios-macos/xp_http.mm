//
//  xp_http.mm
//  xptools
//
//  Created by Gaetan de Villele on 12/06/2025.
//  Copyright © 2025 voxowl. All rights reserved.
//

// apple
#import <Foundation/Foundation.h>

namespace vx {
namespace http {

void clearSystemCache() {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}

} // namespace http
} // namespace vx
