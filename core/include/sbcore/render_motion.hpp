#pragma once

#include <algorithm>
#include <cmath>

#include "vec3.hpp"

namespace sb {

// Detect a teleport without mistaking ordinary high-speed travel at a low render
// rate for one. Physics continues at 2000 Hz even when rendering misses frames.
// A reset/repair is also signalled explicitly by SBVehicle.
inline bool visualMotionDiscontinuity(const Vec3& displacement, const Vec3& velocity, double frameSeconds) {
    if (!(frameSeconds > 0.0) || !std::isfinite(frameSeconds)) return true;
    const double expectedTravel = length(velocity) * frameSeconds;
    const double limit = 4.0 + expectedTravel * 1.5;
    return lengthSq(displacement) > limit * limit;
}

}  // namespace sb
