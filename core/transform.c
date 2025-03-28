// -------------------------------------------------------------
//  Cubzh Core
//  transform.c
//  Created by Arthur Cormerais on January 27, 2021.
// -------------------------------------------------------------

#include "transform.h"

#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "cclog.h"
#include "config.h"
#include "filo_list_uint16.h"
#include "mutex.h"
#include "quad.h"
#include "scene.h"
#include "utils.h"
#include "mesh.h"

#define TRANSFORM_DIRTY_NONE 0
// local mtx, ltw & wtl matrices are dirty, and children down the hierarchy need refresh
#define TRANSFORM_DIRTY_MTX 1
#define TRANSFORM_DIRTY_LOCAL_POS 2
#define TRANSFORM_DIRTY_LOCAL_ROT 4
#define TRANSFORM_DIRTY_POS 8
#define TRANSFORM_DIRTY_ROT 16
// this transform is up-to-date, but children down the hierarchy need refresh
#define TRANSFORM_DIRTY_CHILDREN 32
// collider-relevant transformations (local AND world scale/pos) have been dirty since last
// end-of-frame
#define TRANSFORM_DIRTY_PHYSICS 64
// any transformation has been dirty since last end-of-frame, can be used internally by higher types
#define TRANSFORM_DIRTY_CACHE 128

#define TRANSFORM_FLAG_NONE 0
// flag used by the scene to keep track of removed transforms at end-of-frame
#define TRANSFORM_FLAG_SCENE 1
// skip rendering for the whole branch or self only
#define TRANSFORM_FLAG_HIDDEN_BRANCH 2
#define TRANSFORM_FLAG_HIDDEN_SELF 4
// lua flag TODO: remove this, currently only used by Item Editor (not documented)
#define TRANSFORM_FLAG_ANIMATIONS 8
// helper to debug a specific transform
#define TRANSFORM_FLAG_DEBUG 16
// mask allowing to block inheritance of select transform from parent
#define TRANSFORM_FLAG_LOCK_T 32
#define TRANSFORM_FLAG_LOCK_R 64
#define TRANSFORM_FLAG_LOCK_S 128

#if DEBUG_TRANSFORM
static int debug_transform_refresh_calls = 0;
#endif

struct _Transform {

    // local-to-world and world-to-local matrices for the children of this Transform
    // changing any transformation will flag these matrices dirty
    Matrix4x4 *ltw;
    Matrix4x4 *wtl;
    Matrix4x4 *mtx;

    // transforms hierarchy
    Transform *parent; // self is retained for hierarchy ref count when parent is set
    size_t childrenCount;
    DoublyLinkedList *children; // here for recursion down hierarchy & for helpers

    // defined if the transform is part of the physics simulation
    RigidBody *rigidBody;

    // optionally attach a pointer to this transform (eg. to a Shape)
    void *ptr;

    // optional, name in the world, not unique
    char *name;

    // function pointer, to free ptr when defined
    pointer_free_function ptr_free;

    // optionally create a weak ptr for this transform
    Weakptr *wptr;

    // if managed, transform_destroyed_callback is called w/ this ptr as parameter
    void *managed;

    // SET any LOCAL or WORLD transformation will flag as dirty its counterpart & the matrices, and
    // unflag itself
    Quaternion *localRotation;
    Quaternion *rotation;
    float3 localPosition;
    float3 position;
    float3 localScale; /* + 4 bytes here */

    // optionally set a type to this transform
    TransformType type; /* 4 bytes */

    float shadowDecalSize; /* 4 bytes */

    // Transforms are managed with reference counting.
    uint16_t refCount; /* 2 bytes */

    uint16_t id; /* 2 bytes */

    // dirty flag per transformation type, use the TRANSFORM_* defines
    // GET a dirty transformation will refresh what is necessary to compute it
    uint8_t dirty; /* 1 byte */

    uint8_t flags; /* 1 byte */

    char pad[6];
};

static Mutex *_IDMutex = NULL;
static uint16_t _nextID = 1;
static FiloListUInt16 *_availableIDs = NULL;

static pointer_transform_destroyed_func transform_destroyed_callback = NULL;

// MARK: - Private functions' prototypes -

static uint16_t _transform_get_valid_id(void);
static void _transform_recycle_id(const uint16_t id);
static void _transform_set_dirty(Transform *const t, const uint8_t flag, bool keepCache);
static void _transform_reset_dirty(Transform *const t, const uint8_t flag);
static bool _transform_get_dirty(Transform *const t, const uint8_t flag);
static void _transform_toggle_flag(Transform *const t, const uint8_t flag, const bool toggle);
static bool _transform_get_flag(Transform *const t, const uint8_t flag);
static bool _transform_check_and_refresh_parents(Transform *const t);
static void _transform_refresh_local_position(Transform *t);
static void _transform_refresh_position(Transform *t);
static void _transform_refresh_local_rotation(Transform *t);
static void _transform_refresh_rotation(Transform *t);
static void _transform_refresh_matrices(Transform *t, bool hierarchyDirty);
static bool _transform_vec_equals(const float3 *f,
                                  const float x,
                                  const float y,
                                  const float z,
                                  const float epsilon);
static void _transform_set_all_dirty(Transform *t, bool keepWorld);
static void _transform_unit_to_rotation(const float3 *right,
                                        const float3 *up,
                                        const float3 *forward,
                                        Quaternion *q);
static bool _transform_remove_parent(Transform *t, const bool keepWorld, const bool reciprocal);
static void _transform_remove_from_hierarchy(Transform *t, const bool keepWorld);
static void _transform_utils_box_to_aabox_lossy(Transform *t,
                                                const Box *b,
                                                Box *aab,
                                                const float3 *offset,
                                                SquarifyType squarify);
static void _transform_utils_box_to_aabox_inverse_rot(Transform *t,
                                                      const Box *b,
                                                      Box *aab,
                                                      const float3 *offset,
                                                      SquarifyType squarify);
static void _transform_utils_box_to_aabox_ignore_rot(Transform *t,
                                                     const Box *b,
                                                     Box *aab,
                                                     const float3 *offset,
                                                     SquarifyType squarify);
static void _transform_utils_box_to_aabox_full(Transform *t,
                                               const Box *b,
                                               Box *aab,
                                               const float3 *offset,
                                               SquarifyType squarify);
static void _transform_free(Transform *const t);

// MARK: - Lifecycle -

Transform *transform_new(TransformType type) {
    Transform *t = (Transform *)malloc(sizeof(Transform));
    if (t == NULL) {
        return NULL;
    }

    t->id = _transform_get_valid_id();
    t->refCount = 1;
    t->ltw = matrix4x4_new_identity();
    t->wtl = matrix4x4_new_identity();
    t->mtx = matrix4x4_new_identity();
    t->localRotation = quaternion_new_identity();
    t->rotation = quaternion_new_identity();
    float3_set_zero(&t->localPosition);
    float3_set_zero(&t->position);
    float3_set_one(&t->localScale);
    t->parent = NULL;
    t->childrenCount = 0;
    t->children = doubly_linked_list_new();
    t->dirty = TRANSFORM_DIRTY_NONE;
    t->flags = TRANSFORM_FLAG_ANIMATIONS;
    t->ptr = NULL;
    t->ptr_free = NULL;
    t->wptr = NULL;
    t->managed = NULL;
    t->type = type;
    t->rigidBody = NULL;
    t->name = NULL;
    t->shadowDecalSize = 0;

    return t;
}

Transform *transform_new_with_ptr(TransformType type, void *ptr, pointer_free_function ptrFreeFn) {
    Transform *t = transform_new(type);
    t->ptr = ptr;
    t->ptr_free = ptrFreeFn;
    return t;
}

void transform_init_ID_thread_safety(void) {
    if (_IDMutex != NULL) {
        cclog_error("transform: thread safety initialized more than once");
        return;
    }
    _IDMutex = mutex_new();
    if (_IDMutex == NULL) {
        cclog_error("transform: failed to init thread safety");
    }
}

uint16_t transform_get_id(const Transform *t) {
    return t->id;
}

bool transform_retain(Transform *const t) {
    if (t->refCount < UINT16_MAX) {
        ++(t->refCount);
        return true;
    }
    cclog_error("Transform: maximum refCount reached!");
    return false;
}

uint16_t transform_retain_count(const Transform *const t) {
    return t->refCount;
}

bool transform_release(Transform *t) {
    if (--(t->refCount) == 0) {
        _transform_free(t);
        return true;
    }
    return false;
}

