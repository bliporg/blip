//
//  passkey.hpp
//  xptools
//
//  Created by Gaetan de Villele on 28/03/2025.
//  Copyright © 2025 voxowl. All rights reserved.
//

#pragma once

namespace vx {
namespace auth {

class PassKey {
public:
    static PassKey& getInstance() {
        static PassKey instance;
        return instance;
    }

    static bool IsAvailable();

    // Delete copy constructor and assignment operator
    PassKey(const PassKey&) = delete;
    PassKey& operator=(const PassKey&) = delete;

private:
    // Private constructor to prevent direct instantiation
    PassKey() = default;
};

}
}
