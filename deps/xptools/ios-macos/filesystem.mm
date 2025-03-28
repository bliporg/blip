//
//  filesystem.mm
//  xptools
//
//  Created by Gaetan de Villele on 03/03/2020.
//  Copyright © 2020 voxowl. All rights reserved.
//

#include "filesystem.hpp"

// C++
#include <fstream>

// Obj-C
#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE
#import <Photos/Photos.h>
#import <UIKit/UIKit.h>
#elif TARGET_OS_MAC
#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#endif

// xptools
#include "vxlog.h"

// --------------------------------------------------
// MARK: - Path separator -
// --------------------------------------------------

char vx::fs::getPathSeparator() {
    return '/';
}

std::string vx::fs::getPathSeparatorStr() {
    return "/";
}

// C symbols definition
extern "C" {

char c_getPathSeparator(void) {
    return '/';
}

const char *c_getPathSeparatorCStr(void) {
    return "/";
}

}

// ------------------------------
// Helper
// ------------------------------

bool vx::fs::Helper::setInMemoryStorage(bool b) {
    this->_inMemoryStorage = b;
    return true;
}

/// --------------------------------------------------
///
/// MARK: - static functions -
///
/// --------------------------------------------------

//static NSString *appGroupName = @"group.com.voxowl.blip";
static NSString *appGroupName = @"9JFN8QQG65.com.voxowl.particubes";
static NSString *legacyAppGroupName = @"9JFN8QQG65.com.voxowl.particubes";

std::string dirname(const std::string& fname)
{
     size_t pos = fname.find_last_of("\\/");
     return (std::string::npos == pos)
         ? ""
         : fname.substr(0, pos);
}

///
static NSString *getStoragePath() {

#if defined(CI_STORAGE_PATH)
    // override absPath
    return @CI_STORAGE_PATH;
#endif

    #if TARGET_OS_IPHONE
        NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask , true);
        if (paths.firstObject == nil) {
            return nil;
        } else {
            return [paths firstObject];
        }
    #elif TARGET_OS_MAC
        NSURL *containerUrl = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:appGroupName];
        NSString *containerPath = [containerUrl path];
        if (containerPath == nil) {
            return nil;
        } else {
            NSString *prefixPath = [NSString stringWithUTF8String:vx::fs::Helper::shared()->getStorageRelPathPrefix().c_str()];
            if ([prefixPath length] > 0) {
                containerPath = [containerPath stringByAppendingPathComponent:prefixPath];
            }

            // create the container directory if necessary
            if ([NSFileManager.defaultManager fileExistsAtPath:containerPath] == NO) {
                NSError *error = nil;
                [NSFileManager.defaultManager createDirectoryAtURL:containerUrl withIntermediateDirectories:YES attributes:nil error:&error];
                if (error != nil) {
                    NSLog(@"🔥 failed to create app group container directory: %@", error.localizedDescription);
                    return nil;
                }
            }
        }
        return containerPath;
    #endif
}

#if TARGET_OS_IPHONE
@interface DocumentPickerDelegate: NSObject<UIDocumentPickerDelegate>

@property (nonatomic, assign) vx::fs::ImportFileCallback callback;

+ (id)shared;

@end

@implementation DocumentPickerDelegate

@synthesize callback;

+ (id)shared {
    static DocumentPickerDelegate *sharedDelegate = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedDelegate = [[DocumentPickerDelegate alloc] init];
    });
    return sharedDelegate;
}

- (id)init {
    if ((self = [super init])) {
      // someProperty = [[NSString alloc] initWithString:@"Default Property Value"];
  }
  return self;
}

- (void)dealloc {
  // Should never be called
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    static_cast<DocumentPickerDelegate*>([DocumentPickerDelegate shared]).callback(nullptr, 0, vx::fs::ImportFileCallbackStatus::CANCELLED);
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL* fileURL = [urls objectAtIndex:0];
    NSError* error = nil;
    NSData* data = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingUncached error:&error];
    if (error) {
        static_cast<DocumentPickerDelegate*>([DocumentPickerDelegate shared]).callback(nullptr, 0, vx::fs::ImportFileCallbackStatus::ERROR_IMPORT);

    } else {
        void *bytes = static_cast<void*>(malloc(data.length));
        memcpy(bytes, data.bytes, data.length);
        static_cast<DocumentPickerDelegate*>([DocumentPickerDelegate shared]).callback(bytes, data.length, vx::fs::ImportFileCallbackStatus::OK);
    }
}

