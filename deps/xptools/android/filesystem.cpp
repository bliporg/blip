//
//  filesystem.cpp
//  xptools
//
//  Created by Gaetan de Villèle on 03/03/2020.
//  Copyright © 2020 voxowl. All rights reserved.
//

#include "filesystem.hpp"

// C
#include <sys/stat.h>
#include <dirent.h>
#include <string.h>

// C++
#include <cassert>
#include <cerrno>
#include <vector>
#include <sstream>

// android
#include <android/asset_manager.h>
#include <android/asset_manager_jni.h>
#include <android/log.h>

// vx::tools
#include "compat_android.hpp"
#include "JNIUtils.hpp"

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

static vx::fs::ImportFileCallback currentImportCallback;

//region funopen() delegates
static int android_read(void *cookie, char *buf, int size) {
    return AAsset_read((AAsset *)cookie, buf, size);
}

static int android_write(void *cookie, const char *buf, int size) {
    return EACCES; // can't provide write access to the apk
}

static fpos_t android_seek(void *cookie, fpos_t offset, int whence) {
    return AAsset_seek((AAsset *)cookie, offset, whence);
}

static int android_close(void *cookie) {
    AAsset_close((AAsset *)cookie);
    return 0;
}
//endregion

/// Utility functions

///
std::vector<std::string> splitString(const std::string &s, char delimiter) {
    std::vector<std::string> tokens;
    std::string token;
    std::istringstream tokenStream(s);
    while (std::getline(tokenStream, token, delimiter))
    {
        tokens.push_back(token);
    }
    return tokens;
}

FILE *vx::fs::openFile(const std::string& filePath, const std::string& mode) {
    FILE *result = fopen(filePath.c_str(), mode.c_str());
    return result;
}

/// Opens a file located in the bundle "assets" directory.
/// @param filename name of the file to open. It should not start with a '/'.
FILE *vx::fs::openBundleFile(std::string filename, std::string mode) {
    AAsset *asset = AAssetManager_open(vx::android::getAndroidAssetManager(), filename.c_str(), 0);
    if (asset == nullptr) {
        // try within storage (where we put dynamically loaded "bundle" files).
        return openStorageFile(std::string("bundle/") + filename, mode);
    }
    return funopen(asset, android_read, android_write, android_seek, android_close);
}

/// relFilePath should not start with a / as it is a relative path
FILE *vx::fs::openStorageFile(std::string relFilePath, std::string mode, size_t writeSize) {
    // remove "/" prefix from relFilePath if any
    if (*(relFilePath.cbegin()) == '/') {
        relFilePath.erase(0, 1); // remove first character
    }
    // __android_log_print(ANDROID_LOG_ERROR, "Particubes", "%s", relFilePath.c_str());

    // construct absolute path
    const std::string storagePath = vx::android::getAndroidStoragePath();
    const std::string absFilePath = storagePath + "/" + relFilePath;

    // create parent directories if missing when opening for writing
    const bool writing = (mode.size() > 0 && (mode.at(0) == 'w' || mode.at(0) == 'a'));
    // __android_log_print(ANDROID_LOG_ERROR, "Particubes", "IS WRITING %s | %s", relFilePath.c_str(), absFilePath.c_str());
    if (writing) {
        // check whether parent directory exists
        std::vector<std::string> elements = splitString(relFilePath, '/');
        if (elements.size() > 1) {
            // Create intermediate directories (between storage dir and file to open.
            // Remove last element which represent the file.
            elements.pop_back();
            std::string currentRelPath = "";
            std::string currentAbsPath;
            bool isDir = false;
            for (std::string const& element: elements) {
                // __android_log_print(ANDROID_LOG_ERROR, "Particubes", "ELEMENT %s", element.c_str());
                // create the directory if it doesn't exist
                currentRelPath += "/" + element;
                const bool exists = storageFileExists(currentRelPath, isDir);
                if (!exists) {
                    currentAbsPath = storagePath + "/" + currentRelPath;
                    if (mkdir(currentAbsPath.c_str(), S_IRWXU | S_IRWXG | S_IRWXO) != 0) { // 777 permissions
                        // mkdir failed
                        __android_log_print(ANDROID_LOG_ERROR, "Particubes", "mkdir failed in storage. (%s) (%s)", absFilePath.c_str(), currentRelPath.c_str());
                        return nullptr;
                    }
                } else if (!isDir) {
                    // element exists but is a file, and not a directory
                    __android_log_print(ANDROID_LOG_ERROR, "Particubes", "a parent directory exists but is a regular file. (%s) (%s)", absFilePath.c_str(), currentRelPath.c_str());
                    return nullptr;
                }
            }
        }
        // The file being opened is at the root of the storage directory, there is nothing to do.
    }
    return fopen(absFilePath.c_str(), mode.c_str());
}

