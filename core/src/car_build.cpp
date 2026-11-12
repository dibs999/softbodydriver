#include <array>
// Physical (node-beam) part of the realistic car generator. See car.hpp.
#include <algorithm>
#include <cmath>
#include <map>
#include <stdexcept>

#include "car_profile.hpp"
#include "sbcore/car.hpp"

namespace sb {

using namespace detail;

void buildCarVisual(CarBuild& build, const Profile& prof, const CarRig& rig);

namespace {

BeamParams makeBeam(real spring, real damp, real deform, real strength) {
    BeamParams p;
    p.spring = spring;
    p.damp = damp;
    p.deform = deform;
    p.strength = strength;
    return p;
}

std::vector<std::uint32_t> nearestNodes(const SoftBody& body, const std::vector<std::uint32_t>& candidates,
                                        const Vec3& p, std::size_t k, real maxDist = 1e9) {
    std::vector<std::pair<real, std::uint32_t>> d;
    d.reserve(candidates.size());
    for (std::uint32_t c : candidates) {
        const real dist = length(body.positions()[c] - p);
        if (dist > 1e-4 && dist < maxDist) d.push_back({dist, c});
    }
    std::sort(d.begin(), d.end());
    std::vector<std::uint32_t> out;
    for (std::size_t i = 0; i < d.size() && i < k; ++i) out.push_back(d[i].second);
    return out;
}

void connectAll(SoftBody& body, const std::vector<std::uint32_t>& nodes, const BeamParams& p,
                std::vector<std::uint32_t>* out) {
    for (std::size_t i = 0; i < nodes.size(); ++i)
        for (std::size_t j = i + 1; j < nodes.size(); ++j) {
            const auto bi = body.addBeam(nodes[i], nodes[j], p);
            if (out) out->push_back(bi);
        }
}

}  // namespace

CarBuild buildCar(const CarDefinition& def) {
    CarBuild build;
    build.def = def;
    SoftBody& car = build.body;
    car.setName(def.id);
    const CarBodyDef& bd = def.body;
    const Profile prof(bd, def.tires);
    CarRig rig;

    const real L = prof.L;
    const real stiff = def.chassis.bodyStiffness;
    const real strong = def.chassis.bodyStrength;

    // ------------------------------------------------------------------ stations
    std::vector<real> keys = {0.03, L - 0.03,
                              prof.xRA - prof.Ra - 0.03, prof.xRA, prof.xRA + prof.Ra + 0.03,
                              prof.xFA - prof.Ra - 0.03, prof.xFA, prof.xFA + prof.Ra + 0.03,
                              prof.xCowl, prof.xWsTop, prof.xRwTop, prof.xRwBase, prof.xB};
    std::sort(keys.begin(), keys.end());
    std::vector<real> st;
    for (real k : keys) {
        if (k < 0.03 || k > L - 0.03) continue;
        if (!st.empty() && k - st.back() < 0.16) {
            // Merge: prefer the structurally important one (axles / glass breaks) by averaging.
            st.back() = 0.5 * (st.back() + k);
            continue;
        }
        st.push_back(k);
    }
    st.front() = 0.03;
    st.back() = L - 0.03;
    std::vector<real> stations;
    for (std::size_t i = 0; i + 1 < st.size(); ++i) {
        stations.push_back(st[i]);
        const real gap = st[i + 1] - st[i];
        const int extra = static_cast<int>(std::floor(gap / 0.40));
        for (int e = 1; e <= extra; ++e) stations.push_back(st[i] + gap * e / (extra + 1));
    }
    stations.push_back(st.back());
    if (bd.detachableDoors) {
        // Collision skin must end at the actual aperture, not bridge across it
        // from coarse neighbouring stations and obstruct a closing door.
        std::vector<real> boundaries = {prof.xDoorFR - 0.029, prof.xDoorFF + 0.03};
        if (bd.doors >= 4 && bd.detachableRearDoors) boundaries.push_back(prof.xDoorRR - 0.029);
        for (real boundary : boundaries) {
            stations.erase(std::remove_if(stations.begin(), stations.end(),
                [&](real x) { return std::abs(x - boundary) < 0.08; }), stations.end());
            stations.push_back(boundary);
        }
        std::sort(stations.begin(), stations.end());
    }
    rig.stationX = stations;
    const std::size_t NS = stations.size();

    // ------------------------------------------------------------------ shell nodes
    rig.shell.assign(NS, {});
    for (auto& s : rig.shell)
        for (auto& slot : s) slot = {-1, -1};

    const char* slotNames[5] = {"rail", "sill", "mid", "belt", "top"};
    std::vector<real> nodeWeight;  // for mass distribution
    for (std::size_t i = 0; i < NS; ++i) {
        const real x = stations[i];
        const Section sec = prof.section(x);
        const real hW = prof.halfW(x);
        const real g = prof.greenhouse(x);
        const real arch = prof.archY(x);
        const bool inArch = arch > 0.0;
        std::array<bool, 5> present = {true, !inArch && hW > 0.45, true, true, true};
        std::array<Vec3, 5> pos;
        const real railZ = std::min<real>(0.42, sec.z[1] - 0.05);
        pos[0] = {x, sec.y[0] + 0.04, railZ};
        pos[1] = {x, sec.y[4], sec.z[4] - 0.02};
        pos[2] = {x, sec.y[5], sec.z[5] - 0.01};
        pos[3] = {x, sec.y[6], sec.z[6]};
        if (g > 0.12) pos[4] = {x, sec.y[8], sec.z[8]};
        else pos[4] = {x, sec.y[9], sec.z[9] + 0.05};
        const real w[5] = {1.6, 1.4, 1.0, 0.9, 0.75};
        for (int slot = 0; slot < 5; ++slot) {
            if (!present[static_cast<std::size_t>(slot)]) continue;
            for (int side = 0; side < 2; ++side) {
                Vec3 p = pos[static_cast<std::size_t>(slot)];
                if (side == 0) p.z = -p.z;
                NodeParams np;
                np.mass = 1.0;
                np.friction = 0.45;
                np.group = "body";
                const std::string id = "b" + std::to_string(i) + "_" + slotNames[slot] + (side ? "R" : "L");
                const auto n = car.addNode(id, p, np);
                rig.shell[i][static_cast<std::size_t>(slot)][static_cast<std::size_t>(side)] = n;
                rig.bodyNodes.push_back(n);
                nodeWeight.push_back(w[slot]);
            }
        }
    }

    // ------------------------------------------------------------------ shell beams
    auto regionBeam = [&](const Vec3& a, const Vec3& c) {
        const Vec3 m = (a + c) * 0.5;
        BeamParams p = makeBeam(7.5e5 * stiff, 170.0, 2.3e4 * strong, 7.0e4 * strong);
        p.hardening = 0.08;
        p.deformLimit = 0.55;
        p.deformLimitExpansion = 0.30;
        if (m.x > prof.xFA - 0.05) {            // front crumple zone
            p.deform *= 0.40; p.strength *= 0.55; p.spring *= 0.85;
        } else if (m.x > prof.xCowl + 0.05) {   // engine bay
            p.deform *= 0.70; p.strength *= 0.85;
        } else if (m.x >= prof.xRwBase - 0.05) { // safety cell
            p.deform *= 1.8; p.strength *= 2.0; p.spring *= 1.15;
            if (m.y < prof.ySill(m.x) + 0.10) { p.deform *= 1.3; p.strength *= 1.3; }
        }
        if (m.x < prof.xRA + 0.05) {            // rear crumple zone
            p.deform *= 0.50; p.strength *= 0.65;
        }
        return p;
    };
    auto addShellBeam = [&](std::int64_t a, std::int64_t c, bool glass = false) {
        if (a < 0 || c < 0 || a == c) return;
        const auto ua = static_cast<std::uint32_t>(a), uc = static_cast<std::uint32_t>(c);
        BeamParams p = regionBeam(car.positions()[ua], car.positions()[uc]);
        if (glass) {
            p.spring *= 0.35; p.deform *= 0.4; p.strength *= 0.25;
            p.breakGroup.clear();
        }
        car.addBeam(ua, uc, p);
    };

    auto addRingBrace = [&](std::int64_t a, std::int64_t c) {
        if (a < 0 || c < 0 || a == c) return;
        const auto ua = static_cast<std::uint32_t>(a), uc = static_cast<std::uint32_t>(c);
        BeamParams p = regionBeam(car.positions()[ua], car.positions()[uc]);
        p.spring *= 0.8;
        p.deform *= 0.35;
        p.strength *= 0.4;
        p.breakGroup.clear();
        car.addBeam(ua, uc, p);
    };
    for (std::size_t i = 0; i < NS; ++i) {
        const auto& R = rig.shell[i];
        // Ring perimeter (each side) + cross members.
        for (int side = 0; side < 2; ++side) {
            std::int64_t prev = -1;
            for (int slot = 0; slot < 5; ++slot) {
                const auto n = R[static_cast<std::size_t>(slot)][static_cast<std::size_t>(side)];
                if (n < 0) continue;
                if (prev >= 0) addShellBeam(prev, n);
                prev = n;
            }
        }
        addShellBeam(R[0][0], R[0][1]);
        addShellBeam(R[4][0], R[4][1]);
        if (R[1][0] >= 0) addShellBeam(R[1][0], R[1][1]);
        // Floor diagonals inside the station.
        if (R[1][0] >= 0) {
            addShellBeam(R[0][0], R[1][1]);
            addShellBeam(R[0][1], R[1][0]);
        }
        // Ring bracing outside the passenger compartment (bulkheads) and at the B pillar.
        const real x = stations[i];
        const bool bulkhead = x > prof.xCowl - 0.02 || x < prof.xRwBase + 0.02 || std::abs(x - prof.xB) < 0.05;
        if (bulkhead) {
            addShellBeam(R[0][0], R[2][1]);
            addShellBeam(R[0][1], R[2][0]);
            if (x > prof.xCowl - 0.02 || x < prof.xRwBase + 0.02) {
                addShellBeam(R[2][0], R[4][1]);
                addShellBeam(R[2][1], R[4][0]);
            }
        }
        // Cross-car bracing of every ring. Mid, belt and roof-rail nodes on a side wall lie almost
        // in one vertical line; without a cross-car triangle the belt rail had no lateral stiffness
        // and the body sides swung by up to 9 cm while driving ("jelly"). These stand in for the
        // roof bows, seat cross-members and door-ring stiffness of a monocoque. They yield before
        // the outer shell, so crash deformation stays close to the shell's own behaviour.
        if (!bulkhead) {
            addRingBrace(R[2][0], R[3][1]);
            addRingBrace(R[2][1], R[3][0]);
        }
        addRingBrace(R[3][0], R[4][1]);
        addRingBrace(R[3][1], R[4][0]);
        addRingBrace(R[3][0], R[3][1]);
    }
    for (std::size_t i = 0; i + 1 < NS; ++i) {
        const auto& A = rig.shell[i];
        const auto& B = rig.shell[i + 1];
        const real xm = 0.5 * (stations[i] + stations[i + 1]);
        const bool windowBay = prof.greenhouse(xm) > 0.15;
        for (int side = 0; side < 2; ++side) {
            const auto sd = static_cast<std::size_t>(side);
            // Neighbouring *present* slots on the perimeter of each ring.
            auto range = [&](const std::array<std::array<std::int64_t, 2>, 5>& ring, int slot) {
                int lo = slot, hi = slot;
                for (int k = slot - 1; k >= 0; --k) if (ring[static_cast<std::size_t>(k)][sd] >= 0) { lo = k; break; }
                for (int k = slot + 1; k < 5; ++k) if (ring[static_cast<std::size_t>(k)][sd] >= 0) { hi = k; break; }
                return std::pair<int, int>{lo, hi};
            };
            std::vector<std::pair<int, int>> pairs;  // (slotA, slotB)
            for (int sa = 0; sa < 5; ++sa) {
                if (A[static_cast<std::size_t>(sa)][sd] < 0) continue;
                const auto r = range(A, sa);
                for (int sb2 = r.first; sb2 <= r.second; ++sb2)
                    if (B[static_cast<std::size_t>(sb2)][sd] >= 0) pairs.push_back({sa, sb2});
            }
            for (int sb2 = 0; sb2 < 5; ++sb2) {
                if (B[static_cast<std::size_t>(sb2)][sd] < 0) continue;
                const auto r = range(B, sb2);
                for (int sa = r.first; sa <= r.second; ++sa)
                    if (A[static_cast<std::size_t>(sa)][sd] >= 0) pairs.push_back({sa, sb2});
            }
            std::sort(pairs.begin(), pairs.end());
            pairs.erase(std::unique(pairs.begin(), pairs.end()), pairs.end());
            for (const auto& pr : pairs) {
                const bool glass = windowBay && ((pr.first == 3 && pr.second == 4) || (pr.first == 4 && pr.second == 3));
                addShellBeam(A[static_cast<std::size_t>(pr.first)][sd], B[static_cast<std::size_t>(pr.second)][sd], glass);
            }
        }
        // Floor and roof/deck shear diagonals across the centre line.
        addShellBeam(A[0][0], B[0][1]);
        addShellBeam(A[0][1], B[0][0]);
        addShellBeam(A[4][0], B[4][1]);
        addShellBeam(A[4][1], B[4][0]);
        if (A[1][0] >= 0 && B[1][0] >= 0) {
            addShellBeam(A[1][0], B[0][0]);
            addShellBeam(A[1][1], B[0][1]);
        }
    }
    // Long-range stiffening: skip-one longitudinal members along rails and sills (chassis rails).
    for (std::size_t i = 0; i + 2 < NS; ++i)
        for (int side = 0; side < 2; ++side) {
            addShellBeam(rig.shell[i][0][static_cast<std::size_t>(side)], rig.shell[i + 2][0][static_cast<std::size_t>(side)]);
            addShellBeam(rig.shell[i][3][static_cast<std::size_t>(side)], rig.shell[i + 2][3][static_cast<std::size_t>(side)]);
        }
    const std::size_t shellBeamEnd = car.beamCount();

    // ------------------------------------------------------------------ helpers for mounts
    // Attaches node n to the body with a "cage" of beams in all directions (one per +-x/y/z where
    // possible) so the node sits inside the convex hull of its supports: a planar fan of beams has no
    // out-of-plane stiffness and a lopsided one can snap through to its mirror position.
    auto attach = [&](std::uint32_t n, std::size_t k, const BeamParams& p, std::vector<std::uint32_t>* out = nullptr) {
        const Vec3 pn = car.positions()[n];
        std::vector<std::uint32_t> cand;
        for (std::uint32_t c : nearestNodes(car, rig.bodyNodes, pn, 48, 1.2))
            if (length(car.positions()[c] - pn) > 0.05) cand.push_back(c);
        std::vector<std::uint32_t> chosen;
        const Vec3 axes[6] = {{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}};
        for (const Vec3& ax : axes) {
            bool found = false;
            for (real thr : {0.45, 0.2, 0.05}) {
                for (std::uint32_t c : cand) {  // sorted by distance
                    if (dot(normalize(car.positions()[c] - pn), ax) < thr) continue;
                    if (std::find(chosen.begin(), chosen.end(), c) == chosen.end()) chosen.push_back(c);
                    found = true;
                    break;
                }
                if (found) break;
            }
        }
        for (std::uint32_t c : cand) {
            if (chosen.size() >= k) break;
            if (std::find(chosen.begin(), chosen.end(), c) == chosen.end()) chosen.push_back(c);
        }
        if (std::abs(pn.z) < 1e-4) {  // centre-line node: keep the attachment mirror-symmetric
            const std::size_t nChosen = chosen.size();
            for (std::size_t i = 0; i < nChosen; ++i) {
                const Vec3 q = car.positions()[chosen[i]];
                for (std::uint32_t c : rig.bodyNodes) {
                    const Vec3 r = car.positions()[c];
                    if (std::abs(r.x - q.x) < 1e-6 && std::abs(r.y - q.y) < 1e-6 && std::abs(r.z + q.z) < 1e-6 &&
                        std::find(chosen.begin(), chosen.end(), c) == chosen.end()) {
                        chosen.push_back(c);
                        break;
                    }
                }
            }
        }
        for (std::uint32_t c : chosen) {
            const auto bi = car.addBeam(n, c, p);
            if (out) out->push_back(bi);
        }
    };
    BeamParams mountBeam = makeBeam(9.0e5, 150.0, 7.0e4, 1.8e5);
    mountBeam.deformLimit = 0.20;
    mountBeam.deformLimitExpansion = 0.20;

    // ------------------------------------------------------------------ suspension
    CarSystemsSpec sys;
    sys.suspensionBeams.resize(4);
    std::vector<real> unsprungMass(4, 0.0);
    const TireDef& tire = def.tires;
    const real R = tire.radius;
    for (int c = 0; c < 4; ++c) {
        CarCorner& cn = rig.corners[static_cast<std::size_t>(c)];
        cn.front = c < 2;
        cn.right = (c % 2) == 1;
        const AxleSuspensionDef& sd = cn.front ? def.front : def.rear;
        const real s = cn.right ? 1.0 : -1.0;
        const real xa = cn.front ? prof.xFA : prof.xRA;
        cn.xAxle = xa;
        const real tr = 0.5 * (cn.front ? bd.trackFront : bd.trackRear);
        const std::string pre = std::string(cn.front ? "F" : "R") + (cn.right ? "R" : "L") + "_";
        std::vector<std::uint32_t>& sb = sys.suspensionBeams[static_cast<std::size_t>(c)];

        const real toeDeg = sd.toe > -90.0 ? sd.toe : (cn.front ? 0.0 : 0.25);
        const real toeRad = toeDeg * kPi / 180.0;
        auto node = [&](const std::string& n, Vec3 p, real m, const std::string& group) {
            NodeParams np;
            np.mass = m;
            np.friction = 0.6;
            np.group = group;
            if (group.rfind("upright_", 0) == 0 && toeRad != 0.0) {
                // Static toe: rotate the whole knuckle about the vertical axis through the wheel.
                const real dx = p.x - xa, dz = p.z - tr;
                p.x = xa + dx * std::cos(toeRad) + dz * std::sin(toeRad);
                p.z = tr - dx * std::sin(toeRad) + dz * std::cos(toeRad);
            }
            p.z *= s;
            return car.addNode(pre + n, p, np);
        };
        const std::string up = "upright_" + pre;
        const real caliperMass = 3.0;
        const real hubMass = 0.5 * (tire.rimMass + 9.0 - caliperMass);
        cn.hubIn = node("hub_in", {xa, R, tr - 0.085}, hubMass, up);
        cn.hubOut = node("hub_out", {xa, R, tr + 0.085}, hubMass, up);
        // Ball joints sit inside the rim: small scrub radius, ~9 deg kingpin inclination.
        cn.lbj = node("lbj", {xa, R - 0.15, tr - 0.07}, 6.0, up);
        cn.ubj = node("ubj", {xa - 0.02, R + 0.19, tr - 0.125}, 5.0, up);
        // A non-steering rear upright uses a longer toe-control arm. Reusing
        // the short front steering arm gives lateral tyre forces too little
        // leverage and allows large rear steer without any structural damage.
        const real toeLever = cn.front ? 0.14 : std::min<real>(0.34, 0.85 * R);
        const real pivZ = std::min<real>(0.36, tr - 0.40);
        const real tieY = R - 0.03;
        cn.steerArm = node("steer_arm", {xa - toeLever, tieY, tr - 0.12}, 5.0, up);
        // Brake caliper mount ahead of the axle. Hubs and ball joints lie almost in one transverse
        // plane, so without an off-plane point in front the hub axis could swivel in yaw on its
        // knuckle (held fore-aft by the single steering-arm beam): a ~25 Hz wheel-yaw mode that
        // showed up as toe flutter at the grip limit.
        cn.caliper = node("caliper", {xa + 0.13, R + 0.06, tr - 0.10}, caliperMass, up);
        cn.lowerF = node("lower_f", {xa + 0.18, R - 0.12, pivZ}, 4.0, "subframe");
        cn.lowerR = node("lower_r", {xa - 0.18, R - 0.12, pivZ}, 4.0, "subframe");
        cn.upperF = node("upper_f", {xa + 0.13, R + 0.21, tr - 0.45}, 3.5, "subframe");
        cn.upperR = node("upper_r", {xa - 0.13, R + 0.21, tr - 0.45}, 3.5, "subframe");
        cn.rackEnd = node("rack_end", {xa - toeLever, tieY, pivZ}, 3.5, "subframe");
        // The coilover acts directly on the knuckle at the lower ball joint (motion ratio ~0.95),
        // which keeps the spring path rigid under bump-stop loads.
        cn.armMid = cn.lbj;
        cn.tower = node("tower", {xa, R + 0.43, tr - 0.29}, 10.0, "subframe");
        unsprungMass[static_cast<std::size_t>(c)] = 2 * hubMass + caliperMass + 6 + 5 + 5 + tire.massFor(cn.front);

        // Subframe nodes are bolted to the body.
        for (std::uint32_t n : {cn.lowerF, cn.lowerR, cn.upperF, cn.upperR, cn.rackEnd, cn.tower})
            attach(n, 4, mountBeam, &sb);
        // Strut tower: the spring's top mount is a pressed box welded down to the chassis rail and
        // the sill. Hung only from the nearest (fender/crumple-zone) shell nodes, the front of the
        // body sank ~5 cm around the towers under its own weight and dragged the steering geometry
        // into ~1.8 deg toe-out.
        {
            std::vector<std::pair<real, std::uint32_t>> lower;
            for (std::size_t station = 0; station < rig.shell.size(); ++station)
                for (int slot : {0, 1}) {
                    const auto nIdx = rig.shell[station][static_cast<std::size_t>(slot)][cn.right ? 1 : 0];
                    if (nIdx < 0) continue;
                    const auto un = static_cast<std::uint32_t>(nIdx);
                    lower.push_back({std::abs(car.positions()[un].x - xa), un});
                }
            std::sort(lower.begin(), lower.end());
            const BeamParams towerBox = makeBeam(1.5e6, 150.0, 8.0e4, 2.0e5);
            for (std::size_t k = 0; k < std::min<std::size_t>(4, lower.size()); ++k)
                sb.push_back(car.addBeam(cn.tower, lower[k].second, towerBox));
        }
        car.addBeam(cn.lowerF, cn.lowerR, mountBeam);
        car.addBeam(cn.upperF, cn.upperR, mountBeam);
        // Rear toe links need a triangulated subframe anchorage. Mounting the
        // anchor only to flexible shell nodes lets it steer the rear wheel under
        // cornering loads even though no suspension beam has yielded.
        if (!cn.front) {
            for (auto pivot : {cn.lowerF, cn.lowerR, cn.upperR})
                sb.push_back(car.addBeam(cn.rackEnd, pivot, mountBeam));
        }

        // Upright: rigid knuckle.
        const BeamParams knuckle = makeBeam(3.5e6, 220.0, 1.6e5, 4.0e5);
        std::vector<std::uint32_t> upr = {cn.hubIn, cn.hubOut, cn.lbj, cn.ubj, cn.steerArm, cn.caliper};
        connectAll(car, upr, knuckle, &sb);
        // Wishbones.
        BeamParams arm = makeBeam(1.6e6, 140.0, 9.5e4, 2.4e5);
        arm.deformLimit = 0.14;
        arm.deformLimitExpansion = 0.14;
        for (std::uint32_t p : {cn.lowerF, cn.lowerR}) sb.push_back(car.addBeam(p, cn.lbj, arm));
        for (std::uint32_t p : {cn.upperF, cn.upperR}) sb.push_back(car.addBeam(p, cn.ubj, arm));
        // The wishbone lengths alone also admit a folded pose with the spindle tucked under the car.
        // Inward stops engage beyond normal steering and travel, like contact with the upright housing.
        BeamParams inwardStop = makeBeam(1.6e6, 180.0, kInf, 1.8e5);
        inwardStop.type = BeamType::Support;
        inwardStop.precompression = 0.87;
        for (std::uint32_t p : {cn.lowerF, cn.lowerR}) sb.push_back(car.addBeam(p, cn.hubOut, inwardStop));
        // The upper links need more clearance for full steering lock and normal camber gain.
        inwardStop.precompression = 0.80;
        for (std::uint32_t p : {cn.upperF, cn.upperR}) sb.push_back(car.addBeam(p, cn.hubOut, inwardStop));
        BeamParams hubDroop = makeBeam(0.0, 0.0, kInf, 1.8e5);
        hubDroop.type = BeamType::Anisotropic;
        hubDroop.springExpansion = 1.6e6;
        hubDroop.dampExpansion = 180.0;
        hubDroop.precompression = 1.24;
        sb.push_back(car.addBeam(cn.tower, cn.hubOut, hubDroop));
        // Tie rod (hydro steering on the front axle, fixed toe link on the rear).
        // The tie rod is the weak link of a wheel strike: it yields at ~45 kN (hard cornering and
        // landings stay well below), so a wheel driven into a kerb knocks the toe out and the car
        // pulls, while the wishbones only bend in real crashes.
        BeamParams tie = arm;
        tie.spring = 2.2e6;
        tie.deform = 4.5e4;
        if (cn.front) {
            const real tieLen = length(car.positions()[cn.steerArm] - car.positions()[cn.rackEnd]);
            const real lockDelta = 0.14 * std::sin(34.0 * kPi / 180.0);
            tie.type = BeamType::Hydro;
            tie.hydroInput = 0;
            tie.hydroRatio = (cn.right ? 1.0 : -1.0) * lockDelta / tieLen;
        }
        sb.push_back(car.addBeam(cn.rackEnd, cn.steerArm, tie));

        // Coilover: spring + bump/rebound damper + bump stop + droop strap.
        const Vec3 pm = car.positions()[cn.armMid], pt = car.positions()[cn.tower];
        const real springLen = length(pt - pm);
        const Vec3 dir = (pt - pm) / springLen;
        const real mr = std::max<real>(0.35, dir.y);
        cn.motionRatio = mr;
        const real kSpring = sd.wheelRate / (mr * mr);
        BeamParams spring = makeBeam(kSpring, 0.0, kInf, 1.6e5);
        sb.push_back(car.addBeam(cn.armMid, cn.tower, spring));  // precompression set below
        BeamParams damper = makeBeam(0.0, sd.bumpDamping / (mr * mr), kInf, 1.6e5);
        damper.type = BeamType::Shock;
        damper.dampRebound = sd.reboundDamping / (mr * mr);
        sb.push_back(car.addBeam(cn.armMid, cn.tower, damper));
        BeamParams bump = makeBeam(kSpring * 7.0, 400.0, kInf, kInf);
        bump.type = BeamType::Support;
        bump.precompression = 1.0 - (sd.bumpTravel * mr) / springLen;
        sb.push_back(car.addBeam(cn.armMid, cn.tower, bump));
        BeamParams droop = makeBeam(0.0, 300.0, kInf, kInf);
        droop.type = BeamType::Anisotropic;
        droop.springExpansion = kSpring * 6.0;
        droop.precompression = 1.0 + (sd.droopTravel * mr) / springLen;
        sb.push_back(car.addBeam(cn.armMid, cn.tower, droop));

        // Anti-roll bar arm (torsion bar added after both sides exist).
        // Bar end sits directly above the arm mount so the drop link is vertical.
        const Vec3 lbjP = car.positions()[cn.lbj];
        const real arbY = lbjP.y + 0.17;
        const real arbZ = s * lbjP.z - 0.06;
        cn.arbEnd = node("arb_end", {xa - 0.03, arbY, arbZ}, 2.5, up);
        cn.arbPivot = node("arb_pivot", {xa - 0.28, arbY, arbZ - 0.05}, 2.5, "subframe");
        attach(cn.arbPivot, 3, mountBeam, &sb);
        const BeamParams arbLink = makeBeam(6.0e5, 60.0, 4.0e4, 1.0e5);
        sb.push_back(car.addBeam(cn.arbPivot, cn.arbEnd, arbLink));
        sb.push_back(car.addBeam(cn.arbEnd, cn.armMid, arbLink));  // drop link
    }
    for (int axle = 0; axle < 2; ++axle) {
        CarCorner& l = rig.corners[static_cast<std::size_t>(axle * 2)];
        CarCorner& r = rig.corners[static_cast<std::size_t>(axle * 2 + 1)];
        const BeamParams arbLink = makeBeam(6.0e5, 60.0, 4.0e4, 1.0e5);
        car.addBeam(l.arbPivot, r.arbPivot, arbLink);
        car.addBeam(l.arbEnd, r.arbPivot, arbLink);
        car.addBeam(r.arbEnd, l.arbPivot, arbLink);
        const AxleSuspensionDef& sd = axle == 0 ? def.front : def.rear;
        const Vec3 axis = car.positions()[r.arbPivot] - car.positions()[l.arbPivot];
        const Vec3 rel = car.positions()[l.arbEnd] - car.positions()[l.arbPivot];
        const real lever = length(rel - normalize(axis) * dot(rel, normalize(axis)));
        // Wheel-equivalent roll rate -> torsion stiffness (the bar end follows the knuckle 1:1).
        TorsionbarParams tb;
        tb.spring = sd.antiRollRate * lever * lever * 0.5;
        tb.damp = tb.spring * 0.01;
        tb.strength = 3.0e4;
        if (sd.antiRollRate > 0.0) car.addTorsionbar(l.arbEnd, l.arbPivot, r.arbPivot, r.arbEnd, tb);

        // Subframe: on a real car all wishbone pivots and the steering rack (front) or toe-link
        // pivots (rear) sit on one rigid cross-member that is bolted to the body. Anchoring each
        // pivot to the shell on its own let the body's own sag and twist move the pivots against
        // the tie-rod joints: ~1.8 deg static front toe-out on the Concept and wheels that toed
        // in and out by several degrees under drive torque.
        {
            const BeamParams frame = makeBeam(1.2e6, 120.0, 1.4e5, 3.0e5);
            std::vector<std::uint32_t> sub;
            for (CarCorner* cn : {&l, &r})
                for (std::uint32_t n : {cn->lowerF, cn->lowerR, cn->upperF, cn->upperR, cn->rackEnd}) sub.push_back(n);
            connectAll(car, sub, frame, nullptr);
        }
    }

    // ------------------------------------------------------------------ engine, radiator, oil pan
    const EngineDef& ed = def.engine;
    const bool midEngine = ed.position == "mid";
    {
        const real ex0 = midEngine ? prof.xRA + 0.14 : prof.xFA - 0.42;
        const real ex1 = ex0 + 0.56;
        const real ey0 = R - 0.02, ey1 = std::min<real>(R + 0.46, bd.hoodHeight - 0.12);
        const real ez = 0.27;
        NodeParams np;
        np.mass = ed.mass / 8.0;
        np.friction = 0.5;
        np.group = "engine";
        for (int ix = 0; ix < 2; ++ix)
            for (int iy = 0; iy < 2; ++iy)
                for (int iz = 0; iz < 2; ++iz) {
                    const Vec3 p{ix ? ex1 : ex0, iy ? ey1 : ey0, iz ? ez : -ez};
                    rig.engine.push_back(car.addNode("eng" + std::to_string(ix * 4 + iy * 2 + iz), p, np));
                }
        BeamParams block = makeBeam(1.4e6, 220.0, 1.1e5, kInf);
        connectAll(car, rig.engine, block, &sys.engineBlockBeams);
        // Mounts on the four bottom corners (breakable).
        BeamParams mount = makeBeam(3.5e5, 160.0, 2.4e4, 6.0e4);
        for (int ix = 0; ix < 2; ++ix)
            for (int iz = 0; iz < 2; ++iz) {
                const std::uint32_t n = rig.engine[static_cast<std::size_t>(ix * 4 + iz)];
                attach(n, 3, mount, &sys.engineMountBeams);
            }
        // Upper torque strut to the cowl / strut towers.
        for (int iz = 0; iz < 2; ++iz) {
            const std::uint32_t n = rig.engine[static_cast<std::size_t>(0 * 4 + 1 * 2 + iz)];
            for (std::uint32_t t : nearestNodes(car, rig.bodyNodes, car.positions()[n], 1))
                sys.engineMountBeams.push_back(car.addBeam(n, t, mount));
        }

        // Oil pan.
        NodeParams pan;
        pan.mass = 2.5;
        pan.friction = 0.5;
        pan.group = "engine";
        const real py = bd.groundClearance + 0.035;
        rig.oilPan.push_back(car.addNode("oilpan0", {ex0 + 0.12, py, 0.0}, pan));
        rig.oilPan.push_back(car.addNode("oilpan1", {ex1 - 0.12, py, 0.0}, pan));
        // Cast sump: scraping over a rough trail dents it, only a real impact cracks it. At 4 kN
        // plastic onset a sedan's sump was "damaged" by ordinary gravel-trail bumps and the
        // engine seized within a minute.
        BeamParams panB = makeBeam(4.0e5, 90.0, 1.2e4, 4.5e4);
        for (std::uint32_t p : rig.oilPan)
            for (int ix = 0; ix < 2; ++ix)
                for (int iz = 0; iz < 2; ++iz)
                    sys.oilPanBeams.push_back(car.addBeam(p, rig.engine[static_cast<std::size_t>(ix * 4 + iz)], panB));
        sys.oilPanBeams.push_back(car.addBeam(rig.oilPan[0], rig.oilPan[1], panB));

        // Front radiator (also used by mid-engine cars through coolant plumbing).
        NodeParams rad;
        rad.mass = 2.2;
        rad.friction = 0.5;
        rad.group = "radiator";
        const real rx = L - 0.20;
        const real ry0 = prof.yBottom(rx) + 0.10, ry1 = bd.noseHeight - 0.10;
        const real rz = std::min<real>(0.33, prof.halfW(rx) - 0.18);
        for (int iy = 0; iy < 2; ++iy)
            for (int iz = 0; iz < 2; ++iz)
                rig.radiator.push_back(car.addNode("rad" + std::to_string(iy * 2 + iz), {rx, iy ? ry1 : ry0, iz ? rz : -rz}, rad));
        BeamParams core = makeBeam(2.5e5, 40.0, 4.5e3, 2.6e4);
        connectAll(car, rig.radiator, core, &sys.radiatorBeams);
        BeamParams radMount = makeBeam(2.0e5, 50.0, 6.0e3, 3.0e4);
        for (std::uint32_t n : rig.radiator) attach(n, 3, radMount);
        // Packaging contacts: bumper -> radiator -> engine -> firewall (compression only, late).
        BeamParams contact = makeBeam(5.0e5, 120.0, kInf, kInf);
        contact.type = BeamType::Support;
        contact.precompression = 0.25;
        for (std::uint32_t n : rig.radiator) {
            if (midEngine) continue; // No physical contact beam through the passenger compartment.
            const auto e = nearestNodes(car, rig.engine, car.positions()[n], 1);
            if (!e.empty()) sys.radiatorBeams.push_back(car.addBeam(n, e[0], contact));
        }
        const std::size_t lastStation = NS - 1;
        for (int slot : {0, 2}) {
            for (int side = 0; side < 2; ++side) {
                const auto f = rig.shell[lastStation][static_cast<std::size_t>(slot)][static_cast<std::size_t>(side)];
                if (f < 0) continue;
                const auto r = nearestNodes(car, rig.radiator, car.positions()[static_cast<std::uint32_t>(f)], 1);
                if (!r.empty()) sys.radiatorBeams.push_back(car.addBeam(static_cast<std::uint32_t>(f), r[0], contact));
            }
        }
        // Engine -> nearest passenger bulkhead, front or rear according to packaging.
        BeamParams fw = contact;
        fw.precompression = 0.35;
        std::size_t cowlStation = 0;
        real best = 1e9;
        for (std::size_t i = 0; i < NS; ++i)
            if (std::abs(stations[i] - (midEngine ? prof.xRwTop : prof.xCowl)) < best) {
                best = std::abs(stations[i] - (midEngine ? prof.xRwTop : prof.xCowl)); cowlStation = i;
            }
        for (int iy = 0; iy < 2; ++iy)
            for (int iz = 0; iz < 2; ++iz) {
                const std::uint32_t n = rig.engine[static_cast<std::size_t>((midEngine ? 1 : 0) * 4 + iy * 2 + iz)];
                const auto f = rig.shell[cowlStation][static_cast<std::size_t>(iy ? 3 : 0)][static_cast<std::size_t>(iz)];
                if (f >= 0) car.addBeam(n, static_cast<std::uint32_t>(f), fw);
            }
    }

    // ------------------------------------------------------------------ fuel tank, driveshaft
    {
        NodeParams np;
        const real fuelKg = def.engine.fuelCapacity * 0.8 * 0.745;
        np.mass = (fuelKg + 12.0) / 4.0;
        np.friction = 0.5;
        np.group = "fueltank";
        const real tankOffset = midEngine ? 0.70 : 0.0;
        const real y = prof.yBottom(prof.xRA + 0.5 + tankOffset) + 0.07;
        for (int ix = 0; ix < 2; ++ix)
            for (int iz = 0; iz < 2; ++iz)
                rig.fuelTank.push_back(car.addNode("tank" + std::to_string(ix * 2 + iz),
                                                   {prof.xRA + (ix ? 0.82 : 0.30) + tankOffset, y, iz ? 0.33 : -0.33}, np));
        BeamParams tank = makeBeam(3.0e5, 60.0, 6.0e3, 3.0e4);
        connectAll(car, rig.fuelTank, tank, &sys.fuelTankBeams);
        BeamParams tm = makeBeam(3.0e5, 80.0, 1.5e4, 6.0e4);
        for (std::uint32_t n : rig.fuelTank) attach(n, 3, tm);
    }
    const std::string layoutStr = def.engine.layout;
    const DriveLayout layout = layoutStr == "RWD" ? DriveLayout::RWD : (layoutStr == "AWD" ? DriveLayout::AWD : DriveLayout::FWD);
    if (layout != DriveLayout::FWD) {
        NodeParams np;
        np.mass = 28.0;
        np.friction = 0.5;
        np.group = "subframe";
        rig.diff = car.addNode("diff", {prof.xRA + 0.05, R + 0.03, 0.0}, np);
        const auto d = static_cast<std::uint32_t>(rig.diff);
        for (int c = 2; c < 4; ++c) {
            car.addBeam(d, rig.corners[static_cast<std::size_t>(c)].lowerF, mountBeam);
            car.addBeam(d, rig.corners[static_cast<std::size_t>(c)].lowerR, mountBeam);
        }
        attach(d, 2, mountBeam);
        BeamParams shaft = makeBeam(3.0e5, 60.0, 3.0e4, 7.0e4);
        for (int iz = 0; iz < 2; ++iz)
            sys.driveshaftBeams.push_back(car.addBeam(rig.engine[static_cast<std::size_t>(iz)], d, shaft));
    }

    // A separate panel with sacrificial latch and hinge mounts. Its structure stays
    // intact when the mounts break, so it can leave the vehicle as a physical part.
    auto& bonnet = build.layout.bonnetNodes;
    for (int layer = 0; layer < 2; ++layer) {
        for (int corner = 0; corner < 4; ++corner) {
            const real x = corner < 2 ? prof.xCowl + 0.025 : L - 0.12;
            const real z = prof.halfW(x) * 0.78 * (corner % 2 ? 1.0 : -1.0);
            const real y = prof.section(x).y[9] - 0.035 + layer * 0.025;
            NodeParams p;
            p.mass = 2.25;
            p.group = "bonnet";
            p.friction = 0.5;
            bonnet.push_back(car.addNode("bonnet_" + std::to_string(layer * 4 + corner), {x, y, z}, p));
        }
    }
    connectAll(car, bonnet, makeBeam(8.0e4, 35.0, 1.2e4, 5.0e4), nullptr);
    DoorMechanism bonnetLatch;
    bonnetLatch.nodes = bonnet;
    bonnetLatch.inputChannel = 1;
    bonnetLatch.stroke = 1.25;
    bonnetLatch.catchTolerance = 0.06;
    for (int corner = 0; corner < 4; ++corner) {
        const auto n = bonnet[static_cast<std::size_t>(corner)];
        BeamParams mount = makeBeam(1.0e5, 55.0, 8.0e3, corner < 2 ? 1.2e4 : 5.0e3);
        mount.breakGroup = corner < 2 ? "bonnet_hinge" : "bonnet_latch";
        for (auto anchor : nearestNodes(car, rig.bodyNodes, car.positions()[n], 3))
            (corner < 2 ? bonnetLatch.hingeBeams : bonnetLatch.latchBeams).push_back(car.addBeam(n, anchor, mount));
    }
    // Two low-force gas supports make inspection an actual held-open pose.
    // Their target lengths come from rotating the bonnet by 65 degrees around
    // its rear hinge line; they release with that hinge instead of tethering a
    // crash-detached hood to the car. Native controls ramp input channel 1.
    for (std::size_t side = 0; side < 2; ++side) {
        const auto rear = bonnet[side], front = bonnet[side + 2];
        const Vec3 hinge = car.positions()[rear];
        const auto candidates = nearestNodes(car, rig.bodyNodes, hinge + Vec3{-0.08, -0.32, 0}, 1);
        const auto anchor = candidates.front();
        const Vec3 delta = car.positions()[front] - hinge;
        const real angle = 65.0 * kPi / 180.0;
        const Vec3 openPoint = hinge + Vec3{delta.x * std::cos(angle) - delta.y * std::sin(angle),
                                           delta.x * std::sin(angle) + delta.y * std::cos(angle), delta.z};
        const real closedLength = length(car.positions()[front] - car.positions()[anchor]);
        const real openLength = length(openPoint - car.positions()[anchor]);
        // A gas support must still push at the requested angle. Without this
        // weight preload its force is zero at 65 degrees and gravity lets the
        // bonnet settle much lower despite reaching the nominal stroke.
        real panelMass = 0, hingeInertia = 0;
        Vec3 panelCenter{};
        for (auto node : bonnet) {
            panelMass += car.masses()[node];
            panelCenter += car.positions()[node] * car.masses()[node];
            const Vec3 leverArm = car.positions()[node] - hinge;
            hingeInertia += car.masses()[node] * (leverArm.x * leverArm.x + leverArm.y * leverArm.y);
        }
        panelCenter = panelCenter / panelMass - hinge;
        const real openComX = panelCenter.x * std::cos(angle) - panelCenter.y * std::sin(angle);
        const real lever = std::max<real>(0.04, std::abs(cross(openPoint - hinge,
                                              normalize(openPoint - car.positions()[anchor])).z));
        const real holdingForce = std::clamp(panelMass * 9.81 * std::max<real>(0, openComX) / (2.0 * lever), 0.0, 1000.0);
        BeamParams support = makeBeam(3.0e3, 60.0, kInf, 3.0e3);
        // Convert near-critical rotational damping back to each actuator's
        // linear damping through its actual moment arm. A fixed 60 Ns/m caused
        // the long bonnet to oscillate instead of staying open for inspection.
        support.damp = std::clamp(0.7 * std::sqrt(2.0 * hingeInertia * support.spring) / lever, 300.0, 1800.0);
        support.type = BeamType::Hydro;
        support.hydroInput = 1;
        support.hydroRatio = (openLength + holdingForce / support.spring) / closedLength - 1.0;
        support.breakGroup = "bonnet_hinge";
        build.layout.bonnetStrutBeams.push_back(car.addBeam(anchor, front, support));
    }
    // Reversible latch: opened from the cabin, lowered on its struts and relatched when it is shut.
    bonnetLatch.supportBeams = build.layout.bonnetStrutBeams;
    car.addLid(bonnetLatch);
    ColTriParams panel;
    panel.dragCoef = 1.0;
    car.addTriangle(bonnet[4], bonnet[6], bonnet[7], panel);
    car.addTriangle(bonnet[4], bonnet[7], bonnet[5], panel);

    // Rear lid: tailgate (hatchback, estate, SUV; hinged at the roof's rear edge) or boot lid
    // (saloon, coupe; hinged at the rear window base). Like the bonnet: a rigid eight-node panel on
    // breakable hinges and a latch that the cabin release opens, lifted by gas struts (channel 6).
    if (bd.detachableTailgate) {
        const bool hatch = bd.style == BodyStyle::Hatchback || bd.style == BodyStyle::SUV;
        const real hx = bd.tailgateHingeX > 0.0 ? bd.tailgateHingeX : (hatch ? prof.xRwTop - 0.02 : prof.xRwBase + 0.03);
        const real hy = bd.tailgateHingeY > 0.0 ? bd.tailgateHingeY : (hatch ? prof.yRoofRail(prof.xRwTop) - 0.03 : prof.yBelt(hx));
        const real lx = bd.tailgateLatchX > 0.0 ? bd.tailgateLatchX : 0.05;
        const real ly = bd.tailgateLatchY > 0.0 ? bd.tailgateLatchY : (hatch ? std::max(prof.ySill(0.05) + 0.30, bd.tailHeight - 0.30) : prof.yBelt(0.06));
        const Vec3 hingeLine{hx, hy, 0.0}, latchLine{lx, ly, 0.0};
        const real span = length(latchLine - hingeLine);
        const Vec3 along = (latchLine - hingeLine) / std::max<real>(1e-3, span);
        const Vec3 inward{-along.y, along.x, 0.0};   // into the car, normal to the lid
        const real halfWidth = bd.tailgateHalfWidth > 0.0 ? bd.tailgateHalfWidth : 0.78 * prof.halfW(0.5 * (hx + lx));
        // The lid lies on top of the body skin, never inside it: once released it rests on the
        // body (self-contact) instead of being pushed out of it.
        real proud = 0.0;
        for (auto n : rig.bodyNodes) {
            const Vec3 d = car.positions()[n] - hingeLine;
            const real u = dot(Vec3{d.x, d.y, 0.0}, along), w = dot(Vec3{d.x, d.y, 0.0}, inward);
            // Wider than the lid itself: skin triangles reaching in from just outside count too.
            if (u > -0.10 && u < span + 0.10 && std::abs(d.z) < halfWidth + 0.15 && w < 0.0 && w > -0.25) proud = std::max(proud, -w);
        }
        const Vec3 surface = -inward * (proud + 0.012);
        const real mass = bd.tailgateMass > 0.0 ? bd.tailgateMass : (hatch ? 18.0 : 11.0);
        auto& lid = build.layout.tailgateNodes;
        for (int layer = 0; layer < 2; ++layer)
            for (int corner = 0; corner < 4; ++corner) {
                NodeParams p;
                p.mass = mass / 8.0;
                p.group = "tailgate";
                p.friction = 0.5;
                const Vec3 line = corner < 2 ? hingeLine : latchLine;
                const real z = halfWidth * (corner < 2 ? 1.0 : 0.96) * (corner % 2 ? 1.0 : -1.0);
                lid.push_back(car.addNode("tailgate_" + std::to_string(layer * 4 + corner),
                                          line + surface - inward * (layer * 0.03) + Vec3{0.0, 0.0, z}, p));
            }
        connectAll(car, lid, makeBeam(8.0e4, 35.0, 1.2e4, 5.0e4), nullptr);
        DoorMechanism lidLatch;
        lidLatch.nodes = lid;
        lidLatch.inputChannel = 6;
        lidLatch.stroke = 1.4;
        lidLatch.catchTolerance = 0.06;
        // Hinges and latch are rated for an 18 kg hatch lid; a heavier lid (the Trailhead's 40 kg
        // with its spare wheel) gets proportionally stronger ones, or its own inertia pops the
        // latch in a 50 km/h frontal impact (real latches hold well over 30 g).
        const real lidRating = std::max<real>(1.0, mass / 18.0);
        for (int corner = 0; corner < 4; ++corner) {
            const auto n = lid[static_cast<std::size_t>(corner)];
            BeamParams mount = makeBeam(1.0e5, 55.0, 8.0e3, (corner < 2 ? 1.2e4 : 5.0e3) * lidRating);
            mount.breakGroup = corner < 2 ? "tailgate_hinge" : "tailgate_latch";
            for (auto a : nearestNodes(car, rig.bodyNodes, car.positions()[n], 3))
                (corner < 2 ? lidLatch.hingeBeams : lidLatch.latchBeams).push_back(car.addBeam(n, a, mount));
        }
        // Gas struts from the body beside the opening to the lid's far edge; open pose by rotating
        // the lid about its hinge line (upwards and back: negative about +z).
        const real angle = -(bd.tailgateOpenDeg > 0.0 ? bd.tailgateOpenDeg : (hatch ? 80.0 : 68.0)) * kPi / 180.0;
        for (std::size_t side = 0; side < 2; ++side) {
            const auto near = lid[side], far = lid[side + 2];
            const Vec3 hinge = car.positions()[near];
            // Rooted in the D-pillar / boot side well inside the lid plane, so it has leverage
            // about the hinge from the closed position on.
            const Vec3 target = hinge + inward * 0.25 + along * 0.40;
            std::vector<std::uint32_t> inside;
            for (auto n : rig.bodyNodes) {
                const Vec3 d = car.positions()[n] - hinge;
                if (dot(Vec3{d.x, d.y, 0.0}, inward) > 0.12 && car.positions()[n].z * hinge.z > 0.0) inside.push_back(n);
            }
            const auto anchor = nearestNodes(car, inside.empty() ? rig.bodyNodes : inside, target, 1).front();
            auto rotate = [&](const Vec3& d) {
                return Vec3{d.x * std::cos(angle) - d.y * std::sin(angle), d.x * std::sin(angle) + d.y * std::cos(angle), d.z};
            };
            const Vec3 openPoint = hinge + rotate(car.positions()[far] - hinge);
            const real closedLength = length(car.positions()[far] - car.positions()[anchor]);
            const real openLength = length(openPoint - car.positions()[anchor]);
            real panelMass = 0, hingeInertia = 0;
            Vec3 com{};
            for (auto node : lid) {
                panelMass += car.masses()[node];
                com += car.positions()[node] * car.masses()[node];
                const Vec3 arm = car.positions()[node] - hinge;
                hingeInertia += car.masses()[node] * (arm.x * arm.x + arm.y * arm.y);
            }
            const Vec3 openCom = rotate(com / panelMass - hinge);
            const real lever = std::max<real>(0.04, std::abs(cross(openPoint - hinge,
                                                  normalize(openPoint - car.positions()[anchor])).z));
            const real holdingForce = std::clamp(panelMass * 9.81 * std::abs(openCom.x) / (2.0 * lever), 0.0, 1500.0);
            BeamParams strut = makeBeam(3.0e3, 60.0, kInf, 3.5e3);
            strut.damp = std::clamp(0.7 * std::sqrt(2.0 * hingeInertia * strut.spring) / lever, 300.0, 1800.0);
            strut.type = BeamType::Hydro;
            strut.hydroInput = 6;
            strut.hydroRatio = (openLength + holdingForce / strut.spring) / closedLength - 1.0;
            strut.breakGroup = "tailgate_hinge";
            build.layout.tailgateStrutBeams.push_back(car.addBeam(anchor, far, strut));
        }
        // Outer skin, wound so that its normal points out of the car.
        auto outerTri = [&](std::uint32_t a, std::uint32_t b, std::uint32_t c) {
            if (dot(cross(car.positions()[b] - car.positions()[a], car.positions()[c] - car.positions()[a]), inward) > 0) std::swap(b, c);
            car.addTriangle(a, b, c, panel);
        };
        outerTri(lid[4], lid[6], lid[7]);
        outerTri(lid[4], lid[7], lid[5]);
        lidLatch.supportBeams = build.layout.tailgateStrutBeams;
        car.addLid(lidLatch);
    }


    // Independent lower bumper skins. Their mass is allocated before the shell
    // budget, so opting in preserves curb mass and the specified axle loading.
    auto addBoxCollision = [&](const std::vector<std::uint32_t>& nodes, real drag) {
        const int faces[6][4] = {{0, 1, 3, 2}, {4, 6, 7, 5}, {0, 4, 5, 1},
                                 {2, 3, 7, 6}, {0, 2, 6, 4}, {1, 5, 7, 3}};
        Vec3 center{};
        for (auto node : nodes) center += car.positions()[node];
        center *= 1.0 / static_cast<real>(nodes.size());
        ColTriParams params;
        params.dragCoef = drag;
        params.friction = 0.5;
        for (const auto& face : faces) {
            auto a = nodes[static_cast<std::size_t>(face[0])];
            auto b = nodes[static_cast<std::size_t>(face[1])];
            auto c = nodes[static_cast<std::size_t>(face[2])];
            auto d = nodes[static_cast<std::size_t>(face[3])];
            const Vec3 normal = cross(car.positions()[b] - car.positions()[a], car.positions()[c] - car.positions()[a]);
            if (dot(normal, car.positions()[a] - center) < 0) std::swap(b, d);
            car.addTriangle(a, b, c, params);
            car.addTriangle(a, c, d, params);
        }
    };
    // A real obstacle under a loose hood, rather than an empty engine bay.
    addBoxCollision(rig.engine, 0.0);
    if (bd.detachableBumpers) {
        for (int end = 0; end < 2; ++end) {
            const bool front = end == 0;
            auto& nodes = front ? build.layout.frontBumperNodes : build.layout.rearBumperNodes;
            const std::string group = front ? "bumper_front" : "bumper_rear";
            const real innerX = front ? L - 0.28 : 0.28;
            const real outerX = front ? L + 0.025 : -0.025;
            const real y0 = prof.yBottom(innerX) + 0.035;
            const real y1 = front ? bd.noseHeight - 0.16 : bd.tailHeight - 0.28;
            const real halfWidth = prof.halfW(innerX) * 0.97;
            for (int ix = 0; ix < 2; ++ix)
                for (int iy = 0; iy < 2; ++iy)
                    for (int iz = 0; iz < 2; ++iz) {
                        NodeParams params;
                        params.mass = (front ? 12.0 : 10.0) / 8.0;
                        params.group = group;
                        params.friction = 0.55;
                        nodes.push_back(car.addNode(group + "_" + std::to_string(ix * 4 + iy * 2 + iz),
                            {ix ? outerX : innerX, iy ? y1 : y0, iz ? halfWidth : -halfWidth}, params));
                    }
            // A compliant plastic skin on a coherent cage; sacrificial mount
            // groups release the complete assembly instead of stretching a mesh.
            connectAll(car, nodes, makeBeam(6.0e4, 24.0, 1.2e4, 8.0e4), nullptr);
            // Four clip groups, one per corner: a hit tears the bumper off corner by corner and it
            // can hang from the clips that held, instead of the whole assembly letting go as soon as
            // any single clip is overloaded (an inertial spike at the far end of the car was enough).
            BeamParams mount = makeBeam(8.0e4, 40.0, 8.0e3, 6.0e3); // clips fail before plastic yielding
            for (std::size_t corner = 0; corner < 4; ++corner) {
                mount.breakGroup = group + "_mounts_" + std::to_string(corner);
                for (auto anchor : nearestNodes(car, rig.bodyNodes, car.positions()[nodes[corner]], 3))
                    car.addBeam(nodes[corner], anchor, mount);
            }
            addBoxCollision(nodes, 0.0); // body exterior already supplies aerodynamic load
        }
    }

    // Independent door cages (front, and rear on four-door bodies). Latch disengagement is a
    // mechanism state, not a broken beam; every hinge/check strap can still fail in a collision.
    if (bd.detachableDoors) {
        auto makeDoor = [&](DoorLayout& door, const std::string& group, real rearX, real frontX, real hingeX, int channel, real sign, real openDeg) {
            door.rearX = rearX;
            door.frontX = frontX;
            door.inputChannel = channel;
            for (int ix = 0; ix < 2; ++ix)
                for (int iy = 0; iy < 2; ++iy)
                    for (int iz = 0; iz < 2; ++iz) {
                        const real x = ix ? door.frontX : door.rearX;
                        const auto section = prof.section(x);
                        const auto slot = iy ? 8 : 4;
                        NodeParams node;
                        node.mass = 26.0 / 8.0; node.group = group; node.friction = 0.5;
                        door.nodes.push_back(car.addNode(group + "_" + std::to_string(ix * 4 + iy * 2 + iz),
                            {x, section.y[slot] + (iy ? -0.03 : 0.03), sign * (section.z[slot] - (iz ? 0.0 : 0.11))}, node));
                    }
            const real hingeZ = sign * (prof.halfW(door.frontX) - 0.07);
            for (int end = 0; end < 2; ++end) {
                NodeParams node;
                node.mass = 2.0; node.group = group; node.friction = 0.5;
                const real y = end ? prof.yBelt(door.frontX) - 0.07 : prof.ySill(door.frontX) + 0.12;
                door.hingeNodes.push_back(car.addNode(group + "_hinge_" + std::to_string(end), {hingeX, y, hingeZ}, node));
            }
            auto cage = door.nodes;
            cage.insert(cage.end(), door.hingeNodes.begin(), door.hingeNodes.end());
            connectAll(car, cage, makeBeam(1.2e5, 45.0, 1.2e4, 8.0e4), nullptr);
            // Two bolted hinges, each its own break group: a door hangs from the surviving hinge
            // and only falls off when both have torn out.
            BeamParams hinge = makeBeam(1.5e5, 55.0, 1.4e4, 1.2e4);
            for (std::size_t h = 0; h < door.hingeNodes.size(); ++h) {
                hinge.breakGroup = group + (h == 0 ? "_hinge_lower" : "_hinge_upper");
                for (auto anchor : nearestNodes(car, rig.bodyNodes, car.positions()[door.hingeNodes[h]], 4))
                    door.hingeBeams.push_back(car.addBeam(door.hingeNodes[h], anchor, hinge));
            }
            BeamParams latch = makeBeam(1.0e5, 40.0, 1.2e4, 1.0e4);   // door latches hold > 10 kN
            latch.breakGroup = group + "_latch";
            for (auto node : {door.nodes[0], door.nodes[2]}) {
                const Vec3 at = car.positions()[node];
                bool inboard = false;   // a striker on the car's side of the latch node
                for (auto anchor : nearestNodes(car, rig.bodyNodes, at, 3)) {
                    door.latchBeams.push_back(car.addBeam(node, anchor, latch));
                    inboard = inboard || sign * (car.positions()[anchor].z - at.z) < -0.03;
                }
                // With all three strikers outboard in one plane (imported Trailhead rear doors) the
                // latch has a mirror-image rest pose with the door swung 10-13 degrees out, and the
                // door was caught there. One striker on the inside removes that second pose.
                if (!inboard)
                    for (auto candidate : nearestNodes(car, rig.bodyNodes, at, 16))
                        if (sign * (car.positions()[candidate].z - at.z) < -0.05) {
                            door.latchBeams.push_back(car.addBeam(node, candidate, latch));
                            break;
                        }
            }
            // A breakable check strap/assisted opening actuator, rooted inside the pillar ahead
            // of the door, provides a stable 68-degree inspection position.
            const auto moving = door.nodes[0];
            const Vec3 pivot{hingeX, car.positions()[moving].y, hingeZ};
            const Vec3 delta = car.positions()[moving] - pivot;
            const real angle = sign * openDeg * kPi / 180.0;
            const Vec3 opened = pivot + Vec3{std::cos(angle) * delta.x + std::sin(angle) * delta.z,
                delta.y, -std::sin(angle) * delta.x + std::cos(angle) * delta.z};
            // Of the body nodes around the ideal root, take the one with the most leverage (the
            // largest change of length between shut and open). The nearest one alone could sit
            // almost on the hinge axis with imported hinge lines (Meridian rear doors: 3.6 % stroke),
            // too weak to pull the door shut, and the doors stayed open.
            auto leverage = [&](std::uint32_t a) {
                const real shut = length(car.positions()[moving] - car.positions()[a]);
                return shut > 0.15 ? std::abs(length(opened - car.positions()[a]) / shut - 1.0) : 0.0;
            };
            auto anchor = nearestNodes(car, rig.bodyNodes, {hingeX - 0.15, car.positions()[moving].y + 0.1, hingeZ - sign * 0.45}, 1).front();
            if (leverage(anchor) < 0.3)
                for (auto candidate : nearestNodes(car, rig.bodyNodes, {hingeX - 0.15, car.positions()[moving].y + 0.1, hingeZ - sign * 0.45}, 12))
                    if (leverage(candidate) > leverage(anchor) + 0.05) anchor = candidate;
            const real closedLength = length(car.positions()[moving] - car.positions()[anchor]);
            BeamParams support = makeBeam(2.0e3, 500.0, kInf, 9.0e3);
            support.type = BeamType::Hydro;
            support.hydroInput = door.inputChannel;
            support.hydroRatio = length(opened - car.positions()[anchor]) / closedLength - 1.0;
            // The check strap is riveted next to the upper hinge and tears out with it.
            support.breakGroup = group + "_hinge_upper";
            door.supportBeams.push_back(car.addBeam(anchor, moving, support));
            addBoxCollision(door.nodes, 0.55);
            DoorMechanism mechanism;
            mechanism.nodes = std::move(cage);
            mechanism.hingeBeams = door.hingeBeams; mechanism.latchBeams = door.latchBeams;
            mechanism.supportBeams = door.supportBeams; mechanism.inputChannel = door.inputChannel;
            // Closing is a command: the latch catches a door that has slowed down within 20 cm of
            // shut and draws it in, as the hand pushing it would. On a tilted imported hinge line
            // the weak check-strap actuator alone left doors resting 1-12 degrees short.
            mechanism.catchTolerance = 0.20;
            mechanism.catchMaxSpeed = 0.3;   // a door still swinging fast is not grabbed
            car.addDoor(mechanism);
        };
        for (int side = 0; side < 2; ++side)
            makeDoor(build.layout.frontDoors[static_cast<std::size_t>(side)], side ? "door_right" : "door_left",
                     prof.xDoorFR, prof.xDoorFF, prof.xDoorFH, 2 + side, side ? 1.0 : -1.0, 68.0);
        // Rear doors from the rear wheel arch to the B-pillar, which stays body structure.
        if (bd.doors >= 4 && bd.detachableRearDoors)
            for (int side = 0; side < 2; ++side)
                makeDoor(build.layout.rearDoors[static_cast<std::size_t>(side)], side ? "rdoor_right" : "rdoor_left",
                         prof.xDoorRR, prof.xDoorRF, prof.xDoorRH, 4 + side, side ? 1.0 : -1.0, 62.0);
    }

    // ------------------------------------------------------------------ mass distribution
    {
        real fixedMass = 0.0;
        std::vector<bool> isBody(car.nodeCount(), false);
        for (std::uint32_t n : rig.bodyNodes) isBody[n] = true;
        for (std::size_t i = 0; i < car.nodeCount(); ++i)
            if (!isBody[i]) fixedMass += car.masses()[i];
        fixedMass += tire.totalMass();  // tyres are added below
        const real bodyMass = std::max({300.0, 2.0 * static_cast<real>(rig.bodyNodes.size()), def.chassis.curbMass - fixedMass});
        const real targetX = prof.xRA + def.chassis.frontWeight * bd.wheelbase;
        auto comFor = [&](real tilt, std::vector<real>& masses) {
            real wsum = 0;
            for (std::size_t k = 0; k < rig.bodyNodes.size(); ++k) {
                const real x = car.positions()[rig.bodyNodes[k]].x;
                const real w = nodeWeight[k] * std::max<real>(0.15, 1.0 + tilt * (x - 0.5 * L) / L);
                masses[k] = w;
                wsum += w;
            }
            // Include the minimum-node constraint in the allocation itself.
            // Clamping afterwards used to invent mass and shift the axle loads,
            // particularly on light cars with a heavily rear-biased shell.
            real scaleLo = 0.0, scaleHi = bodyMass / wsum;
            for (int iteration = 0; iteration < 45; ++iteration) {
                const real scale = 0.5 * (scaleLo + scaleHi);
                real total = 0.0;
                for (real weight : masses) total += std::max<real>(2.0, weight * scale);
                if (total > bodyMass) scaleHi = scale; else scaleLo = scale;
            }
            const real scale = 0.5 * (scaleLo + scaleHi);
            real mx = 0, m = 0;
            for (std::size_t k = 0; k < rig.bodyNodes.size(); ++k) {
                masses[k] = std::max<real>(2.0, masses[k] * scale);
                mx += masses[k] * car.positions()[rig.bodyNodes[k]].x;
                m += masses[k];
            }
            for (std::size_t i = 0; i < car.nodeCount(); ++i)
                if (!isBody[i]) { mx += car.masses()[i] * car.positions()[i].x; m += car.masses()[i]; }
            // Tyres sit at the axles.
            mx += 2.0 * (tire.massFor(true) * prof.xFA + tire.massFor(false) * prof.xRA);
            m += tire.totalMass();
            return mx / m;
        };
        std::vector<real> masses(rig.bodyNodes.size());
        real lo = -3.0, hi = 3.0;
        for (int it = 0; it < 50; ++it) {
            const real midT = 0.5 * (lo + hi);
            if (comFor(midT, masses) < targetX) lo = midT; else hi = midT;
        }
        comFor(0.5 * (lo + hi), masses);
        for (std::size_t k = 0; k < rig.bodyNodes.size(); ++k) car.setNodeMass(rig.bodyNodes[k], std::max<real>(2.0, masses[k]));
    }

    // ------------------------------------------------------------------ spring preload for design ride height
    {
        const real g = 9.81;
        real mTotal = car.totalMass() + tire.totalMass();
        real unsprung = 0.0;
        for (real u : unsprungMass) unsprung += u;
        const real sprung = mTotal - unsprung;
        // Sprung COM x (all non-unsprung nodes)
        real mx = 0, m = 0;
        for (std::size_t i = 0; i < car.nodeCount(); ++i) {
            const std::string& grp = car.groupNames()[car.nodeGroups()[i]];
            if (grp.rfind("upright_", 0) == 0) continue;
            mx += car.masses()[i] * car.positions()[i].x;
            m += car.masses()[i];
        }
        const real comX = mx / m;
        const real frontFrac = clamp01((comX - prof.xRA) / bd.wheelbase);
        for (int c = 0; c < 4; ++c) {
            const CarCorner& cn = rig.corners[static_cast<std::size_t>(c)];
            const real axleLoad = sprung * g * (cn.front ? frontFrac : 1.0 - frontFrac);
            const real wheelLoad = 0.5 * axleLoad;
            // Find the spring beam (first Normal beam between armMid and tower).
            for (std::size_t bi = 0; bi < car.beams().size(); ++bi) {
                Beam& bm = car.beams()[bi];
                const bool match = (bm.a == cn.armMid && bm.b == cn.tower);
                if (!match || bm.type != BeamType::Normal || bm.damp != 0.0) continue;
                const Vec3 pm = car.positions()[cn.armMid], pt = car.positions()[cn.tower];
                const real len = length(pt - pm);
                const real mr = cn.motionRatio;
                const real force = wheelLoad / mr;
                bm.baseRestLength = len + force / bm.spring;
                bm.restLength = bm.baseRestLength;
                car.beamParams()[bi].precompression = bm.baseRestLength / len;
                break;
            }
        }
    }

    // ------------------------------------------------------------------ wheels
    for (int c = 0; c < 4; ++c) {
        const CarCorner& cn = rig.corners[static_cast<std::size_t>(c)];
        PressureWheelSpec ws;
        ws.name = std::string(cn.front ? "F" : "R") + (cn.right ? "R" : "L");
        ws.hubRight = cn.right ? cn.hubOut : cn.hubIn;
        ws.hubLeft = cn.right ? cn.hubIn : cn.hubOut;
        ws.radius = tire.radius;
        ws.width = cn.front ? tire.width : tire.rearWidth();
        ws.numRays = tire.rays;
        ws.tireMass = tire.massFor(cn.front);
        ws.friction = tire.friction;
        ws.pressurePsi = tire.pressurePsi;
        const real rayScale = 12.0 / static_cast<real>(tire.rays);
        ws.spokeSpring = 1.05e5 * rayScale;
        ws.treadSpring = 1.3e5;
        // Sidewall and belt damping are the main source of rolling loss. Halved from 40 / 45 N*s/m:
        // rolling resistance at 100 km/h ~280 -> ~200 N (Kestrel), closer to real tyres (~130 N).
        ws.spokeDamp = 20.0 * rayScale;
        ws.treadDamp = 22.5;
        // Compliant tread contact: the rubber stores the leading-edge impact of each tread node
        // instead of a rigid projection destroying it. 2.7e5 N/m per node at 16 rays (scaled to the
        // ray count): at 4.5e5 every node strike excited a ~240 Hz tread resonance and c_rr peaked
        // at 0.021 somewhere in 80-100 km/h on every car (0.012 either side); now 0.006-0.015 from
        // 30 to 150 km/h. Half the old stiffness let a fallen branch snag a wheel arch at 70 km/h.
        ws.contactStiffness = 2.7e5 * 16.0 / static_cast<real>(tire.rays);
        // Inflated tread membrane at twice the bare p*w*R hoop tension: the factor stands in for the
        // belt's bending stiffness, which the skip-two chord beams only partly provide. Removes the
        // tread standing wave that peaked rolling loss around 145 km/h.
        ws.membranePressure = 2.0;
        // Speed-independent share of the rolling resistance. With it and 20 tread nodes
        // (c_rr 0.004 here) the coast-down rolling coefficient stays at ~0.007-0.014 from 30 to 130 km/h instead of
        // rising to 0.04 from the polygon impacts of 16 nodes.
        ws.rollingHysteresis = 0.004;
        ws.steered = cn.front;
        ws.ratedLoad = std::max<real>(1500.0, (car.totalMass() + tire.totalMass()) * 9.81 * (cn.front ? def.chassis.frontWeight : 1.0 - def.chassis.frontWeight) * 0.5);
        ws.braked = true;
        ws.handbraked = !cn.front;
        ws.driven = layout == DriveLayout::AWD || (layout == DriveLayout::FWD && cn.front) ||
                    (layout == DriveLayout::RWD && !cn.front);
        ws.brakeReactionA = cn.ubj;
        ws.brakeReactionB = cn.lbj;
        if (ws.driven) {
            if (cn.front || rig.diff < 0) {
                ws.driveReactionA = rig.engine[cn.right ? 7 : 6];  // front-top
                ws.driveReactionB = rig.engine[cn.right ? 5 : 4];  // front-bottom
            } else {
                // Differential housing on the rear subframe: vertical pair on this side.
                ws.driveReactionA = rig.corners[static_cast<std::size_t>(c)].upperF;
                ws.driveReactionB = rig.corners[static_cast<std::size_t>(c)].lowerF;
            }
        }
        car.addWheel(ws);
        // Tread surface for other bodies: without it a loose object's corner slipped between
        // two tread nodes (12 cm apart) into the tyre and jammed there, so a car could not roll
        // over a 4 cm block, it shoved it along and lost 30 km/h in 3 s.
        {
            const PressureWheel& wheel = car.wheels().back();
            const auto N = static_cast<std::size_t>(wheel.spec.numRays);
            const Vec3 hub = (car.positions()[ws.hubLeft] + car.positions()[ws.hubRight]) * 0.5;
            ColTriParams tread;
            tread.friction = tire.friction;
            tread.dragCoef = 0.0;   // the spinning tread is no aero surface
            tread.selfContact = false;
            for (std::size_t i = 0; i < N; ++i) {
                const std::uint32_t a0 = wheel.treadNodes[i], a1 = wheel.treadNodes[(i + 1) % N];
                const std::uint32_t b0 = wheel.treadNodes[N + i], b1 = wheel.treadNodes[N + (i + 1) % N];
                for (const auto& t : {std::array<std::uint32_t, 3>{a0, a1, b1}, std::array<std::uint32_t, 3>{a0, b1, b0}}) {
                    const Vec3 pa = car.positions()[t[0]], pb = car.positions()[t[1]], pc = car.positions()[t[2]];
                    const Vec3 ctr = (pa + pb + pc) / 3.0;
                    // Outward radially, measured perpendicular to the axle.
                    Vec3 axle = car.positions()[ws.hubLeft] - car.positions()[ws.hubRight];
                    axle = axle / std::max<real>(1e-9, length(axle));
                    Vec3 radial = ctr - hub;
                    radial = radial - axle * dot(radial, axle);
                    if (dot(cross(pb - pa, pc - pa), radial) < 0) car.addTriangle(t[0], t[2], t[1], tread);
                    else car.addTriangle(t[0], t[1], t[2], tread);
                }
            }
        }
    }

    // ------------------------------------------------------------------ powertrain
    PowertrainSpec pt;
    pt.layout = layout;
    if (!ed.torqueCurve.empty()) pt.torqueCurve = ed.torqueCurve;
    pt.idleRpm = ed.idleRpm;
    pt.redlineRpm = ed.redlineRpm;
    pt.engineInertia = ed.inertia;
    pt.engineFrictionNm = ed.friction;
    pt.engineBraking = ed.engineBraking;
    real peak = 0;
    for (auto& tq : pt.torqueCurve) peak = std::max(peak, tq.second);
    pt.clutchMaxTorque = peak * 1.7;
    pt.clutchStiffness = 18.0 * std::max<real>(1.0, peak / 250.0);
    pt.forwardGears = ed.gears;
    pt.reverseRatio = ed.reverse;
    pt.finalDrive = ed.finalDrive;
    pt.automatic = ed.automatic;
    pt.shiftUpRpm = ed.shiftUpRpm;
    pt.shiftDownRpm = ed.shiftDownRpm;
    pt.maxBrakeTorque = ed.maxBrakeTorque;
    pt.frontBrakeBias = ed.frontBrakeBias;
    pt.handbrakeTorque = ed.handbrakeTorque;
    pt.lsdLockingCoeff = ed.lsd;
    car.setPowertrain(pt);

    // ------------------------------------------------------------------ collision skin (ColTris)
    {
        ColTriParams tp;
        tp.friction = 0.5;
        tp.dragCoef = 0.55;
        const real yAxis = 0.5 * (bd.groundClearance + bd.height);
        auto addTri = [&](std::int64_t a, std::int64_t b, std::int64_t c) {
            ColTriParams triParams = tp;
            if (a < 0 || b < 0 || c < 0 || a == b || b == c || a == c) return;
            auto ua = static_cast<std::uint32_t>(a), ub = static_cast<std::uint32_t>(b), uc = static_cast<std::uint32_t>(c);
            const Vec3 pa = car.positions()[ua], pb = car.positions()[ub], pc = car.positions()[uc];
            const Vec3 n = cross(pb - pa, pc - pa);
            if (length(n) < 1e-6) return;
            const Vec3 ctr = (pa + pb + pc) / 3.0;
            auto isShellTop = [&](std::uint32_t node) {
                for (const auto& station : rig.shell)
                    if (station[4][0] == node || station[4][1] == node) return true;
                return false;
            };
            if (ctr.x > prof.xCowl + 0.025 && ctr.x < L - 0.12 &&
                isShellTop(ua) && isShellTop(ub) && isShellTop(uc)) {
                // The bonnet replaces the top skin, but a triangle reaching the nose station closes
                // the slot between the bonnet's front edge and the grille; only the bonnet passes it.
                if (std::max({pa.x, pb.x, pc.x}) < L - 0.06) return;
                triParams.selfContact = false;
            }
            // Skin above the (flat) bonnet cage would trap a released bonnet under it: crowned and
            // boxy bonnets rise above the straight line between hinge and latch. Skin below it stays,
            // the closed bonnet rests on that.
            {
                const auto& bn = build.layout.bonnetNodes;
                const Vec3 rear = car.positions()[bn[0]], front = car.positions()[bn[2]];
                const real u = std::clamp((ctr.x - rear.x) / (front.x - rear.x), 0.0, 1.0);
                const real plane = rear.y + (front.y - rear.y) * u;
                if (ctr.x > rear.x && ctr.x < front.x && std::abs(ctr.z) < prof.halfW(ctr.x) * 0.95) {
                    if (std::min({pa.y, pb.y, pc.y}) > plane - 0.005) return;
                    // Nose skin sloping up over a front corner (latch side) would hold it down. It
                    // stays for everything else: without it the corners were open holes into the
                    // bonnet bay, and a struck cone caught inside lifted the car's nose off its wheels.
                    const real dz = std::abs(ctr.z) - std::abs(front.z);
                    if (front.x - ctr.x < 0.25 && dz > -0.25 && std::max({pa.y, pb.y, pc.y}) > plane + 0.01)
                        triParams.selfContact = false;
                }
            }
            // Lower outer end skins belong to the bumper, not a second fixed
            // collision sheet remaining in space after the fascia detaches.
            if (bd.detachableBumpers) {
                if (std::min({pa.x, pb.x, pc.x}) > L - 0.12 &&
                    std::max({pa.y, pb.y, pc.y}) < bd.noseHeight - 0.16) return;
                if (std::max({pa.x, pb.x, pc.x}) < 0.12 &&
                    std::max({pa.y, pb.y, pc.y}) < bd.tailHeight - 0.28) return;
            }
            const real apertureRear = bd.doors >= 4 && bd.detachableRearDoors ? prof.xDoorRR - 0.029 : prof.xDoorFR - 0.029;
            if (bd.detachableDoors && ctr.x > apertureRear && ctr.x < prof.xDoorFF + 0.03 &&
                std::abs(ctr.z) > prof.hw * 0.6 &&
                (pa.z * pb.z > 0 && pb.z * pc.z > 0) &&
                ctr.y > prof.ySill(ctr.x) - 0.01) return;
            // Outward = away from the car's centre line, including along it near the ends: sliver
            // triangles at the nose and tail must not face into the car, or they hold a foreign
            // node from behind (two cars hooked together after a rear-end collision).
            const real axisX = std::clamp(ctr.x, 0.55, L - 0.55);
            Vec3 out{ctr.x - axisX, ctr.y - yAxis, ctr.z};
            if (ctr.x > L - 0.05) out.x += 1.0;
            if (ctr.x < 0.05) out.x -= 1.0;
            if (dot(n, out) < 0) std::swap(ub, uc);
            car.addTriangle(ua, ub, uc, triParams);
        };
        auto ring = [&](std::size_t i) {
            std::vector<std::int64_t> loop;
            for (int slot = 0; slot < 5; ++slot)
                if (rig.shell[i][static_cast<std::size_t>(slot)][1] >= 0) loop.push_back(rig.shell[i][static_cast<std::size_t>(slot)][1]);
            for (int slot = 4; slot >= 0; --slot)
                if (rig.shell[i][static_cast<std::size_t>(slot)][0] >= 0) loop.push_back(rig.shell[i][static_cast<std::size_t>(slot)][0]);
            return loop;
        };
        for (std::size_t i = 0; i + 1 < NS; ++i) {
            const auto A = ring(i), B = ring(i + 1);
            // Zip two loops of possibly different length by normalized arc parameter.
            std::size_t ia = 0, ib = 0;
            const std::size_t na = A.size(), nb = B.size();
            while (ia < na || ib < nb) {
                const real ta = static_cast<real>(ia + 1) / static_cast<real>(na);
                const real tb = static_cast<real>(ib + 1) / static_cast<real>(nb);
                if (ia < na && (ib >= nb || ta <= tb)) {
                    addTri(A[ia % na], A[(ia + 1) % na], B[ib % nb]);
                    ++ia;
                } else {
                    addTri(A[ia % na], B[(ib + 1) % nb], B[ib % nb]);
                    ++ib;
                }
            }
        }
        for (std::size_t i : {std::size_t(0), NS - 1}) {
            const auto loop = ring(i);
            for (std::size_t k = 1; k + 1 < loop.size(); ++k) addTri(loop[0], loop[k], loop[k + 1]);
        }
    }

    // Register only after every target collision triangle and mount exists.
    car.addSelfCollisionPanel("bonnet", {"body", "engine"}, {"bonnet_latch", "bonnet_hinge"});
    if (bd.detachableBumpers) {
        for (const std::string end : {"bumper_front", "bumper_rear"})
            car.addSelfCollisionPanel(end, {"body"}, {end + "_mounts_0", end + "_mounts_1", end + "_mounts_2", end + "_mounts_3"});
    }

    if (bd.detachableDoors) {
        std::vector<std::string> doors = {"door_left", "door_right"};
        if (bd.doors >= 4 && bd.detachableRearDoors) doors.insert(doors.end(), {"rdoor_left", "rdoor_right"});
        for (const std::string& door : doors)
            // Contact only once a latch or hinge is torn: a door opened by hand swings on intact
            // hinges, and with imported hinge lines its upper corner caught on the roof edge
            // while closing (Meridian rear doors stayed 9-60 degrees open).
            car.addSelfCollisionPanel(door, {"body"}, {door + "_latch", door + "_hinge_lower", door + "_hinge_upper"}, 0.008, false);
    }
    if (bd.detachableTailgate) car.addSelfCollisionPanel("tailgate", {"body"}, {"tailgate_latch", "tailgate_hinge"});

    // ------------------------------------------------------------------ systems
    {
        const real hwi = prof.hw;
        for (std::size_t bi = 0; bi < shellBeamEnd; ++bi) {
            const Beam& bm = car.beams()[bi];
            const Vec3 m = (car.positions()[bm.a] + car.positions()[bm.b]) * 0.5;
            if (m.x > prof.xFA - 0.1) sys.zoneBeams[kZoneFront].push_back(static_cast<std::uint32_t>(bi));
            if (m.x < prof.xRA + 0.1) sys.zoneBeams[kZoneRear].push_back(static_cast<std::uint32_t>(bi));
            if (m.z < -0.35 * hwi) sys.zoneBeams[kZoneLeft].push_back(static_cast<std::uint32_t>(bi));
            if (m.z > 0.35 * hwi) sys.zoneBeams[kZoneRight].push_back(static_cast<std::uint32_t>(bi));
            if (m.y > bd.beltHeight + 0.1) sys.zoneBeams[kZoneRoof].push_back(static_cast<std::uint32_t>(bi));
            if (m.y < prof.ySill(m.x) + 0.02) sys.zoneBeams[kZoneUnder].push_back(static_cast<std::uint32_t>(bi));
        }
        sys.coolantCapacityL = 6.5;
        // A radiator must be able to reject roughly the engine's full power at ~60 K over ambient
        // with highway airflow, otherwise sustained full throttle overheats an undamaged car.
        real peakPowerW = 0.0;
        for (const auto& tq : ed.torqueCurve) peakPowerW = std::max(peakPowerW, tq.second * tq.first * 2.0 * kPi / 60.0);
        sys.radiatorUA = std::max(ed.radiatorUA, peakPowerW / 58.0);
        sys.fuelCapacityL = ed.fuelCapacity;
        sys.fuelL = ed.fuelCapacity * 0.8;
        sys.bsfcGPerKWh = ed.bsfc;
        car.setSystems(sys);
    }

    // ------------------------------------------------------------------ stability guard
    // Explicit integration limit: soften only the shell beams, and only if a shell node is the problem.
    {
        const real dt = 1.0 / 2000.0;
        auto shellRatio = [&]() {
            std::vector<real> sumK(car.nodeCount(), 0.0);
            for (const Beam& bm : car.beams()) {
                const real k = std::max(bm.spring, bm.springExp);
                sumK[bm.a] += k;
                sumK[bm.b] += k;
            }
            real worst = 0.0;
            for (std::uint32_t n : rig.bodyNodes)
                worst = std::max(worst, dt * std::sqrt(2.0 * sumK[n] * car.invMasses()[n]) * 0.5);
            return worst;
        };
        int guard = 0;
        while (shellRatio() > 0.8 && guard++ < 6)
            for (std::size_t bi = 0; bi < shellBeamEnd; ++bi) car.beams()[bi].spring *= 0.9;
    }

    // ------------------------------------------------------------------ layout + visuals
    auto findStation = [&](real x) {
        std::size_t bestI = 0;
        real best = 1e9;
        for (std::size_t i = 0; i < NS; ++i)
            if (std::abs(stations[i] - x) < best) { best = std::abs(stations[i] - x); bestI = i; }
        return bestI;
    };
    // Orientation references inside the stiff passenger cell (front: just behind the firewall,
    // rear: in front of the rear seat bulkhead) so crash damage does not tilt the reference frame.
    const std::size_t sf = findStation(prof.xCowl - 0.15), sr = findStation(std::max(prof.xRwBase + 0.15, prof.xRA + prof.Ra + 0.05));
    build.layout.refFL = static_cast<std::uint32_t>(rig.shell[sf][0][0]);
    build.layout.refFR = static_cast<std::uint32_t>(rig.shell[sf][0][1]);
    build.layout.refRL = static_cast<std::uint32_t>(rig.shell[sr][0][0]);
    build.layout.refRR = static_cast<std::uint32_t>(rig.shell[sr][0][1]);
    build.layout.bodyNodes = rig.bodyNodes;
    build.layout.engineNodes = rig.engine;
    build.layout.radiatorNodes = rig.radiator;
    build.layout.length = bd.length;
    build.layout.width = bd.width;
    build.layout.height = bd.height;

    // ------------------------------------------------------------------ aerodynamic calibration
    // Per-triangle pressure drag over a closed node-beam skin behaves like a box of flat
    // plates and overestimates drag ~2.5x. Measure the skin head-on at unit speed (the same
    // formula as World::accumulateAerodynamicForces) and scale it to the specified Cd * A.
    {
        real cd = bd.dragCoefficient;
        if (cd <= 0.0) {
            switch (bd.style) {
                case BodyStyle::Sedan: cd = 0.29; break;
                case BodyStyle::Coupe: cd = 0.31; break;
                case BodyStyle::SUV: cd = 0.36; break;
                default: cd = 0.32; break;
            }
        }
        const real area = bd.frontalArea > 0.0 ? bd.frontalArea : 0.84 * bd.width * (bd.height - bd.groundClearance);
        real fx = 0.0;
        for (const ColTri& tri : car.triangles()) {
            if (tri.dragCoef <= 0.0) continue;
            const auto& p = car.positions();
            const Vec3 cr = cross(p[tri.b] - p[tri.a], p[tri.c] - p[tri.a]);
            const real dbl = length(cr);
            if (dbl < 1e-8) continue;
            const Vec3 n = cr / dbl;
            const real triArea = 0.5 * dbl;
            fx += -n.x * (0.5 * tri.dragCoef * triArea * n.x) - 0.015 * tri.dragCoef * triArea;
        }
        const real simDragArea = -2.0 * fx;
        if (simDragArea > 1e-6) {
            const real scale = cd * area / simDragArea;
            for (ColTri& tri : car.triangles()) tri.dragCoef *= scale;
        }
        build.layout.dragArea = cd * area;
    }

    buildCarVisual(build, prof, rig);
    setRigidParts(build.visual, {build.layout.bonnetNodes, build.layout.frontDoors[0].nodes, build.layout.frontDoors[1].nodes,
                                 build.layout.rearDoors[0].nodes, build.layout.rearDoors[1].nodes,
                                 build.layout.frontBumperNodes, build.layout.rearBumperNodes, build.layout.tailgateNodes});
    build.restPositions = car.positions();
    return build;
}

}  // namespace sb
