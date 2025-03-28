//
//  passkey.hpp
//  xptools
//
//  Created by Gaetan de Villele on 28/03/2025.
//  Copyright © 2025 voxowl. All rights reserved.
//

#pragma once

#include <string>

namespace vx {
namespace auth {

class PassKey {
public:
    static bool IsAvailable();

    PassKey(std::string domain,
            std::string username,
            std::string userID,
            std::string challenge) :
    _domain(domain),
    _username(username),
    _userID(userID),
    _challenge(challenge),
    _platformImpl(nullptr) {}

    // Delete copy constructor and assignment operator
    PassKey(const PassKey&) = delete;
    PassKey& operator=(const PassKey&) = delete;

    void initPlatformImpl();
    void save();

private:
    std::string _domain;
    std::string _username;
    std::string _userID;
    std::string _challenge;

    void* _platformImpl;
};

}
}
