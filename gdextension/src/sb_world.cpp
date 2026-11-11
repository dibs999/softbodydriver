#include "sb_world.h"

#include <algorithm>
#include <chrono>

#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include "sb_prop.h"
#include "sb_vehicle.h"
#include "sbcore/car.hpp"

namespace godot {

SBWorld::SBWorld() {
    world_.settings().airDensity = 1.225;
}

SBWorld::~SBWorld() {
    stopThread();
}

void SBWorld::_bind_methods() {
    ClassDB::bind_method(D_METHOD("add_ground_plane", "friction"), &SBWorld::add_ground_plane);
    ClassDB::bind_method(D_METHOD("add_box", "center", "half_extents", "euler", "friction"), &SBWorld::add_box);
    ClassDB::bind_method(D_METHOD("add_heightfield", "origin_x", "origin_z", "cell_size", "nx", "nz", "heights", "friction"),
                         &SBWorld::add_heightfield);
    ClassDB::bind_method(D_METHOD("clear_colliders"), &SBWorld::clear_colliders);
    ClassDB::bind_method(D_METHOD("spawn_car", "path", "xform"), &SBWorld::spawn_car);
    ClassDB::bind_method(D_METHOD("remove_vehicle", "vehicle"), &SBWorld::remove_vehicle);
    ClassDB::bind_method(D_METHOD("get_vehicles"), &SBWorld::get_vehicles);
    ClassDB::bind_method(D_METHOD("spawn_prop", "kind", "xform"), &SBWorld::spawn_prop);
    ClassDB::bind_method(D_METHOD("remove_prop", "prop"), &SBWorld::remove_prop);
    ClassDB::bind_method(D_METHOD("get_props"), &SBWorld::get_props);
    ClassDB::bind_method(D_METHOD("get_stats"), &SBWorld::get_stats);
    ClassDB::bind_method(D_METHOD("step_blocking", "seconds"), &SBWorld::step_blocking);
    ClassDB::bind_method(D_METHOD("sync_visuals"), &SBWorld::sync_visuals);

    ClassDB::bind_method(D_METHOD("set_time_scale", "scale"), &SBWorld::set_time_scale);
    ClassDB::bind_method(D_METHOD("get_time_scale"), &SBWorld::get_time_scale);
    ClassDB::bind_method(D_METHOD("set_paused", "paused"), &SBWorld::set_paused);
    ClassDB::bind_method(D_METHOD("is_paused"), &SBWorld::is_paused);
    ClassDB::bind_method(D_METHOD("set_material_library", "materials"), &SBWorld::set_material_library);
    ClassDB::bind_method(D_METHOD("get_material_library"), &SBWorld::get_material_library);
    ClassDB::bind_method(D_METHOD("set_air_density", "density"), &SBWorld::set_air_density);
    ClassDB::bind_method(D_METHOD("get_air_density"), &SBWorld::get_air_density);

    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "time_scale", PROPERTY_HINT_RANGE, "0.01,2,0.01"), "set_time_scale", "get_time_scale");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "paused"), "set_paused", "is_paused");
    ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "material_library"), "set_material_library", "get_material_library");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "air_density"), "set_air_density", "get_air_density");
}

void SBWorld::_ready() {
    if (Engine::get_singleton()->is_editor_hint()) return;
    startThread();
}

void SBWorld::_exit_tree() {
    stopThread();
}

void SBWorld::_process(double delta) {
    if (Engine::get_singleton()->is_editor_hint()) return;
    sync_visuals_with_delta(delta);
}

void SBWorld::sync_visuals() {
    sync_visuals_with_delta(0.0);
}

void SBWorld::sync_visuals_with_delta(double delta) {
    // Snapshot every vehicle under one short lock, then rebuild meshes without holding it.
    {
        std::lock_guard<WorldMutex> lock(mtx_);
        for (SBVehicle* v : vehicles_) v->sync_from_world();
        for (SBProp* p : props_) p->sync_from_world();
    }
    // Visual level of detail from the camera: full mesh deformation every frame up to 30 m, then
    // every 2nd / 4th / 8th frame; off-screen cars at least every 4th. Without a camera (tools,
    // tests) every frame.
    Camera3D* camera = is_inside_tree() && get_viewport() ? get_viewport()->get_camera_3d() : nullptr;
    for (SBVehicle* v : vehicles_) {
        int interval = 1;
        if (camera) {
            const Vector3 p = v->get_position_ws();
            const double d = camera->get_global_position().distance_to(p);
            interval = d < 30.0 ? 1 : d < 70.0 ? 2 : d < 150.0 ? 4 : 8;
            if (d > 12.0 && !camera->is_position_in_frustum(p)) interval = std::max(interval, 4);
        }
        v->set_visual_interval(interval);
    }
    for (SBVehicle* v : vehicles_) v->update_visual(delta);
}

