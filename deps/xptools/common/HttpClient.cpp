//
//  HttpClient.cpp
//  xptools
//
//  Created by Gaetan de Villele on 24/01/2022.
//  Copyright © 2022 voxowl. All rights reserved.
//

#include "HttpClient.hpp"

// C++
#include <cassert>
#include <mutex>
#include <sstream>

// xptools
#include "device.hpp"
#include "vxlog.h"
#include "strings.hpp"
#include "filesystem.hpp"

#include "BZMD5.hpp"
#include "cJSON.h"

#if defined(__VX_USE_LIBWEBSOCKETS)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wall"
#pragma clang diagnostic ignored "-Wextra"
#pragma clang diagnostic ignored "-Wdocumentation"
#include "libwebsockets.h"
#pragma clang diagnostic pop

#endif

#define VX_HTTP_CACHE_MAGICBYTES "CUBZHCACHE!"
#define VX_HTTP_CACHE_MAGICBYTES_LEN 11
#define VX_HTTP_CACHE_FILE_FORMAT_V1 1 // uint8
#define VX_HTTP_CACHE_FILE_FORMAT_V2 2 // uint8
#define VX_HTTP_CACHE_COMPRESSION_NONE 1 // uint8
// chunk IDs are uint8s
#define VX_HTTP_CACHE_CHUNK_CREATIONTIME 1 // value is uint32 (seconds since 2001/01/01)
#define VX_HTTP_CACHE_CHUNK_MAXAGE 2 // value is uint32 (seconds)
#define VX_HTTP_CACHE_CHUNK_URL 3 // value is string
#define VX_HTTP_CACHE_CHUNK_STATUSCODE 4 // value is uint32
#define VX_HTTP_CACHE_CHUNK_HEADERS 5 // value is string (multiple occurences)
#define VX_HTTP_CACHE_CHUNK_BODY 6 // value is string (raw bytes)
#define VX_HTTP_CACHE_CHUNK_ETAG 7 // value is string (ETag bytes)

