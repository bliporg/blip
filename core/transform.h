// -------------------------------------------------------------
//  Cubzh Core
//  transform.c
//  Created by Arthur Cormerais on January 27, 2021.
// -------------------------------------------------------------

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include "doubly_linked_list.h"
#include "float3.h"
#include "float4.h"
#include "matrix4x4.h"
#include "quaternion.h"
#include "rigidBody.h"
#include "shape.h"
#include "weakptr.h"

typedef struct _Transform Transform;
typedef struct _Scene Scene;
typedef struct _RigidBody RigidBody;

/// Select the computing mode for transforms utils euler functions (transform_utils_*)
/// Note: internal & other functions rotations always use quaternions regardless of this mode
/// 0: add euler angles (fastest, but need to manually clamp [0:2PI])
/// 1: combine rotation matrices (accurate, no lock)
/// 2: combine quaternions (safest & most accurate)
#define TRANSFORM_ROTATION_HELPERS_MODE 2
/// Select the computing mode for axis-aligned boxes,
/// 0: use lossy scale & ignore rotation, this is very cheap but causes important issues when
/// lossy scale is skewed by rotation
/// 1: use fully transformed world box, then inverse rotation ; use (0) if no rotation
/// more expensive but the aabox is pivot-proof
/// 2: transform box as if there was no rotation along the hierarchy ; use (0) if no rotation
/// cheaper than (1), but rotation along non-center pivots will result in an offseted box from model
/// 3: use fully transformed world box, then select new box min/max ; use (0) if no rotation
/// most expensive method but this returns the real world-aligned box
#define TRANSFORM_AABOX_AABB_MODE 3
#define TRANSFORM_AABOX_STATIC_COLLIDER_MODE 3
#define TRANSFORM_AABOX_DYNAMIC_COLLIDER_MODE 1

#if DEBUG
#define DEBUG_TRANSFORM false
#else
#define DEBUG_TRANSFORM false
#endif
#if DEBUG_TRANSFORM
/// Count transform_refresh calls
#define DEBUG_TRANSFORM_REFRESH_CALLS true
#else
#define DEBUG_TRANSFORM_REFRESH_CALLS false
#endif

typedef enum {
    /// default type, only contributes to the transformations down the hierarchy
    /// /!\ only used by internal objects
    HierarchyTransform,
    /// a point in space, optional ptr to rigidbody
    PointTransform,
    /// scene primitives, ptr to their respective type
    ShapeTransform,
    QuadTransform,
    CameraTransform,
    LightTransform,
    WorldTextTransform,
    AudioSourceTransform,
    AudioListenerTransform,
    MeshTransform
} TransformType;

typedef bool (*pointer_transform_recurse_func)(Transform *t, void *ptr);
typedef bool (*pointer_transform_recurse_depth_func)(Transform *t, void *ptr, uint32_t depth);
typedef void (*pointer_transform_destroyed_func)(const uint16_t id, void *managed);
typedef Transform **Transform_Array;

/// MARK: - Lifecycle -
Transform *transform_new(TransformType type);
Transform *transform_new_with_ptr(TransformType type, void *ptr, pointer_free_function ptrFreeFn);
void transform_init_ID_thread_safety(void);
uint16_t transform_get_id(const Transform *t);
/// Increases ref count and returns false if the retain count can't be increased
bool transform_retain(Transform *const t);
uint16_t transform_retain_count(const Transform *const t);
/// Releases the transform and frees it if ref count goes to 0.
/// Returns true if the Transform has been freed, false otherwise.
bool transform_release(Transform *t);
void transform_flush(Transform *t);
Weakptr *transform_get_weakptr(Transform *t);
Weakptr *transform_get_and_retain_weakptr(Transform *t);
bool transform_is_hierarchy_dirty(Transform *t);
void transform_refresh(Transform *t, bool hierarchyDirty, bool refreshParents);
void transform_set_children_dirty(Transform *t);
void transform_reset_children_dirty(Transform *t);
void transform_reset_any_dirty(Transform *t);
/// set, but not reset by transform, can be used internally by higher types as custom flag
bool transform_is_any_dirty(Transform *t);
void transform_set_destroy_callback(pointer_transform_destroyed_func f);
void transform_set_managed_ptr(Transform *t, Weakptr *wptr);
void transform_unset_managed_ptr(Transform *t);
bool transform_is_managed(Transform *t);

