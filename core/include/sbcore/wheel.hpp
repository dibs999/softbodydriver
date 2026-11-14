// BeamNG-style Pressure Wheel: a physical tire built from nodes and beams around
// a two-node spindle (hubRight -> hubLeft). Because every spoke connects a tire
// node to a point *on* the spindle axis, the tire ring can rotate freely by any
// angle without stretching a single beam, while cross-spokes lock camber and
// lateral position onto the hub.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "sbcore/vec3.hpp"

namespace sb {

class SoftBody;

struct PressureWheelSpec {
    std::string name = "wheel";
    std::uint32_t hubRight = 0;  ///< Spindle node on the +Z (right) side of the wheel.
    std::uint32_t hubLeft = 0;   ///< Spindle node on the -Z (left) side of the wheel.
    real radius = 0.33;          ///< Outer tire radius in m.
    real width = 0.22;           ///< Tire width in m.
    int numRays = 12;            ///< Number of circumferential segments (>= 6).
    real tireMass = 18.0;        ///< Total mass distributed over the tread nodes (kg).
    real friction = 1.25;        ///< Tire rubber friction coefficient.
    real pressurePsi = 32.0;     ///< Gauge inflation pressure in PSI (0 = flat).
    real spokeSpring = 9.0e4;    ///< Sidewall / spoke stiffness (N/m).
    real spokeDamp = 35.0;       ///< Sidewall damping (N*s/m).
    real treadSpring = 1.2e5;    ///< Belt / tread stiffness (N/m).
    real treadDamp = 45.0;       ///< Belt damping (N*s/m).
    real deform = 3.5e4;         ///< Force above which rim/sidewall bends permanently (N).
    real strength = 9.0e4;       ///< Force above which tire/wheel beams break -> puncture (N).
    bool driven = false;
    bool steered = false;
    bool braked = true;
    bool handbraked = false;
    /// Optional node pairs that receive the reaction couple of the drive torque (engine block /
    /// differential) and of the brake torque (upright / caliper). Their separation should be roughly
    /// perpendicular to the wheel axis. -1 = no reaction (torque is "external").
    std::int64_t driveReactionA = -1, driveReactionB = -1;
    std::int64_t brakeReactionA = -1, brakeReactionB = -1;
    // Tyre condition model.
    real wearRate = 1.0;         ///< Multiplier on tread wear (1 = realistic, >1 = faster for gameplay).
    real burstTempC = 175.0;     ///< Carcass temperature at which the tyre bursts.
    /// Static wheel load (N). A single tread node pressed harder than ~4.5x this (a kerb edge or a
    /// pothole lip, not flat road) pinches the tyre against the rim: bent rim, leak, pinch flat.
    real ratedLoad = 0.0;
    real ambientTempC = 22.0;
    /// Fraction of the inflation pressure acting as a membrane on the tread ring (pressure on
    /// every segment + matching belt hoop tension). 0 = off.
    real membranePressure = 0.0;
    /// Tread rubber contact stiffness per tread node in N/m (0 = rigid contact).
    real contactStiffness = 0.0;
    /// Rubber hysteresis as a rolling-resistance coefficient: a torque c * load * radius against
    /// the roll. Viscous beam damping alone loses energy in proportion to the rolling frequency,
    /// whereas a real tyre loses nearly the same energy per revolution at any speed.
    real rollingHysteresis = 0.0;
};

struct PressureWheel {
    PressureWheelSpec spec;
    std::vector<std::uint32_t> treadNodes;  ///< 2 * numRays node indices in the SoftBody.
    std::vector<std::uint32_t> beamIndices; ///< All beams belonging to this wheel.
    bool burst = false;                     ///< Set to true if any wheel beam breaks.
    real angularVelocity = 0.0;             ///< rad/s around spindle (+ = forward roll).
    real lastDriveTorque = 0.0;             ///< Nm applied in the last step.
    real lastBrakeTorque = 0.0;             ///< Nm applied in the last step.
    /// Static brake hold: while the pads clamp a (nearly) stopped disc they hold it at an angle,
    /// like a stiff torsion spring capped at the clamp torque. A brake that only cancels the spin
    /// of the current step cannot hold against a steady torque (the car crept down hills).
    bool brakeHolding = false;
    real brakeAngle = 0.0;                  ///< Wheel angle relative to the knuckle (rad, integrated).
    real brakeAnchor = 0.0;                 ///< Angle the pads hold the disc at.
    real rollOmegaFiltered = 0.0;  ///< Spin relative to the upright, low-passed for rolling hysteresis.

