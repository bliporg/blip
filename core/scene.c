// -------------------------------------------------------------
//  Cubzh Core
//  scene.c
//  Created by Gaetan de Villele on May 14, 2019.
// -------------------------------------------------------------

#include "scene.h"

#include <stdlib.h>

#include "rigidBody.h"
#include "weakptr.h"

#if DEBUG_SCENE
static int debug_scene_awake_queries = 0;
#endif

struct _Scene {
    Transform *root;
    Transform *map; // weak ref to Map transform (Shape retained by parent)
    Rtree *rtree;

    // transforms potentially removed from scene since last end-of-frame,
    // relevant for physics & sync, internal transforms do not need to be accounted for here
    FifoList *removed;

    // rigidbody couples registered & waiting for a call to end-of-collision callback
    DoublyLinkedList *collisions;

    // awake volumes can be registered for end-of-frame awake phase
    DoublyLinkedList *awakeBoxes;
    Box *mapAwakeBox;

    // constant acceleration for the whole Scene
    // (gravity usually)
    float3 constantAcceleration;
};

typedef struct {
    Weakptr *t1, *t2;
    AxesMaskValue axis;
    uint32_t frames;
} _CollisionCouple;

void _scene_add_rigidbody_rtree(Scene *sc, RigidBody *rb, Transform *t, Box *collider) {
    rigidbody_set_rtree_leaf(rb,
                             rtree_create_and_insert(sc->rtree,
                                                     collider,
                                                     rigidbody_get_groups(rb),
                                                     rigidbody_get_collides_with(rb),
                                                     t));
}

void _scene_update_rtree(Scene *sc, RigidBody *rb, Transform *t, Box *collider) {
    // register awake volume here for new and removed colliders, NOT for transformations change
    if (rigidbody_is_enabled(rb)) {
        // insert rigidbody as a new leaf, if collider is valid
        if (rigidbody_get_rtree_leaf(rb) == NULL) {
            if (rigidbody_is_collider_valid(rb)) {
                _scene_add_rigidbody_rtree(sc, rb, t, collider);
                scene_register_awake_rigidbody_contacts(sc, rb);
            }
        }
        // update leaf due to collider change, or remove it if collider is invalid
        else if (rigidbody_get_collider_dirty(rb)) {
            scene_register_awake_rigidbody_contacts(sc, rb);
            rtree_remove(sc->rtree, rigidbody_get_rtree_leaf(rb));
            rigidbody_set_rtree_leaf(rb, NULL);

            if (rigidbody_is_collider_valid(rb)) {
                _scene_add_rigidbody_rtree(sc, rb, t, collider);
                scene_register_awake_rigidbody_contacts(sc, rb);
            }
        }
        // update leaf due to transformations change
        else if (transform_is_physics_dirty(t)) {
            rtree_remove(sc->rtree, rigidbody_get_rtree_leaf(rb));
            _scene_add_rigidbody_rtree(sc, rb, t, collider);
        }
    }
    // remove disabled rigidbody from rtree
    else if (rigidbody_get_rtree_leaf(rb) != NULL) {
        scene_register_awake_rigidbody_contacts(sc, rb);
        rtree_remove(sc->rtree, rigidbody_get_rtree_leaf(rb));
        rigidbody_set_rtree_leaf(rb, NULL);
    }

    rigidbody_reset_collider_dirty(rb);
    transform_reset_physics_dirty(t);
}

void _scene_refresh_rtree_collision_masks(RigidBody *rb) {
    RtreeNode *rbLeaf = rigidbody_get_rtree_leaf(rb);

    // refresh collision masks if in the rtree
    if (rbLeaf != NULL) {
        const uint8_t groups = rigidbody_get_groups(rb);
        const uint8_t collidesWith = rigidbody_get_collides_with(rb);
        if (groups != rtree_node_get_groups(rbLeaf) ||
            collidesWith != rtree_node_get_collides_with(rbLeaf)) {

            rtree_node_set_collision_masks(rbLeaf, groups, collidesWith);
        }
    }
}

