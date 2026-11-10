// Loose roadside props as small soft bodies: they are hit, tumble, slide and dent like the cars.
#pragma once

#include <string>
#include <vector>

#include "sbcore/softbody.hpp"

namespace sb {

enum class PropKind { Cone, Barrel };

struct PropBuild {
    PropKind kind = PropKind::Cone;
    SoftBody body;
    /// Three nodes that define the prop's rigid frame for its visual (origin, x axis, y axis).
    std::uint32_t frameOrigin = 0, frameX = 0, frameY = 0;
    std::vector<Vec3> restPositions;
};

/// Builds a prop standing on the ground at the origin (y = 0 bottom), upright along +y.
/// Cone: 0.75 m traffic cone, 4.5 kg, flexible PVC that springs back.
/// Barrel: 200 l steel drum, 0.58 m x 0.88 m, 20 kg empty, dents permanently.
PropBuild buildProp(PropKind kind);
/// "cone" / "barrel"; throws std::invalid_argument for anything else.
PropKind propKindFromString(const std::string& name);

}  // namespace sb
