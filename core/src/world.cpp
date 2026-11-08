#include "sbcore/world.hpp"

#include <algorithm>
#include <cmath>

namespace sb {

std::size_t World::addBody(SoftBody body) {
    bodies_.push_back(std::move(body));
    return bodies_.size() - 1;
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
    const real maxDepth = settings_.colTriThickness;
    const real margin = std::max(skin, maxDepth);

    Vec3 nodeLo, nodeHi;
    nodeBody.aabb(nodeLo, nodeHi);

    std::size_t contacts = 0;
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
            w0 /= wSum;
            w1 /= wSum;
            w2 /= wSum;

            const Vec3 vTri = tVel[ia] * w0 + tVel[ib] * w1 + tVel[ic] * w2;
            const Vec3 vRel = nVel[i] - vTri;
            const real vn = dot(vRel, n);
            // Ignore back-face encounters where the node is moving along +n from behind.
            if (dist < 0.0 && vn > 1.0) continue;

            const real wp = nInvM[i];
            const real wa = tInvM[ia], wb = tInvM[ib], wc = tInvM[ic];
            const real wTri = w0 * w0 * wa + w1 * w1 * wb + w2 * w2 * wc;
            const real wTotal = wp + wTri;
            if (wTotal <= 0.0) continue;

            const real penetration = skin - dist;
            const Vec3 corr = n * (penetration / wTotal);
            nPos[i] += corr * wp;
            tPos[ia] -= corr * (w0 * wa);
            tPos[ib] -= corr * (w1 * wb);
            tPos[ic] -= corr * (w2 * wc);
            ++contacts;

            if (vn < 0.0) {
                constexpr real kRestitution = 0.05;
                const real jn = -(1.0 + kRestitution) * vn / wTotal;
                const Vec3 vt = vRel - n * vn;
                const real vtLen = length(vt);
                const real mu = 0.5 * (nFric[i] + tri.friction);
                const real jt = vtLen > 1e-9 ? std::min(mu * jn, vtLen / wTotal) : 0.0;
                const Vec3 vtDir = vtLen > 1e-9 ? (vt / vtLen) : Vec3{};
                const Vec3 impulse = n * jn - vtDir * jt;

                nVel[i] += impulse * wp;
                tVel[ia] -= impulse * (w0 * wa);
                tVel[ib] -= impulse * (w1 * wb);
                tVel[ic] -= impulse * (w2 * wc);
            }
        }
    }
    return contacts;
}

std::size_t World::collideBodies() {
    const std::size_t nb = bodies_.size();
    if (nb < 2) return 0;

    const real margin = std::max(settings_.colTriSkin, settings_.colTriThickness);
    std::vector<Vec3> lo(nb), hi(nb);
    for (std::size_t i = 0; i < nb; ++i) {
        bodies_[i].aabb(lo[i], hi[i]);
        lo[i] -= Vec3{margin, margin, margin};
        hi[i] += Vec3{margin, margin, margin};
    }

    std::size_t contacts = 0;
    for (std::size_t i = 0; i < nb; ++i) {
        for (std::size_t j = i + 1; j < nb; ++j) {
            if (hi[i].x < lo[j].x || lo[i].x > hi[j].x ||
                hi[i].y < lo[j].y || lo[i].y > hi[j].y ||
                hi[i].z < lo[j].z || lo[i].z > hi[j].z) {
                continue;
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
    for (SoftBody& b : bodies_) {
        auto& force = b.forces();
        const auto& mass = b.masses();
        const auto& invMass = b.invMasses();
        for (std::size_t i = 0; i < force.size(); ++i) force[i] = invMass[i] > 0 ? g * mass[i] : Vec3{};
        b.accumulateBeamForces(settings_.dt);
        accumulateAerodynamicForces(b);
        integrateBody(b);
    }
    lastBodyContacts_ = collideBodies();
    for (SoftBody& b : bodies_) {
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
    s.bodyContacts = lastBodyContacts_;
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
