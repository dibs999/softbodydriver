// SBVehicle: one soft-body car. Renders the flexbody (skinned) visual model, the wheels and an
// optional node-beam debug view, and exposes controls + telemetry to GDScript.
#pragma once

#include <vector>

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/immediate_mesh.hpp>
#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/transform3d.hpp>

#include "sbcore/car.hpp"

namespace godot {

class SBWorld;

class SBVehicle : public Node3D {
    GDCLASS(SBVehicle, Node3D)

public:
    SBVehicle() = default;
    ~SBVehicle() override = default;

    // ---- called by SBWorld (mutex held where noted)
    void setup(SBWorld* world, sb::CarBuild&& build, const Transform3D& xform, const Dictionary& materials);  // locked
    void pre_step(double dt);       // locked, physics thread
    void sync_from_world();         // locked, main thread
    void update_visual();           // main thread, not locked
    int body_index() const { return bodyIndex_; }
    void set_body_index(int i) { bodyIndex_ = i; }

    // ---- GDScript API
    void set_input(double throttle, double brake, double steer, double handbrake);
    void set_clutch(double clutch);  ///< < 0 = automatic
    void set_gear(int gear);         ///< -1 R, 0 N, 1.. forward (one-shot)
    void shift_up();
    void shift_down();
    void set_automatic(bool a);
    bool is_automatic() const { return ctl_.automatic; }
    void set_ignition(bool on);
    void start_engine();
    void set_tcs(bool on) { ctl_.tcs = on; }
    bool get_tcs() const { return ctl_.tcs; }
    void set_abs(bool on) { ctl_.abs = on; }
    bool get_abs() const { return ctl_.abs; }
    void set_steer_rate(double r) { ctl_.steerRate = r; }

    void reset_to(const Transform3D& xform);  ///< Repair and place.
    void repair_in_place();                   ///< Repair, keep position and heading, set upright.

    void set_debug_view(bool on);
    bool get_debug_view() const { return debugView_; }
    void set_body_visible(bool on);

    Dictionary get_telemetry() const;
    Dictionary get_info() const;
    Vector3 get_position_ws() const;   ///< Centre between the axles at floor level
    Vector3 get_chase_target() const;
    Vector3 get_driver_eye() const;
    Vector3 get_forward() const;
    Vector3 get_up() const;
    Vector3 get_right() const;
    Vector3 get_velocity() const;
    double get_speed_kmh() const;
    PackedFloat32Array get_wheel_slip() const;   ///< m/s sliding speed per wheel
    PackedFloat32Array get_wheel_load() const;   ///< contact indicator 0..1 per wheel
    double take_impact();                         ///< Damage events since the last call (0 = none)

protected:
    static void _bind_methods();

private:
    struct SurfaceGpu {
        Ref<ArrayMesh> mesh;
        MeshInstance3D* instance = nullptr;
        int64_t format = 0;
        uint32_t vertexStride = 12, normalOffset = 0, normalStride = 4;
        PackedByteArray buffer;
    };
    Ref<Material> materialFor(const std::string& name, const Dictionary& lib) const;
    void buildMeshes(const Dictionary& materials);
    void applyTransform(const Transform3D& xform);  // locked
    sb::Vec3 forwardOf(const std::vector<sb::Vec3>& p) const;

    SBWorld* world_ = nullptr;
    int bodyIndex_ = -1;
    sb::CarDefinition def_;
    sb::CarVisual visual_;
    sb::CarLayout layout_;
    std::vector<sb::Vec3> restPositions_;   ///< Build pose (rear bumper at origin)

    // Snapshot of the physics state (main thread side).
    std::vector<sb::Vec3> pos_;
    std::vector<sb::Vec3> vel_;
    sb::VehicleTelemetry tel_;
    sb::CarSystemsState sys_;
    std::vector<float> slip_, contact_;
    std::vector<float> beamStrain_;
    std::vector<std::uint32_t> beamPairs_;
    double impactAccum_ = 0.0;
    std::size_t lastDeformed_ = 0, lastBroken_ = 0;
    bool snapshotValid_ = false;

    // Controls: written by GDScript into ctl_, copied to phys_ under the world lock once per frame.
    struct Controls {
        double throttle = 0, brake = 0, steer = 0, handbrake = 0, clutch = -1.0;
        double steerRate = 2.6;
        int gear = -99;          // one-shot gear request
        bool automatic = true;
        bool ignition = true;
        bool starter = false;    // one-shot: crank the engine
        bool tcs = true, abs = true;
        bool reset = false;      // one-shot
        Transform3D resetXform;
    };
    Controls ctl_, phys_;
    double starterTimer_ = 0.0;

    // Rendering.
    std::vector<SurfaceGpu> surfaces_;
    std::vector<float> frames_, tmpPos_, tmpNrm_;
    struct WheelGpu {
        Node3D* node = nullptr;
        std::uint32_t hubL = 0, hubR = 0, tread0 = 0;
        bool right = false;
    };
    std::vector<WheelGpu> wheels_;
    bool debugView_ = false;
    MeshInstance3D* debugInstance_ = nullptr;
    Ref<ImmediateMesh> debugMesh_;
    Ref<StandardMaterial3D> debugMaterial_;
};

}  // namespace godot
