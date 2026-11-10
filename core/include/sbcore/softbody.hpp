// Node-beam soft body: the fundamental simulation object (vehicles, props, structures).
//
// Model (BeamNG / Rigs-of-Rods style):
//   * Nodes  = point masses (position, velocity, mass, friction coefficient).
//   * Beams  = massless spring-dampers between two nodes. They only transmit
//              axial force (tension/compression); rigidity comes from bracing.
//   * Plasticity: if the spring force exceeds `deform`, the rest length moves
//              -> permanent dents. Optional work-hardening raises the threshold.
//   * Breaking: if the total beam force exceeds `strength`, the beam breaks and
//              takes its whole break group with it (e.g. a door hinge).
#pragma once

#include <algorithm>
#include <array>
#include <cstdint>
#include <limits>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include "sbcore/car_systems.hpp"
#include "sbcore/powertrain.hpp"
#include "sbcore/vec3.hpp"
#include "sbcore/wheel.hpp"

namespace sb {


enum class BeamType : std::uint8_t {
    Normal,       ///< Spring-damper in tension and compression.
    Support,      ///< Only resists compression (anti-clipping limiter between parts).
    Anisotropic,  ///< Separate spring/damp for expansion vs. compression (tyres, ropes).
    Hydro,        ///< Rest length driven by an input channel (steering racks, actuators).
    Shock,        ///< Coilover / damper: separate bump (compression) and rebound damping.
};

const char* beamTypeToString(BeamType t);
bool beamTypeFromString(const std::string& s, BeamType& out);

/// Authoring parameters of a node (what you write in a .sbeam file).
struct NodeParams {
    real mass = 1.0;        ///< kg
    real friction = 1.0;    ///< Coulomb friction coefficient (multiplied with the surface's).
    bool fixed = false;     ///< Pinned in space (infinite mass).
    bool collision = true;  ///< Collides with static world geometry.
    /// Ground contact compliance in N/m (0 = rigid projection contact). Tyre tread nodes use a
    /// stiff spring-damper contact so the tread rubber stores and returns the leading-edge impact.
    real contactStiffness = 0.0;
    std::string group;      ///< Part / flexbody group (e.g. "body", "bumper_f", "engine"). Empty = "default".
};

/// Authoring parameters of a beam (what you write in a .sbeam file).
struct BeamParams {
    BeamType type = BeamType::Normal;
    real spring = 1.0e6;          ///< N/m
    real damp = 100.0;            ///< N*s/m
    real deform = kInf;           ///< N; force above which the beam deforms permanently.
    real strength = kInf;         ///< N; force above which the beam breaks.
    real deformLimit = kInf;      ///< Max fractional rest-length shrink (0.3 -> may shrink to 70%).
    real deformLimitExpansion = kInf;  ///< Max fractional rest-length growth.
    real hardening = 0.0;         ///< Threshold gain per unit plastic force (0 = perfectly plastic).
    real precompression = 1.0;    ///< Rest length multiplier at spawn.
    // Anisotropic only: values used while the beam is longer than rest length.
    real springExpansion = -1.0;  ///< <0 -> same as `spring`.
    real dampExpansion = -1.0;    ///< <0 -> same as `damp`.
    // Hydro only: restLength = base * (1 + hydroRatio * input[hydroInput]).
    int hydroInput = -1;
    real hydroRatio = 0.0;
    // Shock only: damping while the beam extends (rebound). <0 -> same as `damp` (bump).
    real dampRebound = -1.0;
    std::string breakGroup;       ///< Empty = none.
};

/// Torsion bar (anti-roll bar / torsion spring) acting on the dihedral angle of 4 nodes:
/// the planes (n1, n2, n3) and (n2, n3, n4) rotate about the axis n2 -> n3.
struct TorsionbarParams {
    real spring = 2.0e4;     ///< Nm / rad
    real damp = 30.0;        ///< Nm*s / rad
    real deform = kInf;      ///< Nm; torque above which the bar takes a permanent set.
    real strength = kInf;    ///< Nm; torque above which the bar breaks.
};

struct Torsionbar {
    std::uint32_t n[4] = {0, 0, 0, 0};
    real spring = 0, damp = 0, deform = kInf, strength = kInf;
    real restAngle = 0;
    bool broken = false;
    real lastTorque = 0;
    TorsionbarParams params;
};

/// Runtime beam state.
struct Beam {
    bool disabled = false; ///< Reversibly disengaged mechanism; independent of crash damage.
    std::uint32_t a = 0, b = 0;
    BeamType type = BeamType::Normal;
    bool broken = false;
    std::int32_t breakGroup = -1;
    std::int32_t hydroInput = -1;