std::vector<std::string> vx::fs::listStorageDirectory(const std::string& relStoragePath) {
    const std::string absPath = vx::android::getAndroidStoragePath() + "/" + relStoragePath;
    std::vector<std::string> files;

    DIR *dir = opendir(absPath.c_str());
    if (dir == nullptr) {
        __android_log_print(ANDROID_LOG_ERROR, "Particubes", "opendir failed in storage. (%s)", absPath.c_str());
        return files;
    }

    struct dirent *ent;
    while((ent = readdir(dir)) != nullptr) {
        // filter out "." and ".."
        if (strcmp(ent->d_name, ".") == 0 ||
            strcmp(ent->d_name, "..") == 0) {
            continue;
        }

        std::string fullName(relStoragePath + "/" + ent->d_name);

        if (ent->d_type == DT_REG || ent->d_type == DT_DIR) {
            // regular file or directory
            files.push_back(fullName);
        }
    }
    closedir(dir);

    return files;
}

void vx::fs::importFile(vx::fs::ImportFileCallback callback) {
    __android_log_print(ANDROID_LOG_INFO, "Particubes", "[importFile]");

    // store the callback that will be called once we get the result
    currentImportCallback = callback;

    bool just_attached = false;
    vx::tools::JniMethodInfo methodInfo;

    if (!vx::tools::JNIUtils::getInstance()->getMethodInfo(&just_attached, &methodInfo,
                                                           "com/voxowl/tools/Filesystem",
                                                           "importFile",
                                                           "()V"))
    {
        __android_log_print(ANDROID_LOG_ERROR, "Particubes", "%s %d: error to get methodInfo", __FILE__, __LINE__);
        assert(false); // crash the program
    }

    methodInfo.env->CallStaticVoidMethod(methodInfo.classID, methodInfo.methodID);

    methodInfo.env->DeleteLocalRef(methodInfo.classID);

    if (just_attached) {
        vx::tools::JNIUtils::getInstance()->getJavaVM()->DetachCurrentThread();
    }
}

#ifdef _ANDROID
// calls the assigned static function, bytes needs to be freed
void vx::fs::callCurrentImportCallback(void *bytes, size_t len, vx::fs::ImportFileCallbackStatus status) {
    if (currentImportCallback == nullptr) {
        return;
    }

    currentImportCallback(bytes, len, status);
}
#endif

///
bool vx::fs::removeStorageFileOrDirectory(std::string relFilePath) {
    std::string absFilePath = vx::android::getAndroidStoragePath();
    if (*(relFilePath.cbegin()) != '/') {
        absFilePath += "/";
    }
    absFilePath += relFilePath;
    return remove(absFilePath.c_str()) == 0;
}

///
bool vx::fs::bundleFileExists(const std::string& relFilePath, bool& isDir) {
    {
        AAsset * const asset = AAssetManager_open(vx::android::getAndroidAssetManager(),
                                                  relFilePath.c_str(),
                                                  AASSET_MODE_UNKNOWN);
        if (asset != nullptr) {
            // free resource
            AAsset_close(asset);
            // bundle file exists and is not a directory
            isDir = false;
            return true;
        }
    }
    {
        AAssetDir * const assetDir = AAssetManager_openDir(vx::android::getAndroidAssetManager(),
                                                           relFilePath.c_str());
        if (assetDir != nullptr) {
            // Directory may or may not exist, we need to list its content.
            // Check if the directory contains any files
            const char* firstFileName = AAssetDir_getNextFileName(assetDir);

            // free resource
            AAssetDir_close(assetDir);

            // If firstFileName is NULL, the directory is empty or doesn't exist
            if (firstFileName != nullptr) {
                // bundle file exists and is a directory
                isDir = true;
                return true;
            }
        }
    }

    // bundle file doesn't exist
    return false;
}

///
bool vx::fs::storageFileExists(const std::string &relFilePath, bool &isDir) {
    // construct file absolute path
    std::string absFilePath = vx::android::getAndroidStoragePath();
    if (*(relFilePath.cbegin()) != '/') {
        absFilePath += "/";
    }
    absFilePath += relFilePath;
    // check if file exists
    struct stat buffer;
    int status = stat(absFilePath.c_str(), &buffer); // success if 0
    if (status == 0) {
        // file exists
        isDir = S_ISDIR(buffer.st_mode);
        return true;
    }
    return false;
}

