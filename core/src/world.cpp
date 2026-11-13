#include "sbcore/world.hpp"

#include "worker_pool.hpp"

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
constexpr real kHeavyBody = 600.0;   // kg: vehicles, as opposed to props (a felled log is 380 kg)
constexpr real kDeepContact = 0.01;  // m behind a face of another vehicle: interlocked structure
}  // namespace

void World::removeBody(std::size_t i) {
    if (i >= bodies_.size()) return;
    bodies_.erase(bodies_.begin() + static_cast<std::ptrdiff_t>(i));
    // Links to the removed body go with it; the others follow the index shift.
    std::vector<BodyLink> kept;
    for (BodyLink l : links_) {
        if (l.bodyA == i || l.bodyB == i) continue;
        if (l.bodyA > i) --l.bodyA;
        if (l.bodyB > i) --l.bodyB;
        kept.push_back(l);
    }
    links_.swap(kept);
}

void World::applyLinks() {
    // Serial, after the parallel integration: each link exchanges an equal and opposite impulse,
    // so momentum is conserved like in a beam, only across two bodies.
    const real dt = settings_.dt;
    for (BodyLink& l : links_) {
        if (l.broken || l.bodyA >= bodies_.size() || l.bodyB >= bodies_.size() || l.bodyA == l.bodyB) continue;
        SoftBody& a = bodies_[l.bodyA];
        SoftBody& b = bodies_[l.bodyB];
        if (l.nodeA >= a.nodeCount() || l.nodeB >= b.nodeCount()) continue;
        const Vec3 d = b.positions()[l.nodeB] - a.positions()[l.nodeA];
        const Vec3 dv = b.velocities()[l.nodeB] - a.velocities()[l.nodeA];
        const Vec3 f = d * l.stiffness + dv * l.damping;   // on A, towards B
        l.force = length(f);
        if (l.force > l.breakForce) {
            l.broken = true;
            continue;
        }
        const real ia = a.invMasses()[l.nodeA], ib = b.invMasses()[l.nodeB];
        a.velocities()[l.nodeA] += f * (dt * ia);
        b.velocities()[l.nodeB] -= f * (dt * ib);
        if (l.force > 1.0) {
            if (a.asleep()) a.wake();
            if (b.asleep()) b.wake();
        }
    }
}

real World::waterDepthAt(const Vec3& p) const {
    real depth = 0.0;
    for (const WaterVolume& w : waters_)
        if (p.x >= w.minX && p.x <= w.maxX && p.z >= w.minZ && p.z <= w.maxZ && p.y < w.surfaceY && p.y > w.bottomY)
            depth = std::max(depth, w.surfaceY - p.y);
    return depth;
}