    real spring = 0, damp = 0;
    real springExp = 0, dampExp = 0;  ///< Anisotropic expansion values; Shock: dampExp = rebound damping.
    real restLength = 0;      ///< Current (possibly plastically changed) rest length.
    real baseRestLength = 0;  ///< Rest length at spawn (incl. precompression). Reference for limits.
    real deformThreshold = kInf;
    real deformLimitStress = kInf;  ///< Cap for hardening (internal).
    real hardening = 0;
    real strength = kInf;
    real minRest = 0, maxRest = kInf;
    real hydroRatio = 0;
    real hydroOffset = 0;     ///< Plastic offset preserved while hydro input changes rest length.

    real plasticStrain() const {
        const real change = hydroInput >= 0 ? hydroOffset : restLength - baseRestLength;
        return baseRestLength > 0.0 ? std::abs(change) / baseRestLength : 0.0;
    }

    real lastForce = 0;       ///< Signed axial force of the last step (+ tension), diagnostics.
    // Authoring parameters live in SoftBody::beamParams() so that this hot struct stays compact:
    // with them inline (incl. a string) a beam took ~300 bytes and several cars no longer fit
    // the CPU caches, making four cars cost ~7x one car.
};

struct ColTriParams {
    real friction = 0.5;
    real dragCoef = 1.0;          ///< Aerodynamic pressure drag/lift coefficient.
    bool breakable = true;        ///< Deactivates when an underlying edge beam or breakGroup breaks.
    /// false: skin that other bodies hit, but the car's own released panels (bonnet, doors)
    /// pass, e.g. the nose corners a bonnet lifts past.
    bool selfContact = true;
    std::string breakGroup;
};

struct ColTri {
    std::uint32_t a = 0, b = 0, c = 0;
    real friction = 0.5;
    real dragCoef = 1.0;
    bool breakable = true;
    bool broken = false;
    std::int32_t breakGroup = -1;
    std::int32_t edgeBeams[3] = {-1, -1, -1};  ///< Beam indices for (a,b), (b,c), (c,a), or -1.
    ColTriParams params;
};

struct BodyStats {
    std::size_t nodes = 0;
    std::size_t beams = 0;
    std::size_t brokenBeams = 0;
    std::size_t deformedBeams = 0;  ///< |rest - base| / base > 0.1 %
    std::size_t triangles = 0;
    std::size_t brokenTriangles = 0;
    real totalMass = 0;
    real kineticEnergy = 0;
    real elasticEnergy = 0;
};

struct VehicleControls {
    real throttle = 0.0;     ///< [0, 1]
    real brake = 0.0;        ///< [0, 1]
    real steer = 0.0;        ///< [-1, 1], + = left, - = right
    real handbrake = 0.0;    ///< [0, 1]
    real clutch = -1.0;      ///< < 0: automatic clutch; [0, 1]: manual override
    int gear = -99;          ///< -99: automatic / keep; -1 = R, 0 = N, 1..5 = forward
    real steerRate = 4.5;    ///< Max steering change per second (0 = instant)
    bool ignition = true;    ///< Engine allowed to run.
    bool tcs = true;         ///< Traction control (engine torque + brake intervention on spinning wheels).
    bool abs = true;         ///< Anti-lock brakes.
    bool starter = false;    ///< Crank the engine (restarts a stalled engine).
};

struct VehicleTelemetry {
    real speedKmh = 0.0;
    Vec3 velocity{0, 0, 0};
    real engineRpm = 0.0;
    int gear = 0;
    real clutch = 0.0;
    real clutchTempC = 45.0, clutchWear = 0.0, gearboxDamage = 0.0;
    real shiftRemaining = 0.0, clutchSlipRpm = 0.0, gearGrind = 0.0;
    real throttle = 0.0;
    real brake = 0.0;
    real steer = 0.0;
    std::vector<real> wheelOmega;
    std::vector<bool> wheelBurst;
    std::vector<real> wheelWear, wheelTempC, wheelPressurePsi, wheelSlip, wheelLoad, wheelRimDamage;
    std::size_t deformedBeams = 0;
    std::size_t brokenBeams = 0;
    bool tcsActive = false;
    bool absActive = false;
};

struct SelfCollisionPoint {
    std::array<std::uint32_t, 3> nodes{};
    std::array<real, 3> weights{};
    std::vector<std::uint32_t> jointBeams;
    std::int32_t triangle = -1; ///< Face samples stop participating if their panel face tears.
};

struct SelfCollisionPanel {
    std::vector<std::uint32_t> nodes, triangles, releaseBeams;
    std::vector<SelfCollisionPoint> points; ///< Corners + triangle centroids, no added mass.
    real skin = 0.008;
};

struct DoorMechanism {
    std::vector<std::uint32_t> nodes, hingeBeams, latchBeams, supportBeams;
    int inputChannel = -1;
    bool requestedOpen = false, latched = true;
    real travel = 0;
    real stroke = 1.5;            ///< s for a full open / close stroke of the actuator
    real latchTolerance = 0.015;  ///< m: latch beams re-engage once this close to their rest length
    /// Lids: a lowered panel within this distance of shut is caught by its latch, which then draws
    /// it in at `catchSpeed` (m/s) to the exact shut position (0 = only the strict tolerance).
    real catchTolerance = 0.0, catchSpeed = 0.2;
    bool catching = false;
};

class SoftBody {
public:
    explicit SoftBody(std::string name = "body") : name_(std::move(name)) {}

