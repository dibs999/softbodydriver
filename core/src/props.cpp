#include "sbcore/props.hpp"

#include <cmath>
#include <stdexcept>

namespace sb {
namespace {
constexpr real kPi = 3.14159265358979323846;

void connectAll(SoftBody& body, const std::vector<std::uint32_t>& nodes, const BeamParams& p) {
    for (std::size_t i = 0; i < nodes.size(); ++i)
        for (std::size_t j = i + 1; j < nodes.size(); ++j) body.addBeam(nodes[i], nodes[j], p);
}

// Outward-facing triangle (normal away from `centre`).
void outwardTri(SoftBody& body, std::uint32_t a, std::uint32_t b, std::uint32_t c, const Vec3& centre, const ColTriParams& p) {
    const auto& pos = body.positions();
    if (dot(cross(pos[b] - pos[a], pos[c] - pos[a]), (pos[a] + pos[b] + pos[c]) / 3.0 - centre) < 0) std::swap(b, c);
    body.addTriangle(a, b, c, p);
}

PropBuild buildCone() {
    PropBuild out;
    out.kind = PropKind::Cone;
    SoftBody& b = out.body;
    b.setName("cone");
    std::vector<std::uint32_t> base, mid;
    NodeParams heavy;  // rubber base
    // PVC slides: with rubber-like friction a cone squashed between a tyre and the bumper braked
    // the car like a chock (up to 19 km/h lost in a strike at the tyre's inner edge).
    heavy.mass = 0.7875; heavy.friction = 0.45; heavy.group = "prop";
    NodeParams light = heavy;
    light.mass = 0.30; light.friction = 0.2;
    const real hb = 0.19;
    for (int i = 0; i < 4; ++i) {
        const real sx = (i & 1) ? hb : -hb, sz = (i & 2) ? hb : -hb;
        base.push_back(b.addNode("base" + std::to_string(i), {sx, 0.02, sz}, heavy));
    }
    for (int i = 0; i < 4; ++i) {
        const real a = kPi * 0.5 * i + kPi * 0.25;
        mid.push_back(b.addNode("mid" + std::to_string(i), {0.10 * std::cos(a), 0.34, 0.10 * std::sin(a)}, light));
    }
    NodeParams tip = light;
    tip.mass = 0.15;
    const auto apex = b.addNode("apex", {0.0, 0.74, 0.0}, tip);
    std::vector<std::uint32_t> all = base;
    all.insert(all.end(), mid.begin(), mid.end());
    all.push_back(apex);
    // Flexible PVC: soft, damped, never yields or breaks; it lies down and pops back. A hollow
    // cone barely resists being squashed (a car runs it flat) but does not stretch: with one
    // stiffness for both, a cone run under the front was held at full height, stretched over the
    // bumper with its base under a front tyre, and dragged the car down by up to 19 km/h.
    BeamParams pvc;
    pvc.type = BeamType::Anisotropic;
    pvc.spring = 500.0;          // compression
    pvc.springExpansion = 3.0e3;
    pvc.damp = 8.0;
    pvc.dampExpansion = 8.0;
    // PVC hardly stretches: beyond 15 % a stiff limiter. Without it a cone node caught between
    // tread and road was carried round the tyre while the base stayed on the road, the cone was
    // drawn out to 1.5 m around the wheel and braked the car by up to 13 km/h.
    pvc.longBound = 0.15;
    pvc.boundSpring = 6.0e4;
    connectAll(b, all, pvc);
    ColTriParams skin;
    skin.friction = 0.2;
    skin.dragCoef = 0.6;
    const Vec3 c{0, 0.30, 0};
    // Base plate (both faces: it is what lies on the road), sides, top.
    outwardTri(b, base[0], base[1], base[3], {0, 0.5, 0}, skin);
    outwardTri(b, base[0], base[3], base[2], {0, 0.5, 0}, skin);
    // Mid nodes sit at 45, 135, 225, 315 deg: between base corners (+,+), (-,+), (-,-), (+,-).
    const std::uint32_t corner[4] = {base[3], base[2], base[0], base[1]};  // (+,+) (-,+) (-,-) (+,-)
    for (int k = 0; k < 4; ++k) {
        const auto m0 = mid[static_cast<std::size_t>(k)], m1 = mid[static_cast<std::size_t>((k + 1) % 4)];
        const auto c0 = corner[k], c1 = corner[(k + 1) % 4];
        outwardTri(b, c0, c1, m1, c, skin);
        outwardTri(b, c0, m1, m0, c, skin);
        outwardTri(b, m0, m1, apex, c, skin);
    }
    out.frameOrigin = base[0];
    out.frameX = base[1];
    out.frameY = apex;
    out.restPositions = b.positions();
    return out;
}

PropBuild buildBarrel() {
    PropBuild out;
    out.kind = PropKind::Barrel;
    SoftBody& b = out.body;
    b.setName("barrel");
    constexpr int N = 8;
    const real r = 0.29, h = 0.88;
    NodeParams np;
    np.mass = 20.0 / (3 * N + 2);
    np.friction = 0.5;
    np.group = "prop";
    std::vector<std::vector<std::uint32_t>> rings(3);
    for (int ring = 0; ring < 3; ++ring)
        for (int i = 0; i < N; ++i) {
            const real a = 2.0 * kPi * i / N;
            rings[static_cast<std::size_t>(ring)].push_back(b.addNode("r" + std::to_string(ring) + "_" + std::to_string(i),
                {r * std::cos(a), 0.01 + h * 0.5 * ring, r * std::sin(a)}, np));
        }
    const auto bottom = b.addNode("bottom", {0, 0.01, 0}, np);
    const auto top = b.addNode("top", {0, 0.01 + h, 0}, np);
    // Thin steel sheet: stiff, dents under a hard hit, holds together.
    BeamParams sheet;
    sheet.spring = 1.2e5;
    sheet.damp = 60.0;
    sheet.deform = 3.5e3;
    sheet.strength = 4.0e4;
    BeamParams brace = sheet;      // internal stiffness: the cylinder keeps its round section
    brace.spring = 4.0e4;
    brace.deform = 2.5e3;
    for (int ring = 0; ring < 3; ++ring) {
        const auto& R = rings[static_cast<std::size_t>(ring)];
        for (int i = 0; i < N; ++i) {
            b.addBeam(R[static_cast<std::size_t>(i)], R[static_cast<std::size_t>((i + 1) % N)], sheet);
            b.addBeam(R[static_cast<std::size_t>(i)], R[static_cast<std::size_t>((i + N / 2) % N)], brace);
            b.addBeam(R[static_cast<std::size_t>(i)], R[static_cast<std::size_t>((i + 2) % N)], brace);
        }
    }
    for (int ring = 0; ring < 2; ++ring) {
        const auto& A = rings[static_cast<std::size_t>(ring)];
        const auto& B = rings[static_cast<std::size_t>(ring + 1)];
        for (int i = 0; i < N; ++i) {
            b.addBeam(A[static_cast<std::size_t>(i)], B[static_cast<std::size_t>(i)], sheet);
            b.addBeam(A[static_cast<std::size_t>(i)], B[static_cast<std::size_t>((i + 1) % N)], sheet);
            b.addBeam(A[static_cast<std::size_t>((i + 1) % N)], B[static_cast<std::size_t>(i)], brace);
        }
    }
    for (int i = 0; i < N; ++i) {
        b.addBeam(bottom, rings[0][static_cast<std::size_t>(i)], sheet);
        b.addBeam(top, rings[2][static_cast<std::size_t>(i)], sheet);
        b.addBeam(bottom, rings[1][static_cast<std::size_t>(i)], brace);
        b.addBeam(top, rings[1][static_cast<std::size_t>(i)], brace);
    }
    b.addBeam(bottom, top, brace);
    ColTriParams skin;
    skin.friction = 0.45;
    skin.dragCoef = 0.8;
    const Vec3 c{0, 0.01 + h * 0.5, 0};
    for (int ring = 0; ring < 2; ++ring)
        for (int i = 0; i < N; ++i) {
            const auto& A = rings[static_cast<std::size_t>(ring)];
            const auto& B = rings[static_cast<std::size_t>(ring + 1)];
            const auto a0 = A[static_cast<std::size_t>(i)], a1 = A[static_cast<std::size_t>((i + 1) % N)];
            const auto b0 = B[static_cast<std::size_t>(i)], b1 = B[static_cast<std::size_t>((i + 1) % N)];
            outwardTri(b, a0, a1, b1, c, skin);
            outwardTri(b, a0, b1, b0, c, skin);
        }
    for (int i = 0; i < N; ++i) {
        outwardTri(b, bottom, rings[0][static_cast<std::size_t>(i)], rings[0][static_cast<std::size_t>((i + 1) % N)], c, skin);
        outwardTri(b, top, rings[2][static_cast<std::size_t>(i)], rings[2][static_cast<std::size_t>((i + 1) % N)], c, skin);
    }
    out.frameOrigin = bottom;
    out.frameX = rings[0][0];
    out.frameY = top;
    out.restPositions = b.positions();
    return out;
}
PropBuild buildBarrier() {
    PropBuild out;
    out.kind = PropKind::Barrier;
    SoftBody& b = out.body;
    b.setName("barrier");
    // Two layers of four nodes (a box tapering to a narrower top), water ballast in the lower ones.
    NodeParams low;
    low.mass = 55.0;   // 4 x 55 + 4 x 20 = 300 kg
    low.friction = 0.6;
    low.group = "prop";
    NodeParams high = low;
    high.mass = 20.0;
    std::vector<std::uint32_t> n;
    for (int layer = 0; layer < 2; ++layer)
        for (int i = 0; i < 4; ++i) {
            const real hx = 0.60, hz = layer ? 0.11 : 0.225;
            const real x = (i & 1) ? hx : -hx, z = (i & 2) ? hz : -hz;
            n.push_back(b.addNode("b" + std::to_string(layer * 4 + i), {x, layer ? 0.80 : 0.02, z}, layer ? high : low));
        }
    // Polyethylene shell full of water: firm, yields under a car strike and stays squashed.
    BeamParams shell;
    shell.spring = 1.6e5;
    shell.damp = 900.0;
    shell.deform = 1.2e4;
    shell.strength = 3.0e5;
    shell.deformLimit = 0.35;
    shell.deformLimitExpansion = 0.25;
    connectAll(b, n, shell);
    ColTriParams skin;
    skin.friction = 0.5;
    skin.dragCoef = 0.9;
    const Vec3 c{0, 0.4, 0};
    const int faces[6][4] = {{0, 1, 3, 2}, {4, 6, 7, 5}, {0, 4, 5, 1}, {2, 3, 7, 6}, {0, 2, 6, 4}, {1, 5, 7, 3}};
    for (const auto& f : faces) {
        outwardTri(b, n[static_cast<std::size_t>(f[0])], n[static_cast<std::size_t>(f[1])], n[static_cast<std::size_t>(f[2])], c, skin);
        outwardTri(b, n[static_cast<std::size_t>(f[0])], n[static_cast<std::size_t>(f[2])], n[static_cast<std::size_t>(f[3])], c, skin);
    }
    out.frameOrigin = n[0];
    out.frameX = n[1];
    out.frameY = n[4];
    out.restPositions = b.positions();
    return out;
}
PropBuild buildLog() {
    PropBuild out;
    out.kind = PropKind::Log;
    SoftBody& b = out.body;
    b.setName("log");
    constexpr int N = 6;
    const real r = 0.20, half = 1.5;
    NodeParams np;
    np.mass = 380.0 / (3 * N + 2);   // fresh hardwood, 3 m x 0.4 m
    np.friction = 0.8;
    np.group = "prop";
    std::vector<std::vector<std::uint32_t>> rings(3);
    for (int ring = 0; ring < 3; ++ring)
        for (int i = 0; i < N; ++i) {
            const real a = 2.0 * kPi * i / N;
            rings[static_cast<std::size_t>(ring)].push_back(b.addNode("l" + std::to_string(ring) + "_" + std::to_string(i),
                {-half + half * ring, r + r * std::cos(a), r * std::sin(a)}, np));
        }
    const auto endA = b.addNode("endA", {-half, r, 0}, np);
    const auto endB = b.addNode("endB", {half, r, 0}, np);
    BeamParams wood;
    wood.spring = 4.0e5;
    wood.damp = 120.0;
    std::vector<std::uint32_t> all;
    for (const auto& ring : rings) all.insert(all.end(), ring.begin(), ring.end());
    all.push_back(endA);
    all.push_back(endB);
    for (std::size_t i = 0; i < all.size(); ++i)
        for (std::size_t j = i + 1; j < all.size(); ++j) {
            const Vec3 d = b.positions()[all[i]] - b.positions()[all[j]];
            if (std::abs(d.x) <= half + 1e-6) b.addBeam(all[i], all[j], wood);
        }
    ColTriParams skin;
    skin.friction = 0.8;
    skin.dragCoef = 0.6;
    for (int ring = 0; ring < 2; ++ring)
        for (int i = 0; i < N; ++i) {
            const auto& A = rings[static_cast<std::size_t>(ring)];
            const auto& B = rings[static_cast<std::size_t>(ring + 1)];
            const auto a0 = A[static_cast<std::size_t>(i)], a1 = A[static_cast<std::size_t>((i + 1) % N)];
            const auto b0 = B[static_cast<std::size_t>(i)], b1 = B[static_cast<std::size_t>((i + 1) % N)];
            const Vec3 c{-half * 0.5 + half * ring, r, 0};
            outwardTri(b, a0, a1, b1, c, skin);
            outwardTri(b, a0, b1, b0, c, skin);
        }
    for (int i = 0; i < N; ++i) {
        outwardTri(b, endA, rings[0][static_cast<std::size_t>(i)], rings[0][static_cast<std::size_t>((i + 1) % N)], {0, r, 0}, skin);
        outwardTri(b, endB, rings[2][static_cast<std::size_t>(i)], rings[2][static_cast<std::size_t>((i + 1) % N)], {0, r, 0}, skin);
    }
    out.frameOrigin = endA;
    out.frameX = endB;
    out.frameY = rings[1][1];
    out.restPositions = b.positions();
    return out;
}
// Fallen branch, 2.4 m long, 10 cm thick at the butt tapering to 7 cm, with two side twigs,
// ~14 kg (long axis along x). Two halves of stiff wood, each a triangular prism (one face flat
// on the ground) joined in the middle by brittle fibres: a hard hit or a wheel bending it over
// uneven ground snaps it in two, and each half then follows its own visual frame.
PropBuild buildBranch() {
    PropBuild out;
    out.kind = PropKind::Branch;
    SoftBody& b = out.body;
    b.setName("branch");
    NodeParams np;
    np.mass = 13.0 / 18.0;   // green-ish wood, ~900 kg/m^3
    np.friction = 0.45;
    np.group = "prop";
    const real xs[6] = {-1.2, -0.6, -0.05, 0.05, 0.6, 1.2};
    std::vector<std::vector<std::uint32_t>> st(6);
    for (int k = 0; k < 6; ++k) {
        const real r = 0.05 - 0.015 * (xs[k] + 1.2) / 2.4;
        const real yc = 0.5 * r + 0.005;   // bottom face 5 mm above the ground
        for (int i = 0; i < 3; ++i) {
            const real a = kPi * 0.5 + 2.0 * kPi * i / 3.0;   // top, then the two bottom corners
            st[static_cast<std::size_t>(k)].push_back(
                b.addNode("s" + std::to_string(k) + "_" + std::to_string(i), {xs[k], yc + r * std::sin(a), r * std::cos(a)}, np));
        }
    }
    NodeParams twig = np;
    twig.mass = 0.6;
    const auto twigL = b.addNode("twigL", {-0.40, 0.24, 0.42}, twig);
    const auto twigR = b.addNode("twigR", {0.80, 0.20, -0.46}, twig);
    BeamParams wood;
    wood.spring = 1.5e5;
    wood.damp = 40.0;
    auto half = [&](int first) {
        std::vector<std::uint32_t> nodes;
        for (int k = first; k < first + 3; ++k) nodes.insert(nodes.end(), st[static_cast<std::size_t>(k)].begin(), st[static_cast<std::size_t>(k)].end());
        return nodes;
    };
    connectAll(b, half(0), wood);
    connectAll(b, half(3), wood);
    BeamParams twigWood = wood;
    twigWood.spring = 3.0e4;
    twigWood.damp = 10.0;
    for (int k : {1, 2})
        for (auto n : st[static_cast<std::size_t>(k)]) b.addBeam(twigL, n, twigWood);
    for (int k : {4, 5})
        for (auto n : st[static_cast<std::size_t>(k)]) b.addBeam(twigR, n, twigWood);
    // Dry fibres across the middle: they bend a little, then snap (~1.5 kNm, a dead branch).
    BeamParams fibre = wood;
    fibre.deform = 5.0e3;
    fibre.strength = 8.0e3;
    for (auto a : st[2])
        for (auto c : st[3]) b.addBeam(a, c, fibre);
    ColTriParams skin;
    skin.friction = 0.45;
    skin.dragCoef = 0.6;
    for (int k = 0; k < 5; ++k) {
        const auto& A = st[static_cast<std::size_t>(k)];
        const auto& B = st[static_cast<std::size_t>(k + 1)];
        const Vec3 c = (b.positions()[A[0]] + b.positions()[B[0]]) * 0.5 - Vec3{0, 0.03, 0};
        for (int i = 0; i < 3; ++i) {
            const auto a0 = A[static_cast<std::size_t>(i)], a1 = A[static_cast<std::size_t>((i + 1) % 3)];
            const auto b0 = B[static_cast<std::size_t>(i)], b1 = B[static_cast<std::size_t>((i + 1) % 3)];
            outwardTri(b, a0, a1, b1, c, skin);
            outwardTri(b, a0, b1, b0, c, skin);
        }
    }
    outwardTri(b, st[0][0], st[0][1], st[0][2], {0, 0.03, 0}, skin);
    outwardTri(b, st[5][0], st[5][1], st[5][2], {0, 0.03, 0}, skin);
    // Main frame on the butt half, "Sub" frame on the tip half.
    out.frameOrigin = st[0][1];
    out.frameX = st[2][1];
    out.frameY = st[1][0];
    out.subFrameOrigin = st[3][1];
    out.subFrameX = st[5][1];
    out.subFrameY = st[4][0];
    out.restPositions = b.positions();
    return out;
}

// 240 l wheelie bin, 0.73 x 0.58 x 1.07 m, ~15 kg with some rubbish in it (long side along x).
// HDPE: springy, dents and stays dented after a proper hit. Built like the drum, rings of eight
// nodes (corners and side centres) at three heights: an eight-node box let a car's nose pass
// between its corners and end up inside it.
PropBuild buildBin() {
    PropBuild out;
    out.kind = PropKind::Bin;
    SoftBody& b = out.body;
    b.setName("bin");
    constexpr int N = 8;
    NodeParams np;
    np.mass = 15.0 / (3 * N + 2);
    np.friction = 0.55;
    np.group = "prop";
    const real ys[3] = {0.02, 0.55, 1.07};
    std::vector<std::vector<std::uint32_t>> rings(3);
    for (int ring = 0; ring < 3; ++ring) {
        // Tapered body: the top (lid) is wider than the base.
        const real hx = 0.30 + 0.065 * ring * 0.5, hz = 0.25 + 0.04 * ring * 0.5;
        const real px[N] = {hx, hx, 0, -hx, -hx, -hx, 0, hx};
        const real pz[N] = {0, hz, hz, hz, 0, -hz, -hz, -hz};
        for (int i = 0; i < N; ++i)
            rings[static_cast<std::size_t>(ring)].push_back(b.addNode("r" + std::to_string(ring) + "_" + std::to_string(i),
                {px[i], ys[ring], pz[i]}, np));
    }
    const auto bottom = b.addNode("bottom", {0, 0.02, 0}, np);
    const auto top = b.addNode("top", {0, 1.07, 0}, np);
    BeamParams wall;
    wall.spring = 4.0e4;
    wall.damp = 40.0;
    wall.deform = 1.8e3;
    wall.strength = 2.5e4;
    wall.deformLimit = 0.4;
    wall.deformLimitExpansion = 0.25;
    BeamParams brace = wall;
    brace.spring = 1.5e4;
    brace.deform = 1.2e3;
    for (int ring = 0; ring < 3; ++ring) {
        const auto& R = rings[static_cast<std::size_t>(ring)];
        for (int i = 0; i < N; ++i) {
            b.addBeam(R[static_cast<std::size_t>(i)], R[static_cast<std::size_t>((i + 1) % N)], wall);
            b.addBeam(R[static_cast<std::size_t>(i)], R[static_cast<std::size_t>((i + N / 2) % N)], brace);
            b.addBeam(R[static_cast<std::size_t>(i)], R[static_cast<std::size_t>((i + 2) % N)], brace);
        }
    }
    for (int ring = 0; ring < 2; ++ring) {
        const auto& A = rings[static_cast<std::size_t>(ring)];
        const auto& B = rings[static_cast<std::size_t>(ring + 1)];
        for (int i = 0; i < N; ++i) {
            b.addBeam(A[static_cast<std::size_t>(i)], B[static_cast<std::size_t>(i)], wall);
            b.addBeam(A[static_cast<std::size_t>(i)], B[static_cast<std::size_t>((i + 1) % N)], wall);
            b.addBeam(A[static_cast<std::size_t>((i + 1) % N)], B[static_cast<std::size_t>(i)], brace);
        }
    }
    for (int i = 0; i < N; ++i) {
        b.addBeam(bottom, rings[0][static_cast<std::size_t>(i)], wall);
        b.addBeam(top, rings[2][static_cast<std::size_t>(i)], wall);
        b.addBeam(bottom, rings[1][static_cast<std::size_t>(i)], brace);
        b.addBeam(top, rings[1][static_cast<std::size_t>(i)], brace);
    }
    b.addBeam(bottom, top, brace);
    ColTriParams skin;
    skin.friction = 0.45;
    skin.dragCoef = 0.9;
    const Vec3 c{0, 0.55, 0};
    for (int ring = 0; ring < 2; ++ring)
        for (int i = 0; i < N; ++i) {
            const auto& A = rings[static_cast<std::size_t>(ring)];
            const auto& B = rings[static_cast<std::size_t>(ring + 1)];
            const auto a0 = A[static_cast<std::size_t>(i)], a1 = A[static_cast<std::size_t>((i + 1) % N)];
            const auto b0 = B[static_cast<std::size_t>(i)], b1 = B[static_cast<std::size_t>((i + 1) % N)];
            outwardTri(b, a0, a1, b1, c, skin);
            outwardTri(b, a0, b1, b0, c, skin);
        }
    for (int i = 0; i < N; ++i) {
        outwardTri(b, bottom, rings[0][static_cast<std::size_t>(i)], rings[0][static_cast<std::size_t>((i + 1) % N)], c, skin);
        outwardTri(b, top, rings[2][static_cast<std::size_t>(i)], rings[2][static_cast<std::size_t>((i + 1) % N)], c, skin);
    }
    out.frameOrigin = bottom;
    out.frameX = rings[0][0];
    out.frameY = top;
    out.restPositions = b.positions();
    return out;
}

PropBuild buildBeacon() {
    PropBuild out;
    out.kind = PropKind::Beacon;
    SoftBody& b = out.body;
    b.setName("beacon");
    // Recycled-rubber foot: a low slab, 28 kg, long axis along z.
    NodeParams foot;
    foot.mass = 3.5;
    foot.friction = 0.8;
    foot.group = "prop";
    std::vector<std::uint32_t> f;
    for (int layer = 0; layer < 2; ++layer)
        for (int i = 0; i < 4; ++i) {
            const real x = (i & 1) ? 0.20 : -0.20, z = (i & 2) ? 0.40 : -0.40;
            f.push_back(b.addNode("f" + std::to_string(layer * 4 + i), {x, layer ? 0.07 : 0.01, z}, foot));
        }
    BeamParams rubber;
    rubber.spring = 2.5e5;
    rubber.damp = 400.0;
    connectAll(b, f, rubber);
    // Panel: polyethylene, 1.0 m x 0.25 m, a few centimetres thick, on a short stem in the foot.
    // Four nodes at the bottom edge and four at the top edge give it thickness and bending.
    NodeParams panel;
    panel.mass = 0.38;
    panel.friction = 0.2;   // polyethylene slides: wedged under a car it must not act as a brake shoe
    panel.group = "prop";
    std::vector<std::uint32_t> p;
    for (int layer = 0; layer < 2; ++layer)
        for (int i = 0; i < 4; ++i) {
            const real x = (i & 1) ? 0.03 : -0.03, z = (i & 2) ? 0.125 : -0.125;
            p.push_back(b.addNode("p" + std::to_string(layer * 4 + i), {x, layer ? 1.18 : 0.18, z}, panel));
        }
    BeamParams pe;
    pe.type = BeamType::Anisotropic;
    pe.spring = 2.0e4;
    pe.springExpansion = 2.0e4;
    pe.damp = 25.0;
    pe.longBound = 0.10;
    pe.boundSpring = 8.0e4;
    connectAll(b, p, pe);
    // Stem: plugged into the foot; it lets go under a strike instead of dragging the foot under a
    // wheel (the earlier fixed versions jammed under the front tyre and were dragged along).
    BeamParams stem;
    stem.spring = 6.0e4;
    stem.damp = 120.0;
    stem.strength = 700.0;   // just plugged in: a bumper pushes it out instead of shoving the foot
    for (int i = 0; i < 4; ++i)
        for (int j = 4; j < 8; ++j)
            b.addBeam(p[static_cast<std::size_t>(i)], f[static_cast<std::size_t>(j)], stem);
    ColTriParams skin;
    skin.friction = 0.25;
    skin.dragCoef = 1.1;
    const int faces[6][4] = {{0, 1, 3, 2}, {4, 6, 7, 5}, {0, 4, 5, 1}, {2, 3, 7, 6}, {0, 2, 6, 4}, {1, 5, 7, 3}};
    for (const auto& q : faces) {
        outwardTri(b, f[static_cast<std::size_t>(q[0])], f[static_cast<std::size_t>(q[1])], f[static_cast<std::size_t>(q[2])], {0, 0.04, 0}, skin);
        outwardTri(b, f[static_cast<std::size_t>(q[0])], f[static_cast<std::size_t>(q[2])], f[static_cast<std::size_t>(q[3])], {0, 0.04, 0}, skin);
        outwardTri(b, p[static_cast<std::size_t>(q[0])], p[static_cast<std::size_t>(q[1])], p[static_cast<std::size_t>(q[2])], {0, 0.68, 0}, skin);
        outwardTri(b, p[static_cast<std::size_t>(q[0])], p[static_cast<std::size_t>(q[2])], p[static_cast<std::size_t>(q[3])], {0, 0.68, 0}, skin);
    }
    // Main frame on the foot, the panel as a separate part.
    out.frameOrigin = f[0];
    out.frameX = f[1];
    out.frameY = f[4];
    out.subFrameOrigin = p[0];
    out.subFrameX = p[1];
    out.subFrameY = p[4];
    out.restPositions = b.positions();
    return out;
}

}  // namespace

PropBuild buildProp(PropKind kind) {
    PropBuild out = kind == PropKind::Log ? buildLog() : kind == PropKind::Barrier ? buildBarrier()
                  : kind == PropKind::Barrel ? buildBarrel() : kind == PropKind::Bin ? buildBin()
                  : kind == PropKind::Beacon ? buildBeacon() : kind == PropKind::Branch ? buildBranch() : buildCone();
    out.body.setSleepEnabled(true);
    // Flat-bottomed props only: on a round log the lower faces are the ones a tyre climbs over.
    out.body.setDownFacesPassive(kind != PropKind::Log);
    // Catch other bodies' nodes only within about half the prop's thinnest section: deeper, a
    // node is resolved against the far face and the stiff little body is squeezed out and flung
    // (a log under a tyre left faster than the car pushing it).
    switch (kind) {
        case PropKind::Cone: break;   // soft and hollow: the world depth works (a shallower one let it wedge under bumpers)
        case PropKind::Barrel: out.body.setContactThickness(0.10); break;
        case PropKind::Barrier: out.body.setContactThickness(0.10); break;
        case PropKind::Log: out.body.setContactThickness(0.07); break;
        case PropKind::Bin: out.body.setContactThickness(0.12); break;
        case PropKind::Beacon: out.body.setContactThickness(0.03); break;   // thin foot and panel
        case PropKind::Branch: out.body.setContactThickness(0.03); break;
    }
    return out;
}

PropKind propKindFromString(const std::string& name) {
    if (name == "cone") return PropKind::Cone;
    if (name == "barrel") return PropKind::Barrel;
    if (name == "barrier") return PropKind::Barrier;
    if (name == "log") return PropKind::Log;
    if (name == "bin") return PropKind::Bin;
    if (name == "beacon") return PropKind::Beacon;
    if (name == "branch") return PropKind::Branch;
    throw std::invalid_argument("unknown prop kind '" + name + "'");
}

}  // namespace sb
