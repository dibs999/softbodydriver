#include "sbcore/colliders.hpp"

#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace sb {

StaticCollider StaticCollider::plane(const Vec3& point, const Vec3& normal, real friction, const std::string& name) {
    StaticCollider c;
    c.kind = Kind::Plane;
    c.name = name;
    c.point = point;
    c.normal = normalize(normal);
    c.friction = friction;
    return c;
}

StaticCollider StaticCollider::box(const Vec3& center, const Vec3& halfExtents, const Vec3& eulerRadians,
                                   real friction, const std::string& name) {
    StaticCollider c;
    c.kind = Kind::Box;
    c.name = name;
    c.center = center;
    c.halfExtents = halfExtents;
    c.eulerRadians = eulerRadians;
    c.rotation = Mat3::fromEuler(eulerRadians.x, eulerRadians.y, eulerRadians.z);
    c.invRotation = c.rotation.transposed();
    c.friction = friction;
    c.computeBounds();
    return c;
}

StaticCollider StaticCollider::heightfield(real originX, real originZ,
                                           real cellSizeX, real cellSizeZ,
                                           int nx, int nz,
                                           std::vector<real> heights,
                                           real friction,
                                           const std::string& name) {
    if (nx < 2 || nz < 2 || static_cast<int>(heights.size()) != nx * nz)
        throw std::invalid_argument("StaticCollider::heightfield: invalid dimensions");
    StaticCollider c;
    c.kind = Kind::Heightfield;
    c.name = name;
    c.originX = originX;
    c.originZ = originZ;
    c.cellSizeX = cellSizeX;
    c.cellSizeZ = cellSizeZ;
    c.nx = nx;
    c.nz = nz;
    c.heights = std::move(heights);
    c.friction = friction;
    c.computeBounds();
    return c;
}

void StaticCollider::computeBounds() {
    if (kind == Kind::Plane) {
        unbounded = true;
        return;
    }
    unbounded = false;
    if (kind == Kind::Heightfield) {
        real lo = kInf, hi = -kInf;
        for (real h : heights) {
            lo = std::min(lo, h);
            hi = std::max(hi, h);
        }
        boundsLo = {originX, lo - 1.0, originZ};
        boundsHi = {originX + (nx - 1) * cellSizeX, hi + 0.05, originZ + (nz - 1) * cellSizeZ};
        return;
    }
    Vec3 ext{0, 0, 0};
    for (int r = 0; r < 3; ++r)
        for (int k = 0; k < 3; ++k) ext[r] += std::abs(rotation.m[r][k]) * halfExtents[k];
    boundsLo = center - ext;
    boundsHi = center + ext;
}

real StaticCollider::sampleHeight(real x, real z, Vec3* outNormal) const {
    const real gx = std::clamp((x - originX) / cellSizeX, 0.0, static_cast<real>(nx - 1) - 1e-7);
    const real gz = std::clamp((z - originZ) / cellSizeZ, 0.0, static_cast<real>(nz - 1) - 1e-7);
    const int ix = std::clamp(static_cast<int>(gx), 0, nx - 2);
    const int iz = std::clamp(static_cast<int>(gz), 0, nz - 2);
    const real tx = gx - ix;
    const real tz = gz - iz;

    const auto at = [&](int i, int k) { return heights[static_cast<std::size_t>(i * nz + k)]; };
    const real h00 = at(ix, iz);
    const real h10 = at(ix + 1, iz);
    const real h01 = at(ix, iz + 1);
    const real h11 = at(ix + 1, iz + 1);

    const real h0 = h00 + tx * (h10 - h00);
    const real h1 = h01 + tx * (h11 - h01);
    const real h = h0 + tz * (h1 - h0);

    if (outNormal) {
        const real dhdx = ((1.0 - tz) * (h10 - h00) + tz * (h11 - h01)) / cellSizeX;
        const real dhdz = ((1.0 - tx) * (h01 - h00) + tx * (h11 - h10)) / cellSizeZ;
        *outNormal = normalize({-dhdx, 1.0, -dhdz});
    }
    return h;
}

bool StaticCollider::contact(const Vec3& p, Vec3& outNormal, real& outDepth) const {
    if (kind == Kind::Plane) {
        const real dist = dot(p - point, normal);
        if (dist >= 0) return false;
        outNormal = normal;
        outDepth = -dist;
        return true;
    }

    if (kind == Kind::Heightfield) {
        const real maxX = originX + (nx - 1) * cellSizeX;
        const real maxZ = originZ + (nz - 1) * cellSizeZ;
        if (p.x < originX || p.x > maxX || p.z < originZ || p.z > maxZ) return false;
        Vec3 n;
        const real h = sampleHeight(p.x, p.z, &n);
        if (p.y >= h) return false;
        outNormal = n;
        outDepth = (h - p.y) * n.y;
        return outDepth > 0;
    }

    const Vec3 local = invRotation * (p - center);
    real bestDepth = kInf;
    int bestAxis = -1;
    for (int axis = 0; axis < 3; ++axis) {
        const real depth = halfExtents[axis] - std::abs(local[axis]);
        if (depth <= 0) return false;  // outside along this axis
        if (depth < bestDepth) {
            bestDepth = depth;
            bestAxis = axis;
        }
    }
    Vec3 nLocal;
    nLocal[bestAxis] = local[bestAxis] >= 0 ? 1.0 : -1.0;
    outNormal = rotation * nLocal;
    outDepth = bestDepth;
    return true;
}

}  // namespace sb