@end
#endif

void ::vx::fs::importFile(ImportFileCallback callback) {
#if TARGET_OS_IPHONE
    UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
    
    UIDocumentPickerViewController *pickerVC = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"com.voxowl.particubes.vox",
                                                                                                               @"com.voxowl.particubes.pcubes",
                                                                                                               @"com.voxowl.particubes.particubes",
                                                                                                               @"com.voxowl.particubes.3zh",
                                                                                                               @"com.voxowl.particubes.glb",
                                                                                                               @"com.voxowl.particubes.gltf",
                                                                                                               @"com.voxowl.particubes.gif",
                                                                                                               @"com.voxowl.particubes.jpg",
                                                                                                               @"com.voxowl.particubes.jpeg",
                                                                                                               @"com.voxowl.particubes.png"] inMode:UIDocumentPickerModeImport];

    DocumentPickerDelegate *d = [DocumentPickerDelegate shared];
    d.callback = callback;
    pickerVC.delegate = d;
    [vc presentViewController:pickerVC animated:YES completion:nil];
#elif TARGET_OS_MAC
    NSOpenPanel *op = [NSOpenPanel openPanel];
    [op setCanChooseFiles:YES];
    [op setCanChooseDirectories:NO];
    [op setAllowsMultipleSelection:NO];
    [op setAllowedFileTypes:[NSArray arrayWithObjects:@"vox", @"pcubes", @"3zh", @"glb", @"gltf", @"jpg", @"jpeg", @"gif", nil]];

    [op beginWithCompletionHandler:^(NSInteger result){
        if (result == NSModalResponseOK) {
            NSURL* fileURL = [[op URLs] objectAtIndex:0];
            NSError* error = nil;
            NSData* data = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingUncached error:&error];
            if (error) {
                callback(nullptr, 0, ImportFileCallbackStatus::ERROR_IMPORT);
            } else {
                void *bytes = static_cast<void*>(malloc(data.length));
                memcpy(bytes, data.bytes, data.length);
                callback(bytes, data.length, ImportFileCallbackStatus::OK);
            }
        } else if (result == NSModalResponseCancel) {
            callback(nullptr, 0, ImportFileCallbackStatus::CANCELLED);
        }
    }];
#endif
}

FILE *vx::fs::openFile(const std::string& filePath, const std::string& mode) {
    FILE *result = fopen(filePath.c_str(), mode.c_str());
    return result;
}

std::string vx::fs::getBundleFilePath(const std::string& relFilePath) {
    NSString *bundlePath = nil;

    NSString *relPath = [NSString stringWithUTF8String:relFilePath.c_str()];
    if (relPath == nil) {
        return "";
    }
    
#if TARGET_OS_IPHONE
    bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *absPath = [bundlePath stringByAppendingPathComponent:relPath];
#elif TARGET_OS_MAC

#ifdef ONLINE_GAMESERVER

    NSString *absPath = nil;
    if (relFilePath.compare(0, 8, "modules/") == 0) {
        bundlePath = @PROJECT_LUA_MODULES_PATH;
        absPath = [bundlePath stringByAppendingPathComponent:relPath];
    } else {
        bundlePath = @PROJECT_BUNDLE_PATH;
        absPath = [bundlePath stringByAppendingPathComponent:relPath];
    }

#else // CLIENT

#if DEBUG
    NSString *absPath = nil;
    if (relFilePath.compare(0, 8, "modules/") == 0) {
        bundlePath = @PROJECT_LUA_MODULES_PATH;
        absPath = [bundlePath stringByAppendingPathComponent:relPath];
    } else {
        bundlePath = [[NSBundle mainBundle] bundlePath];
        absPath = [bundlePath stringByAppendingPathComponent:@"Contents"];
        absPath = [absPath stringByAppendingPathComponent:@"Resources"];
        absPath = [absPath stringByAppendingPathComponent:relPath];
    }
#else
    bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *absPath = [bundlePath stringByAppendingPathComponent:@"Contents"];
    absPath = [absPath stringByAppendingPathComponent:@"Resources"];
    absPath = [absPath stringByAppendingPathComponent:relPath];
#endif

#if defined(CI_BUNDLE_PATH)
    if (relFilePath.compare(0, 8, "modules/") == 0) {
        absPath = @CI_MODULES_PATH;
        absPath = [absPath stringByAppendingPathComponent:relPath];
    } else {
        absPath = @CI_BUNDLE_PATH;
        absPath = [absPath stringByAppendingPathComponent:relPath];
    }
#endif

#endif
#endif
    
    return std::string([absPath UTF8String]);
}