///
bool vx::fs::mergeBundleDirInStorage(const std::string &bundleDir, const std::string &storageDir) {
    __android_log_print(ANDROID_LOG_ERROR, "Particubes", "[mergeBundleDirInStorage]");

    bool just_attached = false;
    vx::tools::JniMethodInfo methodInfo;

    if (!vx::tools::JNIUtils::getInstance()->getMethodInfo(&just_attached, &methodInfo,
                                               "com/voxowl/tools/Filesystem",
                                               "mergeBundleDirInStorage",
                                               "(Ljava/lang/String;Ljava/lang/String;)Z"))
    {
        __android_log_print(ANDROID_LOG_ERROR, "Particubes", "%s %d: error to get methodInfo", __FILE__, __LINE__);
        assert(false); // crash the program
    }

    jstring j_bundleDir = methodInfo.env->NewStringUTF(bundleDir.c_str());
    jstring j_storageDir = methodInfo.env->NewStringUTF(storageDir.c_str());

    jboolean result = methodInfo.env->CallStaticBooleanMethod(methodInfo.classID, methodInfo.methodID, j_bundleDir, j_storageDir);

    methodInfo.env->DeleteLocalRef(methodInfo.classID);
    methodInfo.env->DeleteLocalRef(j_bundleDir);
    methodInfo.env->DeleteLocalRef(j_storageDir);

    if (just_attached) {
        vx::tools::JNIUtils::getInstance()->getJavaVM()->DetachCurrentThread();
    }

    return result;
}

void vx::fs::shareFile(const std::string& filepath,
                       const std::string& title,
                       const std::string& filename,
                       const fs::FileType type) {
    __android_log_print(ANDROID_LOG_ERROR, "Particubes", "[shareFile]");

    bool just_attached = false;
    vx::tools::JniMethodInfo methodInfo;

    if (!vx::tools::JNIUtils::getInstance()->getMethodInfo(&just_attached, &methodInfo,
                                                           "com/voxowl/tools/Filesystem",
                                                           "shareFile",
                                                           "(Ljava/lang/String;I)V"))
    {
        __android_log_print(ANDROID_LOG_ERROR, "Particubes", "%s %d: error to get methodInfo", __FILE__, __LINE__);
        assert(false); // crash the program
    }

    jstring j_filepath = methodInfo.env->NewStringUTF(filepath.c_str());
    jint j_type = 0;
    switch (type) {
        case FileType::PNG:
            j_type = 0;
            break;
        case FileType::PCUBES:
            j_type = 1;
            break;
        case FileType::VOX:
            j_type = 2;
            break;
        case FileType::OBJ:
            j_type = 3;
            break;
        default:
            break;
    }

    methodInfo.env->CallStaticVoidMethod(methodInfo.classID, methodInfo.methodID, j_filepath, j_type);

    methodInfo.env->DeleteLocalRef(methodInfo.classID);
    methodInfo.env->DeleteLocalRef(j_filepath);

    if (just_attached) {
        vx::tools::JNIUtils::getInstance()->getJavaVM()->DetachCurrentThread();
    }

    return;
}

///
bool vx::fs::removeStorageFilesWithPrefix(const std::string& directory, const std::string& prefix) {
    if (prefix.empty()) {
        return false;
    }
    bool success = true;

    // storage directory path
    const std::string storagePath = vx::android::getAndroidStoragePath();
    const std::string absStorageDir = storagePath + "/" + directory;

    // enumerate files located in directory
    dirent* dp = nullptr;
    DIR* dirp = opendir(absStorageDir.c_str());
    if (dirp == nullptr) {
        return false;
    }
    while ((dp = readdir(dirp)) != nullptr) {
        if (strcmp(dp->d_name, ".") == 0 || strcmp(dp->d_name, "..") == 0) {
            continue;
        }
        const std::string childName = std::string(dp->d_name);
        const std::string childAbsPath = absStorageDir + "/" + childName;

        // check if file exists
        bool fileExists = false;
        bool isDirectory = false;
        struct stat buffer;
        int status = stat(childAbsPath.c_str(), &buffer); // success if 0
        if (status == 0) { // file exists
            fileExists = true;
            isDirectory = S_ISDIR(buffer.st_mode);
        }

        if (!fileExists || isDirectory) {
            continue;
        }
        if (childName.find(prefix) == 0) {
            if (remove(childAbsPath.c_str()) != 0) {
                success = false;
            }
        }
    }
    closedir(dirp);
    return success;
}

// ------------------------------
// Helper
// ------------------------------

bool vx::fs::Helper::setInMemoryStorage(bool b) {
    // in memory storage not allowed on Android for now
    return false;
}
