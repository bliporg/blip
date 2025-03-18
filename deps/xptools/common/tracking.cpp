//
//  tracking.cpp
//  xptools
//
//  Created by Gaetan de Villele on 04/01/2021.
//  Copyright © 2021 voxowl. All rights reserved.
//

#include "tracking.hpp"

// C++
#include <cstring>
#include <chrono>

// xptools
#include "crypto.hpp"
#include "device.hpp"
#include "filesystem.hpp"
#include "vxlog.h"

#include "HttpClient.hpp"

#define TRACKING_SERVER_ADDR "debug.cu.bzh"
#define TRACKING_SERVER_PORT 443
#define TRACKING_SERVER_SECURE true

#if defined(DEBUG)
#define TRACKING_BRANCH "debug"
#else
#define TRACKING_BRANCH "prod"
#endif

#define NEW_SESSION_DELAY_MS 600000 // 10 minutes
#define KEEP_ALIVE_DELAY 60000 // 1 minute

using namespace vx::tracking;

TrackingClient* TrackingClient::_sharedInstance = nullptr;

// --------------------------------------------------
//
// MARK: - Public -
//
// --------------------------------------------------

TrackingClient &TrackingClient::shared() {
    if (TrackingClient::_sharedInstance == nullptr) {
        TrackingClient::_sharedInstance = new TrackingClient(TRACKING_SERVER_ADDR,
                                                             TRACKING_SERVER_PORT,
                                                             TRACKING_SERVER_SECURE);
    }
    return *TrackingClient::_sharedInstance;
}

TrackingClient::~TrackingClient() {}

void TrackingClient::appDidBecomeActive() {
#if !defined(P3S_NO_METRICS)
    _operationQueue->dispatch([](){
        TrackingClient::shared()._keep_alive_activated = true;
    });
#endif
}

void TrackingClient::appWillResignActive() {
#if !defined(P3S_NO_METRICS)
    _operationQueue->dispatch([](){
        TrackingClient::shared()._keep_alive_activated = false;
    });
#endif
}

void TrackingClient::trackEvent(const std::string& eventType) {
    std::unordered_map<std::string, std::string> properties;
    this->trackEvent(eventType, properties);
}

void TrackingClient::trackEvent(const std::string &eventType,
                                std::unordered_map<std::string, std::string> properties) {
#if !defined(P3S_NO_METRICS)
    _operationQueue->dispatch([eventType, properties](){
        TrackingClient::shared()._trackEvent(eventType, properties);
    });
#endif
}

void TrackingClient::_trackEvent(const std::string& eventType,
                                 std::unordered_map<std::string, std::string> properties) {
#if defined(P3S_NO_METRICS)
    // do nothing
    return;
#else

    vxlog_info("⭐️ TRACK EVENT (%s): %s", TRACKING_BRANCH, eventType.c_str());

    _checkAndRefreshSession();

    std::string userAccountID;
    // It's ok not to have an account ID, it means user is not logged in yet.
    /*bool ok = */ _getUserAccountID(userAccountID);
    //if (ok == false) {
    //    vxlog_error("⚠️ no account ID yet");
    //}

    std::string deviceID;
    bool ok = _getDebugID(deviceID);
    if (ok == false) {
        vxlog_error("failed to get debug ID");
        return;
    }

    // vxlog_debug("TRACK %s - ACCOUNT: %s", eventType.c_str(), userAccountID.c_str());

    cJSON *obj = cJSON_CreateObject();

    // add additional properties if provided
    for (auto pair : properties) {
        vx::json::writeStringField(obj, pair.first, pair.second);
    }

    if (_session_id > 0) {
        vx::json::writeInt64Field(obj, "session_id", _session_id);
    }

    vx::json::writeStringField(obj, "type", eventType);
    vx::json::writeStringField(obj, "user-id", userAccountID);
    vx::json::writeStringField(obj, "device-id", deviceID);
    vx::json::writeStringField(obj, "platform", vx::device::platform());
    vx::json::writeStringField(obj, "os-name", vx::device::osName());
    vx::json::writeStringField(obj, "os-version", vx::device::osVersion());
    vx::json::writeStringField(obj, "app-version", vx::device::appVersionCached());
    if (vx::device::appBuildTargetCached().empty() == false) {
        vx::json::writeStringField(obj, "app-build-target", vx::device::appBuildTargetCached());
    }

    vx::json::writeStringField(obj, "hw-brand", vx::device::hardwareBrand());
    vx::json::writeStringField(obj, "hw-model", vx::device::hardwareModel());
    vx::json::writeStringField(obj, "hw-product", vx::device::hardwareProduct());
    vx::json::writeIntField(obj, "hw-mem", vx::device::hardwareMemoryGB());

    vx::json::writeStringField(obj, "_branch", std::string(TRACKING_BRANCH));

    char *s = cJSON_PrintUnformatted(obj);
    const std::string jsonStr = std::string(s);
    free(s);

    cJSON_Delete(obj);

    HttpClient::shared().POST(this->_host,
                              this->_port,
                              "/event",
                              QueryParams(),
                              this->_secure,
                              HttpClient::noHeaders,
                              nullptr,
                              jsonStr,
                              [](HttpRequest_SharedPtr req) {
//                                 vxlog_debug("[TRACK] CALLBACK: %s %d %s",
//                                             req->getResponse().getSuccess() ? "OK" : "FAIL",
//                                             req->getResponse().getStatusCode(),
//                                             req->getResponse().getText().c_str());
                              });
#endif
}

