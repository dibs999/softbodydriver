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
    const BeamParams mountBeam = makeBeam(9.0e5, 150.0, 5.0e4, 1.4e5);

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

        auto node = [&](const std::string& n, Vec3 p, real m, const std::string& group) {
            NodeParams np;
            np.mass = m;
            np.friction = 0.6;
            np.group = group;
            p.z *= s;
            return car.addNode(pre + n, p, np);
        };
        const std::string up = "upright_" + pre;
        const real hubMass = 0.5 * (tire.rimMass + 9.0);
        cn.hubIn = node("hub_in", {xa, R, tr - 0.085}, hubMass, up);
        cn.hubOut = node("hub_out", {xa, R, tr + 0.085}, hubMass, up);
        // Ball joints sit inside the rim: small scrub radius, ~9 deg kingpin inclination.
        cn.lbj = node("lbj", {xa, R - 0.15, tr - 0.07}, 6.0, up);
        cn.ubj = node("ubj", {xa - 0.02, R + 0.19, tr - 0.125}, 5.0, up);
        cn.steerArm = node("steer_arm", {xa - 0.14, R - 0.03, tr - 0.12}, 5.0, up);
        const real pivZ = std::min<real>(0.36, tr - 0.40);
        cn.lowerF = node("lower_f", {xa + 0.18, R - 0.12, pivZ}, 4.0, "subframe");
        cn.lowerR = node("lower_r", {xa - 0.18, R - 0.12, pivZ}, 4.0, "subframe");
        cn.upperF = node("upper_f", {xa + 0.13, R + 0.21, tr - 0.45}, 3.5, "subframe");
        cn.upperR = node("upper_r", {xa - 0.13, R + 0.21, tr - 0.45}, 3.5, "subframe");
        cn.rackEnd = node("rack_end", {xa - 0.14, R - 0.03, pivZ}, 3.5, "subframe");
        // The coilover acts directly on the knuckle at the lower ball joint (motion ratio ~0.95),
        // which keeps the spring path rigid under bump-stop loads.
        cn.armMid = cn.lbj;
        cn.tower = node("tower", {xa, R + 0.43, tr - 0.29}, 10.0, "subframe");
        unsprungMass[static_cast<std::size_t>(c)] = 2 * hubMass + 6 + 5 + 5 + tire.tireMass;

        // Subframe nodes are bolted to the body.
        for (std::uint32_t n : {cn.lowerF, cn.lowerR, cn.upperF, cn.upperR, cn.rackEnd, cn.tower})
            attach(n, 4, mountBeam, &sb);
        car.addBeam(cn.lowerF, cn.lowerR, mountBeam);
        car.addBeam(cn.upperF, cn.upperR, mountBeam);

        // Upright: rigid knuckle.
        const BeamParams knuckle = makeBeam(3.5e6, 220.0, 1.6e5, 4.0e5);
        std::vector<std::uint32_t> upr = {cn.hubIn, cn.hubOut, cn.lbj, cn.ubj, cn.steerArm};
        connectAll(car, upr, knuckle, &sb);
        // Wishbones.
        const BeamParams arm = makeBeam(1.6e6, 140.0, 4.5e4, 1.2e5);
        for (std::uint32_t p : {cn.lowerF, cn.lowerR}) sb.push_back(car.addBeam(p, cn.lbj, arm));
        for (std::uint32_t p : {cn.upperF, cn.upperR}) sb.push_back(car.addBeam(p, cn.ubj, arm));
        // Tie rod (hydro steering on the front axle, fixed toe link on the rear).
        BeamParams tie = arm;
        tie.spring = 2.2e6;
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
    }

    // ------------------------------------------------------------------ engine, radiator, oil pan
    const EngineDef& ed = def.engine;
    {
        const real ex0 = prof.xFA - 0.42, ex1 = prof.xFA + 0.14;
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
        BeamParams panB = makeBeam(4.0e5, 90.0, 4.0e3, 2.6e4);
        for (std::uint32_t p : rig.oilPan)
            for (int ix = 0; ix < 2; ++ix)
                for (int iz = 0; iz < 2; ++iz)
                    sys.oilPanBeams.push_back(car.addBeam(p, rig.engine[static_cast<std::size_t>(ix * 4 + iz)], panB));
        sys.oilPanBeams.push_back(car.addBeam(rig.oilPan[0], rig.oilPan[1], panB));

        // Radiator in front of the engine, behind the bumper.
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
        // Engine -> firewall.
        BeamParams fw = contact;
        fw.precompression = 0.35;
        std::size_t cowlStation = 0;
        real best = 1e9;
        for (std::size_t i = 0; i < NS; ++i)
            if (std::abs(stations[i] - prof.xCowl) < best) { best = std::abs(stations[i] - prof.xCowl); cowlStation = i; }
        for (int iy = 0; iy < 2; ++iy)
            for (int iz = 0; iz < 2; ++iz) {
                const std::uint32_t n = rig.engine[static_cast<std::size_t>(0 * 4 + iy * 2 + iz)];
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
        const real y = prof.yBottom(prof.xRA + 0.5) + 0.07;
        for (int ix = 0; ix < 2; ++ix)
            for (int iz = 0; iz < 2; ++iz)
                rig.fuelTank.push_back(car.addNode("tank" + std::to_string(ix * 2 + iz),
                                                   {prof.xRA + (ix ? 0.82 : 0.30), y, iz ? 0.33 : -0.33}, np));
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

    // ------------------------------------------------------------------ mass distribution
    {
        real fixedMass = 0.0;
        std::vector<bool> isBody(car.nodeCount(), false);
        for (std::uint32_t n : rig.bodyNodes) isBody[n] = true;
        for (std::size_t i = 0; i < car.nodeCount(); ++i)
            if (!isBody[i]) fixedMass += car.masses()[i];
        fixedMass += 4.0 * tire.tireMass;  // tyres are added below
        const real bodyMass = std::max<real>(300.0, def.chassis.curbMass - fixedMass);
        const real targetX = prof.xRA + def.chassis.frontWeight * bd.wheelbase;
        auto comFor = [&](real tilt, std::vector<real>& masses) {
            real wsum = 0;
            for (std::size_t k = 0; k < rig.bodyNodes.size(); ++k) {
                const real x = car.positions()[rig.bodyNodes[k]].x;
                const real w = nodeWeight[k] * std::max<real>(0.15, 1.0 + tilt * (x - 0.5 * L) / L);
                masses[k] = w;
                wsum += w;
            }
            real mx = 0, m = 0;
            for (std::size_t k = 0; k < rig.bodyNodes.size(); ++k) {
                masses[k] *= bodyMass / wsum;
                mx += masses[k] * car.positions()[rig.bodyNodes[k]].x;
                m += masses[k];
            }
            for (std::size_t i = 0; i < car.nodeCount(); ++i)
                if (!isBody[i]) { mx += car.masses()[i] * car.positions()[i].x; m += car.masses()[i]; }
            // Tyres sit at the axles.
            mx += 2.0 * tire.tireMass * (prof.xFA + prof.xRA);
            m += 4.0 * tire.tireMass;
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
        real mTotal = car.totalMass() + 4.0 * tire.tireMass;
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
            for (Beam& bm : car.beams()) {
                const bool match = (bm.a == cn.armMid && bm.b == cn.tower);
                if (!match || bm.type != BeamType::Normal || bm.damp != 0.0) continue;
                const Vec3 pm = car.positions()[cn.armMid], pt = car.positions()[cn.tower];
                const real len = length(pt - pm);
                const real mr = cn.motionRatio;
                const real force = wheelLoad / mr;
                bm.baseRestLength = len + force / bm.spring;
                bm.restLength = bm.baseRestLength;
                bm.params.precompression = bm.baseRestLength / len;
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
        ws.width = tire.width;
        ws.numRays = tire.rays;
        ws.tireMass = tire.tireMass;
        ws.friction = tire.friction;
        ws.pressurePsi = tire.pressurePsi;
        const real rayScale = 12.0 / static_cast<real>(tire.rays);
        ws.spokeSpring = 1.05e5 * rayScale;
        ws.treadSpring = 1.3e5;
        ws.spokeDamp = 40.0 * rayScale;
        ws.steered = cn.front;
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
            if (a < 0 || b < 0 || c < 0 || a == b || b == c || a == c) return;
            auto ua = static_cast<std::uint32_t>(a), ub = static_cast<std::uint32_t>(b), uc = static_cast<std::uint32_t>(c);
            const Vec3 pa = car.positions()[ua], pb = car.positions()[ub], pc = car.positions()[uc];
            const Vec3 n = cross(pb - pa, pc - pa);
            if (length(n) < 1e-6) return;
            const Vec3 ctr = (pa + pb + pc) / 3.0;
            Vec3 out{0.0, ctr.y - yAxis, ctr.z};
            if (ctr.x > L - 0.05) out.x += 1.0;
            if (ctr.x < 0.05) out.x -= 1.0;
            if (dot(n, out) < 0) std::swap(ub, uc);
            car.addTriangle(ua, ub, uc, tp);
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
        sys.radiatorUA = ed.radiatorUA;
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

    buildCarVisual(build, prof, rig);
    build.restPositions = car.positions();
    return build;
}

}  // namespace sb
