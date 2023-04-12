// -------------------------------------------------------------
//  Cubzh Core
//  serialization.c
//  Created by Gaetan de Villele on September 10, 2017.
// -------------------------------------------------------------

#include "serialization.h"

#include <stdlib.h>
#include <string.h>

#include "cclog.h"
#include "serialization_v5.h"
#include "serialization_v6.h"
#include "stream.h"
#include "transform.h"
#include "zlib.h"

// Returns 0 on success, 1 otherwise.
// This function doesn't close the file descriptor, you probably want to close
// it in the calling context, when an error occurs.
uint8_t readMagicBytes(Stream *s) {
    char current = 0;
    for (int i = 0; i < MAGIC_BYTES_SIZE; i++) {
        if (stream_read(s, &current, sizeof(char), 1) == false) {
            cclog_error("failed to read magic byte");
            return 1; // error
        }
        if (current != MAGIC_BYTES[i]) {
            cclog_error("incorrect magic bytes");
            return 1; // error
        }
    }
    return 0; // ok
}

uint8_t readMagicBytesLegacy(Stream *s) {
    char current = 0;
    for (int i = 0; i < MAGIC_BYTES_SIZE_LEGACY; i++) {
        if (stream_read(s, &current, sizeof(char), 1) == false) {
            cclog_error("failed to read magic byte");
            return 1; // error
        }
        if (current != MAGIC_BYTES_LEGACY[i]) {
            cclog_error("incorrect magic bytes");
            return 1; // error
        }
    }
    return 0; // ok
}

Shape *assets_get_root_shape(DoublyLinkedList *list) {
    Shape *shape = NULL;
    DoublyLinkedListNode *node = doubly_linked_list_first(list);
    while (node != NULL) {
        Asset *r = (Asset *)doubly_linked_list_node_pointer(node);
        if (r->type == AssetType_Shape) {
            Shape *s = (Shape *)r->ptr;
            if (transform_get_parent(shape_get_root_transform(s)) == NULL) {
                shape = s;
                break;
            }
        }
        node = doubly_linked_list_node_next(node);
        if (node == doubly_linked_list_first(list)) {
            node = NULL;
        }
    }
    return shape;
}

/// This does free the Stream
Shape *serialization_load_shape(Stream *s,
                                const char *fullname,
                                ColorAtlas *colorAtlas,
                                LoadShapeSettings *shapeSettings,
                                const bool allowLegacy) {
    DoublyLinkedList *assets = serialization_load_assets(s,
                                                         fullname,
                                                         AssetType_Shape,
                                                         colorAtlas,
                                                         shapeSettings,
                                                         allowLegacy);
    // s is NULL if it could not be loaded
    if (assets == NULL) {
        return NULL;
    }
    Shape *shape = assets_get_root_shape(assets);

    doubly_linked_list_flush(assets, free);
    doubly_linked_list_free(assets);
    return shape;
}

DoublyLinkedList *serialization_load_assets(Stream *s,
                                            const char *fullname,
                                            AssetType filterMask,
                                            ColorAtlas *colorAtlas,
                                            const LoadShapeSettings *const shapeSettings,
                                            const bool allowLegacy) {
    if (s == NULL) {
        cclog_error("can't load asset from NULL Stream");
        return NULL; // error
    }

    // read magic bytes
    if (readMagicBytes(s) != 0) {
        if (allowLegacy) {
            stream_set_cursor_position(s, 0);
            if (readMagicBytesLegacy(s) != 0) {
                stream_free(s);
                return NULL;
            }
        } else {
            stream_free(s);
            return NULL;
        }
    }

    // read file format
    uint32_t fileFormatVersion = 0;
    if (stream_read_uint32(s, &fileFormatVersion) == false) {
        cclog_error("failed to read file format version");
        stream_free(s);
        return NULL;
    }

    DoublyLinkedList *list = NULL;

    switch (fileFormatVersion) {
        case 5: {
            list = doubly_linked_list_new();
            Shape *shape = serialization_v5_load_shape(s, shapeSettings, colorAtlas);
            Asset *asset = malloc(sizeof(Asset));
            if (asset == NULL) {
                stream_free(s);
                return NULL;
            }
            asset->ptr = shape;
            asset->type = AssetType_Shape;
            doubly_linked_list_push_last(list, asset);
            break;
        }
        case 6: {
            list = serialization_load_assets_v6(s, colorAtlas, filterMask, shapeSettings);
            break;
        }
        default: {
            cclog_error("file format version not supported: %d", fileFormatVersion);
            break;
        }
    }

    stream_free(s);
    s = NULL;

    if (list != NULL && doubly_linked_list_node_count(list) == 0) {
        doubly_linked_list_free(list);
        list = NULL;
        cclog_error("[serialization_load_assets] no resources found");
    }

    // set fullname if containing a root shape
    Shape *shape = assets_get_root_shape(list);
    if (shape != NULL) {
        shape_set_fullname(shape, fullname);
    }

    return list;
}

