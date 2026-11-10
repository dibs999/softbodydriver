#include "sbcore/world.hpp"

#include <algorithm>
#include <cmath>

namespace sb {

std::size_t World::addBody(SoftBody body) {
    bodies_.push_back(std::move(body));
    return bodies_.size() - 1;
}

namespace {
constexpr real kSoftContactMaxDepth = 0.02;   // beyond this the rubber is "bottomed": rigid stop
constexpr real kSoftContactDampingRatio = 0.02; // rubber loss lives in the tyre beams
}  // namespace

void World::removeBody(std::size_t i) {
    if (i < bodies_.size()) bodies_.erase(bodies_.begin() + static_cast<std::ptrdiff_t>(i));
}

void World::accumulateAerodynamicForces(SoftBody& b) {
    if (settings_.airDensity <= 0.0 || b.triangleCount() == 0) return;
    const auto& pos = b.positions();
    const auto& vel = b.velocities();
    auto& force = b.forces();
    const real rho = settings_.airDensity;

    for (const ColTri& tri : b.triangles()) {
        if (tri.broken || tri.dragCoef <= 0.0) continue;
        const Vec3& pa = pos[tri.a];
        const Vec3& pb = pos[tri.b];
        const Vec3& pc = pos[tri.c];
        const Vec3 crossVec = cross(pb - pa, pc - pa);
        const real doubleArea = length(crossVec);
        if (doubleArea < 1e-8) continue;
        const Vec3 n = crossVec / doubleArea;
        const real area = 0.5 * doubleArea;

        const Vec3 vTri = (vel[tri.a] + vel[tri.b] + vel[tri.c]) * (1.0 / 3.0);
        const real speed = length(vTri);
        if (speed < 0.1) continue;

        const real vn = dot(vTri, n);
        // Normal pressure drag/lift + small tangential skin friction; strictly dissipative.
        const Vec3 fNormal = -n * (0.5 * rho * tri.dragCoef * area * speed * vn);
        const Vec3 fSkin = -vTri * (0.015 * rho * tri.dragCoef * area * speed);
        const Vec3 fNode = (fNormal + fSkin) * (1.0 / 3.0);
        force[tri.a] += fNode;
        force[tri.b] += fNode;
        force[tri.c] += fNode;
    }
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
    b.clearContacts();
    if (colliders_.empty()) return 0;
    auto& pos = b.positions();
    auto& vel = b.velocities();
    const auto& invMass = b.invMasses();
    const auto& friction = b.frictions();
    const auto& collision = b.collisionFlags();
    const auto& soft = b.contactStiffnesses();
    const real dt = settings_.dt;
    std::size_t contacts = 0;

    // Broadphase: only colliders whose bounds overlap the body's bounds.
    Vec3 lo, hi;
    b.aabb(lo, hi);
    const Vec3 margin{0.1, 0.1, 0.1};
    lo -= margin;
    hi += margin;
    candidates_.clear();
    for (const StaticCollider& c : colliders_) {
        if (!c.unbounded &&
            (c.boundsHi.x < lo.x || c.boundsLo.x > hi.x || c.boundsHi.y < lo.y || c.boundsLo.y > hi.y ||
             c.boundsHi.z < lo.z || c.boundsLo.z > hi.z))
            continue;
        candidates_.push_back(&c);
    }
    if (candidates_.empty()) return 0;

    for (std::size_t i = 0; i < pos.size(); ++i) {
        if (!collision[i] || invMass[i] == 0) continue;
        for (const StaticCollider* cp : candidates_) {
            const StaticCollider& c = *cp;
            if (!c.unbounded && (pos[i].x < c.boundsLo.x || pos[i].x > c.boundsHi.x || pos[i].y < c.boundsLo.y ||
                                 pos[i].y > c.boundsHi.y || pos[i].z < c.boundsLo.z || pos[i].z > c.boundsHi.z))
                continue;
            Vec3 n;
            real depth;
            if (!c.contact(pos[i], n, depth)) continue;
            ++contacts;
            const real mu = friction[i] * c.friction;
            if (soft[i] > 0.0) {
                // Compliant tread rubber: spring-damper normal force, rigid stop beyond kSoftContactMaxDepth.
                const real m = 1.0 / invMass[i];
                const real k = soft[i];
                const real maxDepth = kSoftContactMaxDepth;
                real d = depth;
                real stopDv = 0.0;
                if (d > maxDepth) {
                    pos[i] += n * (d - maxDepth);
                    d = maxDepth;
                    const real vIn = dot(vel[i], n);
                    if (vIn < 0) {
                        vel[i] -= n * vIn;
                        stopDv = -vIn;
                        b.addContact(i, n * (stopDv * m));
                    }
                }
                const real vn = dot(vel[i], n);
                const real cDamp = 2.0 * kSoftContactDampingRatio * std::sqrt(k * m);
                const real fN = std::max<real>(0.0, k * d - cDamp * vn);
                const real dvN = fN * dt * invMass[i];
                vel[i] += n * dvN;
                b.addContact(i, n * (dvN * m));
                const Vec3 vt = vel[i] - n * dot(vel[i], n);
                const real vtLen = length(vt);
                const real maxDv = mu * (dvN + stopDv);
                if (vtLen <= maxDv) {
                    vel[i] -= vt;
                    // Static friction holds the position too: the step already moved the node by
                    // vt * dt before the friction saw it, and that drift made braked cars creep
                    // down hills at ~1.5 km/h.
                    pos[i] -= vt * dt;
                }
                else if (vtLen > 0) vel[i] -= vt * (maxDv / vtLen);
                continue;
            }
            // 1) Positional projection out of the collider.
            pos[i] += n * depth;
            // 2) Velocity: remove approaching normal velocity (optionally bounce),
            //    then Coulomb friction as a velocity-level impulse bounded by mu * normal impulse.
            const real vn = dot(vel[i], n);
            if (vn < 0) {
                b.addContact(i, n * (-vn / invMass[i]));
                vel[i] -= n * (vn * (1.0 + c.restitution));
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

std::size_t World::collideNodeVsTriangles(SoftBody& nodeBody, SoftBody& triBody) {
    if (triBody.triangleCount() == 0 || nodeBody.nodeCount() == 0) return 0;

    auto& nPos = nodeBody.positions();
    auto& nVel = nodeBody.velocities();
    const auto& nInvM = nodeBody.invMasses();
    const auto& nFric = nodeBody.frictions();
    const auto& nCol = nodeBody.collisionFlags();

    auto& tPos = triBody.positions();
    auto& tVel = triBody.velocities();
    const auto& tInvM = triBody.invMasses();

    const real skin = settings_.colTriSkin;
    const real maxDepth = triBody.contactThickness() > 0.0 ? std::min(settings_.colTriThickness, triBody.contactThickness())
                                                          : settings_.colTriThickness;
    const real margin = std::max(skin, maxDepth);

    Vec3 nodeLo, nodeHi;
    nodeBody.aabb(nodeLo, nodeHi);

    // Gather the single best contact per node first. Applying every triangle in range lets two
    // faces of the other body that point towards each other (a crease, a pocket behind a fascia)
    // push a penetrated node back and forth and hold it: the cars hooked together and towed each
    // other. A node outside the surface beats one inside it; inside, the shallowest wins.
    using Candidate = BodyContactCandidate;
    std::vector<Candidate>& best = contactScratch_;
    best.assign(nPos.size(), Candidate{});
    for (const ColTri& tri : triBody.triangles()) {
        if (tri.broken) continue;
        const std::uint32_t ia = tri.a, ib = tri.b, ic = tri.c;
        const Vec3 pa = tPos[ia], pb = tPos[ib], pc = tPos[ic];

        const Vec3 tLo{std::min({pa.x, pb.x, pc.x}) - margin,
                       std::min({pa.y, pb.y, pc.y}) - margin,
                       std::min({pa.z, pb.z, pc.z}) - margin};
        const Vec3 tHi{std::max({pa.x, pb.x, pc.x}) + margin,
                       std::max({pa.y, pb.y, pc.y}) + margin,
                       std::max({pa.z, pb.z, pc.z}) + margin};
        if (tHi.x < nodeLo.x || tLo.x > nodeHi.x ||
            tHi.y < nodeLo.y || tLo.y > nodeHi.y ||
            tHi.z < nodeLo.z || tLo.z > nodeHi.z) {
            continue;
        }

        const Vec3 e0 = pb - pa;
        const Vec3 e1 = pc - pa;
        const Vec3 crossVec = cross(e0, e1);
        const real lenN = length(crossVec);
        if (lenN < 1e-9) continue;
        const Vec3 n = crossVec / lenN;
        if (triBody.downFacesPassive() && n.y < -0.7) continue;

        const real d00 = dot(e0, e0);
        const real d01 = dot(e0, e1);
        const real d11 = dot(e1, e1);
        const real denom = d00 * d11 - d01 * d01;
        if (std::abs(denom) < 1e-12) continue;
        const real invDenom = 1.0 / denom;

        for (std::size_t i = 0; i < nPos.size(); ++i) {
            if (!nCol[i] || nInvM[i] == 0) continue;
            const Vec3 p = nPos[i];
            if (p.x < tLo.x || p.x > tHi.x ||
                p.y < tLo.y || p.y > tHi.y ||
                p.z < tLo.z || p.z > tHi.z) {
                continue;
            }

            const real dist = dot(p - pa, n);
            if (dist >= skin || dist < -maxDepth) continue;
            if (best[i].valid && dist <= best[i].dist) continue;

            // Project onto triangle plane and compute barycentric coordinates (w0, w1, w2).
            const Vec3 pProj = p - n * dist;
            const Vec3 v2 = pProj - pa;
            const real d20 = dot(v2, e0);
            const real d21 = dot(v2, e1);
            real w1 = (d11 * d20 - d01 * d21) * invDenom;
            real w2 = (d00 * d21 - d01 * d20) * invDenom;
            real w0 = 1.0 - w1 - w2;
            constexpr real kBaryTol = -0.04;
            if (w0 < kBaryTol || w1 < kBaryTol || w2 < kBaryTol) continue;

            w0 = std::max<real>(0.0, w0);
            w1 = std::max<real>(0.0, w1);
            w2 = std::max<real>(0.0, w2);
            const real wSum = w0 + w1 + w2;
            if (wSum <= 0.0) continue;

            const Vec3 vTri = (tVel[ia] * w0 + tVel[ib] * w1 + tVel[ic] * w2) / wSum;
            const real vn = dot(nVel[i] - vTri, n);
            // Ignore back-face encounters where the node is moving along +n from behind.
            if (dist < 0.0 && vn > 1.0) continue;
            best[i] = {dist, n, ia, ib, ic, w0 / wSum, w1 / wSum, w2 / wSum, tri.friction, true};
        }
    }

    std::size_t contacts = 0;
    for (std::size_t i = 0; i < nPos.size(); ++i) {
        const Candidate& c = best[i];
        if (!c.valid) continue;
        const Vec3 n = c.n;
        const std::uint32_t ia = c.a, ib = c.b, ic = c.c;
        const real w0 = c.w0, w1 = c.w1, w2 = c.w2;
        const real wp = nInvM[i];
        const real wa = tInvM[ia], wb = tInvM[ib], wc = tInvM[ic];
        const real wTri = w0 * w0 * wa + w1 * w1 * wb + w2 * w2 * wc;
        const real wTotal = wp + wTri;
        if (wTotal <= 0.0) continue;

        // Resolve deep penetration over a few steps rather than at once: a heavy car node sunk
        // into a light prop would otherwise shove the prop's nodes ~15 cm in one 0.5 ms step and
        // its beams would fling it away. The impulse below still removes the approach speed.
        const real penetration = std::min(skin - c.dist, 0.02);
        const Vec3 corr = n * (penetration / wTotal);
        nPos[i] += corr * wp;
        tPos[ia] -= corr * (w0 * wa);
        tPos[ib] -= corr * (w1 * wb);
        tPos[ic] -= corr * (w2 * wc);
        ++contacts;

        const Vec3 vTri = tVel[ia] * w0 + tVel[ib] * w1 + tVel[ic] * w2;
        const Vec3 vRel = nVel[i] - vTri;
        const real vn = dot(vRel, n);
        if (vn < 0.0) {
            constexpr real kRestitution = 0.05;
            const real jn = -(1.0 + kRestitution) * vn / wTotal;
            const Vec3 vt = vRel - n * vn;
            const real vtLen = length(vt);
            const real mu = 0.5 * (nFric[i] + c.friction);
            const real jt = vtLen > 1e-9 ? std::min(mu * jn, vtLen / wTotal) : 0.0;
            const Vec3 vtDir = vtLen > 1e-9 ? (vt / vtLen) : Vec3{};
            const Vec3 impulse = n * jn - vtDir * jt;

            nVel[i] += impulse * wp;
            tVel[ia] -= impulse * (w0 * wa);
            tVel[ib] -= impulse * (w1 * wb);
            tVel[ic] -= impulse * (w2 * wc);
        }
    }
    return contacts;
}

std::size_t World::collideBodies() {
    const std::size_t nb = bodies_.size();
    if (nb < 2) return 0;

    const real margin = std::max(settings_.colTriSkin, settings_.colTriThickness);
    aabbLo_.resize(nb);
    aabbHi_.resize(nb);
    awake_.clear();
    for (std::size_t i = 0; i < nb; ++i) {
        // A sleeping body does not move: its box from the step it fell asleep stays valid.
        if (bodies_[i].asleep() && sleptBox_.size() == nb && sleptBox_[i]) continue;
        bodies_[i].aabb(aabbLo_[i], aabbHi_[i]);
        aabbLo_[i] -= Vec3{margin, margin, margin};
        aabbHi_[i] += Vec3{margin, margin, margin};
        if (!bodies_[i].asleep()) awake_.push_back(i);
    }
    sleptBox_.assign(nb, 0);
    for (std::size_t i = 0; i < nb; ++i) sleptBox_[i] = bodies_[i].asleep() ? 1 : 0;

    // Pairs with at least one awake body only: dozens of resting props cost nothing.
    std::size_t contacts = 0;
    for (const std::size_t i : awake_) {
        for (std::size_t j = 0; j < nb; ++j) {
            if (j == i || (!bodies_[j].asleep() && j < i)) continue;   // awake pairs once
            // A resting body sleeps through contact with another resting one; only something
            // actually moving wakes it.
            const bool jSleep = bodies_[j].asleep();
            if (jSleep && bodies_[i].maxNodeSpeed() < 0.05) continue;
            if (aabbHi_[i].x < aabbLo_[j].x || aabbLo_[i].x > aabbHi_[j].x ||
                aabbHi_[i].y < aabbLo_[j].y || aabbLo_[i].y > aabbHi_[j].y ||
                aabbHi_[i].z < aabbLo_[j].z || aabbLo_[i].z > aabbHi_[j].z) {
                continue;
            }
            // Something moving reached a resting body: it takes part again from this contact on.
            if (jSleep) {
                bodies_[j].wake();
                sleptBox_[j] = 0;
            }
            contacts += collideNodeVsTriangles(bodies_[i], bodies_[j]);
            contacts += collideNodeVsTriangles(bodies_[j], bodies_[i]);
        }
    }
    return contacts;
}

void World::step() {
    const Vec3 g = settings_.gravity;
    std::size_t contacts = 0;
    lastSelfContacts_ = lastSelfContactCandidates_ = 0;
    for (SoftBody& b : bodies_) {
        if (b.asleep()) continue;
        auto& force = b.forces();
        const auto& mass = b.masses();
        const auto& invMass = b.invMasses();
        for (std::size_t i = 0; i < force.size(); ++i) force[i] = invMass[i] > 0 ? g * mass[i] : Vec3{};
        b.accumulateBeamForces(settings_.dt);
        accumulateAerodynamicForces(b);
        const bool selfContact = std::any_of(b.selfCollisionPanels().begin(), b.selfCollisionPanels().end(),
                                            [&](const SelfCollisionPanel& p) { return b.selfCollisionActive(p); });
        if (selfContact) selfContactPrevious_ = b.positions();
        integrateBody(b);
        if (selfContact) lastSelfContacts_ += collideSelfPanels(b, selfContactPrevious_);
    }
    lastBodyContacts_ = collideBodies();
    for (SoftBody& b : bodies_) {
        if (b.asleep()) continue;
        contacts += collideBody(b);
        b.updateSleep(settings_.dt);
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
    s.bodyContacts = lastBodyContacts_;
    s.selfContacts = lastSelfContacts_;
    s.selfContactCandidates = lastSelfContactCandidates_;
    for (const SoftBody& b : bodies_) {
        const BodyStats bs = b.stats();
        s.nodes += bs.nodes;
        s.beams += bs.beams;
        s.brokenBeams += bs.brokenBeams;
        s.deformedBeams += bs.deformedBeams;
        s.triangles += bs.triangles;
        s.brokenTriangles += bs.brokenTriangles;
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