void _scene_refresh_recurse(Scene *sc,
                            Transform *t,
                            bool hierarchyDirty,
                            const TICK_DELTA_SEC_T dt,
                            void *opaqueUserData) {

    // Refresh transform (top-first) after hierarchy changes
    bool dirty = transform_is_hierarchy_dirty(t);
    transform_refresh(t, hierarchyDirty, false);

    // Get rigidbody, compute world collider
    Box collider;
    RigidBody *rb = transform_get_or_compute_world_collider(t, &collider);

    // Step physics (top-first), collider is kept up-to-date
    if (rb != NULL) {
        if (rigidbody_tick(sc, rb, t, &collider, sc->rtree, dt, opaqueUserData)) {
            scene_register_awake_rigidbody_contacts(sc, rb);
        }
    }

    // Refresh transform (top-first) after changes
    dirty = transform_is_hierarchy_dirty(t) || dirty;
    transform_refresh(t, false, false);

    // Update r-tree (top-first) after changes
    if (rb != NULL) {
        transform_get_or_compute_world_collider(t, &collider);
        _scene_update_rtree(sc, rb, t, &collider);
    }

    // Recurse down the branch
    // ⬆ anything above recursion is executed TOP-FIRST
    DoublyLinkedListNode *n = transform_get_children_iterator(t);
    while (n != NULL) {
        _scene_refresh_recurse(sc,
                               (Transform *)doubly_linked_list_node_pointer(n),
                               hierarchyDirty || dirty,
                               dt,
                               opaqueUserData);
        n = doubly_linked_list_node_next(n);
    }
    // ⬇ anything after recursion is executed DEEP-FIRST

    // Clear intra-frame refresh flags (deep-first)
    transform_refresh_children_done(t);
}

void _scene_end_of_frame_refresh_recurse(Scene *sc,
                                         Transform *t,
                                         bool hierarchyDirty,
                                         const TICK_DELTA_SEC_T dt) {

    // Transform ends the frame inside scene hierarchy
    transform_set_scene_dirty(t, false);
    transform_set_is_in_scene(t, true);

    // Refresh transform (top-first) after sandbox changes
    bool dirty = transform_is_hierarchy_dirty(t);
    transform_refresh(t, hierarchyDirty, false);

    // Apply shape current transaction (top-first), this may change BB & collider
    if (transform_get_type(t) == ShapeTransform) {
        shape_apply_current_transaction(transform_get_shape(t), false);
    }

    // Update r-tree (top-first) after sandbox changes
    Box collider;
    RigidBody *rb = transform_get_or_compute_world_collider(t, &collider);
    if (rb != NULL) {
        _scene_update_rtree(sc, rb, t, &collider);
        _scene_refresh_rtree_collision_masks(rb);
    }

    // Recurse down the branch
    // ⬆ anything above recursion is executed TOP-FIRST
    DoublyLinkedListNode *n = transform_get_children_iterator(t);
    while (n != NULL) {
        _scene_end_of_frame_refresh_recurse(sc,
                                            (Transform *)doubly_linked_list_node_pointer(n),
                                            hierarchyDirty || dirty,
                                            dt);
        n = doubly_linked_list_node_next(n);
    }
    // ⬇ anything after recursion is executed DEEP-FIRST

    // Clear intra-frame refresh flags (deep-first)
    transform_refresh_children_done(t);

#ifndef P3S_CLIENT_HEADLESS
    // Refresh shape buffers (deep-first)
    if (transform_get_type(t) == ShapeTransform) {
        shape_refresh_vertices(transform_get_shape(t));
    }
#endif
}

void _scene_shapes_iterator_func(Transform *t, void *ptr) {
    if (transform_get_type(t) == ShapeTransform) {
        doubly_linked_list_push_last((DoublyLinkedList *)ptr, (Shape *)transform_get_ptr(t));
    }
}

void _scene_standalone_refresh_func(Transform *t, void *ptr) {
    if (transform_get_type(t) == ShapeTransform) {
        shape_apply_current_transaction(transform_get_shape(t), true);
    }
    transform_refresh(t, true, false);
}