    // ---------------------------------------------------------------- authoring
    std::uint32_t addNode(const std::string& id, const Vec3& pos, const NodeParams& p = {});
    /// Adds a beam; rest length is taken from the current node positions.
    /// Returns the beam index. Throws std::invalid_argument for bad indices / zero length.
    std::uint32_t addBeam(std::uint32_t a, std::uint32_t b, const BeamParams& p = {});
    std::uint32_t addBeam(const std::string& a, const std::string& b, const BeamParams& p = {});

    /// Adds a collision / aerodynamic surface triangle (a, b, c) with outward normal (b-a) x (c-a).
    std::uint32_t addTriangle(std::uint32_t a, std::uint32_t b, std::uint32_t c, const ColTriParams& p = {});
    std::uint32_t addTriangle(const std::string& a, const std::string& b, const std::string& c,
                              const ColTriParams& p = {});

    /// Opt-in, bounded panel-to-body contact. Register after all nodes, beams and
    /// collision triangles exist. Empty releaseGroups means always active;
    /// otherwise contact starts when any listed attachment beam breaks.
    void addSelfCollisionPanel(const std::string& panelGroup, const std::vector<std::string>& targetGroups,
                               const std::vector<std::string>& releaseGroups, real skin = 0.008);
    const std::vector<SelfCollisionPanel>& selfCollisionPanels() const { return selfCollisionPanels_; }
    bool selfCollisionActive(const SelfCollisionPanel& panel) const;

    /// Adds a 4-node torsion bar (anti-roll bar). Rest angle is taken from the current positions.
    std::uint32_t addTorsionbar(std::uint32_t n1, std::uint32_t n2, std::uint32_t n3, std::uint32_t n4,
                                const TorsionbarParams& p = {});

