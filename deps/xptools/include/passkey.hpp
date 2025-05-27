//
//  passkey.hpp
//  xptools
//
//  Created by Gaetan de Villele on 28/03/2025.
//  Copyright © 2025 voxowl. All rights reserved.
//

#pragma once

// C++
#include <functional>
#include <string>

namespace vx {
namespace auth {

class PassKey {
  public:
    /// Type of callback function for passkey creation
    typedef std::function<void(std::string credentialIDBase64,
                               std::string rawClientDataJSONBase64,
                               std::string rawAttestationObjectBase64,
                               std::string error)>
        CreatePasskeyCallbackFunc;

    /// Type of callback function for passkey login
    typedef std::function<void(std::string credentialIDBase64,
                               std::string authenticatorDataBase64,
                               std::string rawClientDataJSONString,
                               std::string signatureBase64,
                               std::string userIDString,
                               std::string error)>
        LoginWithPasskeyCallbackFunc;

    /// Returns true if PassKey is available on the device, false otherwise.
    static bool IsAvailable();

    static std::string createPasskey(const std::string &relyingPartyIdentifier,
                                     const std::string &challenge,
                                     const std::string &userID,
                                     const std::string &username,
                                     CreatePasskeyCallbackFunc callback);

    static std::string loginWithPasskey(const std::string &relyingPartyIdentifier,
                                        const std::string &challengeBytes,
                                        LoginWithPasskeyCallbackFunc callback);

  private:
};

} // namespace auth
} // namespace vx