void transform_flush(Transform *t) {
    matrix4x4_set_scale(t->ltw, 1.0f);
    matrix4x4_set_scale(t->wtl, 1.0f);
    matrix4x4_set_scale(t->mtx, 1.0f);
    quaternion_set_identity(t->localRotation);
    quaternion_set_identity(t->rotation);
    float3_set_zero(&t->localPosition);
    float3_set_zero(&t->position);
    float3_set_one(&t->localScale);
    _transform_remove_from_hierarchy(t, true);
    t->shadowDecalSize = 0;
    t->dirty = 0;
    // note: keep t->ptr
}

Weakptr *transform_get_weakptr(Transform *t) {
    if (t->wptr == NULL) {
        t->wptr = weakptr_new(t);
    }
    return t->wptr;
}

Weakptr *transform_get_and_retain_weakptr(Transform *t) {
    if (t->wptr == NULL) {
        t->wptr = weakptr_new(t);
    }
    if (weakptr_retain(t->wptr)) {
        return t->wptr;
    } else { // this can only happen if weakptr ref count is at max
        return NULL;
    }
}

bool transform_is_hierarchy_dirty(Transform *t) {
    return _transform_get_dirty(t, TRANSFORM_DIRTY_MTX | TRANSFORM_DIRTY_CHILDREN);
}

void transform_refresh(Transform *t, bool hierarchyDirty, bool refreshParents) {
    // will refresh all parents transforms from root down to this transform
    // note: this may be used for
    // - debugging
    // - transforms that are not part of scene hierarchy
    // - intra-frame calculations involving matrices
    if (refreshParents) {
        hierarchyDirty = _transform_check_and_refresh_parents(t) || hierarchyDirty;
    }

    // refresh local position/rotation if they were dirty
    _transform_refresh_local_position(t);
    _transform_refresh_local_rotation(t);

    // refresh local transformation matrix, then ltw/wtl & world position/rotation when necessary
    _transform_refresh_matrices(t, hierarchyDirty);
}

void transform_set_children_dirty(Transform *t) {
    _transform_set_dirty(t, TRANSFORM_DIRTY_CHILDREN, false);
}

void transform_reset_children_dirty(Transform *t) {
    _transform_reset_dirty(t, TRANSFORM_DIRTY_CHILDREN);
}

void transform_reset_any_dirty(Transform *t) {
    _transform_reset_dirty(t, TRANSFORM_DIRTY_CACHE);
}

bool transform_is_any_dirty(Transform *t) {
    return _transform_get_dirty(t, TRANSFORM_DIRTY_CACHE);
}

void transform_set_destroy_callback(pointer_transform_destroyed_func f) {
    transform_destroyed_callback = f;
}

void transform_set_managed_ptr(Transform *t, Weakptr *wptr) {
    weakptr_retain(wptr);
    t->managed = wptr;
}

void transform_unset_managed_ptr(Transform *t) {
    if (t->managed) {
        weakptr_release(t->managed);
        t->managed = NULL;
    }
}

bool transform_is_managed(Transform *t) {
    return t->managed != NULL;
}

// MARK: - Physics -

void transform_set_physics_dirty(Transform *t) {
    _transform_set_dirty(t, TRANSFORM_DIRTY_PHYSICS, false);
}

void transform_reset_physics_dirty(Transform *t) {
    _transform_reset_dirty(t, TRANSFORM_DIRTY_PHYSICS);
}

bool transform_is_physics_dirty(Transform *t) {
    return _transform_get_dirty(t, TRANSFORM_DIRTY_PHYSICS);
}

bool transform_ensure_rigidbody(Transform *t,
                                uint8_t mode,
                                uint16_t groups,
                                uint16_t collidesWith,
                                RigidBody **out) {
    bool isNew = false;
    if (t->rigidBody == NULL) {
        t->rigidBody = rigidbody_new(mode, groups, collidesWith);
        isNew = true;
    } else {
        rigidbody_set_simulation_mode(t->rigidBody, mode);
        rigidbody_set_groups(t->rigidBody, groups);
        rigidbody_set_collides_with(t->rigidBody, collidesWith);
    }
    if (out != NULL) {
        *out = t->rigidBody;
    }
    return isNew;
}

bool transform_ensure_rigidbody_copy(Transform *t, const Transform *other) {
    if (other->rigidBody == NULL) {
        return false;
    }

    if (t->rigidBody == NULL) {
        t->rigidBody = rigidbody_new_copy(other->rigidBody);
    } else {
        rigidbody_set_collider(t->rigidBody, rigidbody_get_collider(other->rigidBody), false);
        rigidbody_set_constant_acceleration(t->rigidBody,
                                            rigidbody_get_constant_acceleration(other->rigidBody));
        rigidbody_set_mass(t->rigidBody, rigidbody_get_mass(other->rigidBody));
        rigidbody_set_groups(t->rigidBody, rigidbody_get_groups(other->rigidBody));
        rigidbody_set_collides_with(t->rigidBody, rigidbody_get_collides_with(other->rigidBody));
        for (FACE_INDEX_INT_T i = 0; i < FACE_COUNT; ++i) {
            rigidbody_set_friction(t->rigidBody, i, rigidbody_get_friction(other->rigidBody, i));
            rigidbody_set_bounciness(t->rigidBody,
                                     i,
                                     rigidbody_get_bounciness(other->rigidBody, i));
        }
        rigidbody_set_simulation_mode(t->rigidBody,
                                      rigidbody_get_simulation_mode(other->rigidBody));
    }
    return true;
}

RigidBody *transform_get_rigidbody(Transform *const t) {
    return t->rigidBody;
}

RigidBody *transform_get_or_compute_world_aligned_collider(Transform *t,
                                                           Box *collider,
                                                           const bool refreshParents) {
    if (collider != NULL) {
        *collider = box_zero;
    }

    const TransformType type = transform_get_type(t);
    if (type == HierarchyTransform) {
        return NULL;
    }

    RigidBody *rb = transform_get_rigidbody(t);
    if (rb != NULL && collider != NULL && rigidbody_is_enabled(rb)) {
        // we can use collider cached in rtree leaf whenever possible, otherwise compute it
        if (_transform_get_dirty(t, TRANSFORM_DIRTY_PHYSICS) || rigidbody_get_collider_dirty(rb) ||
            rigidbody_get_rtree_leaf(rb) == NULL) {

            if (type == ShapeTransform) {
                shape_compute_world_collider((Shape *)transform_get_ptr(t), collider, refreshParents);
            } else {
                float3 offset = float3_zero;

                if (type == QuadTransform) {
                    const Quad *q = (Quad *)transform_get_ptr(t);
                    offset.x = -quad_get_anchor_x(q) * quad_get_width(q);
                    offset.y = -quad_get_anchor_y(q) * quad_get_height(q);
                } else if (type == MeshTransform) {
                    const float3 pivot = mesh_get_pivot((Mesh *)transform_get_ptr(t));
                    offset = (float3){ -pivot.x, -pivot.y, -pivot.z };
                }

                if (rigidbody_is_dynamic(rb)) {
                    transform_utils_aabox_local_to_dynamic_collider(
                        t,
                        rigidbody_get_collider(rb),
                        collider,
                        &offset,
                        PHYSICS_SQUARIFY_DYNAMIC_COLLIDER ? MinSquarify : NoSquarify,
                        refreshParents);
                } else {
                    transform_utils_aabox_local_to_static_collider(t,
                                                                   rigidbody_get_collider(rb),
                                                                   collider,
                                                                   &offset,
                                                                   NoSquarify,
                                                                   refreshParents);
                }
            }
        } else {
            box_copy(collider, rtree_node_get_aabb(rigidbody_get_rtree_leaf(rb)));
        }
    }

    return rb;
}

// MARK: - Hierarchy -

bool transform_set_parent(Transform *t, Transform *parent, bool keepWorld) {

    // can't set parent on itself
    if (t == parent) {
        return false;
    }

    // parent is already set
    if (t->parent == parent) {
        return true;
    }

    if (parent == NULL) {
        transform_remove_parent(t, keepWorld);
        return true;
    }

    _transform_set_all_dirty(t, keepWorld);

    // replacing parent, no need to release & retain again in hierarchy
    if (t->parent != NULL) {
        _transform_remove_parent(t, keepWorld, true);
    }
    // t has a parent for the 1st time, retain in hierarchy
    else if (transform_retain(t) == false) {
        return false;
    }

    t->parent = parent;
    doubly_linked_list_push_last(parent->children, t);
    parent->childrenCount++;
    return true;
}

bool transform_remove_parent(Transform *t, bool keepWorld) {
    if (_transform_remove_parent(t, keepWorld, true)) {
        transform_release(t);
        return true;
    }
    return false;
}