namespace vx {

// HttpClient::CacheMatch implementation

HttpClient::CacheMatch::CacheMatch() :
didFindCache(false),
isStillFresh(false) {}

HttpClient::CacheMatch::CacheMatch(const bool didFindCache, const bool isNonExpired) :
didFindCache(didFindCache),
isStillFresh(isNonExpired) {}

// HttpClient implementation

HttpClient* HttpClient::_sharedInstance = nullptr;

std::unordered_map<std::string, std::string> HttpClient::noHeaders = std::unordered_map<std::string, std::string>();

// --------------------------------------------------
// Public
// --------------------------------------------------

HttpClient& HttpClient::shared() {
    if (HttpClient::_sharedInstance == nullptr) {
        HttpClient::_sharedInstance = new HttpClient();
    }
    return *_sharedInstance;
}

HttpClient::~HttpClient() {}

void HttpClient::setCallbackMiddleware(HttpClient::CallbackMiddleware func) {
    _callbackMiddleware = func;
}

HttpClient::CallbackMiddleware HttpClient::getCallbackMiddleware() {
    return _callbackMiddleware;
}

HttpRequest_SharedPtr HttpClient::GET(const URL& url,
                                      const std::unordered_map<std::string, std::string>& headers,
                                      const HttpRequestOpts& opts,
                                      HttpRequestCallback callback) {
    if (url.isValid() == false) {
        return nullptr;
    }

    // this function (HttpClient::GET) doesn't support streaming yet
    if (opts.getStreamResponse() == true) {
        return nullptr;
    }

    const bool secure = url.scheme() == VX_HTTPS_SCHEME;

    HttpRequest_SharedPtr req = HttpRequest::make("GET",
                                                  url.host(),
                                                  url.port(),
                                                  url.path(),
                                                  url.queryParams(),
                                                  secure);
    req->setHeaders(headers);
    req->setCallback(callback);
    req->setOpts(opts);

    if (opts.getSendNow()) {
        req->sendAsync();
    }

    return req;
}

HttpRequest_SharedPtr HttpClient::GET(const std::string& host,
                                      const uint16_t& port,
                                      const std::string& path,
                                      const QueryParams& queryParams,
                                      const bool& secure,
                                      const std::unordered_map<std::string, std::string>& headers,
                                      const HttpRequestOpts *opts,
                                      HttpRequestCallback callback) {
    HttpRequest_SharedPtr req = HttpRequest::make("GET", host, port, path, queryParams, secure);
    if (opts != nullptr) {
        req->setOpts(*opts);
    }
    req->setHeaders(headers);
    req->setCallback(callback);
    req->sendAsync();
    return req;
}

HttpRequest_SharedPtr HttpClient::POST(const std::string& host,
                                       const uint16_t& port,
                                       const std::string& path,
                                       const QueryParams& queryParams,
                                       const bool& secure,
                                       const std::unordered_map<std::string, std::string>& headers,
                                       const HttpRequestOpts *opts,
                                       const std::string& body,
                                       HttpRequestCallback callback) {
    HttpRequest_SharedPtr req = HttpRequest::make("POST", host, port, path, queryParams, secure);
    if (opts != nullptr) {
        req->setOpts(*opts);
    }
    req->setHeaders(headers);
    req->setBodyBytes(body);
    req->setCallback(callback);
    req->sendAsync();
    return req;
}

HttpRequest_SharedPtr HttpClient::POST(const std::string &url,
                                       const std::unordered_map<std::string, std::string> &headers,
                                       const HttpRequestOpts *opts,
                                       const std::string& body,
                                       const bool &sendNow,
                                       HttpRequestCallback callback) {
    const std::string httpMethod = "POST";
    return this->_makeRequest(httpMethod, url, headers, opts, body, sendNow, callback);
}

HttpRequest_SharedPtr HttpClient::PATCH(const std::string &url,
                                        const std::unordered_map<std::string, std::string> &headers,
                                        const HttpRequestOpts *opts,
                                        const std::string &body,
                                        const bool &sendNow,
                                        HttpRequestCallback callback) {
    const std::string httpMethod = "PATCH";
    return this->_makeRequest(httpMethod, url, headers, opts, body, sendNow, callback);
}

HttpRequest_SharedPtr HttpClient::PATCH(const URL& url,
                                        const std::unordered_map<std::string, std::string> &headers,
                                        const std::string &body,
                                        const HttpRequestOpts& opts,
                                        HttpRequestCallback callback) {
    if (url.isValid() == false) {
        return nullptr;
    }

    const bool secure = url.scheme() == VX_HTTPS_SCHEME;

    HttpRequest_SharedPtr req = HttpRequest::make("PATCH",
                                                  url.host(),
                                                  url.port(),
                                                  url.path(),
                                                  url.queryParams(),
                                                  secure);
    req->setHeaders(headers);
    req->setHeaders(headers);
    req->setBodyBytes(body);
    req->setCallback(callback);
    req->setOpts(opts);

    if (opts.getSendNow()) {
        req->sendAsync();
    }

    return req;
}

HttpRequest_SharedPtr HttpClient::Delete(const std::string &url,
                                         const std::unordered_map<std::string, std::string> &headers,
                                         const HttpRequestOpts *opts,
                                         const std::string &body,
                                         const bool &sendNow,
                                         HttpRequestCallback callback) {
    const std::string httpMethod = "DELETE";
    return this->_makeRequest(httpMethod, url, headers, opts, body, sendNow, callback);
}

void HttpClient::run_unit_tests() {
    run_unit_tests_parse_url();
    run_unit_tests_get_url();
}

// --------------------------------------------------
// Private
// --------------------------------------------------

HttpRequest_SharedPtr HttpClient::_makeRequest(const std::string& httpMethod,
                                               const std::string& urlStr,
                                               const std::unordered_map<std::string, std::string>& headers,
                                               const HttpRequestOpts *opts,
                                               const std::string& body,
                                               const bool& sendNow,
                                               HttpRequestCallback callback) {
    const vx::URL url = vx::URL::make(urlStr, VX_HTTPS_SCHEME);
    if (url.isValid() == false || (url.scheme() != VX_HTTP_SCHEME && url.scheme() != VX_HTTPS_SCHEME)) {
        return nullptr;
    }

    const bool isSecure = url.scheme() == VX_HTTPS_SCHEME;
    HttpRequest_SharedPtr req = HttpRequest::make(httpMethod,
                                                  url.host(),
                                                  url.port(),
                                                  url.path(),
                                                  url.queryParams(),
                                                  isSecure);
    if (opts != nullptr) {
        req->setOpts(*opts);
    }
    req->setHeaders(headers);
    req->setBodyBytes(body);
    req->setCallback(callback);
    if (sendNow) {
        req->sendAsync();
    }
    return req;
}

void HttpClient::run_unit_tests_parse_url() {
    {
        const vx::URL url = vx::URL::make("https://app.cu.bzh:42/my/path?foo=bar&bar=baz&foo=bar2");
        assert(url.isValid());
        assert(url.scheme() == "https");
        assert(url.host() == "app.cu.bzh");
        assert(url.port() == 42);
        assert(url.path() == "/my/path");
        const QueryParams& queryParams = url.queryParams();
        assert(queryParams.at("foo").size() == 2);
        assert(queryParams.at("bar").size() == 1);
        assert(queryParams.at("foo").find("bar") != queryParams.at("foo").end());
        assert(queryParams.at("foo").find("bar2") != queryParams.at("foo").end());
        assert(queryParams.at("bar").find("baz") != queryParams.at("bar").end());
    }

    {
        const vx::URL url = vx::URL::make("https://google.com");
        assert(url.isValid());
        assert(url.scheme() == "https");
        assert(url.host() == "google.com");
        assert(url.port() == HTTPS_PORT);
        assert(url.path() == "");
    }

    {
        const vx::URL url = vx::URL::make("https://google.com/test");
        assert(url.isValid());
        assert(url.scheme() == "https");
        assert(url.host() == "google.com");
        assert(url.port() == HTTPS_PORT);
        assert(url.path() == "/test");
    }

    {
        const vx::URL url = vx::URL::make("https://google.com///test");
        assert(url.isValid());
        assert(url.scheme() == "https");
        assert(url.host() == "google.com");
        assert(url.port() == HTTPS_PORT);
        assert(url.path() == "///test");
    }

    {
        const vx::URL url = vx::URL::make("http://api.org/api/v1/endpoint?order=asc");
        assert(url.isValid());
        assert(url.scheme() == "http");
        assert(url.host() == "api.org");
        assert(url.port() == HTTP_PORT);
        assert(url.path() == "/api/v1/endpoint");
        const QueryParams& queryParams = url.queryParams();
        assert(queryParams.at("order").find("asc") != queryParams.at("order").end());
    }

    {
        const vx::URL url = vx::URL::make("wss://api.cu.bzh:42/foo");
        assert(url.isValid());
        assert(url.scheme() == "wss");
        assert(url.host() == "api.cu.bzh");
        assert(url.port() == 42);
        assert(url.path() == "/foo");
    }
}

// Makes sure the request is not sent when SendNow is false
void HttpClient::run_unit_tests_get_url() {
    URL url = URL::make("https://api.cu.bzh");
    assert(url.isValid());

    HttpRequestOpts opts;
    opts.setSendNow(false);

    HttpRequest_SharedPtr req = HttpClient::shared().GET(url, HttpClient::noHeaders, opts, [](HttpRequest_SharedPtr req) {});
    assert(req->getStatus() == HttpRequest::Status::WAITING);
}

HttpClient::HttpClient() :
_cacheMutex(),
_callbackMiddleware(nullptr) {}

bool HttpClient::cacheHttpResponse(HttpRequest_SharedPtr req) {
    // For now, there is no caching for streamed HTTP responses
    if (req->getOpts().getStreamResponse()) {
        return false; // was not cached
    }

    const std::lock_guard<std::mutex> lock(this->_cacheMutex);
    bool ok = false;

    HttpResponse& response = req->getResponse();
    const HttpHeaders& responseHeaders = response.getHeaders();

    // test status code
    const uint16_t statusCode = response.getStatusCode();
    if (statusCode < 200 || statusCode >= 400) {
        // status code represents an error, don't cache response
        return false;
    }

    // parse HTTP response headers related to caching
    uint32_t maxAge = 0;
    const bool maxAgeFound = responseHeaders.find("cache-control") != responseHeaders.end();
    if (maxAgeFound) {
        const std::string cacheControlStr = responseHeaders.at("cache-control");
        std::vector<std::string> directives = _parseCacheControlHeaderValue(cacheControlStr);
        for (std::string directive : directives) {
            const std::string prefix = "max-age=";
            if (directive.rfind(prefix, 0) == 0) {
                directive.erase(0, prefix.length());
                if (vx::str::toUInt32(directive, maxAge) == false) {
                    return false;
                }
            }
        }
    }

    std::string etag = "";
    const bool etagFound = responseHeaders.find("etag") != responseHeaders.end();
    if (etagFound) {
        etag = responseHeaders.at("etag");
    }

    // TODO: used cached URL, do not reconstruct URL here
    const std::string requestURL = req->constructURLString();

    // generate hash from URL
    const std::string urlHash = md5(requestURL);

    // open cache file in storage
    const std::string filepath = std::string(VX_HTTP_CACHE_DIR_NAME) + "/" + urlHash;

    // creates file is not present, truncate it otherwise
    FILE* fd = vx::fs::openStorageFile(filepath, "wb");
    if (fd == nullptr) {
        return false;
    }

    // cache file header
    {
        ok = _cacheWriteFileHeader(VX_HTTP_CACHE_FILE_FORMAT_V2, VX_HTTP_CACHE_COMPRESSION_NONE, fd);
        if (ok == false) {
            goto return_false;
        }
    }

    // etag
    {
        ok = _cacheWriteStringChunk(VX_HTTP_CACHE_CHUNK_ETAG, etag, fd);
        if (ok == false) {
            goto return_false;
        }
    }

    // file creation time
    {
        const uint32_t creationTime = static_cast<uint32_t>(vx::device::timestampApple());
        ok = _cacheWriteUint32Chunk(VX_HTTP_CACHE_CHUNK_CREATIONTIME, creationTime, fd);
        if (ok == false) {
            goto return_false;
        }
    }

    // max-age value
    {
        ok = _cacheWriteUint32Chunk(VX_HTTP_CACHE_CHUNK_MAXAGE, maxAge, fd);
        if (ok == false) {
            goto return_false;
        }
    }

    // request URL
    {
        ok = _cacheWriteStringChunk(VX_HTTP_CACHE_CHUNK_URL, requestURL, fd);
        if (ok == false) {
            goto return_false;
        }
    }

    // HTTP status
    {
        ok = _cacheWriteUint32Chunk(VX_HTTP_CACHE_CHUNK_STATUSCODE, response.getStatusCode(), fd);
        if (ok == false) {
            goto return_false;
        }
    }

    // HTTP response headers
    {
        ok = _cacheWriteMapStringStringChunk(VX_HTTP_CACHE_CHUNK_HEADERS, responseHeaders, fd);
        if (ok == false) {
            goto return_false;
        }
    }

    // HTTP response body
    {
        std::string allBytes;
        ok = response.readAllBytes(allBytes);
        if (ok == false) {
            goto return_false;
        }
        ok = _cacheWriteStringChunk(VX_HTTP_CACHE_CHUNK_BODY, allBytes, fd);
        if (ok == false) {
            goto return_false;
        }
    }

    // Success case - close file and return true
    fclose(fd);
    return true;

return_false:
    fclose(fd);
    vx::fs::removeStorageFileOrDirectory(filepath);
    return false;
}

#if !defined(__VX_PLATFORM_WASM)

HttpClient::CacheMatch HttpClient::getCachedResponseForRequest(HttpRequest_SharedPtr req) {
    const std::lock_guard<std::mutex> lock(this->_cacheMutex);

    bool ok = false;
    CacheMatch result;

    if (req == nullptr) {
        return result;
    }

    if (req->getStatus() != HttpRequest::Status::WAITING) {
        return result;
    }

    // TODO: used cached URL, do not reconstruct URL here
    const std::string requestURL = req->constructURLString();

    // generate hash from URL
    const std::string urlHash = md5(requestURL);

    // open cache file in storage
    const std::string filepath = std::string(VX_HTTP_CACHE_DIR_NAME) + "/" + urlHash;

    // check cache file exists
    {
        bool isDir = false;
        const bool exists = vx::fs::storageFileExists(filepath, isDir);
        if (exists == false || isDir) {
            return result;
        }
    }

    // open cache file
    FILE *fd = vx::fs::openStorageFile(filepath);
    if (fd == nullptr) {
        return result;
    }

    result.didFindCache = true;

    // skip header
    {
        fseek(fd, VX_HTTP_CACHE_MAGICBYTES_LEN, SEEK_SET);
    }

    // file format version & file compression method
    uint8_t fileFormatVersion = 0;
    {
        uint8_t fileCompressionMethod = 0;
        ok = _cacheReadFileHeader(&fileFormatVersion, &fileCompressionMethod, fd);
        if (ok == false) {
            goto return_cache_not_found_and_delete_cache;
        }
    }

    if (fileFormatVersion > 1) {
        std::string etag;
        ok = _cacheReadStringChunk(VX_HTTP_CACHE_CHUNK_ETAG, etag, fd);
        if (ok == false) {
            goto return_cache_not_found_and_delete_cache;
        }
        if (etag.empty() == false) {
            req->setOneHeader("If-None-Match", etag);
        }
    } else {
        // ignore & delete old cache
        goto return_cache_not_found_and_delete_cache;
    }

    // check cache is not expired
    {
        uint32_t cacheCreationTime = 0;
        ok = _cacheReadUint32Chunk(VX_HTTP_CACHE_CHUNK_CREATIONTIME, cacheCreationTime, fd);
        if (ok == false) {
            goto return_cache_not_found_and_delete_cache;
        }

        uint32_t maxAge = 0;
        ok = _cacheReadUint32Chunk(VX_HTTP_CACHE_CHUNK_MAXAGE, maxAge, fd);
        if (ok == false) {
            goto return_cache_not_found_and_delete_cache;
        }

        const uint32_t currentTime = static_cast<uint32_t>(vx::device::timestampApple());
        result.isStillFresh = currentTime < (cacheCreationTime + maxAge);
    }

    // read cache content
    {
        std::string url;
        ok = _cacheReadStringChunk(VX_HTTP_CACHE_CHUNK_URL, url, fd);
        if (ok == false || url != requestURL) {
            goto return_cache_not_found_and_delete_cache;
        }

        uint32_t statusCode = 0;
        ok = _cacheReadUint32Chunk(VX_HTTP_CACHE_CHUNK_STATUSCODE, statusCode, fd);
        if (ok == false) {
            goto return_cache_not_found_and_delete_cache;
        }

        HttpHeaders headers;
        ok = _cacheReadMapStringStringChunk(VX_HTTP_CACHE_CHUNK_HEADERS, headers, fd);
        if (ok == false) {
            goto return_cache_not_found_and_delete_cache;
        }

        std::string body;
        ok = _cacheReadStringChunk(VX_HTTP_CACHE_CHUNK_BODY, body, fd);
        if (ok == false) {
            goto return_cache_not_found_and_delete_cache;
        }

        req->setCachedResponse(true, static_cast<uint16_t>(statusCode), std::move(headers), body);
    }

    fclose(fd);
    return result;

return_cache_not_found_and_delete_cache:
    fclose(fd);
    vx::fs::removeStorageFileOrDirectory(filepath);
    result.didFindCache = false;
    result.isStillFresh = false;
    return result;
}

bool HttpClient::removeCachedResponseForRequest(HttpRequest_SharedPtr req) {
    const std::lock_guard<std::mutex> lock(this->_cacheMutex);

    if (req == nullptr) {
        return false;
    }

    // if (req->getStatus() != HttpRequest::Status::DONE) {
    //     return false;
    // }

    // TODO: used cached URL, do not reconstruct URL here
    const std::string requestURL = req->constructURLString();

    // generate hash from URL
    const std::string urlHash = md5(requestURL);

    // open cache file in storage
    const std::string filepath = std::string(VX_HTTP_CACHE_DIR_NAME) + "/" + urlHash;

    //vxlog_debug("❌ REMOVE HTTP CACHE: %s", filepath.c_str());

    const bool ok = vx::fs::removeStorageFileOrDirectory(filepath);
    return ok;
}

#endif // !defined(__VX_PLATFORM_WASM)

bool HttpClient::_cacheWriteFileHeader(const uint8_t fileFormatVersion,
                                       const uint8_t compressionMethod,
                                       FILE * const fd) {
    if (fd == nullptr) {
        return false;
    }

    // make sure cursor is at the start of the file
    if (ftell(fd) != 0) {
        return false;
    }

    size_t n = 0;
    n = fwrite(VX_HTTP_CACHE_MAGICBYTES, sizeof(char), VX_HTTP_CACHE_MAGICBYTES_LEN, fd);
    if (n != VX_HTTP_CACHE_MAGICBYTES_LEN) {
        return false;
    }

    n = fwrite(&fileFormatVersion, sizeof(uint8_t), 1, fd);
    if (n != 1) {
        return false;
    }

    n = fwrite(&compressionMethod, sizeof(uint8_t), 1, fd);
    if (n != 1) {
        return false;
    }

    return true;
}

bool HttpClient::_cacheWriteUint32Chunk(const uint8_t chunkID,
                                        const uint32_t chunkValue,
                                        FILE * const fd) {
    if (fd == nullptr) {
        return false;
    }

    size_t n = 0;

    // chunk ID
    n = fwrite(&chunkID, sizeof(uint8_t), 1, fd);
    if (n != 1) {
        return false;
    }

    // chunk value
    n = fwrite(&chunkValue, sizeof(uint32_t), 1, fd);
    if (n != 1) {
        return false;
    }

    return true;
}

bool HttpClient::_cacheWriteStringChunk(const uint8_t chunkID,
                                        const std::string chunkValue,
                                        FILE * const fd) {
    if (fd == nullptr) {
        return false;
    }

    size_t n = 0;

    // chunk ID
    n = fwrite(&chunkID, sizeof(uint8_t), 1, fd);
    if (n != 1) {
        return false;
    }

    const uint32_t valueLen = static_cast<uint32_t>(chunkValue.length());

    // chunk value length
    n = fwrite(&valueLen, sizeof(uint32_t), 1, fd);
    if (n != 1) {
        return false;
    }

    // chunk value
    n = fwrite(chunkValue.c_str(), sizeof(char), chunkValue.length(), fd);
    if (n != chunkValue.length()) {
        return false;
    }

    return true;
}

bool HttpClient::_cacheWriteMapStringStringChunk(const uint8_t chunkID,
                                                 const std::unordered_map<std::string, std::string>& chunkValue,
                                                 FILE * const fd) {
    if (fd == nullptr) {
        return false;
    }

    size_t n = 0;

    // chunk ID
    {
        n = fwrite(&chunkID, sizeof(uint8_t), 1, fd);
        if (n != 1) {
            return false;
        }
    }

    // count of key-value pairs
    {
        const uint32_t kvCount = static_cast<uint32_t>(chunkValue.size());
        n = fwrite(&kvCount, sizeof(uint32_t), 1, fd);
        if (n != 1) {
            return false;
        }
    }

    // key-value pairs
    for (auto kv : chunkValue) {
        // key
        {
            const std::string& str = kv.first;
            const uint32_t& len = static_cast<uint32_t>(str.length());
            n = fwrite(&len, sizeof(uint32_t), 1, fd);
            if (n != 1) {
                return false;
            }
            n = fwrite(str.c_str(), sizeof(char), len, fd);
            if (n != len) {
                return false;
            }
        }

        // value
        {
            const std::string& str = kv.second;
            const uint32_t& len = static_cast<uint32_t>(str.length());
            n = fwrite(&len, sizeof(uint32_t), 1, fd);
            if (n != 1) {
                return false;
            }
            n = fwrite(str.c_str(), sizeof(char), len, fd);
            if (n != len) {
                return false;
            }
        }
    }

    return true;
}

bool HttpClient::_cacheReadFileHeader(uint8_t *fileFormatVersion, uint8_t *compressionMethod, FILE * const fd) {

    if (fd == nullptr) { return false; }
    if (ftell(fd) != VX_HTTP_CACHE_MAGICBYTES_LEN) { return false; }

    size_t n = 0;

    // file format
    {
        n = fread(fileFormatVersion, sizeof(uint8_t), 1, fd);
        if (n != 1) {
            return false;
        }
    }

    // compression method
    {
        n = fread(compressionMethod, sizeof(uint8_t), 1, fd);
        if (n != 1) {
            return false;
        }
    }

    return true;
}

bool HttpClient::_cacheReadUint32Chunk(const uint8_t chunkID, uint32_t& chunkValue, FILE * const fd) {
    if (fd == nullptr) {
        return false;
    }

    size_t n = 0;

    // chunk ID
    {
        uint8_t chunkIDRead = 0;
        n = fread(&chunkIDRead, sizeof(uint8_t), 1, fd);
        if (n != 1) {
            return false;
        }
        if (chunkIDRead != chunkID) {
            return false;
        }
    }

    // chunk value
    {
        n = fread(&chunkValue, sizeof(uint32_t), 1, fd);
        if (n != 1) {
            return false;
        }
    }

    return true;
}

bool HttpClient::_cacheReadStringChunk(const uint8_t chunkID, std::string& chunkValue, FILE * const fd) {
    if (fd == nullptr) {
        return false;
    }

    size_t n = 0;
    bool ok = false;

    // chunk ID
    {
        uint8_t chunkIDRead = 0;
        n = fread(&chunkIDRead, sizeof(uint8_t), 1, fd);
        if (n != 1) {
            return false;
        }
        if (chunkIDRead != chunkID) {
            return false;
        }
    }

    // chunk value
    {
        std::string value;
        ok = _readString(value, fd);
        if (ok == false) {
            return false;
        }
        chunkValue.assign(value);
    }

    return true;
}

bool HttpClient::_cacheReadMapStringStringChunk(const uint8_t chunkID,
                                                std::unordered_map<std::string, std::string>& chunkValue,
                                                FILE * const fd) {
    if (fd == nullptr) {
        return false;
    }

    size_t n = 0;
    bool ok = false;

    // chunk ID
    {
        uint8_t chunkIDRead = 0;
        n = fread(&chunkIDRead, sizeof(uint8_t), 1, fd);
        if (n != 1) {
            return false;
        }
        if (chunkIDRead != chunkID) {
            return false;
        }
    }

    // count of key-value pairs
    uint32_t count = 0;
    n = fread(&count, sizeof(uint32_t), 1, fd);
    if (n != 1) {
        return false;
    }

    std::string key;
    std::string value;
    for (uint32_t i = 0; i < count; ++i) {
        ok = _readString(key, fd);
        if (ok == false) {
            return false;
        }
        ok = _readString(value, fd);
        if (ok == false) {
            return false;
        }
        chunkValue.emplace(key, value);
    }

    return true;
}

bool HttpClient::_readString(std::string& out, FILE * const fd) {
    if (fd == nullptr) {
        return false;
    }

    size_t n = 0;

    uint32_t strLen = 0;
    n = fread(&strLen, sizeof(uint32_t), 1, fd);
    if (n != 1) {
        return false;
    }

    char *strBuf = static_cast<char *>(malloc(sizeof(char) * strLen));
    if (strBuf == nullptr) {
        return false;
    }
    n = fread(strBuf, sizeof(char), strLen, fd);
    if (n != strLen) {
        free(strBuf);
        return false;
    }
    out.assign(strBuf, strLen);
    free(strBuf);
    return true;
}

std::vector<std::string> HttpClient::_parseCacheControlHeaderValue(const std::string& cacheControlValue) {
    std::vector<std::string> directives;
    std::istringstream iss(cacheControlValue);
    std::string directive;
    while (std::getline(iss, directive, ',')) {
        // Remove leading and trailing whitespace from each directive
        directive.erase(0, directive.find_first_not_of(' '));
        directive.erase(directive.find_last_not_of(' ') + 1);
        directives.push_back(directive);
    }
    return directives;
}

}
