// SBProp: a loose roadside prop (traffic cone, steel drum) simulated as a small soft body in the
// SBWorld. The node follows the body's rigid frame; the game adds its meshes as children in the
// prop's rest coordinates (standing upright on y = 0).
#pragma once

#include <vector>

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>

#include "sbcore/props.hpp"

namespace godot {

class SBWorld;

class SBProp : public Node3D {
    GDCLASS(SBProp, Node3D)

public:
    String get_kind() const { return kind_; }
    /// Puts the prop back where it was spawned, undamaged.
    void reset();
    /// Distance the prop has moved from its spawn point (m).
    double get_displacement() const;
    /// Steel drums dent: 0 = pristine, 1 = crumpled (fraction of permanently deformed beams).
    double get_damage() const { return damage_; }
    /// Trailer: world transforms of its wheels (y = axle, x = towards a tread node: it turns
    /// with the wheel), and its hitch head. Empty / zero for other props.
    Array get_wheel_transforms() const;
    Vector3 get_hitch_position() const { return hitchPos_; }
    /// Trailer: its brakes (0..1), the overrun brake the game sets from the towing car's.
    void set_brake(double brake);
    int hitch_node() const { return hitch_; }

    // Internal (SBWorld).
    void setup(SBWorld* world, int bodyIndex, const sb::PropBuild& build, const std::vector<sb::Vec3>& spawn, const String& kind);
    void sync_from_world();
    int body_index() const { return bodyIndex_; }
    void set_body_index(int i) { bodyIndex_ = i; }

protected:
    static void _bind_methods();

private:
    SBWorld* world_ = nullptr;
    int bodyIndex_ = -1;
    String kind_;
    std::uint32_t frameOrigin_ = 0, frameX_ = 0, frameY_ = 0;
    Basis restInverse_;
    Vector3 restOrigin_;
    std::int64_t subOrigin_ = -1, subX_ = -1, subY_ = -1;
    Basis subRestInverse_;
    Vector3 subRestOrigin_;
    std::vector<sb::Vec3> spawn_;
    Vector3 spawnFrameOrigin_;
    double damage_ = 0.0;
    int hitch_ = -1;
    Vector3 hitchPos_;
    struct WheelNodes { std::uint32_t hubL, hubR, tread0; };
    std::vector<WheelNodes> wheels_;
    std::vector<Transform3D> wheelXf_;
};

}  // namespace godot