Transform *transform_get_parent(Transform *t) {
    return t->parent;
}

bool transform_is_parented(Transform *t) {
    return t->parent != NULL;
}

DoublyLinkedListNode *transform_get_children_iterator(Transform *t) {
    if (t->children == NULL)
        return NULL;
    return doubly_linked_list_first(t->children);
}

Transform_Array transform_get_children_copy(Transform *t, size_t *count) {
    if (count == NULL)
        return NULL;

    if (t->childrenCount == 0) {
        *count = 0;
        return NULL;
    }

    const size_t byteCount = t->childrenCount * sizeof(Transform *);
    Transform_Array children = (Transform_Array)malloc(byteCount);
    if (children == NULL) {
        *count = 0;
        return NULL;
    }

    DoublyLinkedListNode *n = doubly_linked_list_first(t->children);
    for (size_t i = 0; i < t->childrenCount; ++i) {
        vx_assert(n != NULL); // cannot happen (for code analyzer)
        children[i] = (Transform *)doubly_linked_list_node_pointer(n);
        n = doubly_linked_list_node_next(n);
    }

    *count = t->childrenCount;
    return children;
}

size_t transform_get_children_count(Transform *t) {
    return t->childrenCount;
}

void *transform_get_ptr(Transform *const t) {
    return t->ptr;
}

TransformType transform_get_type(const Transform *t) {
    return t->type;
}

bool transform_recurse(Transform *t, pointer_transform_recurse_func f, void *ptr, bool deepFirst) {
    DoublyLinkedListNode *n = transform_get_children_iterator(t);
    Transform *child = NULL;
    while (n != NULL) {
        child = (Transform *)doubly_linked_list_node_pointer(n);
        if (deepFirst) {
            if (transform_recurse(child, f, ptr, deepFirst) || f(child, ptr))
                return true;
        } else {
            if (f(child, ptr) || transform_recurse(child, f, ptr, deepFirst))
                return true;
        }
        n = doubly_linked_list_node_next(n);
    }
    return false;
}

bool transform_recurse_depth(Transform *t, pointer_transform_recurse_depth_func f, void *ptr, bool deepFirst, uint32_t depth) {
    DoublyLinkedListNode *n = transform_get_children_iterator(t);
    Transform *child = NULL;
    while (n != NULL) {
        child = (Transform *)doubly_linked_list_node_pointer(n);
        if (deepFirst) {
            if (transform_recurse_depth(child, f, ptr, deepFirst, depth + 1) || f(child, ptr, depth + 1))
                return true;
        } else {
            if (f(child, ptr, depth + 1) || transform_recurse_depth(child, f, ptr, deepFirst, depth + 1))
                return true;
        }
        n = doubly_linked_list_node_next(n);
    }
    return false;
}

bool transform_is_hidden_branch(Transform *t) {
    return _transform_get_flag(t, TRANSFORM_FLAG_HIDDEN_BRANCH);
}

void transform_set_hidden_branch(Transform *t, bool value) {
    _transform_toggle_flag(t, TRANSFORM_FLAG_HIDDEN_BRANCH, value);
}

bool transform_is_hidden_self(Transform *t) {
    return _transform_get_flag(t, TRANSFORM_FLAG_HIDDEN_SELF);
}

void transform_set_hidden_self(Transform *t, bool value) {
    _transform_toggle_flag(t, TRANSFORM_FLAG_HIDDEN_SELF, value);
}

bool transform_is_hidden(Transform *t) {
    return _transform_get_flag(t, TRANSFORM_FLAG_HIDDEN_BRANCH | TRANSFORM_FLAG_HIDDEN_SELF);
}

bool transform_is_removed_from_scene(Transform *t) {
    return _transform_get_flag(t, TRANSFORM_FLAG_SCENE);
}

void transform_set_removed_from_scene(Transform *t, bool value) {
    _transform_toggle_flag(t, TRANSFORM_FLAG_SCENE, value);
}

const char *transform_get_name(const Transform *t) {
    return t->name;
}

void transform_set_name(Transform *t, const char *name) {
    if (t->name != NULL) {
        free(t->name);
    }
    t->name = string_new_copy(name);
}

void transform_set_locks(Transform *t, bool translation, bool rotation, bool scale) {
    const bool setTranslation = _transform_get_flag(t, TRANSFORM_FLAG_LOCK_T) != translation;
    const bool setRotation = _transform_get_flag(t, TRANSFORM_FLAG_LOCK_R) != rotation;
    const bool setScale = _transform_get_flag(t, TRANSFORM_FLAG_LOCK_S) != scale;

    if (setTranslation || setRotation) {
        _transform_check_and_refresh_parents(t);
    }
    if (setTranslation) {
        _transform_refresh_local_position(t);
        _transform_set_dirty(t, TRANSFORM_DIRTY_POS | TRANSFORM_DIRTY_MTX, false);
        _transform_toggle_flag(t, TRANSFORM_FLAG_LOCK_T, translation);
    }
    if (setRotation) {
        _transform_refresh_local_rotation(t);
        _transform_set_dirty(t, TRANSFORM_DIRTY_ROT | TRANSFORM_DIRTY_MTX, false);
        _transform_toggle_flag(t, TRANSFORM_FLAG_LOCK_R, rotation);
    }
    if (setScale) {
        _transform_set_dirty(t, TRANSFORM_DIRTY_MTX, false);
        _transform_toggle_flag(t, TRANSFORM_FLAG_LOCK_S, scale);
    }
}

void transform_get_locks(Transform *t, bool *translation, bool *rotation, bool *scale) {
    if (translation != NULL) {
        *translation = _transform_get_flag(t, TRANSFORM_FLAG_LOCK_T);
    }
    if (rotation != NULL) {
        *rotation = _transform_get_flag(t, TRANSFORM_FLAG_LOCK_R);
    }
    if (scale != NULL) {
        *scale = _transform_get_flag(t, TRANSFORM_FLAG_LOCK_S);
    }
}

// MARK: - Scale -

void transform_set_local_scale(Transform *t, const float x, const float y, const float z) {
    if (_transform_vec_equals(&t->localScale, x, y, z, EPSILON_ZERO)) {
        return;
    }
    float3_set(&t->localScale, x, y, z);
    _transform_set_dirty(t, TRANSFORM_DIRTY_MTX | TRANSFORM_DIRTY_PHYSICS, false);
}

void transform_set_local_scale_vec(Transform *t, const float3 *scale) {
    transform_set_local_scale(t, scale->x, scale->y, scale->z);
}

const float3 *transform_get_local_scale(Transform *t) {
    return &t->localScale;
}

void transform_get_lossy_scale(Transform *t, float3 *scale, const bool refreshParents) {
    bool hierarchyDirty = false;
    if (refreshParents) {
        hierarchyDirty = _transform_check_and_refresh_parents(t);
    }
    _transform_refresh_matrices(t, hierarchyDirty);
    matrix4x4_get_scaleXYZ(t->ltw, scale);
}

// MARK: - Position -

void transform_set_local_position(Transform *t, const float x, const float y, const float z) {
    if (_transform_get_dirty(t, TRANSFORM_DIRTY_LOCAL_POS) ||
        _transform_vec_equals(&t->localPosition, x, y, z, EPSILON_ZERO) == false) {

        float3_set(&t->localPosition, x, y, z);
        _transform_set_dirty(t,
                             TRANSFORM_DIRTY_POS | TRANSFORM_DIRTY_MTX | TRANSFORM_DIRTY_PHYSICS,
                             false);
    } else {
        _transform_set_dirty(t, TRANSFORM_DIRTY_POS | TRANSFORM_DIRTY_MTX, true);
    }
    _transform_reset_dirty(t, TRANSFORM_DIRTY_LOCAL_POS);
}

void transform_set_local_position_vec(Transform *t, const float3 *pos) {
    transform_set_local_position(t, pos->x, pos->y, pos->z);
}

void transform_set_position(Transform *t, const float x, const float y, const float z) {
    if (_transform_get_dirty(t, TRANSFORM_DIRTY_POS) ||
        _transform_vec_equals(&t->position, x, y, z, EPSILON_ZERO) == false) {

        float3_set(&t->position, x, y, z);
        _transform_set_dirty(t,
                             TRANSFORM_DIRTY_LOCAL_POS | TRANSFORM_DIRTY_MTX |
                                 TRANSFORM_DIRTY_PHYSICS,
                             false);
    } else {
        _transform_set_dirty(t, TRANSFORM_DIRTY_LOCAL_POS | TRANSFORM_DIRTY_MTX, true);
    }
    _transform_reset_dirty(t, TRANSFORM_DIRTY_POS);
}

