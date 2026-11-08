#include "sbcore/colliders.hpp"

#include <cmath>

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
    return c;
}

bool StaticCollider::contact(const Vec3& p, Vec3& outNormal, real& outDepth) const {
    if (kind == Kind::Plane) {
        const real dist = dot(p - point, normal);
        if (dist >= 0) return false;
        outNormal = normal;
        outDepth = -dist;
        return true;
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
