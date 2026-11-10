#include "sb_prop.h"

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
}

void SBProp::sync_from_world() {
    if (!world_ || bodyIndex_ < 0) return;
    const auto& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
    const auto& p = body.positions();
    const Vector3 o = toG(p[frameOrigin_]);
    const Basis b = frameBasis(o, toG(p[frameX_]), toG(p[frameY_])) * restInverse_;
    set_transform(Transform3D(b, o - b.xform(restOrigin_)));
    std::size_t deformed = 0;
    for (const auto& beam : body.beams()) deformed += beam.plasticStrain() > 0.01 ? 1 : 0;
    damage_ = body.beamCount() ? std::min(1.0, 3.0 * static_cast<double>(deformed) / static_cast<double>(body.beamCount())) : 0.0;
}

void SBProp::reset() {
    if (!world_ || bodyIndex_ < 0) return;
    std::lock_guard<WorldMutex> lock(world_->mutex());
    world_->world().body(static_cast<std::size_t>(bodyIndex_)).repair(spawn_);
}

double SBProp::get_displacement() const {
    return (get_transform().xform(restOrigin_) - spawnFrameOrigin_).length();
}

}  // namespace godot
