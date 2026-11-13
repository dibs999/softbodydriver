// Static world geometry that nodes collide with (ground, walls, ramps, heightfield terrain).
#pragma once

#include <string>
#include <vector>

#include "sbcore/vec3.hpp"

namespace sb {

struct StaticCollider {
    enum class Kind { Plane, Box, Heightfield };

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

    // Heightfield: regular grid over [originX, originX + (nx-1)*cellSizeX] x [originZ, originZ + (nz-1)*cellSizeZ].
    int nx = 0, nz = 0;
    real originX = 0, originZ = 0;
    real cellSizeX = 1.0, cellSizeZ = 1.0;
    std::vector<real> heights;  ///< Size nx * nz, row-major: heights[ix * nz + iz].
    // A height patch (heightPatch()) is a heightfield turned about the vertical axis through a
    // pivot: its grid lies in local coordinates, local = R(-yaw) * (p - pivot). It may be thin
    // (points deeper than `thickness` under it do not touch it, so a road can run underneath)
    // and have holes (a NaN height: the four cells round that vertex are open).
    real pivotX = 0, pivotZ = 0;
    real yaw = 0, cosYaw = 1, sinYaw = 0;
    real thickness = kInf;

    // Broadphase bounds (world space). Planes are unbounded.
    bool unbounded = true;
    Vec3 boundsLo{-kInf, -kInf, -kInf}, boundsHi{kInf, kInf, kInf};
    void computeBounds();

    static StaticCollider plane(const Vec3& point, const Vec3& normal, real friction = 1.0,
                                const std::string& name = "ground");
    static StaticCollider box(const Vec3& center, const Vec3& halfExtents, const Vec3& eulerRadians = {},
                              real friction = 1.0, const std::string& name = "box");
    static StaticCollider heightfield(real originX, real originZ,
                                      real cellSizeX, real cellSizeZ,
                                      int nx, int nz,
                                      std::vector<real> heights,
                                      real friction = 1.0,
                                      const std::string& name = "terrain");

    /// A heightfield turned by `yaw` (radians, about +Y: local +Z points along (sin yaw, 0, cos yaw))
    /// round (pivotX, pivotZ), its grid starting at local (originX, originZ). Heights are world y;
    /// NaN marks a hole. Points more than `thickness` below the surface are not in contact.
    static StaticCollider heightPatch(real pivotX, real pivotZ, real yaw, real originX, real originZ, real cellSize,
                                      int nx, int nz, std::vector<real> heights, real thickness,
                                      real friction = 1.0, const std::string& name = "patch");

    /// Samples height and outward normal of a Heightfield at (x, z) in its local grid coordinates
    /// (world x, z unless it is a turned patch). Clamps to grid bounds. NaN inside a hole.
    real sampleHeight(real x, real z, Vec3* outNormal = nullptr) const;

    /// If p is inside/below the collider, returns true with outward normal and penetration depth (> 0).
    bool contact(const Vec3& p, Vec3& outNormal, real& outDepth) const;
};

}  // namespace sb
