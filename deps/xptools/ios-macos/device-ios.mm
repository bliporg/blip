//
//  device-macos.mm
//  xptools
//
//  Created by Adrien Duermael on 04/20/2020.
//  Copyright © 2020 voxowl. All rights reserved.
//

#include "device.hpp"

// Obj-C
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <AuthenticationServices/AuthenticationServices.h>

// C
#include <sys/sysctl.h>
#import <sys/utsname.h>

// C++
#include <unordered_set>

// Returns platform type
vx::device::Platform vx::device::platform() {
    return Platform_Mobile;
}

std::string vx::device::osName() {
    return std::string([[[UIDevice currentDevice] systemName] UTF8String]);
}

std::string vx::device::osVersion() {
    return std::string([[[UIDevice currentDevice] systemVersion] UTF8String]);
}

std::string vx::device::appVersion() {
    NSDictionary* infoDictionary = [[NSBundle mainBundle] infoDictionary];
    if (infoDictionary == nullptr) {
        return std::string();
    }
    NSString* appVersion = infoDictionary[@"CFBundleShortVersionString"];
    if (appVersion == nullptr) {
        return std::string();
    }
    return std::string([appVersion UTF8String]);
}

uint16_t vx::device::appBuildNumber() {
    NSDictionary* infoDictionary = [[NSBundle mainBundle] infoDictionary];
    if (infoDictionary == nullptr) {
        return 0;
    }
    NSString* key = static_cast<NSString*>(kCFBundleVersionKey);
    NSString* bundleVersion = infoDictionary[key];
    if (bundleVersion == nullptr) {
        return 0;
    }
    const uint16_t result = [bundleVersion intValue];
    return result;
}

std::string vx::device::hardwareBrand() {
    return "Apple";
}

std::string vx::device::hardwareModel() {
    NSString *result = @"";
    size_t len=0;
    sysctlbyname("hw.model", nullptr, &len, nullptr, 0);
    if (len) {
        NSMutableData *data=[NSMutableData dataWithLength:len];
        sysctlbyname("hw.model", [data mutableBytes], &len, nullptr, 0);
        const char *bytes = static_cast<const char *>([data bytes]);
        result = [NSString stringWithUTF8String:bytes];
    }
    return std::string([result UTF8String]);
}

std::string vx::device::hardwareProduct() {
    NSString *result = @"";
    size_t len=0;
    sysctlbyname("hw.product", nullptr, &len, nullptr, 0);
    if (len) {
        NSMutableData *data=[NSMutableData dataWithLength:len];
        sysctlbyname("hw.product", [data mutableBytes], &len, nullptr, 0);
        const char *bytes = static_cast<const char *>([data bytes]);
        result = [NSString stringWithUTF8String:bytes];
    }
    return std::string([result UTF8String]);
}

uint64_t vx::device::hardwareMemory() {
    uint64_t result = 0;
    size_t len=0;
    sysctlbyname("hw.memsize", nullptr, &len, nullptr, 0);
    if (len) {
        NSMutableData *data=[NSMutableData dataWithLength:len];
        sysctlbyname("hw.memsize", [data mutableBytes], &len, nullptr, 0);
        memcpy(&result, [data bytes], len);
    }
    return result;
}

void vx::device::terminate() {
    // can't exit the app on iOS
}

bool vx::device::hasTouchScreen() {
    return true;
}

bool vx::device::hasMouseAndKeyboard() {
    return false;
}

bool vx::device::isMobile() {
    return true;
}

bool vx::device::isPC() {
    return false;
}

bool vx::device::isConsole() {
    return false;
}

void vx::device::setClipboardText(const std::string &text) {
    NSString *nstext = [NSString stringWithUTF8String:text.c_str()];
    [UIPasteboard generalPasteboard].string = nstext;
}

std::string vx::device::getClipboardText() {
    NSString *nstext = [UIPasteboard generalPasteboard].string;
    std::string text = std::string();
    if (nstext != nil) {
        text.assign(nstext.UTF8String);
    }
    return text;
}

/// Haptic feedback
void vx::device::hapticImpactLight() {
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle: UIImpactFeedbackStyleLight];
    [g impactOccurred];
}

void vx::device::hapticImpactMedium() {
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle: UIImpactFeedbackStyleMedium];
    [g impactOccurred];
}

void vx::device::hapticImpactHeavy() {
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle: UIImpactFeedbackStyleHeavy];
    [g impactOccurred];
}