bool serialization_save_shape(Shape *shape,
                              const void *imageData,
                              const uint32_t imageDataSize,
                              FILE *fd) {

    if (shape == NULL) {
        cclog_error("shape pointer is NULL");
        fclose(fd);
        return false;
    }

    if (fd == NULL) {
        cclog_error("file descriptor is NULL");
        fclose(fd);
        return false;
    }

    if (fwrite(MAGIC_BYTES, sizeof(char), MAGIC_BYTES_SIZE, fd) != MAGIC_BYTES_SIZE) {
        cclog_error("failed to write magic bytes");
        fclose(fd);
        return false;
    }

    const bool success = serialization_v6_save_shape(shape, imageData, imageDataSize, fd);

    fclose(fd);
    return success;
}

/// serialize a shape in a newly created memory buffer
/// Arguments:
/// - shape (mandatory)
/// - palette (optional)
/// - imageData (optional)
bool serialization_save_shape_as_buffer(Shape *shape,
                                        ColorPalette *artistPalette,
                                        const void *previewData,
                                        const uint32_t previewDataSize,
                                        void **outBuffer,
                                        uint32_t *outBufferSize) {

    return serialization_v6_save_shape_as_buffer(shape,
                                                 artistPalette,
                                                 previewData,
                                                 previewDataSize,
                                                 outBuffer,
                                                 outBufferSize);
}

// =============================================================================
// Previews
// =============================================================================

void free_preview_data(void **imageData) {
    free(*imageData);
}

///
bool get_preview_data(const char *filepath, void **imageData, uint32_t *size) {
    // open file for reading
    FILE *fd = fopen(filepath, "rb");
    if (fd == NULL) {
        // NOTE: this error may be intended
        // cclog_info("ERROR: get_preview_data: opening file");
        return false;
    }

    Stream *s = stream_new_file_read(fd);

    // read magic bytes
    if (readMagicBytes(s) != 0) {
        cclog_error("failed to read magic bytes (%s)", filepath);
        stream_free(s); // closes underlying file
        return false;
    }

    // read file format
    uint32_t fileFormatVersion = 0;
    if (stream_read_uint32(s, &fileFormatVersion) == false) {
        cclog_error("failed to read file format version (%s)", filepath);
        stream_free(s); // closes underlying file
        return false;
    }

    bool success = false;

    switch (fileFormatVersion) {
        case 5:
            success = serialization_v5_get_preview_data(s, imageData, size);
            break;
        case 6:
            // cclog_info("get preview data v6 for file : %s", filepath);
            success = serialization_v6_get_preview_data(s, imageData, size);
            break;
        default:
            cclog_error("file format version not supported (%s)", filepath);
            break;
    }

    stream_free(s); // closes underlying file
    return success;
}

// --------------------------------------------------
// MARK: - Memory buffer writing -
// --------------------------------------------------

void serialization_utils_writeCString(void *dest,
                                      const char *src,
                                      const size_t n,
                                      uint32_t *cursor) {
    RETURN_IF_NULL(dest);
    RETURN_IF_NULL(src);
    memcpy(dest, src, n);
    if (cursor != NULL) {
        *cursor += (uint32_t)n;
    }
    return;
}

void serialization_utils_writeUint8(void *dest, const uint8_t src, uint32_t *cursor) {
    RETURN_IF_NULL(dest);
    memcpy(dest, (const void *)(&src), sizeof(uint8_t));
    if (cursor != NULL) {
        *cursor += sizeof(uint8_t);
    }
}

void serialization_utils_writeUint16(void *dest, const uint16_t src, uint32_t *cursor) {
    RETURN_IF_NULL(dest);
    memcpy(dest, (const void *)(&src), sizeof(uint16_t));
    if (cursor != NULL) {
        *cursor += sizeof(uint16_t);
    }
}

void serialization_utils_writeUint32(void *dest, const uint32_t src, uint32_t *cursor) {
    RETURN_IF_NULL(dest);
    memcpy(dest, (const void *)(&src), sizeof(uint32_t));
    if (cursor != NULL) {
        *cursor += sizeof(uint32_t);
    }
}

// MARK: - Baked files -

