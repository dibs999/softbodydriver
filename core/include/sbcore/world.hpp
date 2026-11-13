// The simulation world: soft bodies + static colliders, advanced with a fixed
// time step (default 2000 Hz, like BeamNG). Rendering should interpolate between
// physics states; the physics step itself is fully deterministic.
#pragma once

#include <cstdint>
#include <vector>

#include "sbcore/colliders.hpp"
#include "sbcore/softbody.hpp"

namespace sb {

struct WorldSettings {
    real dt = 1.0 / 2000.0;           ///< Physics step in seconds.
    Vec3 gravity{0.0, -9.81, 0.0};    ///< Y is up (matches Godot).
    real airDrag = 0.0;               ///< Simple linear velocity damping in 1/s (0 = off).
    real airDensity = 1.225;          ///< Air density in kg/m^3 for ColTri aerodynamics (0 = off).
    real colTriSkin = 0.025;          ///< Outer contact skin thickness for ColTris (m).
    real colTriThickness = 0.14;      ///< Max penetration capture depth behind a ColTri (m).
};

struct WorldStats {
    real time = 0;
    std::uint64_t steps = 0;
    real kineticEnergy = 0;
    real elasticEnergy = 0;
    real potentialEnergy = 0;
    std::size_t nodes = 0, beams = 0, brokenBeams = 0, deformedBeams = 0;
    std::size_t triangles = 0, brokenTriangles = 0;
    std::size_t contacts = 0;      ///< Node-collider contacts in the last step.
    std::size_t bodyContacts = 0;  ///< Inter-body Node-vs-ColTri contacts in the last step.
    std::size_t selfContacts = 0; ///< Opt-in released panel contacts against its own body.
    std::size_t selfContactCandidates = 0; ///< Panel-node/triangle pairs after panel AABB culling.
    bool finite = true;            ///< False if any node position became NaN/inf.
};

/// A coupling between two bodies: a ball joint (spring-damper pulling node A of body A onto node B
/// of body B) that breaks above `breakForce`. A trailer's hitch on a car's tow ball.
struct BodyLink {
    std::size_t bodyA = 0, bodyB = 0;
    std::uint32_t nodeA = 0, nodeB = 0;
    real stiffness = 2.0e5;   ///< N/m
    real damping = 1.5e3;     ///< N*s/m
    real breakForce = 6.0e4;  ///< N; the coupling tears apart above this (a crash, not a tow)
    bool broken = false;
    real force = 0.0;         ///< Magnitude in the last step (N), for HUD and tests.
};

/// Stops the physics worker threads shared by all worlds (e.g. before a plugin is unloaded).
/// The next multi-body step starts them again. Must not run concurrently with World::step().
void shutdownPhysicsThreads();

/// A body of water: an axis-aligned box whose top is the surface (a pond, a river, a ford).
/// Nodes below the surface feel buoyancy and water drag; see SoftBody::setDisplacement.
struct WaterVolume {
    real minX = 0.0, maxX = 0.0, minZ = 0.0, maxZ = 0.0;
    real surfaceY = 0.0;
    real bottomY = -10.0;
    real density = 1000.0;   ///< kg/m^3
};

class World {
public:
    explicit World(WorldSettings s = {}) : settings_(s) {}

    std::size_t addBody(SoftBody body);
    /// Removes body i; indices of later bodies shift down by one.
    void removeBody(std::size_t i);
    void addCollider(const StaticCollider& c) { colliders_.push_back(c); }
    /// Couples two bodies (see BodyLink). Returns its index; links of a removed body go with it.
    std::size_t addLink(const BodyLink& link) { links_.push_back(link); return links_.size() - 1; }
    std::size_t addWater(const WaterVolume& w) { waters_.push_back(w); return waters_.size() - 1; }
    const std::vector<WaterVolume>& waters() const { return waters_; }
    /// Depth of point p below the water surface (0 when not in any water).
    real waterDepthAt(const Vec3& p) const;
    void removeLink(std::size_t i) { if (i < links_.size()) links_.erase(links_.begin() + static_cast<std::ptrdiff_t>(i)); }
    std::vector<BodyLink>& links() { return links_; }
    const std::vector<BodyLink>& links() const { return links_; }
    void clearColliders() { colliders_.clear(); }
    /// Removes every water volume (a map change rebuilds them).
    void clearWater() { waters_.clear(); }

    /// Advances one fixed physics step.
    void step();
    /// Advances by `seconds` (rounded to whole steps). Returns the number of steps taken.
    std::uint64_t simulate(real seconds);

    real time() const { return static_cast<real>(steps_) * settings_.dt; }
    std::uint64_t stepCount() const { return steps_; }
    const WorldSettings& settings() const { return settings_; }
    WorldSettings& settings() { return settings_; }

    std::vector<SoftBody>& bodies() { return bodies_; }
    const std::vector<SoftBody>& bodies() const { return bodies_; }
    SoftBody& body(std::size_t i) { return bodies_.at(i); }
    const SoftBody& body(std::size_t i) const { return bodies_.at(i); }
    const std::vector<StaticCollider>& colliders() const { return colliders_; }

    WorldStats stats() const;
    real worstStabilityRatio() const;

private:
    void accumulateAerodynamicForces(SoftBody& b);
    void integrateBody(SoftBody& b);
    std::size_t collideBody(SoftBody& b, std::vector<const StaticCollider*>& candidates);
    std::size_t collideBodies();
    void applyLinks();
    /// triLo/triHi: triBody's box, grown by the contact margin. heavyPair: both are vehicles.
    std::size_t collideNodeVsTriangles(SoftBody& nodeBody, SoftBody& triBody, const Vec3& triLo, const Vec3& triHi,
                                       bool heavyPair);
    std::size_t collideSelfPanels(SoftBody& body, const std::vector<Vec3>& previous, std::size_t& candidates) const;

    WorldSettings settings_;
    std::vector<SoftBody> bodies_;
    std::vector<StaticCollider> colliders_;
    std::vector<BodyLink> links_;
    std::vector<WaterVolume> waters_;
    void accumulateWaterForces(SoftBody& b);
    std::uint64_t steps_ = 0;
    std::size_t lastContacts_ = 0;
    std::size_t lastBodyContacts_ = 0;
    std::size_t lastSelfContacts_ = 0, lastSelfContactCandidates_ = 0;
    /// Per-body scratch of the parallel part of a step (bodies are independent there).
    struct BodyScratch {
        std::vector<Vec3> selfContactPrevious;  ///< Only for bodies with active panel contact.
        std::vector<const StaticCollider*> candidates;
        std::size_t selfContacts = 0, selfCandidates = 0, contacts = 0;
    };
    std::vector<BodyScratch> scratch_;
    std::vector<std::size_t> awakeStep_;
    struct BodyContactCandidate {
        real dist = -1e9;
        Vec3 n{};
        std::uint32_t a = 0, b = 0, c = 0;
        real w0 = 0, w1 = 0, w2 = 0, friction = 0;
        bool valid = false;
    };
    std::vector<BodyContactCandidate> contactScratch_;
    std::vector<std::uint32_t> contactNodes_;   ///< Inter-body: nodes inside the other body's box.
    std::vector<std::pair<std::int64_t, std::uint32_t>> contactGrid_;  ///< (cell, node), sorted.
    std::vector<Vec3> aabbLo_, aabbHi_;      ///< Inter-body broadphase boxes (kept for sleeping bodies).
    std::vector<std::size_t> awake_;
    std::vector<unsigned char> sleptBox_;   ///< 1 = box of a body already asleep last step (still valid). ///< Best node-vs-triangle contact per node (inter-body).
};

}  // namespace sb
