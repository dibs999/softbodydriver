// Modular vehicle powertrain: Engine (torque curve, idle governor, rev limiter,
// engine braking) -> Clutch (autolaunch / manual) -> Gearbox (R, N, 1..5,
// automatic or manual shifting) -> Viscous LSD Differential.
#pragma once

#include <utility>
#include <vector>

#include "sbcore/vec3.hpp"

namespace sb {

enum class DriveLayout { RWD, FWD, AWD };

struct PowertrainSpec {
    DriveLayout layout = DriveLayout::RWD;
    // Engine: (rpm, full-throttle torque in Nm)
    std::vector<std::pair<real, real>> torqueCurve = {
        {600.0, 110.0},
        {1000.0, 155.0},
        {2200.0, 210.0},
        {3800.0, 250.0},
        {5400.0, 235.0},
        {6400.0, 185.0},
        {6800.0, 0.0},
    };
    real idleRpm = 850.0;
    real redlineRpm = 6500.0;
    real engineInertia = 0.18;       ///< kg*m^2 (flywheel + crank)
    real engineFrictionNm = 20.0;    ///< Constant pumping/friction loss (Nm)
    real engineBraking = 0.04;       ///< Viscous loss per rad/s of engine speed
    // Clutch
    real clutchMaxTorque = 420.0;    ///< Nm capacity at full engagement
    real clutchStiffness = 18.0;     ///< Nm per (rad/s) of clutch slip
    // Gearbox
    real reverseRatio = -3.20;
    std::vector<real> forwardGears = {3.50, 2.15, 1.48, 1.12, 0.89};
    real finalDrive = 3.85;
    real drivetrainEfficiency = 0.92;
    bool automatic = true;
    real shiftUpRpm = 5700.0;
    real shiftDownRpm = 2200.0;
    real shiftDuration = 0.14;       ///< Seconds clutch disengages during an auto shift
    real shiftCooldown = 0.45;       ///< Minimum seconds between auto shifts
    // Differential & brakes
    real lsdLockingCoeff = 12.0;     ///< Nm per (rad/s) left-right wheel speed diff
    real maxBrakeTorque = 2400.0;    ///< Total per-wheel capacity before bias (Nm)
    real frontBrakeBias = 0.65;      ///< Fraction on front axle
    real handbrakeTorque = 1800.0;   ///< Nm per handbraked wheel
};

struct PowertrainInputs {
    real throttle = 0.0;    ///< [0, 1]
    real brake = 0.0;       ///< [0, 1]
    real handbrake = 0.0;   ///< [0, 1]
    real clutch = -1.0;     ///< < 0: automatic clutch; [0, 1]: manual override (1 = engaged)
    int requestedGear = -99;///< -99: keep current / auto; -1 = R, 0 = N, 1..N = forward gear
};

class Powertrain {
public:
    explicit Powertrain(PowertrainSpec spec = {});

    /// Evaluates full-throttle engine torque at the given RPM.
    real maxEngineTorqueAt(real rpm) const;

    /// Total gear ratio for the current gear (including finalDrive; 0 in Neutral).
    real currentTotalRatio() const;

    /// Advances the powertrain by dt given the current wheel angular velocities (rad/s)
    /// and writes per-wheel driveTorque (Nm) and brakeTorque (Nm, >= 0).
    /// Wheel order convention: [0]=FL, [1]=FR, [2]=RL, [3]=RR (or arbitrary with flags).
    void step(const PowertrainInputs& in,
              const std::vector<real>& wheelOmega,
              const std::vector<bool>& wheelDriven,
              const std::vector<bool>& wheelSteered,
              const std::vector<bool>& wheelBraked,
              const std::vector<bool>& wheelHandbraked,
              std::vector<real>& outDriveTorque,
              std::vector<real>& outBrakeTorque,
              real dt);

    real engineRpm() const { return engineOmega_ * (60.0 / (2.0 * 3.14159265358979323846)); }
    real engineOmega() const { return engineOmega_; }
    int gear() const { return gear_; }
    void setGear(int g);
    real clutchEngagement() const { return clutchEngagement_; }
    real lastEngineTorque() const { return lastEngineTorque_; }
    const PowertrainSpec& spec() const { return spec_; }
    PowertrainSpec& spec() { return spec_; }

private:
    PowertrainSpec spec_;
    real engineOmega_ = 0.0;
    int gear_ = 1;
    real clutchEngagement_ = 0.0;
    real shiftTimer_ = 0.0;
    real cooldownTimer_ = 0.0;
    real lastEngineTorque_ = 0.0;
};

}  // namespace sb