void transform_set_position_vec(Transform *t, const float3 *pos) {
    transform_set_position(t, pos->x, pos->y, pos->z);
}

const float3 *transform_get_local_position(Transform *t, const bool refreshParents) {
    if (refreshParents) {
        _transform_check_and_refresh_parents(t);
    }
    _transform_refresh_local_position(t);
    return &t->localPosition;
}

const float3 *transform_get_position(Transform *t, const bool refreshParents) {
    if (refreshParents) {
        _transform_check_and_refresh_parents(t);
    }
    _transform_refresh_position(t);
    return &t->position;
}

// MARK: - Rotation -

void transform_set_local_rotation(Transform *t, Quaternion *q) {
    if (_transform_get_dirty(t, TRANSFORM_DIRTY_LOCAL_ROT) ||
        quaternion_is_equal(t->localRotation, q, EPSILON_ZERO_TRANSFORM_RAD) == false) {

        quaternion_set(t->localRotation, q);
        _transform_set_dirty(t, TRANSFORM_DIRTY_ROT | TRANSFORM_DIRTY_MTX, false);
        if (rigidbody_is_rotation_dependent(t->rigidBody)) {
            _transform_set_dirty(t, TRANSFORM_DIRTY_PHYSICS, false);
        }
    } else {
        _transform_set_dirty(t, TRANSFORM_DIRTY_ROT | TRANSFORM_DIRTY_MTX, true);
    }
    _transform_reset_dirty(t, TRANSFORM_DIRTY_LOCAL_ROT);
}

void transform_set_local_rotation_vec(Transform *t, const float4 *v) {
    Quaternion q = {v->x, v->y, v->z, v->w, false};
    transform_set_local_rotation(t, &q);
}

void transform_set_local_rotation_euler(Transform *t, const float x, const float y, const float z) {
    Quaternion q;
    euler_to_quaternion(x, y, z, &q);
    transform_set_local_rotation(t, &q);
}

void transform_set_local_rotation_euler_vec(Transform *t, const float3 *euler) {
    transform_set_local_rotation_euler(t, euler->x, euler->y, euler->z);
}

void transform_set_rotation(Transform *t, Quaternion *q) {
    if (_transform_get_dirty(t, TRANSFORM_DIRTY_ROT) ||
        quaternion_is_equal(t->rotation, q, EPSILON_ZERO_TRANSFORM_RAD) == false) {

        quaternion_set(t->rotation, q);
        _transform_set_dirty(t, TRANSFORM_DIRTY_LOCAL_ROT | TRANSFORM_DIRTY_MTX, false);
        if (rigidbody_is_rotation_dependent(t->rigidBody)) {
            _transform_set_dirty(t, TRANSFORM_DIRTY_PHYSICS, false);
        }
    } else {
        _transform_set_dirty(t, TRANSFORM_DIRTY_LOCAL_ROT | TRANSFORM_DIRTY_MTX, true);
    }
    _transform_reset_dirty(t, TRANSFORM_DIRTY_ROT);
}

void transform_set_rotation_vec(Transform *t, const float4 *v) {
    Quaternion q = {v->x, v->y, v->z, v->w, false};
    transform_set_rotation(t, &q);
}

void transform_set_rotation_euler(Transform *t, const float x, const float y, const float z) {
    Quaternion q;
    euler_to_quaternion(x, y, z, &q);
    transform_set_rotation(t, &q);
}

void transform_set_rotation_euler_vec(Transform *t, const float3 *euler) {
    transform_set_rotation_euler(t, euler->x, euler->y, euler->z);
}

Quaternion *transform_get_local_rotation(Transform *t) {
    _transform_refresh_local_rotation(t);
    return t->localRotation;
}

void transform_get_local_rotation_euler(Transform *t, float3 *euler) {
    quaternion_to_euler(transform_get_local_rotation(t), euler);
}

Quaternion *transform_get_rotation(Transform *t) {
    _transform_refresh_rotation(t);
    return t->rotation;
}

void transform_get_rotation_euler(Transform *t, float3 *euler) {
    quaternion_to_euler(transform_get_rotation(t), euler);
}

// MARK: - Unit vectors -

void transform_get_forward(Transform *t, float3 *forward, const bool refreshParents) {
    transform_refresh(t, false, refreshParents); // refresh ltw for intra-frame calculations
    *forward = (float3){t->ltw->x3y1, t->ltw->x3y2, t->ltw->x3y3};
    float3_normalize(forward);
}

void transform_get_right(Transform *t, float3 *right, const bool refreshParents) {
    transform_refresh(t, false, refreshParents); // refresh ltw for intra-frame calculations
    *right = (float3){t->ltw->x1y1, t->ltw->x1y2, t->ltw->x1y3};
    float3_normalize(right);
}

void transform_get_up(Transform *t, float3 *up, const bool refreshParents) {
    transform_refresh(t, false, refreshParents); // refresh ltw for intra-frame calculations
    *up = (float3){t->ltw->x2y1, t->ltw->x2y2, t->ltw->x2y3};
    float3_normalize(up);
}

void transform_set_forward(Transform *t, const float x, const float y, const float z) {
    const float3 forward = {x, y, z};
    Quaternion q;

    float3 right = float3_up;
    float3_cross_product(&right, &forward);
    float3_normalize(&right);
    float3 up = forward;
    float3_cross_product(&up, &right);

    _transform_unit_to_rotation(&right, &up, &forward, &q);
    transform_set_rotation(t, &q);
}

void transform_set_right(Transform *t, const float x, const float y, const float z) {
    const float3 right = {x, y, z};
    Quaternion q;

    float3 forward = right;
    float3_cross_product(&forward, &float3_up);
    float3_normalize(&forward);
    float3 up = forward;
    float3_cross_product(&up, &right);

    _transform_unit_to_rotation(&right, &up, &forward, &q);
    transform_set_rotation(t, &q);
}

void transform_set_up(Transform *const t, const float x, const float y, const float z) {
    const float3 up = {x, y, z};
    Quaternion q;

    float3 forward = float3_right;
    float3_cross_product(&forward, &up);
    float3_normalize(&forward);
    float3 right = up;
    float3_cross_product(&right, &forward);

    _transform_unit_to_rotation(&right, &up, &forward, &q);
    transform_set_rotation(t, &q);
}

void transform_set_forward_vec(Transform *t, const float3 *forward) {
    transform_set_forward(t, forward->x, forward->y, forward->z);
}

void transform_set_right_vec(Transform *t, const float3 *right) {
    transform_set_right(t, right->x, right->y, right->z);
}

void transform_set_up_vec(Transform *const t, const float3 *const up) {
    transform_set_up(t, up->x, up->y, up->z);
}

// MARK: - Matrices -

const Matrix4x4 *transform_get_ltw(Transform *t) {
    return t->ltw;
}

const Matrix4x4 *transform_get_wtl(Transform *t) {
    return t->wtl;
}

const Matrix4x4 *transform_get_mtx(Transform *t) {
    return t->mtx;
}

/// MARK: - Utils -

void transform_utils_compute_SRT(Matrix4x4 *mtx,
                                 const float3 *s,
                                 Quaternion *r,
                                 const float3 *t) {
    quaternion_op_normalize(r);

    const float xx = r->y * r->y;
    const float xy = r->y * r->z;
    const float xz = r->y * r->x;
    const float xw = -r->y * r->w;

    const float yy = r->z * r->z;
    const float yz = r->z * r->x;
    const float yw = -r->z * r->w;

    const float zz = r->x * r->x;
    const float zw = -r->x * r->w;

    mtx->x1y1 = s->x * (1.0f - 2.0f * (yy + zz));
    mtx->x1y2 = s->x * (2.0f * (xy - zw));
    mtx->x1y3 = s->x * (2.0f * (xz + yw));
    mtx->x1y4 = 0.0f;

    mtx->x2y1 = s->y * (2.0f * (xy + zw));
    mtx->x2y2 = s->y * (1.0f - 2.0f * (xx + zz));
    mtx->x2y3 = s->y * (2.0f * (yz - xw));
    mtx->x2y4 = 0.0f;

    mtx->x3y1 = s->z * (2.0f * (xz - yw));
    mtx->x3y2 = s->z * (2.0f * (yz + xw));
    mtx->x3y3 = s->z * (1.0f - 2.0f * (xx + yy));
    mtx->x3y4 = 0.0f;

    mtx->x4y1 = t->x;
    mtx->x4y2 = t->y;
    mtx->x4y3 = t->z;
    mtx->x4y4 = 1.0f;
}