void TrackingClient::_checkAndRefreshSession() {
#if !defined(P3S_NO_METRICS)
    using namespace std::chrono;
    TrackingClient& tc = TrackingClient::shared();
    const int64_t now = duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
    if (tc._session_id == 0 || now - tc._session_used_at > NEW_SESSION_DELAY_MS) {
        // create new session starting now
        tc._session_id = now;
    }
    tc._session_used_at = now;
#endif
}

void TrackingClient::_sendKeepAliveEventIfNeeded() {
#if !defined(P3S_NO_METRICS)
    if (_keep_alive_activated) {
        _checkAndRefreshSession();
    }
    _operationQueue->schedule([](){
        TrackingClient::shared()._sendKeepAliveEventIfNeeded();
    }, KEEP_ALIVE_DELAY);
#endif
}

void TrackingClient::removeDebugID() {
    FILE *credsFile = vx::fs::openStorageFile("/credentials.json", "rb", 0);
    if (credsFile == nullptr) {
        return;
    }
    char *content = fs::getFileTextContentAndClose(credsFile);
    if (content == nullptr) {
        return;
    }

    // parse JSON
    cJSON *jsonObj = cJSON_Parse(content);
    free(content);

    if (jsonObj == nullptr) {
        return;
    }

    if (cJSON_IsObject(jsonObj) == false) {
        cJSON_Delete(jsonObj);
        return;
    }

    if (cJSON_HasObjectItem(jsonObj, "debugID") == false) {
        cJSON_Delete(jsonObj);
        return;
    }

    cJSON_DeleteItemFromObject(jsonObj, "debugID");

    // Write updated JSON in file
    char *jsonStr = cJSON_Print(jsonObj);

    credsFile = fs::openStorageFile("/credentials.json", "wb", 0);
    if (credsFile == nullptr) {
        free(jsonStr);
        cJSON_Delete(jsonObj);
        return;
    }
    fputs(jsonStr, credsFile);
    fclose(credsFile);
    free(jsonStr);
    cJSON_Delete(jsonObj);
}

// --------------------------------------------------
//
// MARK: - Private -
//
// --------------------------------------------------

// Constructor
TrackingClient::TrackingClient(const std::string& host,
                               const uint16_t& port,
                               const bool& secure) {
#if !defined(P3S_NO_METRICS)
    _host = host;
    _port = port;
    _secure = secure;
    _session_id = 0;
    _session_used_at = 0;
    _keep_alive_activated = false;

    // default queue used by tracking client
    // this could become configurable.
    _operationQueue = OperationQueue::getBackground();
    _operationQueue->schedule([](){
        TrackingClient::shared()._sendKeepAliveEventIfNeeded();
    }, KEEP_ALIVE_DELAY);
#endif
}

// Returns the user account ID stored in credentials JSON file.
bool TrackingClient::_getUserAccountID(std::string &accountID) const {
    // read user account ID from credentials JSON file
    FILE *credsFile = vx::fs::openStorageFile("/credentials.json", "rb", 0);
    if (credsFile == nullptr) {
        return false;
    }
    char *content = fs::getFileTextContentAndClose(credsFile);
    if (content == nullptr) {
        return false;
    }

    // parse JSON
    cJSON *jsonObj = cJSON_Parse(content);
    free(content);

    if (jsonObj == nullptr) {
        return false;
    }

    if (cJSON_IsObject(jsonObj) == false) {
        cJSON_Delete(jsonObj);
        return false;
    }

    if (cJSON_HasObjectItem(jsonObj, "id") == false) {
        cJSON_Delete(jsonObj);
        return false;
    }

    // an account ID value is already present in the credentials JSON
    const cJSON *accountIDNode = cJSON_GetObjectItem(jsonObj, "id");

    if (accountIDNode == nullptr) {
        cJSON_Delete(jsonObj);
        return false;
    }

    if (cJSON_IsString(accountIDNode) == false) {
        cJSON_Delete(jsonObj);
        return false;
    }

    accountID.assign(cJSON_GetStringValue(accountIDNode));
    cJSON_Delete(jsonObj);
    return true;
}