    /// Generates and registers a node-beam PressureWheel on this body.
    std::size_t addWheel(const PressureWheelSpec& spec);
    void setPowertrain(const PowertrainSpec& spec);
    bool hasPowertrain() const { return powertrain_.has_value(); }
    Powertrain& powertrain() { return *powertrain_; }
    const Powertrain& powertrain() const { return *powertrain_; }

    void setControls(const VehicleControls& c) { controls_ = c; }
    const VehicleControls& controls() const { return controls_; }
    VehicleControls& controls() { return controls_; }
    VehicleTelemetry telemetry() const;

    /// Index of node `id` or -1.
    std::int64_t findNode(const std::string& id) const;

    /// Max penetration depth (m) at which other bodies' nodes are still caught by this body's
    /// collision triangles (< 0 = the world setting). Thin, stiff objects (props) need less than
    /// their half thickness, or a node pushed deep in is resolved against the wrong face.
    void setContactThickness(real t) { contactThickness_ = t; }
    real contactThickness() const { return contactThickness_; }
    void addDoor(const DoorMechanism& door);
    bool setDoorOpen(std::size_t side, bool open);
    const std::vector<DoorMechanism>& doors() const { return doors_; }
    /// Bonnet / tailgate: the same reversible latch, lifted and lowered by struts on `inputChannel`.
    void addLid(const DoorMechanism& lid);
    bool setLidOpen(std::size_t index, bool open);
    const std::vector<DoorMechanism>& lids() const { return lids_; }

    // ---------------------------------------------------------------- simulation
    /// Computes beam, powertrain and wheel forces into force(); applies plasticity and breaking.
    /// Must be called once per physics step after forces are cleared.
    void accumulateBeamForces(real dt);

    /// Hydro input channels (e.g. steering in [-1, 1]).
    void setInput(int channel, real value);
    real input(int channel) const;

    /// Optional higher-level vehicle systems (cooling, engine damage, oil, fuel, brake thermals ...).
    void setSystems(const CarSystemsSpec& spec);
    bool hasSystems() const { return systems_.has_value(); }
    CarSystems& systems() { return *systems_; }
    const CarSystems& systems() const { return *systems_; }

    /// Resets all plastic deformation, broken beams/triangles/torsion bars and wheel bursts and
    /// moves every node back to `restPositions` (an earlier snapshot of positions()).
    void repair(const std::vector<Vec3>& restPositions);

    // ---------------------------------------------------------------- utilities
    void translate(const Vec3& d);
    void setVelocity(const Vec3& v);
    void addVelocity(const Vec3& v);
    Vec3 centerOfMass() const;
    Vec3 centerOfMassVelocity() const;
    real totalMass() const;
    void aabb(Vec3& lo, Vec3& hi) const;
    BodyStats stats() const;
    real kineticEnergy() const;
    real elasticEnergy() const;
    /// Gravity potential energy relative to y = 0 for gravity g.
    real potentialEnergy(const Vec3& gravity) const;

    /// Conservative explicit-integration stability estimate for time step dt.
    /// Values < 1 are stable for symplectic Euler; aim for < ~0.7.
    real stabilityRatio(real dt) const;

    /// Breaks a beam (and its break group).
    void breakBeam(std::uint32_t beamIndex);

    // ---------------------------------------------------------------- access
    const std::string& name() const { return name_; }
    void setName(std::string n) { name_ = std::move(n); }
    std::size_t nodeCount() const { return pos_.size(); }
    std::size_t beamCount() const { return beams_.size(); }
    std::size_t triangleCount() const { return triangles_.size(); }

