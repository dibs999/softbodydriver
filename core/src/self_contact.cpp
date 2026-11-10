#include "sbcore/world.hpp"

#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace sb {

void SoftBody::addSelfCollisionPanel(const std::string& panelGroup, const std::vector<std::string>& targetGroups,
                                     const std::vector<std::string>& releaseGroups, real skin) {
    const int panelId = findGroup(panelGroup);
    if (panelId < 0 || !(skin > 0.0) || !std::isfinite(skin))
        throw std::invalid_argument("invalid self-contact panel group or skin");
    std::vector<int> targets;
    for (const auto& name : targetGroups) {
        const int id = findGroup(name);
        if (id < 0 || id == panelId) throw std::invalid_argument("invalid self-contact target group");
        targets.push_back(id);
    }
    auto targetNode = [&](std::uint32_t n) {
        return std::find(targets.begin(), targets.end(), nodeGroup_[n]) != targets.end();
    };
    SelfCollisionPanel panel;
    panel.skin = skin;
    for (std::uint32_t n = 0; n < pos_.size(); ++n)
        if (nodeGroup_[n] == panelId) {
            panel.nodes.push_back(n);
            SelfCollisionPoint point;
            point.nodes = {n, n, n}; point.weights = {1.0, 0.0, 0.0};
            panel.points.push_back(point);
        }
    for (std::uint32_t t = 0; t < triangles_.size(); ++t) {
        const auto& tri = triangles_[t];
        if (tri.params.selfContact && targetNode(tri.a) && targetNode(tri.b) && targetNode(tri.c)) panel.triangles.push_back(t);
        // A broad bonnet can straddle the engine with all its corners outside
        // the block. Sample its face as well; distribute corrections/impulses
        // back to the three real nodes instead of inventing collision mass.
        if (nodeGroup_[tri.a] == panelId && nodeGroup_[tri.b] == panelId && nodeGroup_[tri.c] == panelId) {
            SelfCollisionPoint point;
            point.nodes = {tri.a, tri.b, tri.c}; point.weights = {1.0 / 3, 1.0 / 3, 1.0 / 3};
            point.triangle = static_cast<std::int32_t>(t);
            panel.points.push_back(point);
        }
    }
    if (panel.triangles.empty()) throw std::invalid_argument("self-contact target has no collision triangles");
    for (const auto& name : releaseGroups) {
        const auto it = std::find(breakGroupNames_.begin(), breakGroupNames_.end(), name);
        if (it == breakGroupNames_.end()) throw std::invalid_argument("unknown self-contact release group");
        const auto group = static_cast<std::size_t>(it - breakGroupNames_.begin());
        panel.releaseBeams.insert(panel.releaseBeams.end(), breakGroupMembers_[group].begin(), breakGroupMembers_[group].end());
    }
    // Include nearby nodes of a thin panel in its hinge exclusion, not just the
    // exact attached node. This prevents its upper skin fighting a lower hinge.
    const real jointRadius = std::max<real>(0.06, 3.0 * skin);
    for (std::uint32_t bi = 0; bi < beams_.size(); ++bi) {
        const auto& beam = beams_[bi];
        const bool aPanel = nodeGroup_[beam.a] == panelId, bPanel = nodeGroup_[beam.b] == panelId;
        if (aPanel == bPanel || !targetNode(aPanel ? beam.b : beam.a)) continue;
        const auto anchor = aPanel ? beam.a : beam.b;
        for (auto& point : panel.points) {
            Vec3 p;
            for (int j = 0; j < 3; ++j) p += pos_[point.nodes[j]] * point.weights[j];
            if (lengthSq(p - pos_[anchor]) <= jointRadius * jointRadius) point.jointBeams.push_back(bi);
        }
    }
    selfCollisionPanels_.push_back(std::move(panel));
}

bool SoftBody::selfCollisionActive(const SelfCollisionPanel& panel) const {
    return panel.releaseBeams.empty() || std::any_of(panel.releaseBeams.begin(), panel.releaseBeams.end(),
                                                    [&](std::uint32_t i) { return beams_[i].broken || beams_[i].disabled; });
}

namespace {
Vec3 lower(const Vec3& a, const Vec3& b) { return {std::min(a.x, b.x), std::min(a.y, b.y), std::min(a.z, b.z)}; }
Vec3 upper(const Vec3& a, const Vec3& b) { return {std::max(a.x, b.x), std::max(a.y, b.y), std::max(a.z, b.z)}; }
bool overlap(const Vec3& a, const Vec3& b, const Vec3& c, const Vec3& d) {
    return a.x <= d.x && b.x >= c.x && a.y <= d.y && b.y >= c.y && a.z <= d.z && b.z >= c.z;
}
bool barycentric(const Vec3& point, const Vec3& a, const Vec3& b, const Vec3& c, real& w0, real& w1, real& w2) {
    const Vec3 e0 = b - a, e1 = c - a, q = point - a;
    const real d00 = dot(e0, e0), d01 = dot(e0, e1), d11 = dot(e1, e1);
    const real denominator = d00 * d11 - d01 * d01;
    if (denominator < 1e-14) return false;
    w1 = (d11 * dot(q, e0) - d01 * dot(q, e1)) / denominator;
    w2 = (d00 * dot(q, e1) - d01 * dot(q, e0)) / denominator;
    w0 = 1.0 - w1 - w2;
    if (std::min({w0, w1, w2}) < -1e-5) return false;
    w0 = std::max<real>(0, w0); w1 = std::max<real>(0, w1); w2 = std::max<real>(0, w2);
    const real total = w0 + w1 + w2;
    w0 /= total; w1 /= total; w2 /= total;
    return true;
}
} // namespace