void transform_utils_position_ltw(Transform *t, const float3 *pos, float3 *result) {
    matrix4x4_op_multiply_vec_point(result, pos, t->ltw);
}

void transform_utils_position_wtl(Transform *t, const float3 *pos, float3 *result) {
    matrix4x4_op_multiply_vec_point(result, pos, t->wtl);
}

void transform_utils_vector_ltw(Transform *t, const float3 *pos, float3 *result) {
    matrix4x4_op_multiply_vec_vector(result, pos, t->ltw);
}

void transform_utils_vector_wtl(Transform *t, const float3 *pos, float3 *result) {
    matrix4x4_op_multiply_vec_vector(result, pos, t->wtl);
}

void transform_utils_rotation_ltw(Transform *t, Quaternion *q, Quaternion *result) {
    Quaternion *qltw = transform_get_rotation(t);
    *result = quaternion_op_mult(qltw, q);
}

void transform_utils_rotation_euler_ltw(Transform *t, const float3 *rot, float3 *result) {
#if TRANSFORM_ROTATION_HELPERS_MODE == 0
    transform_get_rotation_euler(t, result);
    float3_op_add(result, rot);
#elif TRANSFORM_ROTATION_HELPERS_MODE == 1
    Matrix4x4 *ltwRotMtx = matrix4x4_new_rotation(t->ltw);
    Matrix4x4 *rotMtx = matrix4x4_new_from_euler_zyx(rot->x, rot->y, rot->z);
    matrix4x4_op_multiply_2(ltwRotMtx, rotMtx);
    matrix4x4_get_euler(rotMtx, result);

    matrix4x4_free(rotMtx);
    matrix4x4_free(ltwRotMtx);
#elif TRANSFORM_ROTATION_HELPERS_MODE == 2
    Quaternion q;
    euler_to_quaternion_vec(rot, &q);
    transform_utils_rotation_ltw(t, &q, &q);
    quaternion_to_euler(&q, result);
#endif
}

void transform_utils_rotation_wtl(Transform *t, Quaternion *q, Quaternion *result) {
    Quaternion qwtl;
    quaternion_set(&qwtl, transform_get_rotation(t));
    quaternion_op_inverse(&qwtl);
    *result = quaternion_op_mult(&qwtl, q);
}

void transform_utils_rotation_euler_wtl(Transform *t, const float3 *rot, float3 *result) {
#if TRANSFORM_ROTATION_HELPERS_MODE == 0
    transform_get_rotation_euler(t, result);
    float3_op_substract(result, rot);
#elif TRANSFORM_ROTATION_HELPERS_MODE == 1
    Matrix4x4 *wtlRotMtx = matrix4x4_new_rotation(t->wtl);
    Matrix4x4 *rotMtx = matrix4x4_new_from_euler_zyx(rot->x, rot->y, rot->z);
    matrix4x4_op_multiply_2(wtlRotMtx, rotMtx);
    matrix4x4_get_euler(rotMtx, result);

    matrix4x4_free(rotMtx);
    matrix4x4_free(wtlRotMtx);
#elif TRANSFORM_ROTATION_HELPERS_MODE == 2
    Quaternion q;
    euler_to_quaternion_vec(rot, &q);
    transform_utils_rotation_wtl(t, &q, &q);
    quaternion_to_euler(&q, result);
#endif
}

void transform_utils_rotate(Transform *t, Quaternion *q, Quaternion *result, bool isLocal) {
    Quaternion *qt = isLocal ? transform_get_local_rotation(t) : transform_get_rotation(t);
    *result = quaternion_op_mult(q, qt);
}

void transform_utils_rotate_euler(Transform *t, const float3 *rot, float3 *result, bool isLocal) {
#if TRANSFORM_ROTATION_HELPERS_MODE == 0
    if (isLocal) {
        transform_get_local_rotation_euler(t, result);
    } else {
        transform_get_rotation_euler(t, result);
    }
    float3_op_add(result, rot);
#elif TRANSFORM_ROTATION_HELPERS_MODE == 1
    Matrix4x4 *baseMtx = isLocal ? matrix4x4_new_rotation(t->ltw) : matrix4x4_new_rotation(t->mtx);
    Matrix4x4 *rotMtx = matrix4x4_new_from_euler_zyx(rot->x, rot->y, rot->z);
    matrix4x4_op_multiply_2(baseMtx, rotMtx);
    matrix4x4_get_euler(rotMtx, result);

    matrix4x4_free(rotMtx);
    matrix4x4_free(baseMtx);
#elif TRANSFORM_ROTATION_HELPERS_MODE == 2
    Quaternion q;
    euler_to_quaternion_vec(rot, &q);
    transform_utils_rotate(t, &q, &q, isLocal);
    quaternion_to_euler(&q, result);
#endif
}

void transform_utils_move_children(Transform *from, Transform *to, bool keepWorld) {
    size_t count = 0;
    Transform_Array children = transform_get_children_copy(from, &count);
    if (children != NULL) {
        for (size_t i = 0; i < count; ++i) {
            if (transform_set_parent(children[i], to, keepWorld) == false) {
                cclog_error("transform_utils_move_children - parent can't be set");
            }
        }
        free(children);
    }
}

void transform_utils_aabox_local_to_world(Transform *t,
                                          const Box *b,
                                          Box *aab,
                                          const float3 *offset,
                                          SquarifyType squarify,
                                          const bool refreshParents) {

    transform_refresh(t, false, refreshParents); // refresh ltw for intra-frame calculations
#if TRANSFORM_AABOX_AABB_MODE == 0
    _transform_utils_box_to_aabox_lossy(t, b, aab, offset, squarify);
#elif TRANSFORM_AABOX_AABB_MODE == 1
    _transform_utils_box_to_aabox_inverse_rot(t, b, aab, offset, squarify);
#elif TRANSFORM_AABOX_AABB_MODE == 2
    _transform_utils_box_to_aabox_ignore_rot(t, b, aab, offset, squarify);
#elif TRANSFORM_AABOX_AABB_MODE == 3
    _transform_utils_box_to_aabox_full(t, b, aab, offset, squarify);
#endif
}

void transform_utils_aabox_local_to_static_collider(Transform *t,
                                                    const Box *b,
                                                    Box *aab,
                                                    const float3 *offset,
                                                    SquarifyType squarify,
                                                    const bool refreshParents) {

    transform_refresh(t, false, refreshParents); // refresh ltw for intra-frame calculations
#if TRANSFORM_AABOX_STATIC_COLLIDER_MODE == 0
    _transform_utils_box_to_aabox_lossy(t, b, aab, offset, squarify);
#elif TRANSFORM_AABOX_STATIC_COLLIDER_MODE == 1
    _transform_utils_box_to_aabox_inverse_rot(t, b, aab, offset, squarify);
#elif TRANSFORM_AABOX_STATIC_COLLIDER_MODE == 2
    _transform_utils_box_to_aabox_ignore_rot(t, b, aab, offset, squarify);
#elif TRANSFORM_AABOX_STATIC_COLLIDER_MODE == 3
    _transform_utils_box_to_aabox_full(t, b, aab, offset, squarify);
#endif
}

void transform_utils_aabox_local_to_dynamic_collider(Transform *t,
                                                     const Box *b,
                                                     Box *aab,
                                                     const float3 *offset,
                                                     SquarifyType squarify,
                                                     const bool refreshParents) {

    transform_refresh(t, false, refreshParents); // refresh ltw for intra-frame calculations
#if TRANSFORM_AABOX_DYNAMIC_COLLIDER_MODE == 0
    _transform_utils_box_to_aabox_lossy(t, b, aab, offset, squarify);
#elif TRANSFORM_AABOX_DYNAMIC_COLLIDER_MODE == 1
    _transform_utils_box_to_aabox_inverse_rot(t, b, aab, offset, squarify);
#elif TRANSFORM_AABOX_DYNAMIC_COLLIDER_MODE == 2
    _transform_utils_box_to_aabox_ignore_rot(t, b, aab, offset, squarify);
#elif TRANSFORM_AABOX_DYNAMIC_COLLIDER_MODE == 3
    _transform_utils_box_to_aabox_full(t, b, aab, offset, squarify);
#endif
}

Shape *transform_utils_get_shape(Transform *t) {
    if (t == NULL) {
        return NULL;
    }
    if (t->type != ShapeTransform) {
        return NULL;
    }
    return (Shape *)t->ptr;
}

