#include "sbcore/world.hpp"

#include <algorithm>
#include <cmath>

namespace sb {

std::size_t World::addBody(SoftBody body) {
    bodies_.push_back(std::move(body));
    return bodies_.size() - 1;
}

void World::integrateBody(SoftBody& b) {
    const real dt = settings_.dt;
    const real dragFactor = settings_.airDrag > 0 ? std::max<real>(0.0, 1.0 - settings_.airDrag * dt) : 1.0;
    auto& pos = b.positions();
    auto& vel = b.velocities();
    const auto& force = b.forces();
    const auto& invMass = b.invMasses();
    const std::size_t n = pos.size();

    // Semi-implicit (symplectic) Euler: velocity first, then position with the new velocity.
    for (std::size_t i = 0; i < n; ++i) {
        if (invMass[i] == 0) {
            vel[i] = {};
            continue;
        }
        vel[i] += force[i] * (invMass[i] * dt);
        if (dragFactor != 1.0) vel[i] *= dragFactor;
        pos[i] += vel[i] * dt;
    }
}

std::size_t World::collideBody(SoftBody& b) {
    if (colliders_.empty()) return 0;
    auto& pos = b.positions();
    auto& vel = b.velocities();
    const auto& invMass = b.invMasses();
    const auto& friction = b.frictions();
    const auto& collision = b.collisionFlags();
    std::size_t contacts = 0;

    for (std::size_t i = 0; i < pos.size(); ++i) {
        if (!collision[i] || invMass[i] == 0) continue;
        for (const StaticCollider& c : colliders_) {
            Vec3 n;
            real depth;
            if (!c.contact(pos[i], n, depth)) continue;
            ++contacts;
            // 1) Positional projection out of the collider.
            pos[i] += n * depth;
            // 2) Velocity: remove approaching normal velocity (optionally bounce),
            //    then Coulomb friction as a velocity-level impulse bounded by mu * normal impulse.
            const real vn = dot(vel[i], n);
            if (vn < 0) {
                vel[i] -= n * (vn * (1.0 + c.restitution));
                const real mu = friction[i] * c.friction;
                const Vec3 vt = vel[i] - n * dot(vel[i], n);
                const real vtLen = length(vt);
                const real maxDv = mu * (-vn);
                if (vtLen <= maxDv) vel[i] -= vt;            // static friction: stick
                else if (vtLen > 0) vel[i] -= vt * (maxDv / vtLen);  // kinetic friction: slide
            }
        }
    }
    return contacts;
}

void World::step() {
    const Vec3 g = settings_.gravity;
    std::size_t contacts = 0;
    // Bodies are independent until inter-body collision exists (phase 3), so this
    // loop is trivially parallelisable later (one thread per vehicle).
    for (SoftBody& b : bodies_) {
        auto& force = b.forces();
        const auto& mass = b.masses();
        const auto& invMass = b.invMasses();
        for (std::size_t i = 0; i < force.size(); ++i) force[i] = invMass[i] > 0 ? g * mass[i] : Vec3{};
        b.accumulateBeamForces(settings_.dt);
        integrateBody(b);
        contacts += collideBody(b);
    }
    lastContacts_ = contacts;
    ++steps_;
}

std::uint64_t World::simulate(real seconds) {
    const auto n = static_cast<std::uint64_t>(std::llround(seconds / settings_.dt));
    for (std::uint64_t i = 0; i < n; ++i) step();
    return n;
}

WorldStats World::stats() const {
    WorldStats s;
    s.time = time();
    s.steps = steps_;
    s.contacts = lastContacts_;
    for (const SoftBody& b : bodies_) {
        const BodyStats bs = b.stats();
        s.nodes += bs.nodes;
        s.beams += bs.beams;
        s.brokenBeams += bs.brokenBeams;
        s.deformedBeams += bs.deformedBeams;
        s.kineticEnergy += bs.kineticEnergy;
        s.elasticEnergy += bs.elasticEnergy;
        s.potentialEnergy += b.potentialEnergy(settings_.gravity);
        for (const Vec3& p : b.positions())
            if (!isFinite(p)) s.finite = false;
    }
    return s;
}

real World::worstStabilityRatio() const {
    real r = 0;
    for (const SoftBody& b : bodies_) r = std::max(r, b.stabilityRatio(settings_.dt));
    return r;
}

}  // namespace sb