/// Opens a file located in the bundle directory.
/// @param relFilePath name of the file to open. It should not start with a '/'.
FILE *vx::fs::openBundleFile(std::string relFilePath, std::string mode) {
    std::string absPath = getBundleFilePath(relFilePath);
    FILE *result = fopen(absPath.c_str(), mode.c_str());
    if (result == nullptr) {
        // try within storage (where we put dynamically loaded "bundle" files).
        result = openStorageFile(std::string("bundle/") + relFilePath, mode);
    }
    return result;
}

///
FILE *vx::fs::openStorageFile(std::string relFilePath, std::string mode, size_t writeSize) {

    if (Helper::shared()->inMemoryStorage()) {

        /*
         FROM: https://man7.org/linux/man-pages/man3/fmemopen.3.html
         When a stream that has been opened for writing is flushed
         (fflush(3)) or closed (fclose(3)), a null byte is written at the
         end of the buffer if there is space. The caller should ensure
         that an extra byte is available in the buffer (and that size
         counts that byte) to allow for this

         /!\ the "if there is space" condition doesn't seem to be verified
         the same way on all platforms. We spent a full day debugging a crash
         caused by this... And that's why we don't take chances and add
         an extra byte when creating an in memory file.
         When opening the file for reading, the size if decreased not to read
         that last byte.
         */

        FILE* f = nullptr;

        if (mode == "rb") {

            InMemoryFile *inMemFile = Helper::shared()->getInMemoryFile("storage/" + relFilePath);
            if (inMemFile != nullptr) {
                f = fmemopen(inMemFile->bytes, inMemFile->size - 1, mode.c_str());
            }

        } else if (mode == "wb" && writeSize != 0) {
            InMemoryFile *inMemFile = Helper::shared()->createInMemoryFile("storage/" + relFilePath, writeSize + 1);
            if (inMemFile != nullptr) {
                f = fmemopen(inMemFile->bytes, inMemFile->size, mode.c_str());
            }
        }

        return f;

    } else {

        NSString *storagePath = getStoragePath();
        if (storagePath == nil) {
            return nullptr;
        }

        // create parent directories if missing when opening for writing
        bool writing = (mode.size() > 0 && (mode.at(0) == 'w' || mode.at(0) == 'a'));
        if (writing) {

            std::string parent = dirname(relFilePath);
            if (parent.empty() == false) { // expects parent dir(s)
                NSString *parentRelPath = [NSString stringWithUTF8String:parent.c_str()];
                if (parentRelPath == nil) {
                    return nil;
                }
                NSString *absoluteParentPath = [storagePath stringByAppendingPathComponent:parentRelPath];

                if ([[NSFileManager defaultManager] createDirectoryAtPath:absoluteParentPath withIntermediateDirectories:YES attributes:nil error:nil] == NO) {
                    return nil;
                }
            }
        }

        NSString *relPath = [NSString stringWithUTF8String:relFilePath.c_str()];
        if (relPath == nil) {
            return nil;
        }

        // generate absolute file path
        NSString *absoluteFilePath = [storagePath stringByAppendingPathComponent:relPath];

        // open file
        return fopen([absoluteFilePath UTF8String], mode.c_str());
    }
}