void transform_utils_get_model_ltw(const Transform *t, Matrix4x4 *out) {
    *out = *t->ltw;

    const TransformType type = transform_get_type(t);

    if (type == ShapeTransform || type == MeshTransform) {
        const float3 pivot = type == ShapeTransform ? shape_get_pivot((Shape *)t->ptr) :
                             mesh_get_pivot((Mesh *)t->ptr);
        out->x4y1 -= t->ltw->x1y1 * pivot.x + t->ltw->x2y1 * pivot.y + t->ltw->x3y1 * pivot.z;
        out->x4y2 -= t->ltw->x1y2 * pivot.x + t->ltw->x2y2 * pivot.y + t->ltw->x3y2 * pivot.z;
        out->x4y3 -= t->ltw->x1y3 * pivot.x + t->ltw->x2y3 * pivot.y + t->ltw->x3y3 * pivot.z;
    } else if (type == QuadTransform) {
        const Quad *q = (Quad *)t->ptr;
        const float anchorX = quad_get_anchor_x(q) * quad_get_width(q);
        const float anchorY = quad_get_anchor_y(q) * quad_get_height(q);
        out->x4y1 -= t->ltw->x1y1 * anchorX + t->ltw->x2y1 * anchorY;
        out->x4y2 -= t->ltw->x1y2 * anchorX + t->ltw->x2y2 * anchorY;
        out->x4y3 -= t->ltw->x1y3 * anchorX + t->ltw->x2y3 * anchorY;
    }
}

void transform_utils_get_model_wtl(const Transform *t, Matrix4x4 *out) {
    *out = *t->wtl;

    const TransformType type = transform_get_type(t);

    if (type == ShapeTransform || type == MeshTransform) {
        const float3 pivot = type == ShapeTransform ? shape_get_pivot((Shape *)t->ptr) :
                             mesh_get_pivot((Mesh *)t->ptr);
        out->x4y1 += pivot.x;
        out->x4y2 += pivot.y;
        out->x4y3 += pivot.z;
    } else if (type == QuadTransform) {
        const Quad *q = (Quad *)t->ptr;
        out->x4y1 += quad_get_anchor_x(q) * quad_get_width(q);
        out->x4y2 += quad_get_anchor_y(q) * quad_get_height(q);
    }
}

void transform_utils_get_backward(Transform *t, float3 *backward, const bool refreshParents) {
    transform_get_forward(t, backward, refreshParents);
    backward->x *= -1;
    backward->y *= -1;
    backward->z *= -1;
}

void transform_utils_get_left(Transform *t, float3 *left, const bool refreshParents) {
    transform_get_right(t, left, refreshParents);
    left->x *= -1;
    left->y *= -1;
    left->z *= -1;
}

void transform_utils_get_down(Transform *t, float3 *down, const bool refreshParents) {
    transform_get_up(t, down, refreshParents);
    down->x *= -1;
    down->y *= -1;
    down->z *= -1;
}

const float3 *transform_utils_get_velocity(Transform *t) {
    if (t->rigidBody != NULL) {
        return rigidbody_get_velocity(t->rigidBody);
    } else {
        return NULL;
    }
}

const float3 *transform_utils_get_motion(Transform *t) {
    if (t->rigidBody != NULL) {
        return rigidbody_get_motion(t->rigidBody);
    } else {
        return NULL;
    }
}

const float3 *transform_utils_get_acceleration(Transform *t) {
    if (t->rigidBody != NULL) {
        return rigidbody_get_constant_acceleration(t->rigidBody);
    } else {
        return NULL;
    }
}

void transform_utils_box_fit_recurse(Transform *t,
                                     Matrix4x4 mtx,
                                     Box *inout_box,
                                     bool applyTransaction) {
    DoublyLinkedListNode *n = transform_get_children_iterator(t);
    Transform *child = NULL;
    while (n != NULL) {
        child = (Transform *)doubly_linked_list_node_pointer(n);

        const TransformType type = transform_get_type(child);

        if (type == ShapeTransform || type == MeshTransform) {

            transform_refresh(child, false, false); // refresh mtx for intra-frame calculations
            if (type == ShapeTransform && applyTransaction) {
                shape_apply_current_transaction((Shape *)child->ptr, true);
            }

            Matrix4x4 child_mtx = mtx;
            matrix4x4_op_multiply(&child_mtx, child->mtx);

            const Box model = type == ShapeTransform ? shape_get_model_aabb((Shape *)child->ptr) :
                              *mesh_get_model_aabb((Mesh *)child->ptr);
            const float3 offset = type == ShapeTransform ? shape_get_pivot((Shape *)child->ptr) :
                                  mesh_get_pivot((Mesh *)child->ptr);
            Box aabb;
            box_to_aabox2(&model, &aabb, &child_mtx, &offset, NoSquarify);

            if (box_is_empty(inout_box)) {
                box_copy(inout_box, &aabb);
            } else {
                box_op_merge(inout_box, &aabb, inout_box);
            }

            transform_utils_box_fit_recurse(child, child_mtx, inout_box, applyTransaction);
        }

        n = doubly_linked_list_node_next(n);
    }
}

void transform_utils_set_mtx(Transform *t, const Matrix4x4 *mtx) {
    transform_set_local_position(t, mtx->x4y1, mtx->x4y2, mtx->x4y3);

    Matrix4x4 rot; matrix4x4_get_rotation(mtx, &rot);
    Quaternion q; rotation_matrix_to_quaternion(&rot, &q);
    transform_set_local_rotation(t, &q);

    float3 scale; matrix4x4_get_scaleXYZ(mtx, &scale);
    transform_set_local_scale_vec(t, &scale);

    *t->mtx = *mtx;
    _transform_reset_dirty(t, TRANSFORM_DIRTY_MTX);
}

bool transform_utils_has_shadow(const Transform *t) {
    switch(t->type) {
        case ShapeTransform: return shape_has_shadow((Shape*)t->ptr);
        case QuadTransform: return quad_has_shadow((Quad*)t->ptr);
        case MeshTransform: return mesh_has_shadow((Mesh*)t->ptr);
        default: return false;
    }
}

// MARK: - Misc. -

void transform_set_animations_enabled(Transform *const t, const bool enabled) {
    if (t == NULL) {
        return;
    }
    _transform_toggle_flag(t, TRANSFORM_FLAG_ANIMATIONS, enabled);
}

bool transform_is_animations_enabled(Transform *const t) {
    if (t == NULL) {
        return false;
    }
    return _transform_get_flag(t, TRANSFORM_FLAG_ANIMATIONS);
}

float transform_get_shadow_decal(Transform *t) {
    return t->shadowDecalSize;
}

void transform_set_shadow_decal(Transform *t, float size) {
    t->shadowDecalSize = size;
}

void transform_recycle_id(const uint16_t id) {
    // NOTE: We could probably expose a version that doesn't use the mutex lock
    // for managers that recycle IDs while clearly accounting for thread context.
    _transform_recycle_id(id);
}

// MARK: - Private functions -

static uint16_t _transform_get_valid_id(void) {
    uint16_t resultId = 0;
    mutex_lock(_IDMutex);
    if (_availableIDs == NULL || filo_list_uint16_pop(_availableIDs, &resultId) == false) {
        resultId = _nextID;
        _nextID += 1;
    }
    mutex_unlock(_IDMutex);
    return resultId;
}

static void _transform_recycle_id(const uint16_t id) {
    mutex_lock(_IDMutex);
    if (_availableIDs == NULL) {
        _availableIDs = filo_list_uint16_new();
    }
    filo_list_uint16_push(_availableIDs, id);
    mutex_unlock(_IDMutex);
}

static void _transform_set_dirty(Transform *const t, const uint8_t flag, bool keepCache) {
#if DEBUG_TRANSFORM
    if (_transform_get_flag(t, TRANSFORM_FLAG_DEBUG)) {
        printf("---- BEGIN transform dirty flags\n");
        if ((flag & TRANSFORM_DIRTY_POS) > 0) {
            printf("-- _transform_set_dirty TRANSFORM_DIRTY_POS\n");
        }
        if ((flag & TRANSFORM_DIRTY_LOCAL_POS) > 0) {
            printf("-- _transform_set_dirty TRANSFORM_DIRTY_LOCAL_POS\n");
        }
        if ((flag & TRANSFORM_DIRTY_ROT) > 0) {
            printf("-- _transform_set_dirty TRANSFORM_DIRTY_ROT\n");
        }
        if ((flag & TRANSFORM_DIRTY_LOCAL_ROT) > 0) {
            printf("-- _transform_set_dirty TRANSFORM_DIRTY_LOCAL_ROT\n");
        }
        if ((flag & TRANSFORM_DIRTY_PHYSICS) > 0) {
            printf("-- _transform_set_dirty TRANSFORM_DIRTY_PHYSICS\n");
        }
        printf("---- END transform dirty flags\n");
    }
#endif
    if (keepCache) {
        t->dirty |= flag;
    } else {
        t->dirty |= (flag | TRANSFORM_DIRTY_CACHE);
    }
}

