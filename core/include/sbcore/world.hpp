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
};

struct WorldStats {
    real time = 0;
    std::uint64_t steps = 0;
    real kineticEnergy = 0;
    real elasticEnergy = 0;
    real potentialEnergy = 0;
    std::size_t nodes = 0, beams = 0, brokenBeams = 0, deformedBeams = 0;
    std::size_t contacts = 0;  ///< Node-collider contacts in the last step.
    bool finite = true;        ///< False if any node position became NaN/inf.
};

class World {
public:
    explicit World(WorldSettings s = {}) : settings_(s) {}

    std::size_t addBody(SoftBody body);
    void addCollider(const StaticCollider& c) { colliders_.push_back(c); }

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
    void integrateBody(SoftBody& b);
    std::size_t collideBody(SoftBody& b);

    WorldSettings settings_;
    std::vector<SoftBody> bodies_;
    std::vector<StaticCollider> colliders_;
    std::uint64_t steps_ = 0;
    std::size_t lastContacts_ = 0;
};

}  // namespace sb
