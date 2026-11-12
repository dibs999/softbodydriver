#include "sb_prop.h"

#include <algorithm>

#include <godot_cpp/core/class_db.hpp>

#include "sb_world.h"

namespace godot {
namespace {
Vector3 toG(const sb::Vec3& v) { return Vector3(static_cast<real_t>(v.x), static_cast<real_t>(v.y), static_cast<real_t>(v.z)); }

Basis frameBasis(const Vector3& o, const Vector3& px, const Vector3& py) {
    const Vector3 x = (px - o).normalized();
    Vector3 y = py - o;
    y = (y - x * y.dot(x)).normalized();
    const Vector3 z = x.cross(y);
    return Basis(x, y, z);  // columns
}
}  // namespace

void SBProp::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_kind"), &SBProp::get_kind);
    ClassDB::bind_method(D_METHOD("reset"), &SBProp::reset);
    ClassDB::bind_method(D_METHOD("get_displacement"), &SBProp::get_displacement);
    ClassDB::bind_method(D_METHOD("get_damage"), &SBProp::get_damage);
    ClassDB::bind_method(D_METHOD("get_wheel_transforms"), &SBProp::get_wheel_transforms);
    ClassDB::bind_method(D_METHOD("get_hitch_position"), &SBProp::get_hitch_position);
    ClassDB::bind_method(D_METHOD("set_brake", "brake"), &SBProp::set_brake);
    ClassDB::bind_method(D_METHOD("set_load", "kg"), &SBProp::set_load);
    ClassDB::bind_method(D_METHOD("get_load"), &SBProp::get_load);
}

void SBProp::setup(SBWorld* world, int bodyIndex, const sb::PropBuild& build, const std::vector<sb::Vec3>& spawn, const String& kind) {
    world_ = world;
    bodyIndex_ = bodyIndex;
    kind_ = kind;
    frameOrigin_ = build.frameOrigin;
    frameX_ = build.frameX;
    frameY_ = build.frameY;
    const auto& r = build.restPositions;
    const Basis rest = frameBasis(toG(r[frameOrigin_]), toG(r[frameX_]), toG(r[frameY_]));
    restInverse_ = rest.transposed();
    restOrigin_ = toG(r[frameOrigin_]);
    spawn_ = spawn;
    spawnFrameOrigin_ = toG(spawn[frameOrigin_]);
    hitch_ = static_cast<int>(build.hitch);
    wheels_.clear();
    for (const auto& w : build.body.wheels())
        if (!w.treadNodes.empty()) wheels_.push_back({w.spec.hubLeft, w.spec.hubRight, w.treadNodes.front()});
    subOrigin_ = build.subFrameOrigin;
    subX_ = build.subFrameX;
    subY_ = build.subFrameY;
    if (subOrigin_ >= 0) {
        const auto so = static_cast<std::size_t>(subOrigin_);
        subRestInverse_ = frameBasis(toG(r[so]), toG(r[static_cast<std::size_t>(subX_)]), toG(r[static_cast<std::size_t>(subY_)])).transposed();
        subRestOrigin_ = toG(r[so]);
    }
}

void SBProp::sync_from_world() {
    if (!world_ || bodyIndex_ < 0) return;
    const auto& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
    const auto& p = body.positions();
    const Vector3 o = toG(p[frameOrigin_]);
    const Basis b = frameBasis(o, toG(p[frameX_]), toG(p[frameY_])) * restInverse_;
    const Transform3D main(b, o - b.xform(restOrigin_));
    set_transform(main);
    // A second rigid part (a beacon's panel): its "Sub" child follows that part's own frame.
    if (subOrigin_ >= 0) {
        if (Node3D* sub = Object::cast_to<Node3D>(get_node_or_null(NodePath("Sub")))) {
            const Vector3 so = toG(p[static_cast<std::size_t>(subOrigin_)]);
            const Basis sb = frameBasis(so, toG(p[static_cast<std::size_t>(subX_)]), toG(p[static_cast<std::size_t>(subY_)])) * subRestInverse_;
            sub->set_transform(main.affine_inverse() * Transform3D(sb, so - sb.xform(subRestOrigin_)));
        }
    }
    if (hitch_ >= 0) hitchPos_ = toG(p[static_cast<std::size_t>(hitch_)]);
    wheelXf_.resize(wheels_.size());
    for (std::size_t i = 0; i < wheels_.size(); ++i) {
        const Vector3 l = toG(p[wheels_[i].hubL]), r = toG(p[wheels_[i].hubR]);
        const Vector3 c = (l + r) * 0.5f, axle = (l - r).normalized();
        Vector3 spoke = toG(p[wheels_[i].tread0]) - c;
        spoke = (spoke - axle * spoke.dot(axle)).normalized();
        wheelXf_[i] = Transform3D(Basis(spoke, axle, spoke.cross(axle)), c);
    }
    std::size_t deformed = 0;
    for (const auto& beam : body.beams()) deformed += beam.plasticStrain() > 0.01 ? 1 : 0;
    damage_ = body.beamCount() ? std::min(1.0, 3.0 * static_cast<double>(deformed) / static_cast<double>(body.beamCount())) : 0.0;
}

void SBProp::reset() {
    if (!world_ || bodyIndex_ < 0) return;
    std::lock_guard<WorldMutex> lock(world_->mutex());
    world_->world().body(static_cast<std::size_t>(bodyIndex_)).repair(spawn_);
}

Array SBProp::get_wheel_transforms() const {
    Array out;
    for (const auto& xf : wheelXf_) out.push_back(xf);
    return out;
}

void SBProp::set_brake(double brake) {
    if (!world_ || bodyIndex_ < 0) return;
    std::lock_guard<WorldMutex> lock(world_->mutex());
    auto& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
    auto c = body.controls();
    c.brake = std::clamp(brake, 0.0, 1.0);
    body.setControls(c);
}

void SBProp::set_load(double kg) {
    if (!world_ || bodyIndex_ < 0) return;
    std::lock_guard<WorldMutex> lock(world_->mutex());
    auto& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
    if (deckBase_.empty()) {
        // The six deck nodes of the box trailer (sbcore buildTrailer: "up<station><side>").
        for (int i = 0; i < 3; ++i)
            for (int sd = 0; sd < 2; ++sd) {
                const auto n = body.findNode("up" + std::to_string(i) + std::to_string(sd));
                if (n >= 0) deckBase_.push_back({static_cast<std::uint32_t>(n), body.masses()[static_cast<std::size_t>(n)]});
            }
    }
    if (deckBase_.empty()) return;
    load_ = std::clamp(kg, 0.0, 600.0);
    // Stacked towards the middle of the deck (a fifth over each end station, three fifths over
    // the middle one), so the trailer's yaw inertia is that of real cargo, not of two loads at
    // its ends; the middle station sits 15 cm ahead of the axle, which keeps a tongue load.
    for (std::size_t k = 0; k < deckBase_.size(); ++k) {
        const double weight = (deckBase_.size() == 6 && k / 2 == 1) ? 0.6 : 0.2;
        body.setNodeMass(deckBase_[k].first, deckBase_[k].second + load_ * weight * 0.5);
    }
    body.wake();
}

double SBProp::get_displacement() const {
    return (get_transform().xform(restOrigin_) - spawnFrameOrigin_).length();
}

}  // namespace godot