/// Creates if necessary and returns a debug ID.
/// Returns false on error.
bool TrackingClient::_getDebugID(std::string &debugID) const {
    // read debug ID from credentials JSON file
    FILE *credsFile = vx::fs::openStorageFile("/credentials.json", "rb", 0);
    if (credsFile == nullptr) {
        // File doesn't exist yet.
        // Try to create a credentials.json file with debugID in it.
        return this->_createCredentialsJsonWithDebugID(debugID);
    }
    char *content = fs::getFileTextContentAndClose(credsFile);
    if (content == nullptr) {
        return false;
    }

    // parse JSON
    cJSON *jsonObj = cJSON_Parse(content);
    free(content);

    if (jsonObj == nullptr) {
        return false;
    }

    if (cJSON_IsObject(jsonObj) == false) {
        cJSON_Delete(jsonObj);
        return false;
    }

    bool debugIDKeyAlreadyExists = false;

    if (cJSON_HasObjectItem(jsonObj, "debugID")) {

        debugIDKeyAlreadyExists = true;

        // a debugID value is already present in the credentials JSON
        const cJSON *debugIDNode = cJSON_GetObjectItem(jsonObj, "debugID");

        if (debugIDNode == nullptr) {
            cJSON_Delete(jsonObj);
            return false;
        }

        if (cJSON_IsString(debugIDNode) == false) {
            cJSON_Delete(jsonObj);
            return false;
        }

        char *strValue = cJSON_GetStringValue(debugIDNode);
        if (strlen(strValue) == 64) {
            debugID.assign(strValue);
            cJSON_Delete(jsonObj);
            return true;
        }
    }

    // There is no debugID in credentials JSON file. (or it is an empty string)
    // We generate one and store it in the file.
    const std::string newDebugID = vx::crypto::generateRandomHex(32);

    cJSON *debugIDNode = cJSON_CreateString(newDebugID.c_str());
    if (debugIDNode == nullptr) {
        cJSON_Delete(jsonObj);
        return false;
    }
    if (debugIDKeyAlreadyExists == true) {
        cJSON_ReplaceItemInObject(jsonObj, "debugID", debugIDNode);
    } else {
        cJSON_AddItemToObject(jsonObj, "debugID", debugIDNode);
    }

    // Write updated JSON in file
    char *jsonStr = cJSON_Print(jsonObj);

    credsFile = fs::openStorageFile("/credentials.json", "wb", 0);
    if (credsFile == nullptr) {
        free(jsonStr);
        cJSON_Delete(jsonObj);
        return false;
    }
    fputs(jsonStr, credsFile);
    fclose(credsFile);
    free(jsonStr);
    cJSON_Delete(jsonObj);

    debugID.assign(newDebugID);
    return true;
}

bool TrackingClient::_createCredentialsJsonWithDebugID(std::string &debugID) const {

    cJSON *jsonObj = cJSON_CreateObject();

    if (jsonObj == nullptr) {
        return false;
    }

    if (cJSON_IsObject(jsonObj) == false) {
        cJSON_Delete(jsonObj);
        return false;
    }

    // There is no debugID in credentials JSON file.
    // We generate one and store it in the file.
    const std::string newDebugID = vx::crypto::generateRandomHex(32);

    cJSON *debugIDNode = cJSON_CreateString(newDebugID.c_str());
    if (debugIDNode == nullptr) {
        cJSON_Delete(jsonObj);
        return false;
    }
    cJSON_AddItemToObject(jsonObj, "debugID", debugIDNode);

    // Write updated JSON in file
    char *jsonStr = cJSON_Print(jsonObj);

    FILE *credsFile = vx::fs::openStorageFile("/credentials.json", "wb", 0);
    if (credsFile == nullptr) {
        free(jsonStr);
        cJSON_Delete(jsonObj);
        return false;
    }
    fputs(jsonStr, credsFile);
    fclose(credsFile);
    free(jsonStr);
    cJSON_Delete(jsonObj);

    debugID.assign(newDebugID);
    return true;
}