//
std::vector<std::string> vx::fs::listStorageDirectory(const std::string& relStoragePath) {
    std::vector<std::string> result;

    // convert relative path to NSString
    NSString *relPath = [NSString stringWithUTF8String:relStoragePath.c_str()];
    if (relPath == nil) {
        // error
        return result;
    }

    // get storage directory path
    NSString *storagePath = getStoragePath();
    if (storagePath == nil) {
        // error
        return result;
    }

    // append relative path to storage directory path
    NSString *absStorageDir = [storagePath stringByAppendingPathComponent:relPath];

    // make sure a file exists at the given path and that it's a directory
    BOOL isDirectory = NO;
    BOOL fileExists = NO;
    fileExists = [[NSFileManager defaultManager] fileExistsAtPath:absStorageDir isDirectory:&isDirectory];
    if (fileExists == NO || isDirectory == NO) {
        // error
        return result;
    }

    NSDirectoryEnumerator *dirEnumerator = [[NSFileManager defaultManager] enumeratorAtPath: absStorageDir];
    for (NSString *path in dirEnumerator) {
        // only consider top level items (NSDirectoryEnumerator is recursive)
        if (dirEnumerator.level == 1) {
            NSString *pathRelativeToStorageRoot = [relPath stringByAppendingPathComponent:path];
            result.push_back(std::string([pathRelativeToStorageRoot UTF8String]));
        }
    }

    return result;
}

//
bool vx::fs::removeStorageFileOrDirectory(std::string relFilePath) {
    NSString *storagePath = getStoragePath();
    if (storagePath == nil) {
        return false;
    }

    NSString *relPath = [NSString stringWithUTF8String:relFilePath.c_str()];
    if (relPath == nil) {
        return false;
    }

    // generate absolute file path
    NSString *absoluteFilePath = [storagePath stringByAppendingPathComponent:relPath];
    // remove file
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:absoluteFilePath error:&error];
    return error == nil ? true : false;
}

///
bool vx::fs::bundleFileExists(const std::string& relFilePath, bool& isDir) {
    const std::string absPathStr = vx::fs::getBundleFilePath(relFilePath);
    NSString *absPath = [NSString stringWithUTF8String:absPathStr.c_str()];

    BOOL isDirectory = NO;
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:absPath isDirectory:&isDirectory];

    isDir = isDirectory;

    return fileExists;
}

///
bool vx::fs::storageFileExists(const std::string& relFilePath, bool& isDir) {

    BOOL fileExists = NO;
    BOOL isDirectory = NO;
    NSString *absoluteFilePath = nil;

    if (Helper::shared()->inMemoryStorage()) {

        InMemoryFile *inMemFile = Helper::shared()->getInMemoryFile("storage/" + relFilePath);
        fileExists = inMemFile != nullptr;

    } else {

        NSString *storagePath = getStoragePath();
        if (storagePath == nil) {
            return false;
        }

        NSString *relPath = [NSString stringWithUTF8String:relFilePath.c_str()];
        if (relPath == nil) {
            return false;
        }

        // generate absolute file path
        absoluteFilePath = [storagePath stringByAppendingPathComponent:relPath];

        fileExists = [[NSFileManager defaultManager] fileExistsAtPath:absoluteFilePath isDirectory:&isDirectory];

        isDir = isDirectory;
    }

    return fileExists;
}

bool vx::fs::mergeBundleDirInStorage(const std::string& bundleDir, const std::string& storageDir) {

    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];

    NSString *relPath = [NSString stringWithUTF8String:bundleDir.c_str()];
    if (relPath == nil) {
        return false;
    }

    #if TARGET_OS_IPHONE
        NSString *absBundleDir = [bundlePath stringByAppendingPathComponent:relPath];
    #elif TARGET_OS_MAC
        NSString *absBundleDir = [bundlePath stringByAppendingPathComponent:@"Contents"];
        absBundleDir = [absBundleDir stringByAppendingPathComponent:@"Resources"];
        absBundleDir = [absBundleDir stringByAppendingPathComponent:relPath];
    #endif

    NSString *storagePath = getStoragePath();
    if (storagePath == nil) {
        return false;
    }

    relPath = [NSString stringWithUTF8String:storageDir.c_str()];
    if (relPath == nil) {
        return false;
    }

    NSString *absStorageDir = [storagePath stringByAppendingPathComponent:relPath];

    BOOL isDirectory = NO;
    BOOL fileExists = NO;

    fileExists = [[NSFileManager defaultManager] fileExistsAtPath:absBundleDir isDirectory:&isDirectory];
    if (fileExists == NO || isDirectory == NO) {
        return false;
    }

    fileExists = [[NSFileManager defaultManager] fileExistsAtPath:absStorageDir isDirectory:&isDirectory];
    if (fileExists == NO) {
        if ([[NSFileManager defaultManager] createDirectoryAtPath:absStorageDir withIntermediateDirectories:YES attributes:nil error:nil] == NO) {
            return false;
        }
    } else if (isDirectory == NO) {
        return false;
    }

    NSDirectoryEnumerator *dirEnumerator = [[NSFileManager defaultManager] enumeratorAtPath: absBundleDir];

    NSString *source;
    NSString *destination;

    for (NSString *path in dirEnumerator) {
        source = [absBundleDir stringByAppendingPathComponent:path];
        fileExists = [[NSFileManager defaultManager] fileExistsAtPath:source isDirectory:&isDirectory];
        if (fileExists == NO || isDirectory == YES) {
            continue;
        }

        destination = [absStorageDir stringByAppendingPathComponent:path];
        fileExists = [[NSFileManager defaultManager] fileExistsAtPath:destination isDirectory:&isDirectory];
        if (fileExists) {
            if (isDirectory) {
                NSLog(@"can't replace directory by file");
                return false;
            }
            if ([[NSFileManager defaultManager] removeItemAtPath:destination error:nil] == NO) {
                NSLog(@"can't remove file");
                return false;
            }
        }

        if ([[NSFileManager defaultManager] copyItemAtPath:source toPath:destination error:nil] == NO) {
            // it usually fails because parent dir can't be found
            // create it and try again.
            if ([[NSFileManager defaultManager] createDirectoryAtPath:[destination stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil] == NO) {
                NSLog(@"can't copy file");
                return false;
            }

            if ([[NSFileManager defaultManager] copyItemAtPath:source toPath:destination error:nil] == NO) {
                NSLog(@"can't copy file");
                return false;
            }
        }
    }

    return true;
}