bool serialization_save_baked_file(const Shape *s, uint64_t hash, FILE *fd) {
    if (shape_has_baked_lighting_data(s) == false) {
        return false;
    }

    // write baked file version
    uint32_t version = 1;
    if (fwrite(&version, sizeof(uint32_t), 1, fd) != 1) {
        cclog_error("baked file: failed to write version");
        return false;
    }

    // write palette hash
    if (fwrite(&hash, sizeof(uint64_t), 1, fd) != 1) {
        cclog_error("baked file: failed to write palette hash");
        return false;
    }

    // write lighting data uncompressed size
    int3 shape_size;
    shape_get_allocated_size(s, &shape_size);
    uint32_t size = (uint32_t)(shape_size.x * shape_size.y * shape_size.z) *
                    sizeof(VERTEX_LIGHT_STRUCT_T);
    if (fwrite(&size, sizeof(uint32_t), 1, fd) != 1) {
        cclog_error("baked file: failed to write lighting data uncompressed size");
        return false;
    }

    // compress lighting data
    uLong compressedSize = compressBound(size);
    const void *uncompressedData = shape_get_lighting_data(s);
    void *compressedData = malloc(compressedSize);
    if (compress(compressedData, &compressedSize, uncompressedData, size) != Z_OK) {
        cclog_error("baked file: failed to compress lighting data");
        free(compressedData);
        return false;
    }

    // write lighting data compressed size
    if (fwrite(&compressedSize, sizeof(uint32_t), 1, fd) != 1) {
        cclog_error("baked file: failed to write lighting data compressed size");
        free(compressedData);
        return false;
    }

    // write compressed lighting data
    if (fwrite(compressedData, compressedSize, 1, fd) != 1) {
        cclog_error("baked file: failed to write compressed lighting data");
        free(compressedData);
        return false;
    }

    free(compressedData);
    return true;
}

bool serialization_load_baked_file(Shape *s, uint64_t expectedHash, FILE *fd) {
    // read baked file version
    uint32_t version;
    if (fread(&version, sizeof(uint32_t), 1, fd) != 1) {
        cclog_error("baked file: failed to read version");
        return false;
    }

    switch (version) {
        case 1: {
            // read palette hash
            uint64_t hash;
            if (fread(&hash, sizeof(uint64_t), 1, fd) != 1) {
                cclog_error("baked file: failed to read palette hash");
                return false;
            }

            // match with shape's current palette hash
            if (hash != expectedHash) {
                cclog_info("baked file: mismatched palette hash, skip");
                return false;
            }

            // read lighting data uncompressed size
            uint32_t size;
            if (fread(&size, sizeof(uint32_t), 1, fd) != 1) {
                cclog_error("baked file: failed to read lighting data uncompressed size");
                return false;
            }

            // sanity check
            int3 shape_size;
            shape_get_allocated_size(s, &shape_size);
            uint32_t expectedSize = (uint32_t)(shape_size.x * shape_size.y * shape_size.z) *
                                    sizeof(VERTEX_LIGHT_STRUCT_T);
            if (size != expectedSize) {
                cclog_info("baked file: mismatched lighting data size, skip");
                return false;
            }

            // read lighting data compressed size
            uint32_t compressedSize;
            if (fread(&compressedSize, sizeof(uint32_t), 1, fd) != 1) {
                cclog_error("baked file: failed to read lighting data compressed size");
                return false;
            }

            // read compressed lighting data
            void *compressedData = malloc(compressedSize);
            if (fread(compressedData, compressedSize, 1, fd) != 1) {
                cclog_error("baked file: failed to read compressed lighting data");
                free(compressedData);
                return false;
            }

            // uncompress lighting data
            uLong resultSize = size;
            void *uncompressedData = malloc(size);

            if (uncompressedData == NULL) {
                // memory allocation failed
                cclog_error("baked file: failed to uncompress lighting data (memory alloc)");
                free(compressedData);
                return false;
            }

            if (uncompress(uncompressedData, &resultSize, compressedData, compressedSize) != Z_OK) {
                cclog_error("baked file: failed to uncompress lighting data");
                free(uncompressedData);
                free(compressedData);
                return false;
            }
            free(compressedData);
            compressedData = NULL;

            // sanity check
            if (resultSize != size) {
                cclog_info("baked file: mismatched lighting data uncompressed size, skip");
                free(uncompressedData);
                return false;
            }

            shape_set_lighting_data(s, uncompressedData);

            return true;
        }
        default: {
            cclog_error("baked file: unsupported version");
            return false;
        }
    }
}