void SBWorld::startThread() {
    if (running_) return;
    running_ = true;
    thread_ = std::thread(&SBWorld::threadMain, this);
}

void SBWorld::stopThread() {
    if (!running_) return;
    running_ = false;
    if (thread_.joinable()) thread_.join();
}

void SBWorld::threadMain() {
    using clock = std::chrono::steady_clock;
    const double dt = world_.settings().dt;
    auto last = clock::now();
    double debt = 0.0;  // simulated seconds we still owe
    auto statT0 = clock::now();
    std::uint64_t statSteps = 0;
    double statSim = 0.0;
    while (running_) {
        const auto now = clock::now();
        const double wall = std::chrono::duration<double>(now - last).count();
        last = now;
        if (!paused_) debt += wall * timeScale_.load();
        // Never try to catch up more than 100 ms: the game slows down instead of spiralling.
        debt = std::min(debt, 0.1);
        int steps = static_cast<int>(debt / dt);
        if (steps <= 0) {
            std::this_thread::sleep_for(std::chrono::microseconds(300));
            continue;
        }
        while (steps > 0 && running_) {
            const int chunk = std::min(steps, 16);
            {
                std::lock_guard<WorldMutex> lock(mtx_);
                for (int i = 0; i < chunk; ++i) {
                    for (SBVehicle* v : vehicles_) v->pre_step(dt);
                    world_.step();
                }
            }
            steps -= chunk;
            debt -= chunk * dt;
            statSteps += static_cast<std::uint64_t>(chunk);
            statSim += chunk * dt;
            // Hand the lock to a waiting main thread before the next chunk.
            for (int spin = 0; mtx_.contended() && running_; ++spin) {
                if (spin < 64) std::this_thread::yield();
                else std::this_thread::sleep_for(std::chrono::microseconds(50));
            }
        }
        const double statWall = std::chrono::duration<double>(clock::now() - statT0).count();
        if (statWall > 0.5) {
            stepsPerSecond_ = static_cast<double>(statSteps) / statWall;
            realtimeFactor_ = statSim / statWall;
            statT0 = clock::now();
            statSteps = 0;
            statSim = 0.0;
        }
    }
}

void SBWorld::add_ground_plane(double friction) {
    std::lock_guard<WorldMutex> lock(mtx_);
    world_.addCollider(sb::StaticCollider::plane({0, 0, 0}, {0, 1, 0}, friction, "ground"));
}

void SBWorld::add_box(const Vector3& c, const Vector3& h, const Vector3& e, double friction) {
    std::lock_guard<WorldMutex> lock(mtx_);
    world_.addCollider(sb::StaticCollider::box({c.x, c.y, c.z}, {h.x, h.y, h.z}, {e.x, e.y, e.z}, friction, "box"));
}

void SBWorld::add_heightfield(double ox, double oz, double cell, int nx, int nz, const PackedFloat32Array& heights,
                              double friction) {
    if (nx < 2 || nz < 2 || heights.size() < static_cast<int64_t>(nx) * nz) {
        UtilityFunctions::push_error("SBWorld.add_heightfield: heights must contain nx * nz values");
        return;
    }
    std::vector<sb::real> h(static_cast<std::size_t>(nx) * static_cast<std::size_t>(nz));
    for (std::size_t i = 0; i < h.size(); ++i) h[i] = heights[static_cast<int64_t>(i)];
    std::lock_guard<WorldMutex> lock(mtx_);
    world_.addCollider(sb::StaticCollider::heightfield(ox, oz, cell, cell, nx, nz, std::move(h), friction, "terrain"));
}

void SBWorld::clear_colliders() {
    std::lock_guard<WorldMutex> lock(mtx_);
    world_.clearColliders();
}

SBVehicle* SBWorld::spawn_car(const String& path, const Transform3D& xform) {
    const String text = FileAccess::get_file_as_string(path);
    if (text.is_empty()) {
        UtilityFunctions::push_error("SBWorld.spawn_car: cannot read ", path);
        return nullptr;
    }
    sb::CarBuild build;
    try {
        const sb::CarDefinition def = sb::parseCarDefinition(text.utf8().get_data(), path.utf8().get_data());
        build = sb::buildCar(def);
    } catch (const std::exception& e) {
        UtilityFunctions::push_error("SBWorld.spawn_car: ", path, ": ", e.what());
        return nullptr;
    }
    SBVehicle* v = memnew(SBVehicle);
    v->set_name(String(build.def.id.c_str()));
    add_child(v);
    {
        std::lock_guard<WorldMutex> lock(mtx_);
        v->setup(this, std::move(build), xform, materials_);
        vehicles_.push_back(v);
    }
    return v;
}

