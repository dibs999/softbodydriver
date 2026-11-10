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
    heavy.mass = 0.7875; heavy.friction = 0.55; heavy.group = "prop";
    NodeParams light = heavy;
    light.mass = 0.30; light.friction = 0.4;
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
    connectAll(b, all, pvc);
    ColTriParams skin;
    skin.friction = 0.35;
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
}  // namespace

PropBuild buildProp(PropKind kind) {
    PropBuild out = kind == PropKind::Log ? buildLog() : kind == PropKind::Barrier ? buildBarrier()
                  : kind == PropKind::Barrel ? buildBarrel() : buildCone();
    // Catch other bodies' nodes only within about half the prop's thinnest section: deeper, a
    // node is resolved against the far face and the stiff little body is squeezed out and flung
    // (a log under a tyre left faster than the car pushing it).
    switch (kind) {
        case PropKind::Cone: break;   // soft and hollow: the world depth works (a shallower one let it wedge under bumpers)
        case PropKind::Barrel: out.body.setContactThickness(0.10); break;
        case PropKind::Barrier: out.body.setContactThickness(0.10); break;
        case PropKind::Log: out.body.setContactThickness(0.07); break;
    }
    return out;
}

PropKind propKindFromString(const std::string& name) {
    if (name == "cone") return PropKind::Cone;
    if (name == "barrel") return PropKind::Barrel;
    if (name == "barrier") return PropKind::Barrier;
    if (name == "log") return PropKind::Log;
    throw std::invalid_argument("unknown prop kind '" + name + "'");
}

}  // namespace sb