#if TARGET_OS_IPHONE
@interface PopoverPresentationControllerDelegate: NSObject<UIPopoverPresentationControllerDelegate> {

}

+ (id)shared;

@end

@implementation PopoverPresentationControllerDelegate

+ (id)shared {
    static PopoverPresentationControllerDelegate *sharedDelegate = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedDelegate = [[PopoverPresentationControllerDelegate alloc] init];
    });
    return sharedDelegate;
}

- (id)init {
    if ((self = [super init])) {
      // someProperty = [[NSString alloc] initWithString:@"Default Property Value"];
  }
  return self;
}

- (void)dealloc {
  // Should never be called
}

// called when taping outside the activity view
// not called when share action completed.
// NOTE: animation done in activityViewController.completionWithItemsHandler,
// as it can handle both cases (action completed or not)
//-(void)presentationControllerWillDismiss:(UIPresentationController *)presentationController {
//    UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
//    [UIView animateWithDuration:0.2 animations:^{
//        vc.view.alpha = 1.0;
//    }];
//}

-(void)prepareForPopoverPresentation:(UIPopoverPresentationController *)popoverPresentationController {
    
    UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
    [UIView animateWithDuration:0.2 animations:^{
        vc.view.alpha = 0.5;
    }];
}

- (void)popoverPresentationController:(UIPopoverPresentationController *)popoverPresentationController willRepositionPopoverToRect:(inout CGRect *)rect inView:(inout UIView * _Nonnull __autoreleasing *)view {
 
    UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;
    
    *rect = CGRectMake(CGRectGetMidX(vc.view.bounds),
                      CGRectGetMidY(vc.view.bounds),
                      0,
                      0);
}

@end
#endif

///
void vx::fs::shareFile(const std::string& filepath,
                       const std::string& title,
                       const std::string& filename,
                       const fs::FileType type) {
    
    vxlog_info("📸 [shareFile] %s", filepath.c_str());
#if TARGET_OS_IPHONE
    UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;

    NSString *filepathStr = [NSString stringWithCString:filepath.c_str() encoding:NSUTF8StringEncoding];
    NSString *srcFullpath = [NSString stringWithFormat:@"%@/%@", getStoragePath(), filepathStr];
    NSURL *srcURL = [NSURL fileURLWithPath:srcFullpath];

    NSArray *share = @[srcURL];
    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:share applicationActivities:nil];
    
    // for iPadOS
    if (activityViewController.popoverPresentationController != nil) {
        activityViewController.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirection();
        activityViewController.popoverPresentationController.sourceView = vc.view;
        activityViewController.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(vc.view.bounds),
                                                                                     CGRectGetMidY(vc.view.bounds),
                                                                                     0,
                                                                                     0);
        activityViewController.popoverPresentationController.delegate = [PopoverPresentationControllerDelegate shared];
        
        activityViewController.completionWithItemsHandler = ^(NSString *activityType,
                                                              BOOL completed,
                                                              NSArray *returnedItems,
                                                              NSError *activityError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.2 animations:^{
                    vc.view.alpha = 1.0;
                }];
            });
        };
    }
    
    [vc presentViewController:activityViewController animated:YES completion:nil];