// MARK: -

Scene *scene_new(void) {
    Scene *sc = (Scene *)malloc(sizeof(Scene));
    if (sc != NULL) {
        sc->root = transform_make(HierarchyTransform);
        sc->map = NULL;
        sc->rtree = rtree_new(RTREE_NODE_MIN_CAPACITY, RTREE_NODE_MAX_CAPACITY);
        sc->removed = fifo_list_new();
        sc->collisions = doubly_linked_list_new();
        sc->awakeBoxes = doubly_linked_list_new();
        sc->mapAwakeBox = NULL;
        float3_set(&sc->constantAcceleration, 0.0f, 0.0f, 0.0f);
    }
    return sc;
}

void scene_free(Scene *sc) {
    if (sc == NULL) {
        return;
    }

    transform_release(sc->root);
    rtree_free(sc->rtree);
    fifo_list_free(sc->removed);
    doubly_linked_list_free(sc->collisions);
    doubly_linked_list_flush(sc->awakeBoxes, (pointer_free_function)box_free);
    doubly_linked_list_free(sc->awakeBoxes);

    free(sc);
}

Transform *scene_get_root(Scene *sc) {
    return sc->root;
}

Rtree *scene_get_rtree(Scene *sc) {
    return sc->rtree;
}

void scene_refresh(Scene *sc, const TICK_DELTA_SEC_T dt, void *opaqueUserData) {
    if (sc == NULL) {
        return;
    }
#if DEBUG_RIGIDBODY_EXTRA_LOGS
    cclog_debug("🏞 physics step");
#endif
    _scene_refresh_recurse(sc,
                           sc->root,
                           transform_is_hierarchy_dirty(sc->root),
                           dt,
                           opaqueUserData);
}

void scene_end_of_frame_refresh(Scene *sc, const TICK_DELTA_SEC_T dt, void *opaqueUserData) {
    if (sc == NULL) {
        return;
    }

    _scene_end_of_frame_refresh_recurse(sc, sc->root, transform_is_hierarchy_dirty(sc->root), dt);

#if DEBUG_RTREE_CHECK
    vx_assert(debug_rtree_integrity_check(sc->rtree));
#endif

    // process transforms removal from hierarchy
    Transform *t = (Transform *)fifo_list_pop(sc->removed);
    DoublyLinkedListNode *n = NULL;
    Transform *child = NULL;
    RigidBody *rb = NULL;
    while (t != NULL) {
        // if still outside of hierarchy at end-of-frame, proceed with removal
        if (transform_is_scene_dirty(t)) {
            // enqueue children for r-tree leaf removal
            n = transform_get_children_iterator(t);
            while (n != NULL) {
                child = doubly_linked_list_node_pointer(n);

                transform_set_scene_dirty(child, true);
                scene_register_removed_transform(sc, child);

                n = doubly_linked_list_node_next(n);
            }

            // r-tree leaf removal
            rb = transform_get_rigidbody(t);
            if (rb != NULL && rigidbody_get_rtree_leaf(rb) != NULL) {
                rtree_remove(sc->rtree, rigidbody_get_rtree_leaf(rb));
                rigidbody_set_rtree_leaf(rb, NULL);
            }

            transform_set_scene_dirty(t, false);
            transform_set_is_in_scene(t, false);
        }
        transform_release(t); // from scene_register_removed_transform

        t = (Transform *)fifo_list_pop(sc->removed);
    }

    // process collision couples for end-of-contact callback
    n = doubly_linked_list_first(sc->collisions);
    _CollisionCouple *cc = NULL;
    Transform *t2 = NULL;
    while (n != NULL) {
        cc = (_CollisionCouple *)doubly_linked_list_node_pointer(n);
        t = weakptr_get(cc->t1);
        t2 = weakptr_get(cc->t2);

        if (t == NULL || t2 == NULL ||
            rigidbody_check_end_of_contact(t, t2, cc->axis, &cc->frames, opaqueUserData)) {
            weakptr_release(cc->t1);
            weakptr_release(cc->t2);
            free(cc);

            DoublyLinkedListNode *next = doubly_linked_list_node_next(n);
            doubly_linked_list_delete_node(sc->collisions, n);
            n = next;
        } else {
            n = doubly_linked_list_node_next(n);
        }
    }

    // awake phase
    FifoList *awakeQuery = fifo_list_new();
    Box *awakeBox;
    n = doubly_linked_list_first(sc->awakeBoxes);
    while (n != NULL) {
        // TODO: save groups in the list
        awakeBox = (Box *)doubly_linked_list_node_pointer(n);

        vx_assert(fifo_list_pop(awakeQuery) == NULL);
        if (rtree_query_overlap_box(sc->rtree,
                                    awakeBox,
                                    PHYSICS_GROUP_ALL,
                                    PHYSICS_GROUP_ALL,
                                    awakeQuery,
                                    EPSILON_COLLISION) > 0) {
            RtreeNode *hit = fifo_list_pop(awakeQuery);
            Transform *hitLeaf = NULL;
            RigidBody *hitRb = NULL;
            while (hit != NULL) {
                hitLeaf = (Transform *)rtree_node_get_leaf_ptr(hit);
                vx_assert(rtree_node_is_leaf(hit));

                hitRb = transform_get_rigidbody(hitLeaf);
                vx_assert(hitRb != NULL);

                rigidbody_set_awake(hitRb);

                hit = fifo_list_pop(awakeQuery);
            }
#if DEBUG_SCENE_CALLS
            debug_scene_awake_queries++;
#endif
        }

        DoublyLinkedListNode *next = doubly_linked_list_node_next(n);
        doubly_linked_list_delete_node(sc->awakeBoxes, n);
        n = next;
        box_free(awakeBox);
    }
    sc->mapAwakeBox = NULL;
    fifo_list_free(awakeQuery);

    // physics layers mask changes take effect in the rtree at the end of each frame
    rtree_refresh_collision_masks(sc->rtree);
}