    // ---- tyre condition (all updated in step())
    std::vector<std::uint32_t> spokeBeams;  ///< Sidewall beams whose stiffness comes from the air pressure.
    std::vector<real> spokeBaseSpring;
    real wear = 0.0;                        ///< 0 = new, 1 = cords exposed (bursts)
    real tempC = 22.0;                      ///< Carcass / tread temperature
    real pressurePsi = 0.0;                 ///< Current gauge pressure (hot), 0 when burst
    real coldPressurePsi = 0.0;             ///< Gauge pressure referred to ambient temperature
    real leakPsiPerS = 0.0;                 ///< Slow puncture leak rate
    real rimDamage = 0.0;                   ///< 0..1 bent rim from kerb / pothole strikes
    real peakNodeForce = 0.0;               ///< Highest single tread node contact force since the last condition update
    real strikeGrace = 0.5;                 ///< s after spawn / reset in which the set-down is not a rim strike
    real load = 0.0;                        ///< Estimated vertical load (N)
    real slipSpeed = 0.0;                   ///< Sliding speed of the contact patch (m/s)
    real contactAge = 1.0;
    Vec3 contactPoint{}, contactNormal{0, 1, 0};
    real grip = 1.0;                        ///< Friction multiplier from wear and temperature
    real surfaceGrip = 1.0;                 ///< Additional loose-surface factor, set by the road classifier.
    int conditionCounter = 0;
    real appliedSpokeFactor = 1.0;
    real appliedGrip = 1.0;
    real groundGrip = 1.0;                  ///< Road-only factor: slip/load curve x kGroundScale
    real appliedGroundGrip = 1.0;

    /// Restores a new, correctly inflated tyre (used by SoftBody::repair).
    void resetCondition(SoftBody& body);
    /// Punctures the tyre: rate in psi/s (very large = burst).
    void puncture(real psiPerSecond);

    /// Unit vector from hubRight to hubLeft (points toward -Z for an unsteered wheel).
    Vec3 axis(const SoftBody& body) const;
    /// Midpoint between hubRight and hubLeft.
    Vec3 center(const SoftBody& body) const;
    /// Computes angular velocity (rad/s, + = forward) and moment of inertia (kg*m^2) about the spindle.
    real measureAngularVelocity(const SoftBody& body, real* outInertia = nullptr) const;
    /// Applies inflation pressure, drive torque (Nm, + = forward) and brake torque (Nm, >= 0) for step dt.
    void step(SoftBody& body, real driveTorque, real brakeTorque, real dt);
    /// The tyre's friction curve on top of the rubber's own coefficient: full grip up to ~15 %
    /// combined slip (contact patch sliding speed over road speed), falling to kSlideGrip when the
    /// patch slides outright (a locked or spinning wheel, a drift), and load sensitivity (a tyre
    /// pressed harder grips less per newton: twice its rated load gives ~1.76x the force).
    real slideAndLoadFactor(const SoftBody& body);   // called at the condition rate (100 Hz)
    real slideFactor = 1.0;
    static constexpr real kConditionPeriod = 0.01;
    static constexpr real kSlideGrip = 0.82;          ///< sliding / peak friction (dry rubber on asphalt)
    static constexpr real kLoadSensitivity = 0.12;    ///< per unit of load over the rated load
    /// The node tyre brakes ~15 % harder than its rubber coefficient (the tread ring's stiffness in
    /// the patch); this brings a compact on road tyres (1.15) to ~35 m from 100 km/h with ABS and
    /// ~0.88 g on a skidpad, like the real thing.
    static constexpr real kGroundScale = 0.92;
};

/// Generates the tread nodes and spoke/belt beams of a PressureWheel inside `body`.
PressureWheel addPressureWheel(SoftBody& body, const PressureWheelSpec& spec);

}  // namespace sb
