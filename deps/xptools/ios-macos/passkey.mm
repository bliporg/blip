//
//  passkey.mm
//  xptools
//
//  Created by Gaetan de Villele on 28/03/2025.
//  Copyright © 2025 voxowl. All rights reserved.
//

#include "passkey.hpp"

bool vx::auth::PassKey::IsAvailable() {
    // PassKey is available on Apple platforms
    return true;
}
