// SBVehicle: one soft-body car. Renders the flexbody (skinned) visual model, the wheels and an
// optional node-beam debug view, and exposes controls + telemetry to GDScript.
#pragma once

#include <utility>
#include <array>
#include <vector>

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/immediate_mesh.hpp>
#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/variant/array.hpp>
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
    void update_visual(double delta); // main thread, not locked
    int body_index() const { return bodyIndex_; }
    void set_body_index(int i) { bodyIndex_ = i; }

    // ---- GDScript API
    void set_input(double throttle, double brake, double steer, double handbrake);
    void set_clutch(double clutch);  ///< < 0 = automatic
    void set_surface_grip(const PackedFloat32Array& grip);
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
    bool relocate_to(const Transform3D& xform); ///< Rigid recovery preserving damage and fuel; ground-origin convention.
    bool service_repair(); ///< Repair in place without adding fuel; leave ignition off.
    double refuel(double litres); ///< Adds fuel while stopped with engine off; returns accepted litres.
    bool set_door_open(int index, bool open); ///< 0 driver/left, 1 passenger/right; stationary operation.
    bool toggle_door(int index);
    Array get_door_states() const; ///< Actual latch/attachment/angle state under the physics lock.
    bool release_bonnet(); ///< Releases latch once; hinges may subsequently break under impact.
    void repair_in_place();                   ///< Repair, keep position and heading, set upright.

    void set_debug_view(bool on);
    bool get_debug_view() const { return debugView_; }
    void set_body_visible(bool on);

    Dictionary get_telemetry() const;
    Dictionary get_effect_anchors() const;
    void puncture_tire(int wheel, double leak_psi_per_second);
    Dictionary get_info() const;
    Vector3 get_position_ws() const;   ///< Centre between the axles at floor level
    Vector3 get_chase_target() const;
    Vector3 get_driver_eye() const;
    Variant get_dashboard_transform() const;
    Array get_mirror_surfaces() const; ///< Live optical faces and their deformed planes, in world space.
    Basis get_visual_basis() const;
    Vector3 get_forward() const;
    Vector3 get_up() const;
    Vector3 get_right() const;
    Vector3 get_velocity() const;
    double get_speed_kmh() const;
    double get_engine_rpm() const;
    /// Replaces the procedural body with an imported model (e.g. a glTF scene). `to_build` maps model
    /// coordinates to the car's build frame (rear bumper at x = 0, ground y = 0, +x forward, +z right).
    /// options: wheels {"FL": node name, ...}, hide [name substrings], keep_procedural [material names],
    /// ao_on_uv2 (restore an imported AO atlas authored on the second UV channel).
    void attach_model(Node3D* root, const Transform3D& to_build, const Dictionary& options);
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
        PackedFloat32Array restTangents; // imported tangent frames in build coordinates
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
    std::vector<sb::Vec3> renderPos_;
    sb::Vec3 renderReference_;
    std::vector<sb::Vec3> vel_;
    sb::VehicleTelemetry tel_;
    sb::CarSystemsState sys_;
    std::vector<float> slip_, contact_;
    PackedVector3Array contactPoints_, contactNormals_;
    std::vector<float> beamStrain_;
    std::vector<std::uint32_t> beamPairs_;
    double impactAccum_ = 0.0;
    std::size_t lastDeformed_ = 0, lastBroken_ = 0;
    bool snapshotValid_ = false;
    bool visualResetPending_ = false; // Set by physics under the world lock.
    bool visualReset_ = false;

    // Controls: written by GDScript into ctl_, copied to phys_ under the world lock once per frame.
    struct Controls {
        double throttle = 0, brake = 0, steer = 0, handbrake = 0, clutch = -1.0;
        double steerRate = 2.6;
        int gear = -99;          // one-shot gear request
        bool automatic = true;
        bool ignition = true;
        bool starter = false;    // one-shot: crank the engine
        bool tcs = true, abs = true;
        std::array<double, 4> surfaceGrip{1.0, 1.0, 1.0, 1.0};
        bool reset = false;      // one-shot
        int puncture = -1;
        double punctureLeak = 4.0;
        Transform3D resetXform;
    };
    Controls ctl_, phys_;
    double starterTimer_ = 0.0;
    // Physical bonnet support uses hydro channel 1; state is world-mutex protected.
    bool bonnetOpenRequested_ = false;
    double bonnetSupportTravel_ = 0.0;

    // Rendering.
    std::vector<SurfaceGpu> surfaces_;
    std::vector<float> frames_, tmpPos_, tmpNrm_;
    struct WheelSurf {
        Ref<ArrayMesh> mesh;
        MeshInstance3D* instance = nullptr;
        std::vector<float> restPos, restNrm;   // wheel-local
        uint32_t vertexStride = 12, normalOffset = 0, normalStride = 4;
        PackedByteArray buffer;
        bool deformed = false;                 // currently uploaded in deformed state
    };
    struct WheelGpu {
        Node3D* node = nullptr;
        std::uint32_t hubL = 0, hubR = 0, tread0 = 0;
        std::vector<std::uint32_t> tread;      // 2 * rays tread nodes
        std::vector<std::pair<double, double>> spinWeights;
        std::vector<double> treadRadii;
        bool right = false;
        double visualRimRadius = 0.0;
        std::vector<WheelSurf> surfs;
        sb::Vec3 restX{1, 0, 0};               // rest frame (build coordinates) for imported meshes
    };
    void addWheelSurface(WheelGpu& wg, const PackedVector3Array& v, const PackedVector3Array& n, const Array& extra,
                         const PackedInt32Array& idxGodotOrder, const Ref<Material>& mat, bool deformable);
    void updateWheelMeshes(WheelGpu& w, const sb::Vec3& c, const sb::Vec3& rx, const sb::Vec3& ry, const sb::Vec3& out,
                           double retention);
    // Imported (glTF) body meshes.
    std::vector<sb::MeshSurface> importedSurf_;
    std::vector<SurfaceGpu> importedGpu_;
    bool hasImportedModel_ = false;
    bool dashboardAvailable_ = true;
    std::vector<WheelGpu> wheels_;
    bool debugView_ = false;
    MeshInstance3D* debugInstance_ = nullptr;
    Ref<ImmediateMesh> debugMesh_;
    Ref<StandardMaterial3D> debugMaterial_;
};

}  // namespace godot
