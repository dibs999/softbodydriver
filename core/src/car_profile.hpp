// Internal: continuous exterior profile of a car body (shared by physics + visual generation).
// Coordinates: x from the rear bumper (0) to the front bumper (length), y up from the ground,
// z lateral (+z = right side of the car).
#pragma once

#include <algorithm>
#include <array>
#include <cmath>

#include "sbcore/car.hpp"

namespace sb::detail {

constexpr real kPi = 3.14159265358979323846;

inline real clamp01(real v) { return std::clamp<real>(v, 0.0, 1.0); }
inline real lerp(real a, real b, real t) { return a + (b - a) * t; }
inline real smoothstep(real e0, real e1, real x) {
    const real t = clamp01((x - e0) / (e1 - e0));
    return t * t * (3.0 - 2.0 * t);
}
/// Lowering of a surface near an edge, rounded with radius r (0 at distance >= r from the edge).
inline real edgeRound(real distToEdge, real r) {
    if (distToEdge >= r) return 0.0;
    const real d = r - std::max<real>(0.0, distToEdge);
    return r - std::sqrt(std::max<real>(0.0, r * r - d * d));
}

struct Section {
    // Half section (z >= 0), bottom centre -> top centre. See Profile::section().
    std::array<real, 11> z{}, y{};
};

struct Profile {
    const CarBodyDef& b;
    const TireDef& t;
    real L, hw, xFA, xRA, xCowl, xWsTop, xRwTop, xRwBase, xB, xFD0, xRD1, Ra, hubY;

    Profile(const CarBodyDef& body, const TireDef& tire) : b(body), t(tire) {
        L = b.length;
        hw = 0.5 * b.width;
        xFA = L - b.frontOverhang;
        xRA = xFA - b.wheelbase;
        xCowl = L - b.hoodLength;
        xWsTop = xCowl - b.windshieldRun;
        xRwTop = xWsTop - b.roofLength;
        xRwBase = std::max<real>(0.08, xRwTop - b.rearWindowRun);
        Ra = t.radius + b.archClearance;
        hubY = t.radius;
        // Door layout.
        xFD0 = xFA - Ra - 0.06;
        if (b.doors >= 4) {
            xRD1 = xRA + Ra + 0.05;
            xB = xRD1 + 0.52 * (xFD0 - xRD1);
        } else {
            xRD1 = xRA + Ra + 0.25;
            xB = xRD1 + 0.08;
        }
    }

    bool inGreenhouse(real x) const { return x > xRwBase && x < xCowl; }

    real yBottom(real x) const {
        const real gc = b.groundClearance;
        real y = gc;
        if (x > xFA) y += 0.11 * std::pow(clamp01((x - xFA) / (L - xFA)), 1.6);
        if (x < xRA) y += 0.15 * std::pow(clamp01((xRA - x) / xRA), 1.6);
        y += edgeRound(L - x, 0.07) + edgeRound(x, 0.07);
        return y;
    }

    real beltRear() const { return b.beltHeight + 0.035; }

    /// Height of the "shoulder" / deck line at the outer edge (hood, belt line, trunk).
    real yBelt(real x) const {
        real y;
        if (x >= xCowl) {
            const real tt = clamp01((L - x) / std::max<real>(0.05, L - xCowl));
            y = b.noseHeight + (b.hoodHeight - b.noseHeight) * std::pow(std::sin(tt * kPi * 0.5), 0.7);
        } else if (x >= xRwBase) {
            const real u = clamp01((xCowl - x) / std::max<real>(0.05, xCowl - xRwBase));
            y = b.hoodHeight + (beltRear() - b.hoodHeight) * std::pow(u, 0.55);
        } else {
            const real tt = clamp01(x / std::max<real>(0.05, xRwBase));
            y = b.tailHeight + (beltRear() - b.tailHeight) * std::pow(std::sin(tt * kPi * 0.5), 0.5);
        }
        y -= edgeRound(L - x, 0.11);
        y -= edgeRound(x, 0.08);
        return y;
    }

    /// Absolute height of the roof rail (top of the side glass) inside the greenhouse.
    real yRoofRail(real x) const {
        const real H = b.height - 0.035;
        const real y0c = yBelt(xCowl), y0r = yBelt(xRwBase);
        if (x >= xWsTop) {
            const real tt = clamp01((xCowl - x) / std::max<real>(0.05, xCowl - xWsTop));
            return y0c + (H - y0c) * (1.0 - std::pow(1.0 - tt, 1.35));
        }
        if (x >= xRwTop) {
            const real u = clamp01((x - xRwTop) / std::max<real>(0.05, xWsTop - xRwTop));
            return H + 0.012 * (1.0 - (2.0 * u - 1.0) * (2.0 * u - 1.0));
        }
        const real tt = clamp01((xRwTop - x) / std::max<real>(0.05, xRwTop - xRwBase));
        return H - (H - y0r) * std::pow(tt, 1.25);
    }

    real greenhouse(real x) const {
        if (!inGreenhouse(x)) return 0.0;
        return std::max<real>(0.0, yRoofRail(x) - yBelt(x));
    }