#elif TARGET_OS_MAC
    NSString *nsFileName = [NSString stringWithCString:filename.c_str() encoding:NSUTF8StringEncoding];
    NSString *filenameWithExtension = @"";
    
    switch (type) {
        case FileType::NONE:
            filenameWithExtension = [NSString stringWithFormat:@"%@", nsFileName];
            break;
        case FileType::PNG:
            filenameWithExtension = [NSString stringWithFormat:@"%@.png", nsFileName];
            break;
        case FileType::PCUBES:
            filenameWithExtension = [NSString stringWithFormat:@"%@.pcubes", nsFileName];
            break;
        case FileType::CUBZH:
            filenameWithExtension = [NSString stringWithFormat:@"%@.3zh", nsFileName];
            break;
        case FileType::VOX:
            filenameWithExtension = [NSString stringWithFormat:@"%@.vox", nsFileName];
            break;
        case FileType::OBJ:
            filenameWithExtension = [NSString stringWithFormat:@"%@.obj", nsFileName];
            break;
    }
    
    NSSavePanel *dialog = [NSSavePanel savePanel];
    dialog.title = [NSString stringWithCString:title.c_str() encoding:NSUTF8StringEncoding];
    dialog.showsResizeIndicator = YES;
    dialog.canCreateDirectories = YES;
    dialog.showsHiddenFiles = NO;
    dialog.nameFieldStringValue = filenameWithExtension;

    if ([dialog runModal] == NSModalResponseOK) {
        std::string srcFullpath = std::string(getStoragePath().UTF8String) + "/" + filepath;
        // copy
        std::ifstream src(srcFullpath, std::ios::binary);
        std::ofstream dst(std::string(dialog.URL.path.UTF8String), std::ios::binary);
        dst << src.rdbuf();
    } else {
        // User clicked on "Cancel"
    }
#endif
}

bool vx::fs::removeStorageFilesWithPrefix(const std::string& directory,
                                          const std::string& prefix) {
    if (prefix.empty()) {
        return false;
    }
    
    // storage directory path
    NSString *storagePath = getStoragePath();
    if (storagePath == nil) {
        return false;
    }
    NSString* relPath = [NSString stringWithUTF8String:directory.c_str()];
    if (relPath == nil) {
        return false;
    }
    NSString *absStorageDir = [storagePath stringByAppendingPathComponent:relPath];

    
    // enumerate files located in directory
    NSDirectoryEnumerator *dirEnumerator = [[NSFileManager defaultManager] enumeratorAtPath: absStorageDir];

    BOOL isDirectory = NO;
    BOOL fileExists = NO;
    NSString *fileAbsPath = nil;
    NSString *nsprefix = [NSString stringWithUTF8String:prefix.c_str()];
    bool success = true;
    
    for (NSString *path in dirEnumerator) {
        fileAbsPath = [absStorageDir stringByAppendingPathComponent:path];
        fileExists = [[NSFileManager defaultManager] fileExistsAtPath:fileAbsPath isDirectory:&isDirectory];
        if (fileExists == NO || isDirectory == YES) {
            continue;
        }
        
        if ([path hasPrefix:nsprefix]) {
            if ([[NSFileManager defaultManager] removeItemAtPath:fileAbsPath error:nil] == NO) {
                success = false;
            }
        }
    }
    
    return success;
}

#if TARGET_OS_IPHONE
@interface ImagePickerDelegate: NSObject<UIImagePickerControllerDelegate> {

}

+ (id)shared;

@end

@implementation ImagePickerDelegate

+ (id)shared {
    static ImagePickerDelegate *sharedDelegate = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedDelegate = [[ImagePickerDelegate alloc] init];
    });
    return sharedDelegate;
}

- (id)init {
    if ((self = [super init])) {
      // someProperty = [[NSString alloc] initWithString:@"Default Property Value"];
  }
  return self;
}