void SBWorld::remove_vehicle(SBVehicle* v) {
    if (!v) return;
    {
        std::lock_guard<WorldMutex> lock(mtx_);
        auto it = std::find(vehicles_.begin(), vehicles_.end(), v);
        if (it == vehicles_.end()) return;
        const int idx = v->body_index();
        vehicles_.erase(it);
        removeBodyAt(idx);
    }
    v->queue_free();
}

void SBWorld::removeBodyAt(int idx) {
    world_.removeBody(static_cast<std::size_t>(idx));
    for (SBVehicle* o : vehicles_)
        if (o->body_index() > idx) o->set_body_index(o->body_index() - 1);
    for (SBProp* o : props_)
        if (o->body_index() > idx) o->set_body_index(o->body_index() - 1);
}

SBProp* SBWorld::spawn_prop(const String& kind, const Transform3D& xform) {
    sb::PropBuild build;
    try {
        build = sb::buildProp(sb::propKindFromString(kind.utf8().get_data()));
    } catch (const std::exception& e) {
        UtilityFunctions::push_error("SBWorld.spawn_prop: ", e.what());
        return nullptr;
    }
    for (auto& p : build.body.positions()) {
        const Vector3 w = xform.xform(Vector3(static_cast<real_t>(p.x), static_cast<real_t>(p.y), static_cast<real_t>(p.z)));
        p = {w.x, w.y, w.z};
    }
    const std::vector<sb::Vec3> spawn = build.body.positions();
    SBProp* prop = memnew(SBProp);
    prop->set_name(kind);
    add_child(prop);
    {
        std::lock_guard<WorldMutex> lock(mtx_);
        const int idx = static_cast<int>(world_.addBody(build.body));
        prop->setup(this, idx, build, spawn, kind);
        props_.push_back(prop);
        prop->sync_from_world();
    }
    return prop;
}

void SBWorld::remove_prop(SBProp* p) {
    if (!p) return;
    {
        std::lock_guard<WorldMutex> lock(mtx_);
        auto it = std::find(props_.begin(), props_.end(), p);
        if (it == props_.end()) return;
        const int idx = p->body_index();
        props_.erase(it);
        removeBodyAt(idx);
    }
    p->queue_free();
}

TypedArray<SBProp> SBWorld::get_props() const {
    TypedArray<SBProp> out;
    for (SBProp* p : props_) out.push_back(p);
    return out;
}

TypedArray<SBVehicle> SBWorld::get_vehicles() const {
    TypedArray<SBVehicle> out;
    for (SBVehicle* v : vehicles_) out.push_back(v);
    return out;
}

int SBWorld::body_index_of(const SBVehicle* v) const {
    for (std::size_t i = 0; i < vehicles_.size(); ++i)
        if (vehicles_[i] == v) return static_cast<int>(i);
    return -1;
}

void SBWorld::set_air_density(double d) {
    std::lock_guard<WorldMutex> lock(mtx_);
    world_.settings().airDensity = d;
}

double SBWorld::get_air_density() const {
    return world_.settings().airDensity;
}

Dictionary SBWorld::get_stats() {
    Dictionary d;
    std::size_t nodes = 0, beams = 0;
    double simTime = 0;
    {
        std::lock_guard<WorldMutex> lock(mtx_);
        for (const auto& b : world_.bodies()) {
            nodes += b.nodeCount();
            beams += b.beamCount();
        }
        simTime = world_.time();
    }
    d["sim_time"] = simTime;
    d["nodes"] = static_cast<int64_t>(nodes);
    d["beams"] = static_cast<int64_t>(beams);
    d["steps_per_second"] = stepsPerSecond_.load();
    d["realtime_factor"] = realtimeFactor_.load();
    d["physics_hz"] = 1.0 / world_.settings().dt;
    d["vehicles"] = static_cast<int64_t>(vehicles_.size());
    return d;
}

void SBWorld::step_blocking(double seconds) {
    const double dt = world_.settings().dt;
    const auto n = static_cast<int>(seconds / dt);
    std::lock_guard<WorldMutex> lock(mtx_);
    for (SBVehicle* v : vehicles_) v->sync_from_world();  // hand over pending controls
    for (int i = 0; i < n; ++i) {
        for (SBVehicle* v : vehicles_) v->pre_step(dt);
        world_.step();
    }
}

}  // namespace godot