static void _transform_reset_dirty(Transform *const t, const uint8_t flag) {
    t->dirty &= ~flag;
}

static bool _transform_get_dirty(Transform *const t, const uint8_t flag) {
    return (t->dirty & flag) != 0;
}

static void _transform_toggle_flag(Transform *const t, const uint8_t flag, const bool toggle) {
    if (toggle) {
        t->flags |= flag;
    } else {
        t->flags &= ~flag;
    }
}

static bool _transform_get_flag(Transform *const t, const uint8_t flag) {
    return (t->flags & flag) != 0;
}

/// refreshes parents hierarchy if necessary, for up-to-date parent transformation
/// @returns true if any of the ancestors' mtx was refreshed
static bool _transform_check_and_refresh_parents(Transform *const t) {
    bool hierarchyDirty = false;
    DoublyLinkedList *parents = doubly_linked_list_new();
    Transform *it = t;
    while (it->parent != NULL) {
        doubly_linked_list_push_last(parents, it->parent);
        it = it->parent;
    }
    it = doubly_linked_list_pop_last(parents);
    while (it != NULL) {
        if (hierarchyDirty || _transform_get_dirty(it, TRANSFORM_DIRTY_MTX)) {
            transform_refresh(it, hierarchyDirty, false);
            hierarchyDirty = true;
        }
        it = doubly_linked_list_pop_last(parents);
    }
    doubly_linked_list_free(parents);

    return hierarchyDirty;
}

/// refreshes local position getter
/// note: here, parents wtl matrices must be up-to-date
static void _transform_refresh_local_position(Transform *t) {
    if (_transform_get_dirty(t, TRANSFORM_DIRTY_LOCAL_POS)) {
        if (t->parent != NULL) {
            matrix4x4_op_multiply_vec_point(&t->localPosition, &t->position, t->parent->wtl);
        } else {
            float3_copy(&t->localPosition, &t->position);
        }
        _transform_reset_dirty(t, TRANSFORM_DIRTY_LOCAL_POS);
    }
}

/// refreshes world position getter
/// note: here, parents ltw matrices must be up-to-date, if additionally the transform own matrices
/// are not dirty, we can use its ltw for a cheaper refresh
static void _transform_refresh_position(Transform *t) {
    if (_transform_get_dirty(t, TRANSFORM_DIRTY_POS)) {
        if (t->parent != NULL) {
            if (_transform_get_dirty(t, TRANSFORM_DIRTY_MTX)) {
                matrix4x4_op_multiply_vec_point(&t->position, &t->localPosition, t->parent->ltw);
            } else {
                float3_set(&t->position, t->ltw->x4y1, t->ltw->x4y2, t->ltw->x4y3);
            }
        } else {
            float3_copy(&t->position, &t->localPosition);
        }

        _transform_reset_dirty(t, TRANSFORM_DIRTY_POS);
    }
}

/// refreshes local rotation getter
/// note: here, nothing needs to be up-to-date
static void _transform_refresh_local_rotation(Transform *t) {
    if (_transform_get_dirty(t, TRANSFORM_DIRTY_LOCAL_ROT)) {
        if (t->parent != NULL) {
            Quaternion *parentRot = transform_get_rotation(t->parent);
            if (quaternion_is_zero(parentRot, EPSILON_ZERO_TRANSFORM_RAD) == false) {
                Quaternion qwtl;
                quaternion_set(&qwtl, parentRot);
                quaternion_op_inverse(&qwtl);
                *t->localRotation = quaternion_op_mult(&qwtl, t->rotation);
            } else {
                quaternion_set(t->localRotation, t->rotation);
            }
        } else {
            quaternion_set(t->localRotation, t->rotation);
        }
        _transform_reset_dirty(t, TRANSFORM_DIRTY_LOCAL_ROT);
    }
}

/// refreshes world rotation getter
/// note: here, nothing needs to be up-to-date
static void _transform_refresh_rotation(Transform *t) {
    if (_transform_get_dirty(t, TRANSFORM_DIRTY_ROT)) {
        if (t->parent != NULL) {
            Quaternion *parentRot = transform_get_rotation(t->parent);
            if (quaternion_is_zero(parentRot, EPSILON_ZERO_TRANSFORM_RAD) == false) {
                *t->rotation = quaternion_op_mult(parentRot, t->localRotation);
            } else {
                quaternion_set(t->rotation, t->localRotation);
            }
        } else {
            quaternion_set(t->rotation, t->localRotation);
        }
        _transform_reset_dirty(t, TRANSFORM_DIRTY_ROT);
    }
}

/// note: here, local transformations must be up-to-date
static void _transform_refresh_matrices(Transform *t, bool hierarchyDirty) {
    const bool dirty = _transform_get_dirty(t, TRANSFORM_DIRTY_MTX);

    if (dirty) {
        /// compute local mtx
        transform_utils_compute_SRT(t->mtx, &t->localScale, t->localRotation, &t->localPosition);

        _transform_reset_dirty(t, TRANSFORM_DIRTY_MTX);

        // transform's mtx was refreshed, therefore other children down the hierarchy
        // may be refreshed on intra-frame demand, or automatically at next end-of-frame
        _transform_set_dirty(t, TRANSFORM_DIRTY_CHILDREN, true);
    }

    if (dirty || hierarchyDirty) {

        /// refreshes ltw & wtl
        matrix4x4_copy(t->ltw, t->mtx);
        if (t->parent != NULL) {
            // if any lock in place, build custom parent ltw matrix
            if (_transform_get_flag(t,
                                    TRANSFORM_FLAG_LOCK_T | TRANSFORM_FLAG_LOCK_R |
                                        TRANSFORM_FLAG_LOCK_S)) {
                Matrix4x4 *parentLtw = matrix4x4_new_identity();

                if (_transform_get_flag(t, TRANSFORM_FLAG_LOCK_S) == false) {
                    float3 lossyScale;
                    matrix4x4_get_scaleXYZ(t->parent->ltw, &lossyScale);
                    matrix4x4_set_scaleXYZ(parentLtw, lossyScale.x, lossyScale.y, lossyScale.z);
                }
                if (_transform_get_flag(t, TRANSFORM_FLAG_LOCK_R) == false) {
                    Matrix4x4 mtx;
                    quaternion_to_rotation_matrix(t->parent->rotation, &mtx);
                    matrix4x4_op_multiply_2(&mtx, parentLtw);
                }
                if (_transform_get_flag(t, TRANSFORM_FLAG_LOCK_T) == false) {
                    Matrix4x4 mtx;
                    matrix4x4_set_translation(&mtx,
                                              t->parent->ltw->x4y1,
                                              t->parent->ltw->x4y2,
                                              t->parent->ltw->x4y3);
                    matrix4x4_op_multiply_2(&mtx, parentLtw);
                }

                matrix4x4_op_multiply_2(parentLtw, t->ltw);
                matrix4x4_free(parentLtw);
            } else {
                matrix4x4_op_multiply_2(t->parent->ltw, t->ltw);
            }
        }
        matrix4x4_copy(t->wtl, t->ltw);
        matrix4x4_op_invert(t->wtl);

        if (hierarchyDirty) {
            // parent ltw changed, any world transformations may have changed from the ancestors
            _transform_set_dirty(t,
                                 TRANSFORM_DIRTY_POS | TRANSFORM_DIRTY_ROT |
                                     TRANSFORM_DIRTY_PHYSICS,
                                 false);
        }

#if DEBUG_TRANSFORM_REFRESH_CALLS
        debug_transform_refresh_calls++;
#endif
    }
}

static bool _transform_vec_equals(const float3 *f,
                                  const float x,
                                  const float y,
                                  const float z,
                                  const float epsilon) {
    return float_isEqual(f->x, x, epsilon) && float_isEqual(f->y, y, epsilon) &&
           float_isEqual(f->z, z, epsilon);
}

