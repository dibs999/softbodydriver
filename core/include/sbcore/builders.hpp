// Procedural builders for test structures (lattices, trusses, car-shaped hulls).
// Real vehicles will be authored as .sbeam.json files; these builders are used
// for tests, benchmarks and the phase-1 demo scenes.
#pragma once

#include <functional>
#include <string>

#include "sbcore/softbody.hpp"

namespace sb {

enum class LatticeBeamKind { Edge, FaceDiagonal, BodyDiagonal };

struct LatticeSpec {
    std::string name = "lattice";
    Vec3 origin{0, 0, 0};       ///< Minimum corner.
    int cellsX = 1, cellsY = 1, cellsZ = 1;
    Vec3 cellSize{0.5, 0.5, 0.5};
    real totalMass = 100.0;     ///< Distributed evenly over all nodes.
    NodeParams node;            ///< Mass is overwritten by the even distribution.
    BeamParams edge, faceDiagonal, bodyDiagonal;
    bool faceDiagonals = true;
    bool bodyDiagonals = true;
    bool surfaceTriangles = true;  ///< Generate outward ColTris on exposed boundary faces.
    ColTriParams surfaceTri;
    /// Optional: which cells exist (default: all). Nodes are created for corners of included cells.
    std::function<bool(int, int, int)> includeCell;
    /// Optional: per-node tweak (after mass distribution), receives the node position.
    std::function<void(NodeParams&, const Vec3&)> customizeNode;
    /// Optional: per-beam tweak, receives the beam midpoint and kind.
    std::function<void(BeamParams&, const Vec3&, LatticeBeamKind)> customizeBeam;
};

/// Builds a braced lattice. Node ids are "n_<i>_<j>_<k>" (grid indices).
SoftBody buildLattice(const LatticeSpec& spec);

/// Rotates all node positions around `pivot`.
void rotateBody(SoftBody& body, const Mat3& rotation, const Vec3& pivot);

}  // namespace sb
