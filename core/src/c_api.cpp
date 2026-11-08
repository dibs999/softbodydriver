#include "sbcore/c_api.h"

#include <cmath>
#include <exception>

#include "sbcore/sbcore.hpp"
#include "sbcore/vehicle.hpp"

struct sb_world_t {
    sb::World world;
    explicit sb_world_t(double dt) : world(sb::WorldSettings{dt}) {}
};

extern "C" {

sb_world_t* sb_world_create(double dt) {
    return new sb_world_t(dt > 0.0 ? dt : 1.0 / 2000.0);
}

void sb_world_destroy(sb_world_t* w) {
    delete w;
}

void sb_world_add_ground_plane(sb_world_t* w, double friction) {
    if (!w) return;
    w->world.addCollider(sb::StaticCollider::plane({0, 0, 0}, {0, 1, 0}, friction, "ground"));
}

void sb_world_add_box_collider(sb_world_t* w,
                              double cx, double cy, double cz,
                              double hx, double hy, double hz,
                              double rx, double ry, double rz,
                              double friction) {
    if (!w) return;
    w->world.addCollider(sb::StaticCollider::box({cx, cy, cz}, {hx, hy, hz}, {rx, ry, rz}, friction, "box"));
}

void sb_world_add_heightfield_collider(sb_world_t* w,
                                       double origin_x, double origin_z,
                                       double cell_size_x, double cell_size_z,
                                       int32_t nx, int32_t nz,
                                       const double* heights,
                                       double friction) {
    if (!w || !heights || nx < 2 || nz < 2) return;
    std::vector<sb::real> h(heights, heights + static_cast<std::size_t>(nx) * static_cast<std::size_t>(nz));
    w->world.addCollider(sb::StaticCollider::heightfield(
        origin_x, origin_z, cell_size_x, cell_size_z, nx, nz, std::move(h), friction, "terrain"));
}

int32_t sb_world_spawn_drivable_car(sb_world_t* w, double x, double y, double z) {
    if (!w) return -1;
    sb::SoftBody car = sb::buildDrivableCar();
    car.translate({x, y, z});
    return static_cast<int32_t>(w->world.addBody(std::move(car)));
}

int32_t sb_world_load_sbeam(sb_world_t* w, const char* path, double x, double y, double z) {
    if (!w || !path) return -1;
    try {
        sb::SoftBody b = sb::loadSBeam(path);
        b.translate({x, y, z});
        return static_cast<int32_t>(w->world.addBody(std::move(b)));
    } catch (const std::exception&) {
        return -1;
    }
}

void sb_body_set_controls(sb_world_t* w, int32_t idx,
                          double throttle, double brake, double steer,
                          double handbrake, int32_t gear) {
    if (!w || idx < 0 || static_cast<std::size_t>(idx) >= w->world.bodies().size()) return;
    sb::VehicleControls c = w->world.body(static_cast<std::size_t>(idx)).controls();
    c.throttle = throttle;
    c.brake = brake;
    c.steer = steer;
    c.handbrake = handbrake;
    c.gear = gear;
    w->world.body(static_cast<std::size_t>(idx)).setControls(c);
}

void sb_body_get_telemetry(const sb_world_t* w, int32_t idx, sb_telemetry_c* out) {
    if (!w || !out || idx < 0 || static_cast<std::size_t>(idx) >= w->world.bodies().size()) return;
    const sb::VehicleTelemetry t = w->world.body(static_cast<std::size_t>(idx)).telemetry();
    out->speed_kmh = t.speedKmh;
    out->engine_rpm = t.engineRpm;
    out->gear = t.gear;
    out->clutch = t.clutch;
    out->throttle = t.throttle;
    out->brake = t.brake;
    out->steer = t.steer;
    out->deformed_beams = static_cast<uint32_t>(t.deformedBeams);
    out->broken_beams = static_cast<uint32_t>(t.brokenBeams);
}

void sb_world_step(sb_world_t* w, uint32_t steps) {
    if (!w) return;
    for (uint32_t i = 0; i < steps; ++i) w->world.step();
}

double sb_world_time(const sb_world_t* w) {
    return w ? w->world.time() : 0.0;
}

uint32_t sb_body_node_count(const sb_world_t* w, int32_t idx) {
    if (!w || idx < 0 || static_cast<std::size_t>(idx) >= w->world.bodies().size()) return 0;
    return static_cast<uint32_t>(w->world.body(static_cast<std::size_t>(idx)).nodeCount());
}

uint32_t sb_body_beam_count(const sb_world_t* w, int32_t idx) {
    if (!w || idx < 0 || static_cast<std::size_t>(idx) >= w->world.bodies().size()) return 0;
    return static_cast<uint32_t>(w->world.body(static_cast<std::size_t>(idx)).beamCount());
}

uint32_t sb_body_triangle_count(const sb_world_t* w, int32_t idx) {
    if (!w || idx < 0 || static_cast<std::size_t>(idx) >= w->world.bodies().size()) return 0;
    return static_cast<uint32_t>(w->world.body(static_cast<std::size_t>(idx)).triangleCount());
}

void sb_body_get_positions_f32(const sb_world_t* w, int32_t idx, float* out_xyz) {
    if (!w || !out_xyz || idx < 0 || static_cast<std::size_t>(idx) >= w->world.bodies().size()) return;
    const auto& pos = w->world.body(static_cast<std::size_t>(idx)).positions();
    for (std::size_t i = 0; i < pos.size(); ++i) {
        out_xyz[3 * i + 0] = static_cast<float>(pos[i].x);
        out_xyz[3 * i + 1] = static_cast<float>(pos[i].y);
        out_xyz[3 * i + 2] = static_cast<float>(pos[i].z);
    }
}

void sb_body_get_beams_state(const sb_world_t* w, int32_t idx, uint32_t* out_pairs, float* out_strain) {
    if (!w || idx < 0 || static_cast<std::size_t>(idx) >= w->world.bodies().size()) return;
    const auto& b = w->world.body(static_cast<std::size_t>(idx));
    const auto& pos = b.positions();
    const auto& beams = b.beams();
    for (std::size_t i = 0; i < beams.size(); ++i) {
        if (out_pairs) {
            out_pairs[2 * i + 0] = beams[i].a;
            out_pairs[2 * i + 1] = beams[i].b;
        }
        if (out_strain) {
            if (beams[i].broken) {
                out_strain[i] = -1.0f;
            } else {
                const sb::real len = sb::length(pos[beams[i].b] - pos[beams[i].a]);
                out_strain[i] = static_cast<float>(std::abs(len - beams[i].baseRestLength) / beams[i].baseRestLength);
            }
        }
    }
}

void sb_body_get_triangles_state(const sb_world_t* w, int32_t idx, uint32_t* out_triplets, uint8_t* out_broken) {
    if (!w || idx < 0 || static_cast<std::size_t>(idx) >= w->world.bodies().size()) return;
    const auto& tris = w->world.body(static_cast<std::size_t>(idx)).triangles();
    for (std::size_t i = 0; i < tris.size(); ++i) {
        if (out_triplets) {
            out_triplets[3 * i + 0] = tris[i].a;
            out_triplets[3 * i + 1] = tris[i].b;
            out_triplets[3 * i + 2] = tris[i].c;
        }
        if (out_broken) {
            out_broken[i] = tris[i].broken ? 1 : 0;
        }
    }
}

}  // extern "C"
