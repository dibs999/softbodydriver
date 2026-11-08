// SBWorld: owns the 2000 Hz soft-body simulation and runs it on a background thread.
#pragma once

#include <atomic>
#include <mutex>
#include <thread>
#include <vector>

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>

#include "sbcore/world.hpp"

namespace godot {

class SBVehicle;

class SBWorld : public Node3D {
    GDCLASS(SBWorld, Node3D)

public:
    SBWorld();
    ~SBWorld() override;

    void _ready() override;
    void _process(double delta) override;
    void _exit_tree() override;

    // Static world geometry.
    void add_ground_plane(double friction);
    void add_box(const Vector3& center, const Vector3& half_extents, const Vector3& euler, double friction);
    void add_heightfield(double origin_x, double origin_z, double cell_size, int nx, int nz,
                         const PackedFloat32Array& heights, double friction);
    void clear_colliders();

    // Vehicles.
    SBVehicle* spawn_car(const String& path, const Transform3D& xform);
    void remove_vehicle(SBVehicle* v);
    TypedArray<SBVehicle> get_vehicles() const;

    void set_time_scale(double s) { timeScale_ = s; }
    double get_time_scale() const { return timeScale_; }
    void set_paused(bool p) { paused_ = p; }
    bool is_paused() const { return paused_; }
    void set_material_library(const Dictionary& d) { materials_ = d; }
    Dictionary get_material_library() const { return materials_; }
    void set_air_density(double d);
    double get_air_density() const;

    /// Simulation statistics: sim time, real-time factor, step rate, node/beam counts.
    Dictionary get_stats();
    /// Advance the simulation synchronously by `seconds` (for tests / headless use).
    void step_blocking(double seconds);
    /// Copy the physics state into all vehicles and rebuild their meshes (normally done in _process).
    void sync_visuals();

    // Internal (used by SBVehicle).
    std::mutex& mutex() { return mtx_; }
    sb::World& world() { return world_; }
    int body_index_of(const SBVehicle* v) const;

protected:
    static void _bind_methods();

private:
    void sync_visuals_with_delta(double delta);
    void threadMain();
    void startThread();
    void stopThread();

    sb::World world_;
    std::mutex mtx_;
    std::thread thread_;
    std::atomic<bool> running_{false};
    std::atomic<double> timeScale_{1.0};
    std::atomic<bool> paused_{false};
    std::vector<SBVehicle*> vehicles_;
    Dictionary materials_;
    // Statistics (written by the physics thread).
    std::atomic<double> stepsPerSecond_{0.0};
    std::atomic<double> realtimeFactor_{1.0};
};

}  // namespace godot