// Water: each node carries a share of the body's displacement (by mass) and feels buoyancy as it
// goes under (over its first 15 cm, a node's "size"), plus drag that grows with the square of its
// speed through the water (the body's drag area shared out by volume) and a little linear damping. While a body sits in the water it floods:
// its displacement falls from the dry value to the flooded one over floodSeconds, and it sinks.
void World::accumulateWaterForces(SoftBody& b) {
    const auto& pos = b.positions();
    const auto& vel = b.velocities();
    const auto& mass = b.masses();
    auto& force = b.forces();
    auto& depth = b.waterDepths();
    depth.assign(pos.size(), 0.0);
    const real total = b.totalMass();
    if (total <= 0.0) return;
    const real dry = b.displacement() > 0.0 ? b.displacement() : total / 700.0;
    const real wet = b.floodedDisplacement() >= 0.0 ? b.floodedDisplacement() : dry;
    const real disp = dry + (wet - dry) * b.flooding();
    const real g = -settings_.gravity.y;
    real under = 0.0;
    for (std::size_t i = 0; i < pos.size(); ++i) {
        if (mass[i] <= 0.0) continue;
        real d = 0.0, rho = 1000.0;
        for (const WaterVolume& w : waters_)
            if (pos[i].x >= w.minX && pos[i].x <= w.maxX && pos[i].z >= w.minZ && pos[i].z <= w.maxZ &&
                pos[i].y < w.surfaceY && pos[i].y > w.bottomY && w.surfaceY - pos[i].y > d) {
                d = w.surfaceY - pos[i].y;
                rho = w.density;
            }
        if (d <= 0.0) continue;
        depth[i] = d;
        const real s = std::min<real>(1.0, d / 0.15);
        const real vol = disp * mass[i] / total;
        under += mass[i] * s;
        force[i].y += rho * g * vol * s;
        // Drag: 0.5 rho Cd A |v| v with A ~ vol^(2/3); limited so one step never reverses the node.
        const Vec3 v = vel[i];
        const real speed = length(v);
        // The body's drag area (~1.5 disp^(2/3), a blunt body) shared out by volume: summed over
        // the nodes it is the whole car's, not the far larger sum of each node's own cross-section.
        const real area = 1.5 * std::cbrt(disp * disp) * vol / disp;
        real k = 0.5 * rho * 1.0 * area * speed + 0.4 * mass[i];   // N per (m/s)
        k = std::min(k * s, 0.5 * mass[i] / settings_.dt);
        force[i] -= v * k;
    }
    const real frac = under / total;
    b.setSubmerged(frac);
    // Flooding: water gets in while a good part of the body is under, drains slowly when out.
    real f = b.flooding();
    if (frac > 0.25) f = std::min<real>(1.0, f + settings_.dt * frac / std::max<real>(b.floodSeconds(), 1.0));
    else if (frac < 0.02) f = std::max<real>(0.0, f - settings_.dt / 120.0);
    b.setFlooding(f);
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

std::size_t World::collideBody(SoftBody& b, std::vector<const StaticCollider*>& candidates_) {
    b.clearContacts();
    if (colliders_.empty()) return 0;
    auto& pos = b.positions();
    auto& vel = b.velocities();
    const auto& invMass = b.invMasses();
    const auto& friction = b.frictions();
    const auto& collision = b.collisionFlags();
    const auto& soft = b.contactStiffnesses();
    const auto& hold = b.positionHold();
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
                    // down hills at ~1.5 km/h. Only under a holding brake (see positionHold).
                    if (hold[i]) pos[i] -= vt * dt;
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

std::size_t World::collideNodeVsTriangles(SoftBody& nodeBody, SoftBody& triBody, const Vec3& triLo,
                                          const Vec3& triHi, bool heavyPair) {
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

    // Only nodes inside the other body's box can touch it. They go into a uniform grid sorted by
    // cell, so a triangle tests just the nodes of the cells around it instead of every node of
    // the body: two cars side by side or interlocked after a crash cost a few hundred tests per
    // triangle less, and a car whose torn-off parts lie far apart (a box kilometres wide) no
    // longer turns every pair into nodes x triangles. Nodes are tested per triangle in the same
    // triangle order as before, so the chosen contacts are exactly the same.
    std::vector<std::uint32_t>& list = contactNodes_;
    list.clear();
    Vec3 nodeLo{kInf, kInf, kInf}, nodeHi{-kInf, -kInf, -kInf};
    for (std::size_t i = 0; i < nPos.size(); ++i) {
        if (!nCol[i] || nInvM[i] == 0) continue;
        const Vec3 p = nPos[i];
        // Written so that a non-finite position fails it too (it must not reach the cell index).
        if (!(p.x >= triLo.x && p.x <= triHi.x && p.y >= triLo.y && p.y <= triHi.y && p.z >= triLo.z && p.z <= triHi.z))
            continue;
        list.push_back(static_cast<std::uint32_t>(i));
        nodeLo = {std::min(nodeLo.x, p.x), std::min(nodeLo.y, p.y), std::min(nodeLo.z, p.z)};
        nodeHi = {std::max(nodeHi.x, p.x), std::max(nodeHi.y, p.y), std::max(nodeHi.z, p.z)};
    }
    if (list.empty()) return 0;

    const Vec3 ext = nodeHi - nodeLo;
    const real cell = std::max<real>(0.3, std::max({ext.x, ext.y, ext.z}) / 1024.0);
    const real invCell = 1.0 / cell;
    const std::int64_t ny = static_cast<std::int64_t>(ext.y * invCell) + 1;
    const std::int64_t nz = static_cast<std::int64_t>(ext.z * invCell) + 1;
    const std::int64_t nx = static_cast<std::int64_t>(ext.x * invCell) + 1;
    auto cellOf = [&](real v, real lo, std::int64_t n) {
        return std::clamp<std::int64_t>(static_cast<std::int64_t>(std::floor((v - lo) * invCell)), 0, n - 1);
    };
    std::vector<std::pair<std::int64_t, std::uint32_t>>& grid = contactGrid_;
    grid.clear();
    for (const std::uint32_t i : list) {
        const Vec3 p = nPos[i];
        grid.push_back({(cellOf(p.x, nodeLo.x, nx) * ny + cellOf(p.y, nodeLo.y, ny)) * nz + cellOf(p.z, nodeLo.z, nz), i});
    }
    std::sort(grid.begin(), grid.end());

    // Gather the single best contact per node first. Applying every triangle in range lets two
    // faces of the other body that point towards each other (a crease, a pocket behind a fascia)
    // push a penetrated node back and forth and hold it: the cars hooked together and towed each
    // other. A node outside the surface beats one inside it; inside, the shallowest wins.
    using Candidate = BodyContactCandidate;
    std::vector<Candidate>& best = contactScratch_;
    if (best.size() < nPos.size()) best.resize(nPos.size());
    for (const std::uint32_t i : list) best[i] = Candidate{};
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

        auto test = [&](const std::uint32_t i) {
            const Vec3 p = nPos[i];
            if (p.x < tLo.x || p.x > tHi.x ||
                p.y < tLo.y || p.y > tHi.y ||
                p.z < tLo.z || p.z > tHi.z) {
                return;
            }

            const real dist = dot(p - pa, n);
            if (dist >= skin || dist < -maxDepth) return;
            if (best[i].valid && dist <= best[i].dist) return;

            // Project onto triangle plane and compute barycentric coordinates (w0, w1, w2).
            const Vec3 pProj = p - n * dist;
            const Vec3 v2 = pProj - pa;
            const real d20 = dot(v2, e0);
            const real d21 = dot(v2, e1);
            real w1 = (d11 * d20 - d01 * d21) * invDenom;
            real w2 = (d00 * d21 - d01 * d20) * invDenom;
            real w0 = 1.0 - w1 - w2;
            constexpr real kBaryTol = -0.04;
            if (w0 < kBaryTol || w1 < kBaryTol || w2 < kBaryTol) return;

            w0 = std::max<real>(0.0, w0);
            w1 = std::max<real>(0.0, w1);
            w2 = std::max<real>(0.0, w2);
            const real wSum = w0 + w1 + w2;
            if (wSum <= 0.0) return;

            const Vec3 vTri = (tVel[ia] * w0 + tVel[ib] * w1 + tVel[ic] * w2) / wSum;
            const real vn = dot(nVel[i] - vTri, n);
            // Ignore back-face encounters where the node is moving along +n from behind.
            if (dist < 0.0 && vn > 1.0) return;
            best[i] = {dist, n, ia, ib, ic, w0 / wSum, w1 / wSum, w2 / wSum, tri.friction, true};
        };
        const std::int64_t x0 = cellOf(tLo.x, nodeLo.x, nx), x1 = cellOf(tHi.x, nodeLo.x, nx);
        const std::int64_t y0 = cellOf(tLo.y, nodeLo.y, ny), y1 = cellOf(tHi.y, nodeLo.y, ny);
        const std::int64_t z0 = cellOf(tLo.z, nodeLo.z, nz), z1 = cellOf(tHi.z, nodeLo.z, nz);
        if ((x1 - x0 + 1) * (y1 - y0 + 1) > static_cast<std::int64_t>(list.size())) {
            for (const std::uint32_t i : list) test(i);   // a huge (torn, stretched) triangle
            continue;
        }
        for (std::int64_t x = x0; x <= x1; ++x)
            for (std::int64_t y = y0; y <= y1; ++y) {
                const std::int64_t col = (x * ny + y) * nz;
                auto it = std::lower_bound(grid.begin(), grid.end(), std::make_pair(col + z0, std::uint32_t{0}));
                for (; it != grid.end() && it->first <= col + z1; ++it) test(it->second);
            }
    }

    std::size_t contacts = 0;
    for (const std::uint32_t i : list) {
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
        // Between two vehicles, a node more than 1 cm inside the other is part of two crushed
        // structures pressed into each other, not a fresh touch: pushing it out by 2 cm every step
        // against both sets of beams pumped energy into them. Two crashed cars that stayed
        // interlocked gained ~1.5 MJ in ten seconds without any engine and finally flew apart at
        // 320 km/h, scattering parts. 2 mm per step lets them settle. Props (a cone squashed under
        // a bumper) keep the fast push-out, without which they wedge under the car.
        const real penetration = std::min(skin - c.dist, c.dist < -kDeepContact && heavyPair ? 0.002 : 0.02);
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
            // Geometric mean of the two surfaces (rubber 1.0 on PVC 0.2 -> 0.45, paint on paint
            // unchanged). The arithmetic mean gave rubber on a PVC cone 0.6: a cone the rear tyre
            // dragged up into the wheel arch self-locked between tread and body and braked the car
            // by up to 10 km/h (2 of 30 strike positions); now at most ~2 km/h, mean 0.9 -> 0.1.
            const real mu = std::sqrt(std::max<real>(0.0, nFric[i] * c.friction));
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
            const bool heavyPair = bodies_[i].totalMass() > kHeavyBody && bodies_[j].totalMass() > kHeavyBody;
            contacts += collideNodeVsTriangles(bodies_[i], bodies_[j], aabbLo_[j], aabbHi_[j], heavyPair);
            contacts += collideNodeVsTriangles(bodies_[j], bodies_[i], aabbLo_[i], aabbHi_[i], heavyPair);
        }
    }
    return contacts;
}

