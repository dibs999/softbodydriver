/* C ABI for SoftBodyDriver (sbcore) - used by Godot 4 / Python / external tools. */
#pragma once

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#  define SB_API __declspec(dllexport)
#else
#  define SB_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct sb_world_t sb_world_t;

typedef struct sb_telemetry_c {
    double speed_kmh;
    double engine_rpm;
    int32_t gear;
    double clutch;
    double throttle;
    double brake;
    double steer;
    uint32_t deformed_beams;
    uint32_t broken_beams;
} sb_telemetry_c;

SB_API sb_world_t* sb_world_create(double dt);
SB_API void sb_world_destroy(sb_world_t* world);
SB_API void sb_world_add_ground_plane(sb_world_t* world, double friction);
SB_API void sb_world_add_box_collider(sb_world_t* world,
                                      double cx, double cy, double cz,
                                      double hx, double hy, double hz,
                                      double rx, double ry, double rz,
                                      double friction);
SB_API void sb_world_add_heightfield_collider(sb_world_t* world,
                                              double origin_x, double origin_z,
                                              double cell_size_x, double cell_size_z,
                                              int32_t nx, int32_t nz,
                                              const double* heights,
                                              double friction);

/* Spawns the built-in drivable car at (x, y, z) and returns its body index. */
SB_API int32_t sb_world_spawn_drivable_car(sb_world_t* world, double x, double y, double z);
/* Loads a .sbeam.json file at (x, y, z) and returns its body index (< 0 on error). */
SB_API int32_t sb_world_load_sbeam(sb_world_t* world, const char* path, double x, double y, double z);

SB_API void sb_body_set_controls(sb_world_t* world, int32_t body_index,
                                 double throttle, double brake, double steer,
                                 double handbrake, int32_t gear);
SB_API void sb_body_get_telemetry(const sb_world_t* world, int32_t body_index, sb_telemetry_c* out_telemetry);

SB_API void sb_world_step(sb_world_t* world, uint32_t steps);
SB_API double sb_world_time(const sb_world_t* world);

SB_API uint32_t sb_body_node_count(const sb_world_t* world, int32_t body_index);
SB_API uint32_t sb_body_beam_count(const sb_world_t* world, int32_t body_index);
SB_API uint32_t sb_body_triangle_count(const sb_world_t* world, int32_t body_index);
/* Writes nodeCount * 3 floats (x, y, z) into out_xyz. */
SB_API void sb_body_get_positions_f32(const sb_world_t* world, int32_t body_index, float* out_xyz);
/* Writes beamCount * 2 endpoint indices into out_pairs and beamCount strain values into out_strain (<0 if broken). */
SB_API void sb_body_get_beams_state(const sb_world_t* world, int32_t body_index,
                                    uint32_t* out_pairs, float* out_strain);
/* Writes triangleCount * 3 vertex indices into out_triplets and triangleCount broken flags (0/1) into out_broken. */
SB_API void sb_body_get_triangles_state(const sb_world_t* world, int32_t body_index,
                                        uint32_t* out_triplets, uint8_t* out_broken);

#ifdef __cplusplus
}
#endif