- (void)dealloc {
  // Should never be called
}

inline double rad(double deg) {
    return deg / 180.0 * M_PI;
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {

    UIImage *image = info[UIImagePickerControllerOriginalImage];

    [picker dismissViewControllerAnimated:YES completion:nil];

    NSString *storagePath = getStoragePath();
    if (storagePath == nil) {
        return;
    }

    UIImage *normalizedImage = image;

    if (image.imageOrientation != UIImageOrientationUp) {
        UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
        [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
        normalizedImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }

    // CROP

    double ratio = 16.0 / 9.0;

    CGFloat imageWidth = normalizedImage.size.width;
    CGFloat imageHeight = normalizedImage.size.height;

    CGRect crop = CGRectMake(0, 0, imageWidth, imageHeight);

    // check if too large
    if (imageWidth / imageHeight > ratio) {
        crop.size.width = imageHeight * ratio;
        crop.origin.x = (imageWidth - crop.size.width) * 0.5;
    } else if (imageWidth / imageHeight < ratio) { // check if too tall
        crop.size.height = imageWidth / ratio;
        crop.origin.y = (imageHeight - crop.size.height) * 0.5;
    }

    CGImageRef imageRef = CGImageCreateWithImageInRect(normalizedImage.CGImage, crop);

    UIImage *result = [UIImage imageWithCGImage:imageRef scale: 1.0 orientation: UIImageOrientationUp];

    // SCALE

    CGImageRelease(imageRef);

    imageWidth = 800.0;
    imageHeight = 450.0;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(nullptr, imageWidth, imageHeight, 8, 0, colorSpace, kCGImageAlphaPremultipliedLast);
    CGContextClearRect(context, CGRectMake(0, 0, imageWidth, imageHeight));

    CGContextDrawImage(context, CGRectMake(0, 0, imageWidth, imageHeight), result.CGImage);

    imageRef = CGBitmapContextCreateImage(context);

    CGColorSpaceRelease(colorSpace);
    CGContextRelease(context);

    result = [UIImage imageWithCGImage:imageRef scale: 1.0 orientation: UIImageOrientationUp];

    CGImageRelease(imageRef);

    // generate absolute file path
    NSString *absoluteFilePath = [storagePath stringByAppendingPathComponent:@"new-thumbnail.png"];

    BOOL success = [UIImagePNGRepresentation(result) writeToFile:absoluteFilePath atomically:YES];

    if (success == false) {
        vx::fs::Helper::shared()->callThumbnailCallback(nullptr);
        return;
    }

    vx::fs::Helper::shared()->callThumbnailCallback(vx::fs::openStorageFile("new-thumbnail.png"));
}

@end

void showIOSPicker() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIImagePickerController* imagePicker = [[UIImagePickerController alloc]init];
        // Check if image access is authorized
        if([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
            imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
            // Use delegate methods to get result of photo library -- Look up UIImagePicker delegate methods

            // imagePicker.mediaTypes = [[NSArray alloc] initWithObjects: (NSString *)kCIAttributeTypeImage, nil];
            imagePicker.allowsEditing = false;
            imagePicker.delegate = [ImagePickerDelegate shared];

            UIViewController *rootController = [[[UIApplication sharedApplication] keyWindow] rootViewController];
            [rootController presentViewController:imagePicker animated:true completion:nil];
        }
    });
}
#elif TARGET_OS_MAC

@interface NSImage (PCubesAdditions)

- (BOOL)writePNGToURL:(NSURL*)URL outputSizeInPixels:(NSSize)outputSizePx error:(NSError*__autoreleasing*)error;

@end

@implementation NSImage (PCubesAdditions)