    real halfW(real x) const {
        real w = hw * (1.0 - 0.022 * clamp01((x - 0.5 * L) / (0.5 * L)));
        const real rf = b.cornerRadiusFront, rr = b.cornerRadiusRear;
        if (x > L - rf) {
            const real dx = x - (L - rf);
            w = w - rf + std::sqrt(std::max<real>(0.0, rf * rf - dx * dx));
        }
        if (x < rr) {
            const real dx = rr - x;
            w = w - rr + std::sqrt(std::max<real>(0.0, rr * rr - dx * dx));
        }
        return w;
    }

    real shoulderHalf(real x) const { return halfW(x) - 0.045; }

    real roofHalf(real x) const {
        const real rr = hw * b.roofWidthRatio;
        if (x >= xWsTop) {
            const real tt = clamp01((xCowl - x) / std::max<real>(0.05, xCowl - xWsTop));
            return lerp(shoulderHalf(xCowl) - 0.07, rr, std::pow(tt, 0.7));
        }
        if (x >= xRwTop) return rr;
        const real tt = clamp01((xRwTop - x) / std::max<real>(0.05, xRwTop - xRwBase));
        return lerp(rr, shoulderHalf(xRwBase) - 0.07, std::pow(tt, 1.2));
    }

    real trackAt(real x) const { return x > 0.5 * (xFA + xRA) ? b.trackFront : b.trackRear; }
    real zIn(real x) const { return 0.5 * trackAt(x) - 0.5 * t.width - 0.055; }

    /// Wheel arch top at x, or -1 if x is not inside an arch opening.
    real archY(real x) const {
        for (real xa : {xFA, xRA}) {
            const real dx = x - xa;
            if (std::abs(dx) < Ra) return hubY + std::sqrt(Ra * Ra - dx * dx);
        }
        return -1.0;
    }

    real ySill(real x) const { return yBottom(x) + 0.11; }

    Section section(real x) const {
        Section s;
        const real yB = yBottom(x);
        const real ys = ySill(x);
        const real yBe = yBelt(x);
        const real hW = halfW(x);
        const real sH = shoulderHalf(x);
        const real arch = archY(x);
        const bool inArch = arch > 0.0;
        const real ya = inArch ? arch : yB;
        const real zin = std::min(zIn(x), hW - 0.12);
        const real g = greenhouse(x);
        const real sg = smoothstep(0.0, 0.06, g);
        const real rr = inGreenhouse(x) ? roofHalf(x) : sH * 0.8;
        const real yMid = ys + 0.45 * (yBe - ys);

        s.z[0] = 0.0;            s.y[0] = yB;
        s.z[1] = zin;            s.y[1] = yB;
        s.z[2] = zin;            s.y[2] = ya;
        s.z[3] = inArch ? hW - 0.025 : hW - 0.07;  s.y[3] = ya;
        s.z[4] = hW - 0.015;     s.y[4] = std::max(ys, ya + 0.015);
        s.z[5] = hW;             s.y[5] = std::max(yMid, ya + 0.04);
        s.z[6] = sH;             s.y[6] = yBe;
        s.z[7] = sH - 0.025 - 0.02 * sg;  s.y[7] = yBe + 0.012;
        s.z[8] = lerp(sH * 0.80, rr, sg); s.y[8] = yBe + 0.012 + g;
        s.z[9] = lerp(sH * 0.42, rr * 0.55, sg);
        s.y[9] = s.y[8] + 0.024;
        s.z[10] = 0.0;           s.y[10] = s.y[8] + 0.036;
        // Keep the section monotonic in height above the rocker.
        for (int i = 5; i <= 10; ++i) s.y[i] = std::max(s.y[i], s.y[i - 1]);
        return s;
    }
};

/// Node indices of the generated rig (shared with the visual generator).
struct CarCorner {
    std::uint32_t hubIn = 0, hubOut = 0, lbj = 0, ubj = 0, steerArm = 0;
    std::uint32_t lowerF = 0, lowerR = 0, upperF = 0, upperR = 0, rackEnd = 0;
    std::uint32_t armMid = 0, tower = 0;  ///< armMid = lower coilover mount (on the knuckle at the LBJ)
    real motionRatio = 1.0;
    std::uint32_t arbEnd = 0, arbPivot = 0;
    bool front = false, right = false;
    real xAxle = 0;
};

struct CarRig {
    // Shell: per station, slot (0 rail, 1 sill, 2 mid, 3 belt, 4 top), side (0 = left/-z, 1 = right/+z)
    std::vector<real> stationX;
    std::vector<std::array<std::array<std::int64_t, 2>, 5>> shell;
    std::vector<std::uint32_t> bodyNodes;
    std::array<CarCorner, 4> corners;  // FL, FR, RL, RR
    std::vector<std::uint32_t> engine;   // 8 nodes: [x0/x1][y0/y1][z0/z1]
    std::vector<std::uint32_t> radiator; // 4 nodes
    std::vector<std::uint32_t> oilPan;   // 2
    std::vector<std::uint32_t> fuelTank; // 4
    std::int64_t diff = -1;
    std::uint32_t eyeNode = 0;
};

}  // namespace sb::detail