/// note: refreshes what is necessary to not lose any prior transformation, then set all dirty
static void _transform_set_all_dirty(Transform *t, bool keepWorld) {
    _transform_check_and_refresh_parents(t);
    if (keepWorld) {
        _transform_refresh_position(t);
        _transform_refresh_rotation(t);
        _transform_set_dirty(t, TRANSFORM_DIRTY_LOCAL_POS | TRANSFORM_DIRTY_LOCAL_ROT, true);
    } else {
        _transform_refresh_local_position(t);
        _transform_refresh_local_rotation(t);
        _transform_set_dirty(t, TRANSFORM_DIRTY_POS | TRANSFORM_DIRTY_ROT, true);
    }
    _transform_set_dirty(t, TRANSFORM_DIRTY_MTX | TRANSFORM_DIRTY_PHYSICS, false);
}

static void _transform_unit_to_rotation(const float3 *right,
                                        const float3 *up,
                                        const float3 *forward,
                                        Quaternion *q) {
    // creating a look-at rotation matrix seems the most straightforward approach, since we know the
    // unit vectors
    float lookAt[16];

    lookAt[0] = right->x;
    lookAt[1] = up->x;
    lookAt[2] = forward->x;

    lookAt[4] = right->y;
    lookAt[5] = up->y;
    lookAt[6] = forward->y;

    lookAt[8] = right->z;
    lookAt[9] = up->z;
    lookAt[10] = forward->z;

    lookAt[3] = lookAt[7] = lookAt[11] = 0.0f;
    lookAt[12] = lookAt[13] = lookAt[14] = 0.0f;
    lookAt[15] = 1.0f;

    rotation_matrix_to_quaternion((const Matrix4x4 *)&lookAt, q);
    quaternion_op_inverse(q); // a look-at rot mtx is meant to be a view matrix, so just negate it
}

/// @param reciprocal whether parent's children list should be maintained, set to false to avoid an
/// unnecessary search
static bool _transform_remove_parent(Transform *t, const bool keepWorld, const bool reciprocal) {
    if (t->parent == NULL) {
        return false;
    }

    _transform_set_all_dirty(t, keepWorld);

    if (reciprocal) {
        DoublyLinkedListNode *it = doubly_linked_list_first(t->parent->children);
        Transform *child = NULL;
        while (it != NULL) {
            child = (Transform *)doubly_linked_list_node_pointer(it);
            if (child == t) {
                doubly_linked_list_delete_node(t->parent->children, it);
                t->parent->childrenCount--;
                break;
            }
            it = doubly_linked_list_node_next(it);
        }
    }

    t->parent = NULL;
    _transform_toggle_flag(t, TRANSFORM_FLAG_SCENE, true);

    return true;
}

static void _transform_remove_from_hierarchy(Transform *t, const bool keepWorld) {
    if (t->parent != NULL) {
        transform_remove_parent(t, keepWorld);
    }
    if (t->childrenCount > 0) {
        DoublyLinkedListNode *n = doubly_linked_list_first(t->children);
        Transform *child = NULL;
        while (n != NULL) {
            child = (Transform *)doubly_linked_list_node_pointer(n);
            if (_transform_remove_parent(child, keepWorld, false)) {
                transform_release(child);
            }
            n = doubly_linked_list_node_next(n);
        }
        doubly_linked_list_flush(t->children, NULL);
        t->childrenCount = 0;
    }
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

static void _transform_utils_box_to_aabox_lossy(Transform *t,
                                                const Box *b,
                                                Box *aab,
                                                const float3 *offset,
                                                SquarifyType squarify) {
    float3 scale;
    matrix4x4_get_scaleXYZ(t->ltw, &scale);
    box_to_aabox_no_rot(b,
                        aab,
                        transform_get_position(t, false),
                        offset != NULL ? offset : &float3_zero,
                        &scale,
                        squarify);
}

static void _transform_utils_box_to_aabox_inverse_rot(Transform *t,
                                                      const Box *b,
                                                      Box *aab,
                                                      const float3 *offset,
                                                      SquarifyType squarify) {
    // if no world rotation, call cheaper function using lossy scale
    if (quaternion_is_zero(transform_get_rotation(t), EPSILON_ZERO_TRANSFORM_RAD)) {
        _transform_utils_box_to_aabox_lossy(t, b, aab, offset, squarify);
    }

    float3 min = b->min;
    float3 max = b->max;

    // optional local offset
    if (offset != NULL) {
        float3_op_add(&min, offset);
        float3_op_add(&max, offset);
    }

    float3 center = {min.x + (max.x - min.x) * .5f,
                     min.y + (max.y - min.y) * .5f,
                     min.z + (max.z - min.z) * .5f};
    float3 wCenter;

    // box points local to world
    transform_utils_position_ltw(t, &min, &aab->min);
    transform_utils_position_ltw(t, &max, &aab->max);
    transform_utils_position_ltw(t, &center, &wCenter);

    // inverse world rotation to re-align box
    Quaternion qwtl;
    quaternion_set(&qwtl, transform_get_rotation(t));
    quaternion_op_inverse(&qwtl);
    float3_op_substract(&aab->min, &wCenter);
    float3_op_substract(&aab->max, &wCenter);
    quaternion_rotate_vector(&qwtl, &aab->min);
    quaternion_rotate_vector(&qwtl, &aab->max);
    float3_op_add(&aab->min, &wCenter);
    float3_op_add(&aab->max, &wCenter);

    // lastly, squarify box base if required
    if (squarify) {
        box_squarify(aab, squarify);
    }
}

static void _transform_utils_box_to_aabox_ignore_rot(Transform *t,
                                                     const Box *b,
                                                     Box *aab,
                                                     const float3 *offset,
                                                     SquarifyType squarify) {
    // if no world rotation, call cheaper function using lossy scale
    if (quaternion_is_zero(transform_get_rotation(t), EPSILON_ZERO_TRANSFORM_RAD)) {
        _transform_utils_box_to_aabox_lossy(t, b, aab, offset, squarify);
    }

    aab->min = b->min;
    aab->max = b->max;

    // optional local offset
    if (offset != NULL) {
        float3_op_add(&aab->min, offset);
        float3_op_add(&aab->max, offset);
    }

    // box to aabox as if there was no rotation along the hierarchy
    Transform *p = t;
    while (p != NULL) {
        float3_op_mult(&aab->min, &p->localScale);
        float3_op_mult(&aab->max, &p->localScale);

        const float3 *local = transform_get_local_position(p, false);
        float3_op_add(&aab->min, local);
        float3_op_add(&aab->max, local);

        p = p->parent;
    }

    // lastly, squarify box base if required
    if (squarify) {
        box_squarify(aab, squarify);
    }
}

static void _transform_utils_box_to_aabox_full(Transform *t,
                                               const Box *b,
                                               Box *aab,
                                               const float3 *offset,
                                               SquarifyType squarify) {
    // if no world rotation, call cheaper function using lossy scale
    if (quaternion_is_zero(transform_get_rotation(t), EPSILON_ZERO_TRANSFORM_RAD)) {
        _transform_utils_box_to_aabox_lossy(t, b, aab, offset, squarify);
    }

    box_to_aabox2(b, aab, transform_get_ltw(t), offset, squarify);
}

#pragma clang diagnostic pop

static void _transform_free(Transform *const t) {
    if (t == NULL) {
        return;
    }

    if (t->managed != NULL && transform_destroyed_callback != NULL) {
        transform_destroyed_callback(t->id, t->managed);
    } else {
        // Only recycle transform ID if transform destruction isn't managed.
        // Otherwise, it's the responsability of the manager to trigger recycling,
        // when done dealing with potential cleanup operations involving the ID.
        _transform_recycle_id(t->id);
    }
    weakptr_release(t->managed);

    if (t->ptr != NULL) {
        if (t->ptr_free != NULL) {
            t->ptr_free(t->ptr);
        }
        t->ptr = NULL;
        t->ptr_free = NULL;
    }

    if (t->rigidBody != NULL) {
        rigidbody_free(t->rigidBody);
        t->rigidBody = NULL;
    }

    if (t->name != NULL) {
        free(t->name);
        t->name = NULL;
    }

    _transform_remove_from_hierarchy(t, true);
    doubly_linked_list_free(t->children);

    matrix4x4_free(t->ltw);
    matrix4x4_free(t->wtl);
    matrix4x4_free(t->mtx);

    quaternion_free(t->localRotation);
    quaternion_free(t->rotation);

    weakptr_invalidate(t->wptr);
    free(t);
}

// MARK: - Debug -
#if DEBUG_TRANSFORM

int debug_transform_get_refresh_calls(void) {
    return debug_transform_refresh_calls;
}

void debug_transform_reset_refresh_calls(void) {
    debug_transform_refresh_calls = 0;
}

#endif

void debug_transform_set_debug(Transform *const t, const bool enabled) {
    _transform_toggle_flag(t, TRANSFORM_FLAG_DEBUG, enabled);
}