void World::step() {
    const Vec3 g = settings_.gravity;
    lastSelfContacts_ = lastSelfContactCandidates_ = 0;
    // Bodies only interact through collideBodies(): forces, integration, self-contact and the
    // static colliders of each body are independent and run in parallel. Every body is computed
    // exactly as in a serial step, so the result does not depend on the thread count.
    awakeStep_.clear();
    for (std::size_t i = 0; i < bodies_.size(); ++i)
        if (!bodies_[i].asleep()) awakeStep_.push_back(i);
    if (scratch_.size() < bodies_.size()) scratch_.resize(bodies_.size());
    auto dynamics = [&](std::size_t k) {
        const std::size_t bi = awakeStep_[k];
        SoftBody& b = bodies_[bi];
        BodyScratch& sc = scratch_[bi];
        auto& force = b.forces();
        const auto& mass = b.masses();
        const auto& invMass = b.invMasses();
        for (std::size_t i = 0; i < force.size(); ++i) force[i] = invMass[i] > 0 ? g * mass[i] : Vec3{};
        b.accumulateBeamForces(settings_.dt);
        accumulateAerodynamicForces(b);
        if (!waters_.empty()) accumulateWaterForces(b);
        const bool selfContact = std::any_of(b.selfCollisionPanels().begin(), b.selfCollisionPanels().end(),
                                            [&](const SelfCollisionPanel& p) { return b.selfCollisionActive(p); });
        if (selfContact) sc.selfContactPrevious = b.positions();
        integrateBody(b);
        sc.selfContacts = sc.selfCandidates = 0;
        if (selfContact) sc.selfContacts = collideSelfPanels(b, sc.selfContactPrevious, sc.selfCandidates);
    };
    detail::WorkerPool::instance().run(awakeStep_.size(), dynamics);
    for (std::size_t bi : awakeStep_) {
        lastSelfContacts_ += scratch_[bi].selfContacts;
        lastSelfContactCandidates_ += scratch_[bi].selfCandidates;
    }
    if (!links_.empty()) applyLinks();
    lastBodyContacts_ = collideBodies();
    // Bodies woken by a contact in collideBodies() take part from here on.
    awakeStep_.clear();
    for (std::size_t i = 0; i < bodies_.size(); ++i)
        if (!bodies_[i].asleep()) awakeStep_.push_back(i);
    auto statics = [&](std::size_t k) {
        const std::size_t bi = awakeStep_[k];
        SoftBody& b = bodies_[bi];
        scratch_[bi].contacts = collideBody(b, scratch_[bi].candidates);
        b.updateSleep(settings_.dt);
    };
    // Static collision is cheap per body; a second hand-off to the workers costs more than it saves.
    for (std::size_t k = 0; k < awakeStep_.size(); ++k) statics(k);
    std::size_t contacts = 0;
    for (std::size_t bi : awakeStep_) contacts += scratch_[bi].contacts;
    lastContacts_ = contacts;
    ++steps_;
}

void shutdownPhysicsThreads() { detail::WorkerPool::shutdown(); }

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
