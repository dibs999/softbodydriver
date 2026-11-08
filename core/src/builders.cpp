#include "sbcore/builders.hpp"

#include <algorithm>
#include <set>
#include <utility>
#include <vector>

namespace sb {

SoftBody buildLattice(const LatticeSpec& s) {
    const int nx = s.cellsX + 1, ny = s.cellsY + 1, nz = s.cellsZ + 1;
    auto cellIncluded = [&](int i, int j, int k) {
        if (i < 0 || j < 0 || k < 0 || i >= s.cellsX || j >= s.cellsY || k >= s.cellsZ) return false;
        return !s.includeCell || s.includeCell(i, j, k);
    };
    auto gridIndex = [&](int i, int j, int k) { return (i * ny + j) * nz + k; };

    // 1) Which grid points are used by at least one included cell.
    std::vector<char> used(static_cast<std::size_t>(nx * ny * nz), 0);
    for (int i = 0; i < s.cellsX; ++i)
        for (int j = 0; j < s.cellsY; ++j)
            for (int k = 0; k < s.cellsZ; ++k) {
                if (!cellIncluded(i, j, k)) continue;
                for (int c = 0; c < 8; ++c)
                    used[static_cast<std::size_t>(gridIndex(i + (c & 1), j + ((c >> 1) & 1), k + ((c >> 2) & 1)))] = 1;
            }
    const auto nodeCount = static_cast<std::size_t>(std::count(used.begin(), used.end(), 1));
    if (nodeCount == 0) return SoftBody(s.name);

    auto gridPos = [&](int i, int j, int k) {
        return s.origin + Vec3{i * s.cellSize.x, j * s.cellSize.y, k * s.cellSize.z};
    };

    // 2) Nodes.
    SoftBody body(s.name);
    std::vector<std::int64_t> nodeOf(used.size(), -1);
    const real nodeMass = s.totalMass / static_cast<real>(nodeCount);
    for (int i = 0; i < nx; ++i)
        for (int j = 0; j < ny; ++j)
            for (int k = 0; k < nz; ++k) {
                const auto g = static_cast<std::size_t>(gridIndex(i, j, k));
                if (!used[g]) continue;
                NodeParams np = s.node;
                np.mass = nodeMass;
                const Vec3 p = gridPos(i, j, k);
                if (s.customizeNode) s.customizeNode(np, p);
                nodeOf[g] = body.addNode("n_" + std::to_string(i) + "_" + std::to_string(j) + "_" + std::to_string(k), p, np);
            }

    // 3) Beams per included cell, deduplicated.
    std::set<std::pair<std::uint32_t, std::uint32_t>> seen;
    auto addBeam = [&](int i0, int j0, int k0, int i1, int j1, int k1, LatticeBeamKind kind) {
        const auto a = nodeOf[static_cast<std::size_t>(gridIndex(i0, j0, k0))];
        const auto b = nodeOf[static_cast<std::size_t>(gridIndex(i1, j1, k1))];
        if (a < 0 || b < 0) return;
        const auto ua = static_cast<std::uint32_t>(a);
        const auto ub = static_cast<std::uint32_t>(b);
        const std::pair<std::uint32_t, std::uint32_t> key = ua < ub ? std::make_pair(ua, ub) : std::make_pair(ub, ua);
        if (!seen.insert(key).second) return;
        BeamParams bp = kind == LatticeBeamKind::Edge           ? s.edge
                        : kind == LatticeBeamKind::FaceDiagonal ? s.faceDiagonal
                                                                : s.bodyDiagonal;
        if (s.customizeBeam) s.customizeBeam(bp, (gridPos(i0, j0, k0) + gridPos(i1, j1, k1)) * 0.5, kind);
        body.addBeam(key.first, key.second, bp);
    };

    for (int i = 0; i < s.cellsX; ++i)
        for (int j = 0; j < s.cellsY; ++j)
            for (int k = 0; k < s.cellsZ; ++k) {
                if (!cellIncluded(i, j, k)) continue;
                // 12 edges
                for (int a = 0; a < 2; ++a)
                    for (int b = 0; b < 2; ++b) {
                        addBeam(i, j + a, k + b, i + 1, j + a, k + b, LatticeBeamKind::Edge);
                        addBeam(i + a, j, k + b, i + a, j + 1, k + b, LatticeBeamKind::Edge);
                        addBeam(i + a, j + b, k, i + a, j + b, k + 1, LatticeBeamKind::Edge);
                    }
                // 12 face diagonals (2 per face)
                if (s.faceDiagonals) {
                    for (int a = 0; a < 2; ++a) {
                        // faces normal to X
                        addBeam(i + a, j, k, i + a, j + 1, k + 1, LatticeBeamKind::FaceDiagonal);
                        addBeam(i + a, j + 1, k, i + a, j, k + 1, LatticeBeamKind::FaceDiagonal);
                        // faces normal to Y
                        addBeam(i, j + a, k, i + 1, j + a, k + 1, LatticeBeamKind::FaceDiagonal);
                        addBeam(i + 1, j + a, k, i, j + a, k + 1, LatticeBeamKind::FaceDiagonal);
                        // faces normal to Z
                        addBeam(i, j, k + a, i + 1, j + 1, k + a, LatticeBeamKind::FaceDiagonal);
                        addBeam(i + 1, j, k + a, i, j + 1, k + a, LatticeBeamKind::FaceDiagonal);
                    }
                }
                // 4 body diagonals
                if (s.bodyDiagonals) {
                    addBeam(i, j, k, i + 1, j + 1, k + 1, LatticeBeamKind::BodyDiagonal);
                    addBeam(i + 1, j, k, i, j + 1, k + 1, LatticeBeamKind::BodyDiagonal);
                    addBeam(i, j + 1, k, i + 1, j, k + 1, LatticeBeamKind::BodyDiagonal);
                    addBeam(i, j, k + 1, i + 1, j + 1, k, LatticeBeamKind::BodyDiagonal);
                }
            }

    // 4) Outward-oriented collision triangles on exposed boundary faces.
    if (s.surfaceTriangles) {
        auto addQuad = [&](int i0, int j0, int k0, int i1, int j1, int k1,
                           int i2, int j2, int k2, int i3, int j3, int k3) {
            const auto n0 = static_cast<std::uint32_t>(nodeOf[static_cast<std::size_t>(gridIndex(i0, j0, k0))]);
            const auto n1 = static_cast<std::uint32_t>(nodeOf[static_cast<std::size_t>(gridIndex(i1, j1, k1))]);
            const auto n2 = static_cast<std::uint32_t>(nodeOf[static_cast<std::size_t>(gridIndex(i2, j2, k2))]);
            const auto n3 = static_cast<std::uint32_t>(nodeOf[static_cast<std::size_t>(gridIndex(i3, j3, k3))]);
            body.addTriangle(n0, n1, n2, s.surfaceTri);
            body.addTriangle(n0, n2, n3, s.surfaceTri);
        };
        for (int i = 0; i < s.cellsX; ++i)
            for (int j = 0; j < s.cellsY; ++j)
                for (int k = 0; k < s.cellsZ; ++k) {
                    if (!cellIncluded(i, j, k)) continue;
                    // -X face (outward normal -X)
                    if (!cellIncluded(i - 1, j, k))
                        addQuad(i, j, k, i, j, k + 1, i, j + 1, k + 1, i, j + 1, k);
                    // +X face (outward normal +X)
                    if (!cellIncluded(i + 1, j, k))
                        addQuad(i + 1, j, k, i + 1, j + 1, k, i + 1, j + 1, k + 1, i + 1, j, k + 1);
                    // -Y face (outward normal -Y)
                    if (!cellIncluded(i, j - 1, k))
                        addQuad(i, j, k, i + 1, j, k, i + 1, j, k + 1, i, j, k + 1);
                    // +Y face (outward normal +Y)
                    if (!cellIncluded(i, j + 1, k))
                        addQuad(i, j + 1, k, i, j + 1, k + 1, i + 1, j + 1, k + 1, i + 1, j + 1, k);
                    // -Z face (outward normal -Z)
                    if (!cellIncluded(i, j, k - 1))
                        addQuad(i, j, k, i, j + 1, k, i + 1, j + 1, k, i + 1, j, k);
                    // +Z face (outward normal +Z)
                    if (!cellIncluded(i, j, k + 1))
                        addQuad(i, j, k + 1, i + 1, j, k + 1, i + 1, j + 1, k + 1, i, j + 1, k + 1);
                }
    }
    return body;
}

void rotateBody(SoftBody& body, const Mat3& rotation, const Vec3& pivot) {
    for (Vec3& p : body.positions()) p = pivot + rotation * (p - pivot);
}

}  // namespace sb
