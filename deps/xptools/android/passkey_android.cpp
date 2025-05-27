//
//  passkey_android.cpp
//  xptools
//
//  Created by Gaetan de Villele on 16/05/2025.
//  Copyright © 2025 voxowl. All rights reserved.
//

#include "passkey.hpp"

bool vx::auth::PassKey::IsAvailable() {
    // Passkey is not available on Android for now
    return false;
}

std::string vx::auth::PassKey::createPasskey(
    const std::string &relyingPartyIdentifier,
    const std::string &challenge,
    const std::string &userID,
    const std::string &username,
    vx::auth::PassKey::CreatePasskeyCallbackFunc callback) {
    return "not implemented"; // error
}

std::string vx::auth::PassKey::loginWithPasskey(
    const std::string &relyingPartyIdentifier,
    const std::string &challengeBytes,
    vx::auth::PassKey::LoginWithPasskeyCallbackFunc callback) {
    return "not implemented"; // error
}
