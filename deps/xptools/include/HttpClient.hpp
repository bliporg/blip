//
//  HttpClient.hpp
//  xptools
//
//  Created by Gaetan de Villele on 24/01/2022.
//  Copyright © 2022 voxowl. All rights reserved.
//

#pragma once

// C++
#include <memory>
#include <mutex>
#include <queue>
#include <unordered_set>

// xptools
#include "HttpRequest.hpp"
#include "URL.hpp"

#define VX_HTTP_CACHE_DIR_NAME "http_cache"

// HTTP status codes
#define HTTP_OK 200
#define HTTP_NOT_MODIFIED 304

namespace vx {

/// singleton
class HttpClient final {

    // --------------------------------------------------
    // Public
    // --------------------------------------------------
public:

    ///
    class CacheMatch final {
    public:
        CacheMatch();
        CacheMatch(const bool didFindCache,
                   const bool isNonExpired);
        bool didFindCache;
        bool isStillFresh;
    };

    ///
    static std::unordered_map<std::string, std::string> noHeaders;

    /// Returns shared instance
    static HttpClient& shared();

    /// Destructor
    virtual ~HttpClient();

    typedef std::function<void(HttpRequest_SharedPtr stringReq)> CallbackMiddleware;
    void setCallbackMiddleware(CallbackMiddleware func);
    CallbackMiddleware getCallbackMiddleware();

    /// Sends a GET request
    ///
    /// Callback example:
    ///
    /// [](HttpRequest_SharedPtr req, const HttpResponse& resp){
    ///     vxlog_debug("%d %s", resp.getStatusCode(), resp.getBytes().c_str());
    /// }
    ///
    HttpRequest_SharedPtr GET(const URL& url,
                              const std::unordered_map<std::string, std::string>& headers,
                              const HttpRequestOpts& opts,
                              HttpRequestCallback callback);

    /// Sends a GET request
    ///
    /// Callback example:
    ///
    /// [](HttpRequest_SharedPtr req, const HttpResponse& resp){
    ///     vxlog_debug("%d %s", resp.getStatusCode(), resp.getBytes().c_str());
    /// }
    ///
    HttpRequest_SharedPtr GET(const std::string& host,
                              const uint16_t& port,
                              const std::string& path,
                              const QueryParams& queryParams,
                              const bool& secure,
                              const std::unordered_map<std::string, std::string>& headers,
                              const HttpRequestOpts *opts,
                              HttpRequestCallback callback);

    /// Sends a POST request
    ///
    /// Callback example:
    ///
    /// [](HttpRequest_SharedPtr req, const HttpResponse& resp){
    ///     vxlog_debug("%d %s", resp.getStatusCode(), resp.getBytes().c_str());
    /// }
    ///
    HttpRequest_SharedPtr POST(const std::string& host,
                               const uint16_t& port,
                               const std::string& path,
                               const QueryParams& queryParams,
                               const bool& secure,
                               const std::unordered_map<std::string, std::string>& headers,
                               const HttpRequestOpts *opts,
                               const std::string& body,
                               HttpRequestCallback callback);

    /// Sends or prepares a POST request
    ///
    /// Callback example:
    ///
    /// [](HttpRequest_SharedPtr req, const HttpResponse& resp){
    ///     vxlog_debug("%d %s", resp.getStatusCode(), resp.getBytes().c_str());
    /// }
    ///
    HttpRequest_SharedPtr POST(const std::string &url,
                               const std::unordered_map<std::string, std::string> &headers,
                               const HttpRequestOpts *opts,
                               const std::string &body,
                               const bool &sendNow,
                               HttpRequestCallback callback);

    /// Construct a PATCH HTTP request, and sends it now if asked.
    HttpRequest_SharedPtr PATCH(const std::string &url,
                                const std::unordered_map<std::string, std::string> &headers,
                                const HttpRequestOpts *opts,
                                const std::string &body,
                                const bool &sendNow,
                                HttpRequestCallback callback);

    HttpRequest_SharedPtr PATCH(const URL& url,
                                const std::unordered_map<std::string, std::string> &headers,
                                const std::string &body,
                                const HttpRequestOpts& opts,
                                HttpRequestCallback callback);

    /// Construct a DELETE HTTP request, and sends it now if asked.
    HttpRequest_SharedPtr Delete(const std::string &url,
                                 const std::unordered_map<std::string, std::string> &headers,
                                 const HttpRequestOpts *opts,
                                 const std::string &body,
                                 const bool &sendNow,
                                 HttpRequestCallback callback);

    /// Store HTTP response in cache
    bool cacheHttpResponse(HttpRequest_SharedPtr req);

#if !defined(__VX_PLATFORM_WASM)

    /// Retrieve cached response
    CacheMatch getCachedResponseForRequest(HttpRequest_SharedPtr req);

    /// Remove cached response from cache
    bool removeCachedResponseForRequest(HttpRequest_SharedPtr req);

#endif

    static void run_unit_tests();

    // --------------------------------------------------
    // Private
    // --------------------------------------------------
private:

    /// Shared instance
    static HttpClient* _sharedInstance;

    /// Constructor
    HttpClient();

    /// Generic function to make HTTP requests.
    HttpRequest_SharedPtr _makeRequest(const std::string& httpMethod,
                                       const std::string& url,
                                       const std::unordered_map<std::string, std::string>& headers,
                                       const HttpRequestOpts *opts,
                                       const std::string& body,
                                       const bool& sendNow,
                                       HttpRequestCallback callback);

    // HTTP Caching

    std::mutex _cacheMutex;

    CallbackMiddleware _callbackMiddleware;

    // file utils
    static bool _cacheWriteFileHeader(const uint8_t fileFormatVersion, const uint8_t compressionMethod, FILE * const fd);
    static bool _cacheWriteUint32Chunk(const uint8_t chunkID, const uint32_t chunkValue, FILE * const fd);
    static bool _cacheWriteStringChunk(const uint8_t chunkID, const std::string chunkValue, FILE * const fd);
    static bool _cacheWriteMapStringStringChunk(const uint8_t chunkID,
                                                const std::unordered_map<std::string, std::string>& chunkValue,
                                                FILE * const fd);
    static bool _cacheReadFileHeader(uint8_t *fileFormatVersion, uint8_t *compressionMethod, FILE * const fd);
    static bool _cacheReadUint32Chunk(const uint8_t chunkID, uint32_t& chunkValue, FILE * const fd);
    static bool _cacheReadStringChunk(const uint8_t chunkID, std::string& chunkValue, FILE * const fd);
    static bool _cacheReadMapStringStringChunk(const uint8_t chunkID,
                                               std::unordered_map<std::string, std::string>& chunkValue,
                                               FILE * const fd);

    static bool _readString(std::string& out, FILE * const fd);

    // Returns an array containing the cache-control directives
    static std::vector<std::string> _parseCacheControlHeaderValue(const std::string& cacheControlValue);

    // Unit tests
    static void run_unit_tests_parse_url();
    static void run_unit_tests_get_url();
};

}