void scene_standalone_refresh(Scene *sc) {
    transform_recurse(sc->root, _scene_standalone_refresh_func, NULL, false);
}

DoublyLinkedList *scene_new_shapes_iterator(Scene *sc) {
    DoublyLinkedList *list = doubly_linked_list_new();
    transform_recurse(sc->root, _scene_shapes_iterator_func, list, true);
    return list;
}

void scene_add_map(Scene *sc, Shape *map) {
    vx_assert(sc != NULL);
    vx_assert(map != NULL);

    if (sc->map != NULL) {
        transform_remove_parent(sc->map, true);
    }

    sc->map = shape_get_root_transform(map);
    transform_set_parent(sc->map, sc->root, true);

#if DEBUG_SCENE_EXTRALOG
    cclog_debug("🏞 map added to the scene");
#endif
}

Transform *scene_get_map(Scene *sc) {
    return sc->map;
}

void scene_remove_map(Scene *sc) {
    vx_assert(sc != NULL);

    if (sc->map != NULL) {
        transform_remove_parent(sc->map, true);
        sc->map = NULL;
    }

#if DEBUG_SCENE_EXTRALOG
    cclog_debug("🏞 map removed from the scene");
#endif
}

void scene_remove_transform(Scene *sc, Transform *t) {
    vx_assert(sc != NULL);
    if (t == NULL)
        return;

    scene_register_removed_transform(sc, t);
    transform_remove_parent(t, true);

#if DEBUG_SCENE_EXTRALOG
    cclog_debug("🏞 transform removed from the scene");
#endif
}

void scene_register_removed_transform(Scene *sc, Transform *t) {
    if (sc == NULL || t == NULL) {
        return;
    }

    transform_retain(t);
    fifo_list_push(sc->removed, t);
}