std::size_t World::collideSelfPanels(SoftBody& body, const std::vector<Vec3>& previous) {
    auto& pos = body.positions();
    auto& vel = body.velocities();
    const auto& inv = body.invMasses();
    std::size_t contacts = 0;
    for (const auto& panel : body.selfCollisionPanels()) {
        if (!body.selfCollisionActive(panel)) continue;
        const real skin = panel.skin;
        const Vec3 margin{skin, skin, skin};
        Vec3 panelLo = pos[panel.nodes.front()], panelHi = panelLo;
        for (auto n : panel.nodes) {
            panelLo = lower(panelLo, lower(previous[n], pos[n]));
            panelHi = upper(panelHi, upper(previous[n], pos[n]));
        }
        for (auto ti : panel.triangles) {
            const auto& tri = body.triangles()[ti];
            if (tri.broken) continue;
            const auto a = tri.a, b = tri.b, c = tri.c;
            const Vec3 triLo = lower(lower(lower(pos[a], pos[b]), pos[c]), lower(lower(previous[a], previous[b]), previous[c])) - margin;
            const Vec3 triHi = upper(upper(upper(pos[a], pos[b]), pos[c]), upper(upper(previous[a], previous[b]), previous[c])) + margin;
            if (!overlap(panelLo, panelHi, triLo, triHi)) continue;
            for (const auto& point : panel.points) {
                if (point.triangle >= 0 && body.triangles()[static_cast<std::size_t>(point.triangle)].broken) continue;
                ++lastSelfContactCandidates_;
                real inversePointMass = 0;
                Vec3 pointPos, pointPrevious, pointVelocity;
                bool collidable = false;
                for (int j = 0; j < 3; ++j) {
                    const auto n = point.nodes[j]; const real weight = point.weights[j];
                    inversePointMass += weight * weight * inv[n];
                    pointPos += pos[n] * weight; pointPrevious += previous[n] * weight; pointVelocity += vel[n] * weight;
                    collidable |= weight > 0 && body.collisionFlags()[n];
                }
                if (inversePointMass == 0 || !collidable) continue;
                bool joint = false;
                for (auto bi : point.jointBeams) {
                    const auto& beam = body.beams()[bi];
                    if (!beam.broken && !beam.disabled && (beam.a == a || beam.a == b || beam.a == c || beam.b == a || beam.b == b || beam.b == c)) {
                        joint = true; break;
                    }
                }
                if (joint || !overlap(lower(pointPrevious, pointPos), upper(pointPrevious, pointPos), triLo, triHi)) continue;
                const Vec3 crossNow = cross(pos[b] - pos[a], pos[c] - pos[a]);
                if (lengthSq(crossNow) < 1e-16) continue;
                const Vec3 normal = normalize(crossNow);
                const real distance = dot(pointPos - pos[a], normal);
                if (distance >= skin) continue;
                const Vec3 crossOld = cross(previous[b] - previous[a], previous[c] - previous[a]);
                const real oldDistance = dot(pointPrevious - previous[a], normalize(crossOld));
                const bool swept = oldDistance >= skin && distance < skin;
                if (!swept && distance < -std::max<real>(0.04, skin * 4.0)) continue;
                real w0, w1, w2;
                if (swept) {
                    // Sample the relative plane crossing, so a fast panel cannot
                    // tunnel through a thin roof between the two physics states.
                    const real t = std::clamp((oldDistance - skin) / (oldDistance - distance), 0.0, 1.0);
                    const auto at = [&](std::uint32_t i) { return previous[i] + (pos[i] - previous[i]) * t; };
                    if (!barycentric(pointPrevious + (pointPos - pointPrevious) * t, at(a), at(b), at(c), w0, w1, w2)) continue;
                } else if (!barycentric(pointPos, pos[a], pos[b], pos[c], w0, w1, w2)) continue;
                const real wTri = w0 * w0 * inv[a] + w1 * w1 * inv[b] + w2 * w2 * inv[c];
                const real effective = inversePointMass + wTri;
                if (effective <= 0) continue;
                const Vec3 relative = pointVelocity - (vel[a] * w0 + vel[b] * w1 + vel[c] * w2);
                const real vn = dot(relative, normal);
                // Ignore nodes exiting through the back of a folded surface.
                if (!swept && distance < 0 && vn > 0.0) continue;
                const Vec3 correction = normal * ((skin - distance) / effective);
                for (int j = 0; j < 3; ++j) pos[point.nodes[j]] += correction * (point.weights[j] * inv[point.nodes[j]]);
                pos[a] -= correction * (w0 * inv[a]);
                pos[b] -= correction * (w1 * inv[b]);
                pos[c] -= correction * (w2 * inv[c]);
                if (vn < 0.0) {
                    const real jn = -vn / effective; // Inelastic sheet-metal contact; no added bounce energy.
                    const Vec3 tangent = relative - normal * vn;
                    const real speed = length(tangent);
                    real pointFriction = 0;
                    for (int j = 0; j < 3; ++j) pointFriction += point.weights[j] * body.frictions()[point.nodes[j]];
                    const real mu = std::max<real>(0.0, 0.5 * (pointFriction + tri.friction));
                    const real jt = speed > 1e-10 ? std::min(mu * jn, speed / effective) : 0.0;
                    const Vec3 impulse = normal * jn - (speed > 1e-10 ? tangent * (jt / speed) : Vec3{});
                    for (int j = 0; j < 3; ++j) vel[point.nodes[j]] += impulse * (point.weights[j] * inv[point.nodes[j]]);
                    vel[a] -= impulse * (w0 * inv[a]);
                    vel[b] -= impulse * (w1 * inv[b]);
                    vel[c] -= impulse * (w2 * inv[c]);
                }
                ++contacts;
            }
        }
    }
    return contacts;
}

} // namespace sb