    std::vector<Vec3>& positions() { return pos_; }
    const std::vector<Vec3>& positions() const { return pos_; }
    std::vector<Vec3>& velocities() { return vel_; }
    const std::vector<Vec3>& velocities() const { return vel_; }
    std::vector<Vec3>& forces() { return force_; }
    const std::vector<Vec3>& forces() const { return force_; }
    const std::vector<real>& masses() const { return mass_; }
    const std::vector<real>& invMasses() const { return invMass_; }
    const std::vector<real>& frictions() const { return friction_; }
    const std::vector<Vec3>& contactImpulses() const { return contactImpulse_; }
    void clearContacts() { std::fill(contactImpulse_.begin(), contactImpulse_.end(), Vec3{}); }
    void addContact(std::size_t i, const Vec3& impulse) { contactImpulse_[i] += impulse; }
    const std::vector<std::uint8_t>& collisionFlags() const { return collision_; }
    const std::vector<real>& contactStiffnesses() const { return contactStiffness_; }
    const std::vector<std::string>& nodeIds() const { return nodeIds_; }
    const NodeParams& nodeParams(std::uint32_t i) const { return nodeParams_[i]; }
    std::vector<Beam>& beams() { return beams_; }
    const std::vector<Beam>& beams() const { return beams_; }
    /// Original authoring parameters per beam (same index as beams()), for saving and tooling.
    std::vector<BeamParams>& beamParams() { return beamParams_; }
    const std::vector<BeamParams>& beamParams() const { return beamParams_; }
    std::vector<ColTri>& triangles() { return triangles_; }
    const std::vector<ColTri>& triangles() const { return triangles_; }
    const std::vector<std::string>& breakGroupNames() const { return breakGroupNames_; }
    std::vector<Torsionbar>& torsionbars() { return torsionbars_; }
    const std::vector<Torsionbar>& torsionbars() const { return torsionbars_; }
    /// Group index per node (see groupNames()).
    const std::vector<std::uint16_t>& nodeGroups() const { return nodeGroup_; }
    const std::vector<std::string>& groupNames() const { return groupNames_; }
    /// Index of a group name or -1.
    int findGroup(const std::string& name) const;
    std::vector<PressureWheel>& wheels() { return wheels_; }
    const std::vector<PressureWheel>& wheels() const { return wheels_; }

    void setNodeFriction(std::uint32_t i, real f) { if (i < friction_.size()) friction_[i] = f; }
    /// Changes a node's mass at runtime (e.g. cargo / load tests).
    void setNodeMass(std::uint32_t i, real mass);
    bool isFixed(std::uint32_t i) const { return invMass_[i] == 0; }

private:
    std::int32_t breakGroupIndex(const std::string& name);
    std::int32_t findBeamBetween(std::uint32_t u, std::uint32_t v) const;
    void processPendingBreaks();
    void stepDrivetrain(real dt);
    void accumulateTorsionbars();

    std::string name_;
    // Node data, structure-of-arrays for cache / SIMD friendliness.
    std::vector<Vec3> pos_, vel_, force_;
    std::vector<real> mass_, invMass_, friction_, contactStiffness_;
    std::vector<Vec3> contactImpulse_; // Static-surface normal impulse from the previous solver step.
    std::vector<std::uint8_t> collision_;
    std::vector<std::string> nodeIds_;
    std::vector<NodeParams> nodeParams_;
    std::vector<std::uint16_t> nodeGroup_;
    std::vector<std::string> groupNames_;
    std::unordered_map<std::string, std::uint32_t> nodeLookup_;

    void updateDoors(real dt);
    bool requestOpen(DoorMechanism& m, bool open);
    std::vector<DoorMechanism> doors_, lids_;
    real contactThickness_ = -1.0;
    std::vector<Beam> beams_;
    std::vector<BeamParams> beamParams_;
    std::vector<ColTri> triangles_;
    std::vector<SelfCollisionPanel> selfCollisionPanels_;
    std::vector<Torsionbar> torsionbars_;
    std::vector<std::string> breakGroupNames_;
    std::vector<std::vector<std::uint32_t>> breakGroupMembers_;
    std::vector<std::uint32_t> pendingBreaks_;
    std::vector<real> inputs_;

    std::vector<PressureWheel> wheels_;
    std::optional<Powertrain> powertrain_;
    VehicleControls controls_;
    real smoothedSteer_ = 0.0;
    real tcsFactor_ = 1.0;       ///< Throttle multiplier commanded by the traction control.
    bool tcsActive_ = false, absActive_ = false;
    std::optional<CarSystems> systems_;
};

}  // namespace sb
