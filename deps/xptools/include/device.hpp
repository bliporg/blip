//
//  device.hpp
//  xptools
//
//  Created by Adrien Duermael on 04/20/2020.
//  Copyright © 2020 voxowl. All rights reserved.
//

#pragma once

// C
#include <cstdint>
// C++
#include <string>
#include <vector>

namespace vx {
namespace device {

typedef std::string Platform;
const Platform Platform_Mobile = "Mobile";
const Platform Platform_Desktop = "Desktop";
const Platform Platform_Wasm = "Wasm";
// const Platform Platform_Web = "Web";

typedef enum {
    PerformanceTier_Minimal,
    PerformanceTier_Low,
    PerformanceTier_Medium,
    PerformanceTier_High
} PerformanceTier;

// Returns platform type
Platform platform();

// Returns OS name
std::string osName();

// Returns OS version
std::string osVersion();

/// Returns the version of the application
std::string appVersion();

/// Returns the name of the build target
std::string appBuildTarget();

/// Returns the build number (also called "revision") of the application
uint16_t appBuildNumber();

///
std::string hardwareBrand();

///
std::string hardwareModel();

///
std::string hardwareProduct();

///
uint64_t hardwareMemory();

///
int hardwareMemoryGB();

/// same as appVersion() but the value is computed only the first time the function is called,
/// and the value is returned as a string reference.
const std::string& appVersionCached();

/// same as appBuildNumber() but the value is computed only the first time the function is called,
/// and the value is returned as a string reference.
const std::string& appBuildNumberCached();

/// same as appBuildTarget() but the value is computed only the first time the function is called,
/// and the value is returned as a string reference.
const std::string& appBuildTargetCached();

/// Exits application (does not work on all systems)
void terminate();

/// Returns true if device has a touch screen.
bool hasTouchScreen();

///
void setScreenAllowedOrientation(const std::string &orientation);

///
const std::string& getScreenAllowedOrientation();

/// Called when changing allowed orientation for the device
/// to try again and pick possible orientation.
void refreshScreenOrientation();

/// Returns true if device has a mouse and a keyboard.
bool hasMouseAndKeyboard();

/// Returns true if device is a mobile device
bool isMobile();

/// Returns true if device is a PC
bool isPC();

/// Returns true if device is a console
bool isConsole();

/// System clipboard
void setClipboardText(const std::string &text);
std::string getClipboardText();

/// Seconds elapsed since the Epoch (1970-01-01)
int32_t timestampUnix();

/// Seconds elapsed since 2001-01-01
int32_t timestampApple();

/// Haptic feedback
void hapticImpactLight();
void hapticImpactMedium();
void hapticImpactHeavy();

/// Indicates whether the device is considered performant
PerformanceTier getPerformanceTier();

void openApplicationSettings();

std::vector<std::string> preferredLanguages();

void signinwithapple();

}
}
