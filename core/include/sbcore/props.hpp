// Loose roadside props as small soft bodies: they are hit, tumble, slide and dent like the cars.
#pragma once

#include <string>
#include <vector>

#include "sbcore/softbody.hpp"

namespace sb {

enum class PropKind { Cone, Barrel, Barrier, Log, Bin, Beacon };

struct PropBuild {
    PropKind kind = PropKind::Cone;
    SoftBody body;
    /// Three nodes that define the prop's rigid frame for its visual (origin, x axis, y axis).
    std::uint32_t frameOrigin = 0, frameX = 0, frameY = 0;
    /// Optional second rigid part with its own frame (-1 = none), e.g. a beacon's panel that comes
    /// off its foot: the visual's "Sub" child follows it.
    std::int64_t subFrameOrigin = -1, subFrameX = -1, subFrameY = -1;
    std::vector<Vec3> restPositions;
};

/// Builds a prop standing on the ground at the origin (y = 0 bottom), upright along +y.
/// Cone: 0.75 m traffic cone, 4.5 kg, flexible PVC that springs back.
/// Barrel: 200 l steel drum, 0.58 m x 0.88 m, 20 kg empty, dents permanently.
/// Barrier: water-filled plastic roadworks barrier, 1.2 x 0.45 x 0.8 m, ~300 kg; it slides and
/// squashes, the shell deforms permanently (long axis along x).
/// Log: felled tree trunk, 3 m x 0.4 m, ~380 kg (long axis along x); rolls, can be climbed.
/// Bin: 240 l wheelie bin, 0.73 x 0.58 x 1.07 m, ~15 kg; dents.
/// Beacon: Leitbake (sign 605) on a rubber foot, 1.0 x 0.25 m panel, 28 kg foot 0.8 x 0.4 m; the
/// panel faces +x/-x (the approaching traffic when x points along the road), the foot runs along
/// z under it, parallel to the panel; the panel pops off its foot in a hard strike.
PropBuild buildProp(PropKind kind);
/// "cone" / "barrel" / "barrier" / "log" / "bin" / "beacon"; throws std::invalid_argument otherwise.
PropKind propKindFromString(const std::string& name);

}  // namespace sb
