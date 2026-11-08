#include "sbcore/wheel.hpp"

#include <algorithm>
#include <cmath>
#include <stdexcept>

#include "sbcore/softbody.hpp"

namespace sb {

namespace {
constexpr real kPi = 3.14159265358979323846;
constexpr real kPsiToPa = 6894.75729;
}  // namespace

Vec3 PressureWheel::axis(const SoftBody& body) const {
    const auto& pos = body.positions();
    return normalize(pos[spec.hubLeft] - pos[spec.hubRight]);
}

Vec3 PressureWheel::center(const SoftBody& body) const {
    const auto& pos = body.positions();
    return (pos[spec.hubLeft] + pos[spec.hubRight]) * 0.5;
}

real PressureWheel::measureAngularVelocity(const SoftBody& body, real* outInertia) const {
    const Vec3 a = axis(body);
    const Vec3 c = center(body);
    const auto& pos = body.positions();
    const auto& vel = body.velocities();
    const auto& mass = body.masses();
    const Vec3 vc = (vel[spec.hubLeft] + vel[spec.hubRight]) * 0.5;

    real num = 0.0, inertia = 0.0;
    for (std::uint32_t idx : treadNodes) {
        const Vec3 rel = pos[idx] - c;
        const Vec3 r = rel - a * dot(rel, a);
        const real r2 = lengthSq(r);
        const real m = mass[idx];
        num += m * dot(cross(r, vel[idx] - vc), a);
        inertia += m * r2;
    }
    if (outInertia) *outInertia = inertia;
    return inertia > 1e-6 ? num / inertia : 0.0;
}

void PressureWheel::step(SoftBody& body, real driveTorque, real brakeTorque, real dt) {
    // Check if any wheel beam broke -> tire deflates.
    if (!burst) {
        const auto& beams = body.beams();
        for (std::uint32_t bi : beamIndices) {
            if (beams[bi].broken) {
                burst = true;
                break;
            }
        }
    }

    const Vec3 a = axis(body);
    const Vec3 c = center(body);
    auto& force = body.forces();
    const auto& pos = body.positions();
    const auto& mass = body.masses();

    real inertia = 0.0;
    angularVelocity = measureAngularVelocity(body, &inertia);

    // Brake torque opposes current wheel rotation, bounded so it cannot reverse the wheel in one step.
    const real maxStopTorque = dt > 0 ? std::abs(angularVelocity) * inertia / dt : 0.0;
    const real clampedBrake = std::min( std::max<real>(0.0, brakeTorque), maxStopTorque);
    const real signedBrake = angularVelocity > 0 ? -clampedBrake : (angularVelocity < 0 ? clampedBrake : 0.0);
    const real totalTorque = driveTorque + signedBrake;
    lastDriveTorque = driveTorque;
    lastBrakeTorque = signedBrake;

    // Gauge air pressure force per tread node (if not punctured).
    // Precompression of the spoke beams already carries the static inflation tension;
    // this dynamic radial term increases stiffness with pressure and vanishes on a flat tire.
    const real pressurePa = (!burst && spec.pressurePsi > 0) ? spec.pressurePsi * kPsiToPa : 0.0;
    const real patchAreaPerNode = (2.0 * kPi * spec.radius * spec.width) / static_cast<real>(treadNodes.size());
    // Scaled so 32 PSI adds a realistic ~180 N outward radial preload per tread node.
    const real radialPressureForce = 0.02 * pressurePa * patchAreaPerNode;

    Vec3 sumForce{0, 0, 0};
    for (std::uint32_t idx : treadNodes) {
        const Vec3 rel = pos[idx] - c;
        const Vec3 r = rel - a * dot(rel, a);
        const real rl = length(r);
        if (rl < 1e-6) continue;
        const Vec3 rHat = r / rl;
        const Vec3 tHat = cross(a, rHat);  // tangential direction for +omega (forward roll)

        Vec3 f = rHat * radialPressureForce;
        if (inertia > 1e-6) {
            f += tHat * (totalTorque * (mass[idx] * rl) / inertia);
        }
        force[idx] += f;
        sumForce += f;
    }
    // Equal and opposite reaction on the spindle nodes -> exact linear momentum conservation.
    force[spec.hubLeft] -= sumForce * 0.5;
    force[spec.hubRight] -= sumForce * 0.5;
}

PressureWheel addPressureWheel(SoftBody& body, const PressureWheelSpec& spec) {
    if (spec.numRays < 6) throw std::invalid_argument("PressureWheel requires numRays >= 6");
    if (spec.hubLeft >= body.nodeCount() || spec.hubRight >= body.nodeCount() || spec.hubLeft == spec.hubRight)
        throw std::invalid_argument("PressureWheel: invalid hub node indices");

    PressureWheel w;
    w.spec = spec;
    const Vec3 c = w.center(body);
    const Vec3 a = w.axis(body);  // points toward -Z (left)

    // Orthonormal basis (u, v) in the wheel plane perpendicular to `a`.
    Vec3 ref = std::abs(a.y) < 0.9 ? Vec3{0, 1, 0} : Vec3{1, 0, 0};
    const Vec3 u = normalize(cross(ref, a));  // ~ +X
    const Vec3 v = cross(a, u);               // ~ +Y

    NodeParams np;
    np.mass = spec.tireMass / static_cast<real>(2 * spec.numRays);
    np.friction = spec.friction;
    np.collision = true;

    const int N = spec.numRays;
    w.treadNodes.reserve(static_cast<std::size_t>(2 * N));
    for (int ring = 0; ring < 2; ++ring) {
        // ring 0 = right (+width/2, i.e. -a), ring 1 = left (-width/2, i.e. +a)
        const real axial = (ring == 0 ? -0.5 : 0.5) * spec.width;
        const std::string side = ring == 0 ? "r" : "l";
        for (int i = 0; i < N; ++i) {
            const real angle = (2.0 * kPi * i) / static_cast<real>(N);
            const Vec3 p = c + a * axial + (u * std::cos(angle) + v * std::sin(angle)) * spec.radius;
            const std::string id = spec.name + "_" + side + std::to_string(i);
            w.treadNodes.push_back(body.addNode(id, p, np));
        }
    }

    auto nodeAt = [&](int ring, int i) {
        return w.treadNodes[static_cast<std::size_t>(ring * N + (i % N))];
    };
    auto addWheelBeam = [&](std::uint32_t n0, std::uint32_t n1, const BeamParams& bp) {
        w.beamIndices.push_back(body.addBeam(n0, n1, bp));
    };

    BeamParams spoke;
    spoke.spring = spec.spokeSpring;
    spoke.damp = spec.spokeDamp;
    spoke.deform = spec.deform;
    spoke.strength = spec.strength;
    spoke.deformLimit = 0.35;
    spoke.deformLimitExpansion = 0.25;
    spoke.precompression = 1.01;  // slight inflation preload

    BeamParams tread;
    tread.spring = spec.treadSpring;
    tread.damp = spec.treadDamp;
    tread.deform = spec.deform * 1.2;
    tread.strength = spec.strength;
    tread.deformLimit = 0.3;
    tread.deformLimitExpansion = 0.2;

    BeamParams belt = tread;
    belt.spring = spec.treadSpring * 0.65;
    belt.damp = spec.treadDamp * 0.7;

    for (int i = 0; i < N; ++i) {
        const std::uint32_t r0 = nodeAt(0, i), r1 = nodeAt(0, i + 1);
        const std::uint32_t l0 = nodeAt(1, i), l1 = nodeAt(1, i + 1);

        // Spokes from both rings to BOTH hub nodes -> locks axial & camber, free rotation around spindle!
        addWheelBeam(r0, spec.hubRight, spoke);
        addWheelBeam(r0, spec.hubLeft, spoke);
        addWheelBeam(l0, spec.hubLeft, spoke);
        addWheelBeam(l0, spec.hubRight, spoke);

        // Circumferential tread edges
        addWheelBeam(r0, r1, tread);
        addWheelBeam(l0, l1, tread);

        // Cross-tread width beam + X-diagonals on the tread surface
        addWheelBeam(r0, l0, tread);
        addWheelBeam(r0, l1, tread);
        addWheelBeam(l0, r1, tread);

        // Skip-2 chord beams (bending stiffness of the tire belt)
        addWheelBeam(r0, nodeAt(0, i + 2), belt);
        addWheelBeam(l0, nodeAt(1, i + 2), belt);
    }

    return w;
}

}  // namespace sb
