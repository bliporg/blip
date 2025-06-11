//
//  filesystem.hpp
//  xptools
//
//  Created by Gaetan de Villele on 03/03/2020.
//  Copyright © 2020 voxowl. All rights reserved.
//

#pragma once

// C
#include <cstdint>
// C++
#include <string>
#include <functional>
#include <map>
#include <vector>

#include <png.h>

namespace vx {
namespace fs {

//--------------------------------------------------
//
// MARK: - common -
//
//--------------------------------------------------

char getPathSeparator();
std::string getPathSeparatorStr();

class InMemoryFile {
public:
    InMemoryFile(size_t aSize);
    ~InMemoryFile();
    
    char *bytes;
    size_t size;
    
};

enum class FileType {
    NONE = -1,
    PNG = 0,
    PCUBES, // to be removed
    CUBZH,
    VOX,
    OBJ,
};

/// Singleton, used to store things like C++ callbacks that are a hard
/// to move around (different languages, etc.)
class Helper {
    
public:
    ///
    static Helper *shared();
    
    ///
    void setThumbnailCallback(std::function<void(FILE* thumbnail)> callback);
    
    ///
    void callThumbnailCallback(FILE* thumbnail);

    ///
    void setStorageRelPathPrefix(const std::string &prefix);

    ///
    std::string getStorageRelPathPrefix();

    /// Returns true if the change has been accepted
    /// All platforms may not support it.
    bool setInMemoryStorage(bool b);
    
    /// Returns true if using in memory storage.
    bool inMemoryStorage();
    
    ///
    InMemoryFile* getInMemoryFile(std::string path);
    
    ///
    InMemoryFile* createInMemoryFile(std::string path, size_t size);
    
private:
    ///
    static Helper *_instance;
    
    ///
    Helper();
    
    /// Callback to be triggered when the thumbnail is ready to be uploaded.
    std::function<void(FILE* thumbnail)> _thumbnailCallback;
    
    /// When set to true, all storage files are stored in memory
    bool _inMemoryStorage;
    
    /// A map to store in memory files and index them by path
    std::map<std::string, InMemoryFile*> _inMemoryFiles;

    ///
    std::string _storageRelPathPrefix;

};

//--------------------------------------------------
//
// MARK: - common -
//
//--------------------------------------------------

/// Computes the size (in bytes) of a file.
/// @param fp a valid FILE pointer.
size_t getFileSize(FILE *fp);

/// Returns a memory buffer with the content of a file.
/// The returned buffer cannot be cast directly into a NULL-terminated string (char*)
/// because it doesn't end with a NULL char. See function `getFileTextContentAndClose`.
/// After this function returned, the file descriptor is not valid anymore.
/// (it has been fclose-d)
/// @param fp a valid FILE pointer.
/// @param outDataSize a pointer to a variable to receive the size of the buffer.
void *getFileContent(FILE *fp, size_t *outDataSize);

/// Returns a null-terminated string containing the content of a text file.
/// After this function returned, the file descriptor is not valid anymore.
/// (it has been fclose-d)
/// @param fd a valid FILE pointer.
char *getFileTextContentAndClose(FILE *fd);

/// Returns a null-terminated string and closes the provided file
/// @param fd a valid FILE pointer.
/// @param textContent file output as a string
bool getFileTextContentAsStringAndClose(FILE *fd, std::string &textContent);

//// Writes data into a png file with standard compression
/// @param filename in storage, w/o extension
/// @param w image width
/// @param h image height
/// @param row_pointers data is expected as an array of rows
/// @param out copy of the PNG file content
/// @param outSize size of the content
/// @param bitDepth default 8
/// @param doWrite false to not write to file
bool writePng(const std::string& filename,
              uint32_t w,
              uint32_t h,
              png_bytepp row_pointers,
              void **out = nullptr,
              size_t *outSize = nullptr,
              int bitDepth = 8,
              bool doWrite = true);

//--------------------------------------------------
//
// MARK: - plateform specific -
//
//--------------------------------------------------

/// Description
/// @param relFilePath relFilePath description
// std::string getStorageFileAbsolutePath(std::string relFilePath);

/// Opens a file located on the system at given path
/// @param filePath path of the file to open.
FILE *openFile(const std::string& filePath, const std::string& mode = "rb");

/// Returns absolute path to bundle file, giving its rel path
std::string getBundleFilePath(const std::string& relFilePath);

/// Opens a file located in the bundle "assets" directory.
/// @param relFilePath name of the file to open. It shouldn't start with a '/'.
FILE *openBundleFile(std::string relFilePath, std::string mode = "rb");

/// Description
/// @param relFilePath relFilePath description
/// @param writeSize is used to reserve size for writing, mandatory when writing to memory
FILE *openStorageFile(std::string relFilePath, std::string mode = "rb", size_t writeSize = 0);

/// returns a vector containing the storage-relative paths of direct (not recursive) children of the given directory
std::vector<std::string> listStorageDirectory(const std::string& relStoragePath);

enum class ImportFileCallbackStatus {
    OK = 0,
    ERROR_IMPORT,
    CANCELLED,
};
typedef std::function<void(void *bytes, size_t len, ImportFileCallbackStatus status)> ImportFileCallback;
void importFile(ImportFileCallback callback);

#ifdef _ANDROID
void callCurrentImportCallback(void *bytes, size_t len, ImportFileCallbackStatus status);
#endif

/// Description
/// @param relFilePath file or directory to remove
bool removeStorageFileOrDirectory(std::string relFilePath);

///
bool bundleFileExists(const std::string& relFilePath, bool& isDir);

///
bool storageFileExists(const std::string& relFilePath);
bool storageFileExists(const std::string& relFilePath, bool& isDir);

/// Merges content of bundle directory into cache directory.
/// Overriding existing cache files if found.
bool mergeBundleDirInStorage(const std::string& bundleDir, const std::string& storageDir);

/// filepath is relative to storage
void shareFile(const std::string& filepath, // where the file to export is stored
               const std::string& title, // share dialog title (when applicable)
               const std::string& filename, // name of shared file, without extension
               const fs::FileType type); // png, pcubes, etc.

///
bool unzipBundle();

///
bool removeStorageFilesWithPrefix(const std::string& directory,
                                  const std::string& prefix);

///
unsigned char *getIcon16Pixels();

///
unsigned char *getIcon32Pixels();

///
unsigned char *getIcon48Pixels();

/// This is used on Web only to write the emscripten in-memory FS to the IBFS
/// on-disk storage
void syncFSToDisk();

/// 
void removeStorageDirectoryRecurse(std::string dirPath);

/// Reads entire file content.
/// Returns true on success, false otherwise.
bool readFile(const std::string filepath, std::string& dest);

/// Returns path without its last element.
std::string pathDir(const std::string& path);

/// Normalizes the given path, removing all "." and ".." elements it may contain.
std::string normalizePath(const std::string &path);

}
}