void scene_register_collision_couple(Scene *sc, Transform *t1, Transform *t2, AxesMaskValue axis) {
    if (sc == NULL || t1 == NULL || t2 == NULL) {
        return;
    }

    _CollisionCouple *cc = (_CollisionCouple *)malloc(sizeof(_CollisionCouple));
    cc->t1 = transform_get_and_retain_weakptr(t1);
    cc->t2 = transform_get_and_retain_weakptr(t2);
    cc->axis = axis;
    cc->frames = 0;
    doubly_linked_list_push_last(sc->collisions, cc);
}

void scene_register_awake_box(Scene *sc, Box *b) {
    float3 size;
    box_get_size_float(b, &size);
    if (float3_isZero(&size, EPSILON_COLLISION) == false) {
        DoublyLinkedListNode *n = doubly_linked_list_first(sc->awakeBoxes);
        Box *awakeBox;
        while (n != NULL) {
            awakeBox = doubly_linked_list_node_pointer(n);
            if (awakeBox != sc->mapAwakeBox && box_collide_epsilon(awakeBox, b, EPSILON_ZERO)) {
                box_op_merge(awakeBox, b, awakeBox);
                box_free(b);
                return;
            }
            n = doubly_linked_list_node_next(n);
        }
        doubly_linked_list_push_last(sc->awakeBoxes, b);
    }
}

void scene_register_awake_rigidbody_contacts(Scene *sc, RigidBody *rb) {
    if (rigidbody_get_rtree_leaf(rb) != NULL) {
        Box *awakeBox = box_new_copy(rtree_node_get_aabb(rigidbody_get_rtree_leaf(rb)));
        float3_op_add_scalar(&awakeBox->max, PHYSICS_AWAKE_DISTANCE);
        float3_op_substract_scalar(&awakeBox->min, PHYSICS_AWAKE_DISTANCE);
        scene_register_awake_box(sc, awakeBox);
    }
}

void scene_register_awake_map_box(Scene *sc,
                                  const SHAPE_COORDS_INT_T x,
                                  const SHAPE_COORDS_INT_T y,
                                  const SHAPE_COORDS_INT_T z) {
    float3 scale;
    transform_get_lossy_scale(sc->map, &scale);
    Box *worldBox = box_new_2(((float)x) * scale.x - PHYSICS_AWAKE_DISTANCE,
                              ((float)y) * scale.y - PHYSICS_AWAKE_DISTANCE,
                              ((float)z) * scale.z - PHYSICS_AWAKE_DISTANCE,
                              ((float)(x + 1)) * scale.x + PHYSICS_AWAKE_DISTANCE,
                              ((float)(y + 1)) * scale.y + PHYSICS_AWAKE_DISTANCE,
                              ((float)(z + 1)) * scale.z + PHYSICS_AWAKE_DISTANCE);

    if (sc->mapAwakeBox == NULL) {
        sc->mapAwakeBox = worldBox;
        doubly_linked_list_push_last(sc->awakeBoxes, sc->mapAwakeBox);
    } else {
        box_op_merge(sc->mapAwakeBox, worldBox, sc->mapAwakeBox);
        box_free(worldBox);
    }
}

void scene_set_constant_acceleration(Scene *sc, const float3 *f3) {
    vx_assert(sc != NULL);
    vx_assert(f3 != NULL);

    float3_copy(&sc->constantAcceleration, f3);
}

void scene_set_constant_acceleration_2(Scene *sc, const float *x, const float *y, const float *z) {
    vx_assert(sc != NULL);

    if (x != NULL) {
        sc->constantAcceleration.x = *x;
    }
    if (y != NULL) {
        sc->constantAcceleration.y = *y;
    }
    if (z != NULL) {
        sc->constantAcceleration.x = *z;
    }
}

const float3 *scene_get_constant_acceleration(const Scene *sc) {
    vx_assert(sc != NULL);
    return &sc->constantAcceleration;
}

// MARK: - Debug -
#if DEBUG_SCENE

int debug_scene_get_awake_queries(void) {
    return debug_scene_awake_queries;
}

void debug_scene_reset_calls(void) {
    debug_scene_awake_queries = 0;
}

#endif