vx::device::PerformanceTier vx::device::getPerformanceTier() {
    // https://gist.github.com/adamawolf/3048717

    // default performance tier:
    vx::device::PerformanceTier result = vx::device::PerformanceTier_Low;

    const std::unordered_set<std::string> mediumDevices({
        "iPhone13,1", // iPhone 12 Mini
        "iPhone13,2", // iPhone 12
        "iPhone13,3", // iPhone 12 Pro
        "iPhone13,4", // iPhone 12 Pro Max

        // iPad
        "iPad11,6",   // iPad 8th Gen (WiFi)
        "iPad11,7",   // iPad 8th Gen (WiFi+Cellular)
        "iPad12,1",   // iPad 9th Gen (WiFi)
        "iPad12,2",   // iPad 9th Gen (WiFi+Cellular)
        "iPad14,1",   // iPad mini 6th Gen (WiFi)
        "iPad14,2",   // iPad mini 6th Gen (WiFi+Cellular)
        "iPad13,1",   // iPad Air 4th Gen (WiFi)
        "iPad13,2",   // iPad Air 4th Gen (WiFi+Cellular)
        "iPad13,4",   // iPad Pro 11 inch 5th Gen
        "iPad13,5",   // iPad Pro 11 inch 5th Gen
        "iPad13,6",   // iPad Pro 11 inch 5th Gen
        "iPad13,7",   // iPad Pro 11 inch 5th Gen
        "iPad13,8",   // iPad Pro 12.9 inch 5th Gen
        "iPad13,9",   // iPad Pro 12.9 inch 5th Gen
        "iPad13,10",  // iPad Pro 12.9 inch 5th Gen
        "iPad13,11",  // iPad Pro 12.9 inch 5th Gen
        "iPad13,16",  // iPad Air 5th Gen (WiFi)
        "iPad13,17",  // iPad Air 5th Gen (WiFi+Cellular)
        "iPad13,18",  // iPad 10th Gen
        "iPad13,19",  // iPad 10th Gen
        "iPad14,3",   // iPad Pro 11 inch 4th Gen
        "iPad14,4",   // iPad Pro 11 inch 4th Gen
        "iPad14,5",   // iPad Pro 12.9 inch 6th Gen
        "iPad14,6"    // iPad Pro 12.9 inch 6th Gen
    });

    const std::unordered_set<std::string> highDevices({
        "iPhone14,2", // iPhone 13 Pro
        "iPhone14,3", // iPhone 13 Pro Max
        "iPhone14,4", // iPhone 13 Mini
        "iPhone14,5", // iPhone 13
        "iPhone14,6", // iPhone SE 3rd Gen
        "iPhone14,7", // iPhone 14
        "iPhone14,8", // iPhone 14 Plus
        "iPhone15,2", // iPhone 14 Pro
        "iPhone15,3", // iPhone 14 Pro Max
        "iPhone15,4", // iPhone 15
        "iPhone15,5", // iPhone 15 Plus
        "iPhone16,1", // iPhone 15 Pro
        "iPhone16,2", // iPhone 15 Pro Max
    });

    const std::string product = vx::device::hardwareProduct();
    if (highDevices.find(product) != highDevices.end()) {
        result = vx::device::PerformanceTier_High;
    } else if (mediumDevices.find(product) != mediumDevices.end()) {
        result = vx::device::PerformanceTier_Medium;
    }

    return result;
}

void vx::device::openApplicationSettings() {
    // Create the URL that deep links to your app's custom settings.
    NSURL *url = [[NSURL alloc] initWithString:UIApplicationOpenSettingsURLString];
    // Ask the system to open that URL.
    [[UIApplication sharedApplication] openURL:url
                                       options:@{}
                             completionHandler:nil];
}

std::vector<std::string> vx::device::preferredLanguages() {
    std::vector<std::string> languages;
    NSArray *preferredLanguages = [NSLocale preferredLanguages]; // Get the list of preferred languages
    for (NSString *lang in preferredLanguages) {
        languages.push_back([lang UTF8String]); // Convert each NSString to std::string and add to the vector
    }
    return languages;
}

void vx::device::refreshScreenOrientation() {
    [UINavigationController attemptRotationToDeviceOrientation];
}

// -------------------------------------------------------------

void handleAuthorizationAppleIDButtonPress() {
    ASAuthorizationAppleIDProvider *appleIDProvider = [[ASAuthorizationAppleIDProvider alloc] init];
    ASAuthorizationAppleIDRequest *request = [appleIDProvider createRequest];
    request.requestedScopes = @[ASAuthorizationScopeFullName, ASAuthorizationScopeEmail];
    
    ASAuthorizationController *authorizationController = [[ASAuthorizationController alloc] initWithAuthorizationRequests:@[request]];
//    authorizationController.delegate = self;
//    authorizationController.presentationContextProvider = self;
    [authorizationController performRequests];
}

void vx::device::signinwithapple() {
    NSLog(@"Sign in with Apple!");
    handleAuthorizationAppleIDButtonPress();
}
