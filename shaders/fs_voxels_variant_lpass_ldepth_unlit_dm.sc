/*
 * Voxels fragment shader variant: unlit, lighting pass, linear depth, draw modes
 */

// Unlit (only relevant w/ lighting pass)
#define VOXEL_VARIANT_UNLIT 1

// Multiple render target lighting and linear depth
#define VOXEL_VARIANT_MRT_LIGHTING 1
#define VOXEL_VARIANT_MRT_LINEAR_DEPTH 1

// Non-default draw modes
#define VOXEL_VARIANT_DRAWMODE_OVERRIDES 1

#include "./fs_voxels_common.sh"