/// MARK: - Physics -
void transform_set_physics_dirty(Transform *t);
void transform_reset_physics_dirty(Transform *t);
bool transform_is_physics_dirty(Transform *t);
bool transform_ensure_rigidbody(Transform *t,
                                uint8_t mode,
                                uint16_t groups,
                                uint16_t collidesWith,
                                RigidBody **out);
bool transform_ensure_rigidbody_copy(Transform *t, const Transform *other);
RigidBody *transform_get_rigidbody(Transform *const t);
RigidBody *transform_get_or_compute_world_aligned_collider(Transform *t,
                                                           Box *collider,
                                                           const bool refreshParents);

/// MARK: - Hierarchy -
bool transform_set_parent(Transform *const t, Transform *parent, bool keepWorld);
bool transform_remove_parent(Transform *t, bool keepWorld);
Transform *transform_get_parent(Transform *t);
bool transform_is_parented(Transform *t);
DoublyLinkedListNode *transform_get_children_iterator(Transform *t);
Transform_Array transform_get_children_copy(Transform *t, size_t *count);
size_t transform_get_children_count(Transform *t);
void *transform_get_ptr(Transform *const t);
TransformType transform_get_type(const Transform *t);
bool transform_recurse(Transform *t, pointer_transform_recurse_func f, void *ptr, bool deepFirst);
bool transform_recurse_depth(Transform *t, pointer_transform_recurse_depth_func f, void *ptr, bool deepFirst, uint32_t depth);
bool transform_is_hidden_branch(Transform *t);
void transform_set_hidden_branch(Transform *t, bool value);
bool transform_is_hidden_self(Transform *t);
void transform_set_hidden_self(Transform *t, bool value);
bool transform_is_hidden(Transform *t);
bool transform_is_removed_from_scene(Transform *t);
void transform_set_removed_from_scene(Transform *t, bool value);
const char *transform_get_name(const Transform *t);
void transform_set_name(Transform *t, const char *value);
void transform_set_locks(Transform *t, bool translation, bool rotation, bool scale);
void transform_get_locks(Transform *t, bool *translation, bool *rotation, bool *scale);

/// MARK: - Scale -
void transform_set_local_scale(Transform *t, const float x, const float y, const float z);
void transform_set_local_scale_vec(Transform *t, const float3 *scale);
const float3 *transform_get_local_scale(Transform *t);
void transform_get_lossy_scale(Transform *t, float3 *scale, const bool refreshParents);

/// MARK: - Position -
void transform_set_local_position(Transform *t, const float x, const float y, const float z);
void transform_set_local_position_vec(Transform *t, const float3 *pos);
void transform_set_position(Transform *t, const float x, const float y, const float z);
void transform_set_position_vec(Transform *t, const float3 *pos);
const float3 *transform_get_local_position(Transform *t, const bool refreshParents);
const float3 *transform_get_position(Transform *t, const bool refreshParents);

/// MARK: - Rotation -
void transform_set_local_rotation(Transform *t, Quaternion *q);
void transform_set_local_rotation_vec(Transform *t, const float4 *v);
void transform_set_local_rotation_euler(Transform *t, const float x, const float y, const float z);
void transform_set_local_rotation_euler_vec(Transform *t, const float3 *euler);
void transform_set_rotation(Transform *t, Quaternion *q);
void transform_set_rotation_vec(Transform *t, const float4 *v);
void transform_set_rotation_euler(Transform *t, const float x, const float y, const float z);
void transform_set_rotation_euler_vec(Transform *t, const float3 *euler);
Quaternion *transform_get_local_rotation(Transform *t);
void transform_get_local_rotation_euler(Transform *t, float3 *euler);
Quaternion *transform_get_rotation(Transform *t);
void transform_get_rotation_euler(Transform *t, float3 *euler);

/// MARK: - Unit vectors -
/// Unit vector getters are computed on demand, the rationale is that the majority of transforms in
/// a hierarchy will never use unit vectors and that it is redundant w/ storing rotation A simple
/// optimization tip would be to store the return value if a player/another object intends to use it
/// multiple times in a same frame Unit vector setters internally set rotation
void transform_get_forward(Transform *t, float3 *forward, const bool refreshParents);
void transform_get_right(Transform *t, float3 *right, const bool refreshParents);
void transform_get_up(Transform *t, float3 *up, const bool refreshParents);
void transform_set_forward(Transform *t, const float x, const float y, const float z);
void transform_set_right(Transform *t, const float x, const float y, const float z);
void transform_set_up(Transform *const t, const float x, const float y, const float z);
void transform_set_forward_vec(Transform *t, const float3 *forward);
void transform_set_right_vec(Transform *t, const float3 *right);
void transform_set_up_vec(Transform *const t, const float3 *const up);

