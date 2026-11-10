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
    // Flexible PVC: soft, damped, never yields or breaks; it lies down and pops back.
    BeamParams pvc;
    pvc.spring = 3.0e3;
    pvc.damp = 8.0;
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
}  // namespace

PropBuild buildProp(PropKind kind) {
    return kind == PropKind::Barrel ? buildBarrel() : buildCone();
}

PropKind propKindFromString(const std::string& name) {
    if (name == "cone") return PropKind::Cone;
    if (name == "barrel") return PropKind::Barrel;
    throw std::invalid_argument("unknown prop kind '" + name + "'");
}

}  // namespace sb
