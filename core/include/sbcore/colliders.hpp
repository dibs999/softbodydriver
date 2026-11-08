// Static world geometry that nodes collide with (ground, walls, ramps).
// Phase 1: infinite planes and oriented boxes. Heightfield terrain and
// triangle meshes follow in later phases.
#pragma once

#include <string>

#include "sbcore/vec3.hpp"

namespace sb {

struct StaticCollider {
    enum class Kind { Plane, Box };

    Kind kind = Kind::Plane;
    std::string name;
    real friction = 1.0;     ///< Surface friction coefficient (multiplied with node friction).
    real restitution = 0.0;  ///< 0 = no bounce.

    // Plane: all points p with dot(p - point, normal) < 0 are inside.
    Vec3 point{0, 0, 0};
    Vec3 normal{0, 1, 0};

    // Box: center, half extents along local axes, rotation local->world.
    Vec3 center{0, 0, 0};
    Vec3 halfExtents{0.5, 0.5, 0.5};
    Mat3 rotation;       ///< local -> world
    Mat3 invRotation;    ///< world -> local
    Vec3 eulerRadians;   ///< Kept for export / tooling.

    static StaticCollider plane(const Vec3& point, const Vec3& normal, real friction = 1.0,
                                const std::string& name = "ground");
    static StaticCollider box(const Vec3& center, const Vec3& halfExtents, const Vec3& eulerRadians = {},
                              real friction = 1.0, const std::string& name = "box");

    /// If p is inside, returns true with outward normal and penetration depth (> 0).
    bool contact(const Vec3& p, Vec3& outNormal, real& outDepth) const;
};

}  // namespace sb