/// MARK: - Matrices -
const Matrix4x4 *transform_get_ltw(Transform *t);
const Matrix4x4 *transform_get_wtl(Transform *t);
const Matrix4x4 *transform_get_mtx(Transform *t);

/// MARK: - Utils -
/// Utils function do not refresh matrices, so that the caller may decide whether or not it's
/// necessary. Typically, you may call a refresh if you are in an intra-frame computation context
/// (eg. Lua functions)
void transform_utils_compute_SRT(Matrix4x4 *mtx, const float3 *s, Quaternion *r, const float3 *t);
void transform_utils_position_ltw(Transform *t, const float3 *pos, float3 *result);
void transform_utils_position_wtl(Transform *t, const float3 *pos, float3 *result);
void transform_utils_vector_ltw(Transform *t, const float3 *pos, float3 *result);
void transform_utils_vector_wtl(Transform *t, const float3 *pos, float3 *result);
void transform_utils_rotation_ltw(Transform *t, Quaternion *q, Quaternion *result);
void transform_utils_rotation_euler_ltw(Transform *t, const float3 *rot, float3 *result);
void transform_utils_rotation_wtl(Transform *t, Quaternion *q, Quaternion *result);
void transform_utils_rotation_euler_wtl(Transform *t, const float3 *rot, float3 *result);
void transform_utils_rotate(Transform *t, Quaternion *q, Quaternion *result, bool isLocal);
void transform_utils_rotate_euler(Transform *t, const float3 *rot, float3 *result, bool isLocal);
void transform_utils_move_children(Transform *from, Transform *to, bool keepWorld);
void transform_utils_aabox_local_to_world(Transform *t,
                                          const Box *b,
                                          Box *aab,
                                          const float3 *offset,
                                          SquarifyType squarify,
                                          const bool refreshParents);
void transform_utils_aabox_local_to_static_collider(Transform *t,
                                                    const Box *b,
                                                    Box *aab,
                                                    const float3 *offset,
                                                    SquarifyType squarify,
                                                    const bool refreshParents);
void transform_utils_aabox_local_to_dynamic_collider(Transform *t,
                                                     const Box *b,
                                                     Box *aab,
                                                     const float3 *offset,
                                                     SquarifyType squarify,
                                                     const bool refreshParents);
Shape *transform_utils_get_shape(Transform *t);
void transform_utils_get_model_ltw(const Transform *t, Matrix4x4 *out);
void transform_utils_get_model_wtl(const Transform *t, Matrix4x4 *out);
void transform_utils_get_backward(Transform *t, float3 *backward, const bool refreshParents);
void transform_utils_get_left(Transform *t, float3 *left, const bool refreshParents);
void transform_utils_get_down(Transform *t, float3 *down, const bool refreshParents);
const float3 *transform_utils_get_velocity(Transform *t);
const float3 *transform_utils_get_motion(Transform *t);
const float3 *transform_utils_get_acceleration(Transform *t);
void transform_utils_box_fit_recurse(Transform *t,
                                     Matrix4x4 mtx,
                                     Box *inout_box,
                                     bool applyTransaction);
void transform_utils_set_mtx(Transform *t, const Matrix4x4 *mtx);
bool transform_utils_has_shadow(const Transform *t);

// MARK: - Misc. -
void transform_set_animations_enabled(Transform *const t, const bool enabled);
bool transform_is_animations_enabled(Transform *const t);
float transform_get_shadow_decal(Transform *t);
void transform_set_shadow_decal(Transform *t, float size);

void transform_recycle_id(const uint16_t id);

/// MARK: - Debug -
#if DEBUG_TRANSFORM
int debug_transform_get_refresh_calls(void);
void debug_transform_reset_refresh_calls(void);
#endif
void debug_transform_set_debug(Transform *const t, const bool enabled);

#ifdef __cplusplus
} // extern "C"
#endif
