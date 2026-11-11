// SBVehicle: one soft-body car. Renders the flexbody (skinned) visual model, the wheels and an
// optional node-beam debug view, and exposes controls + telemetry to GDScript.
#pragma once
#include <deque>

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
    /// Visual level of detail, set by the world from the camera: deform the meshes every n-th
    /// frame (1 = every frame) and move the last deformed meshes rigidly in between.
    void set_visual_interval(int frames) { visualInterval_ = frames < 1 ? 1 : frames; }
    int body_index() const { return bodyIndex_; }
    void set_body_index(int i) { bodyIndex_ = i; }

    // ---- GDScript API
    void set_input(double throttle, double brake, double steer, double handbrake);
    void set_clutch(double clutch);  ///< < 0 = automatic
    void set_surface_grip(const PackedFloat32Array& grip);
    /// Tuning: cold tyre pressure per axle (PSI) and the front share of the service brakes.
    void set_tire_pressure(double front_psi, double rear_psi);
    void set_brake_bias(double front_share);
    Dictionary get_tuning() const;
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
    /// Lamp corners (head/tail x left/right): crush of the body structure around each lamp.
    /// [{name, front, side, damage, broken}]; a broken lamp stays dark until repaired.
    Array get_lamp_states() const;
    /// Glass panes of the generated body: [{name, instance, damage, center}]. Damage is the crush
    /// of the structure the pane is bonded to (0 intact, >= 1 shattered); repair resets it.
    Array get_glass_states() const;
    /// Bumpers: [{name ("front"/"rear"), clips (intact clip groups, 0..4), center}].
    Array get_bumper_states() const;
    /// Replay of the last seconds: node positions are recorded at 30 Hz (20 s ring buffer).
    /// replay_begin() freezes the visual on the recording and returns its frame count;
    /// replay_show(i) displays frame i; replay_end() returns to the live simulation.
    int replay_begin();
    void replay_show(int frame);
    void replay_end();
    bool release_bonnet(); ///< Releases latch once; hinges may subsequently break under impact.
    bool release_tailgate(); ///< Same for the rear lid (tailgate / boot lid), if the car has one.
    bool close_bonnet();     ///< Lowers an open bonnet on its struts until its latch catches.
    bool close_tailgate();
    int break_group(const String& name); ///< Breaks every intact beam of a break group, as a crash would (tests, tools).
    void ignite(int source);              ///< Starts a vehicle fire: 0 engine bay, 1 fuel tank (tests, tools).
    Array get_lid_states() const; ///< [{name, available, open_requested, latched, travel, damaged}] bonnet, tailgate
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
    Array get_plate_transforms() const;
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
        Array arrays;                    // source arrays, to rebuild the index buffer when the mesh tears
        Ref<Material> material;
        std::vector<uint8_t> torn;       // per triangle: removed because its edges overstretched
        int tornCount = 0;
        // Paint damage mask in the vertex colour (red = 1 - damage), uploaded only when it changes.
        bool damageMask = false;
        uint32_t attrStride = 0, colorOffset = 0;
        PackedByteArray attrBuffer;
    };
    std::deque<std::vector<float>> replay_;
    double lastRecordTime_ = -1.0;
    bool replaying_ = false;
    std::vector<float> nodeDamage_;   ///< per node: worst plastic strain of the beams attached to it
    bool damageDirty_ = false;
    void tearOverstretched(SurfaceGpu& g, const sb::MeshSurface& s, bool reset, const std::vector<float>& deformed);
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
    struct DeformJob { bool imported; std::size_t surface; uint8_t* dst; };
    std::vector<DeformJob> deformJobs_;
    std::vector<std::vector<float>> jobPositions_;
    static void deformJobEntry(void* self, uint32_t index);
    void deformJob(uint32_t index);
    int visualInterval_ = 1, visualCounter_ = 0;
    bool lodFrameValid_ = false, lodMoved_ = false;
    std::size_t lodDamageSeen_ = 0;
    Transform3D lodFrame_, lodSteering_;
    std::vector<sb::Vec3> lodPositions_;   ///< renderPos_ at the last deformation
    Transform3D rigidVisualFrame() const;   ///< position and heading of renderPos_
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
        double tirePsiFront = -1.0, tirePsiRear = -1.0, brakeBias = -1.0;  // tuning, -1 = as defined
        int tuneSerial = 0;      // bumped by every tuning call, applied once on the physics side
        bool reset = false;      // one-shot
        int puncture = -1;
        double punctureLeak = 4.0;
        Transform3D resetXform;
    };
    Controls ctl_, phys_;
    int appliedTuneSerial_ = 0;
    double starterTimer_ = 0.0;
    // Bonnet (lid 0, struts on channel 1) and tailgate (lid 1, channel 6) are core latch mechanisms.
    bool lidAvailable(int index) const;
    bool setLid(int index, bool open);

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
        double width = 0.0;                    // physics tyre width of this axle
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
    unsigned tearCheckCounter_ = 0;
    bool importedDoors_ = false;   ///< imported door panels follow the physical door cages
    bool importedTailgate_ = false;
    bool importedBonnet_ = false;  ///< imported bonnet follows the physical bonnet
    bool dashboardAvailable_ = true;
    double scrape_ = 0.0;          ///< 0..1 body grinding on the ground (force x sliding speed)
    Vector3 scrapePoint_;
    /// Beams around each lamp corner (head left/right, tail left/right), collected on first use.
    mutable std::vector<std::vector<std::uint32_t>> lampBeams_;
    struct GlassPane { std::size_t surface; std::vector<std::uint32_t> beams, nodes; std::vector<bool> bonded; };
    mutable std::vector<GlassPane> glassPanes_;
    mutable bool glassPanesBuilt_ = false;
    std::vector<WheelGpu> wheels_;
    bool debugView_ = false;
    MeshInstance3D* debugInstance_ = nullptr;
    Ref<ImmediateMesh> debugMesh_;
    Ref<StandardMaterial3D> debugMaterial_;
};

}  // namespace godot