- (BOOL)writePNGToURL:(NSURL*)URL outputSizeInPixels:(NSSize)outputSizePx error:(NSError*__autoreleasing*)error
{
    BOOL result = YES;
    NSImage* scalingImage = [NSImage imageWithSize:[self size] flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        [self drawAtPoint:NSMakePoint(0.0, 0.0) fromRect:dstRect operation:NSCompositingOperationSourceOver fraction:1.0];
        return YES;
    }];
    NSRect proposedRect = NSMakeRect(0.0, 0.0, outputSizePx.width, outputSizePx.height);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    CGContextRef cgContext = CGBitmapContextCreate(nullptr,
                                                   static_cast<size_t>(proposedRect.size.width),
                                                   static_cast<size_t>(proposedRect.size.height),
                                                   8,
                                                   static_cast<size_t>(4 * proposedRect.size.width),
                                                   colorSpace,
                                                   kCGImageByteOrderDefault | kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    NSGraphicsContext* context = [NSGraphicsContext graphicsContextWithCGContext:cgContext flipped:NO];
    CGContextRelease(cgContext);
    CGImageRef cgImage = [scalingImage CGImageForProposedRect:&proposedRect context:context hints:nil];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)(URL), kUTTypePNG, 1, nullptr);
    CGImageDestinationAddImage(destination, cgImage, nil);
    if(!CGImageDestinationFinalize(destination))
    {
        NSDictionary* details = @{NSLocalizedDescriptionKey:@"Error writing PNG image"};
        [details setValue:@"ran out of money" forKey:NSLocalizedDescriptionKey];
        if (error != nil) {
            *error = [NSError errorWithDomain:@"SSWPNGAdditionsErrorDomain" code:10 userInfo:details];
        }
        result = NO;
    }
    CFRelease(destination);
    return result;
}

@end

void prepareThumbnail(NSImage *image) {

    if (image == nil) {
        NSLog(@"Could not load image");
        return;
    }

    NSString *storagePath = getStoragePath();
    if (storagePath == nil) {
        return;
    }

    double ratio = 16.0 / 9.0;

    CGFloat imageWidth = image.size.width;
    CGFloat imageHeight = image.size.height;

    // CROP

    NSRect cropRect = NSMakeRect(0, 0, imageWidth, imageHeight);

    // check if too large
    if (imageWidth / imageHeight > ratio) {
        cropRect.size.width = imageHeight * ratio;
        cropRect.origin.x = (imageWidth - cropRect.size.width) * 0.5;
    } else if (imageWidth / imageHeight < ratio) { // check if too tall
        cropRect.size.height = imageWidth / ratio;
        cropRect.origin.y = (imageHeight - cropRect.size.height) * 0.5;
    }

    // SCALE

    NSSize destSize = NSMakeSize(800.0, 450.0);

    NSImage *newImage = [NSImage imageWithSize:destSize flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        [image drawInRect:dstRect fromRect:cropRect operation:NSCompositingOperationSourceOver fraction:1.0];
        return YES;
    }];

    // generate absolute file path
    NSString *absoluteFilePath = [storagePath stringByAppendingPathComponent:@"new-thumbnail.png"];

    NSURL *destinationURL = [NSURL fileURLWithPath:absoluteFilePath];

    NSError *error = nil;

    BOOL success = [newImage writePNGToURL:destinationURL outputSizeInPixels:destSize error:&error];

    if (success == false) {
        vx::fs::Helper::shared()->callThumbnailCallback(nullptr);
        return;
    }

    vx::fs::Helper::shared()->callThumbnailCallback(vx::fs::openStorageFile("new-thumbnail.png"));
}

#endif

void vx::fs::pickThumbnail(std::function<void(FILE* thumbnail)> callback) {

    Helper::shared()->setThumbnailCallback(callback);

#if TARGET_OS_IPHONE
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if(status == PHAuthorizationStatusNotDetermined) {

        // Request photo authorization
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            showIOSPicker();

    }];
    } else if (status == PHAuthorizationStatusAuthorized) {

        showIOSPicker();

    } else if (status == PHAuthorizationStatusRestricted) {

        Helper::shared()->callThumbnailCallback(nullptr);

    } else if (status == PHAuthorizationStatusDenied) {

        Helper::shared()->callThumbnailCallback(nullptr);

    }
#elif TARGET_OS_MAC
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:NO];
    [panel setAllowedFileTypes:[NSArray arrayWithObjects:@"png", @"jpg", @"jpeg", nil]];

    NSInteger clicked = [panel runModal];

    if (clicked == NSModalResponseOK) {
        if ([[panel URLs] count] > 0) {

            NSData *data = [NSData dataWithContentsOfURL:[panel URLs][0]];

            if (data == nil) {
                callback(nullptr);
                return;
            }

            NSImage *img = [[NSImage alloc] initWithData:data];
            if (img == nil) {
                callback(nullptr);
                return;
            }

            prepareThumbnail(img);
        }
    }
#endif
}
