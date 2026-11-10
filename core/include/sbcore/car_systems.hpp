// Vehicle subsystems on top of the node-beam structure, driven by real physical damage:
//
//   * Cooling circuit: engine heat -> coolant -> thermostat -> radiator (airflow + fan).
//     A deformed / pierced radiator leaks coolant; with too little coolant the engine overheats,
//     loses power, blows its head gasket and finally seizes.
//   * Lubrication: oil pan nodes under the engine. A crushed oil pan leaks oil; without oil
//     pressure the bearings wear out within seconds and the engine seizes.
//   * Engine block: if the block beams themselves are deformed in a crash the engine is damaged.
//   * Engine mounts: breakable beams; the drivetrain disconnects when the engine tears loose.
//   * Fuel: consumption from brake-specific fuel consumption (g/kWh); a damaged tank leaks.
//   * Brakes: disc temperature, convective cooling with airflow, fade above ~450 degC.
//   * Damage zones (front / rear / left / right / roof / underbody) for the HUD.
//
// The structure only stores beam *indices* into the owning SoftBody, so it is cheap to copy.
#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "sbcore/vec3.hpp"

namespace sb {

class SoftBody;
class Powertrain;

enum DamageZone : int { kZoneFront = 0, kZoneRear, kZoneLeft, kZoneRight, kZoneRoof, kZoneUnder, kZoneCount };

struct CarSystemsSpec {
    // ---- structure references (beam indices into the SoftBody)
    std::vector<std::uint32_t> radiatorBeams;
    std::vector<std::uint32_t> engineBlockBeams;
    std::vector<std::uint32_t> oilPanBeams;
    std::vector<std::uint32_t> fuelTankBeams;
    std::vector<std::uint32_t> engineMountBeams;
    std::vector<std::uint32_t> driveshaftBeams;   ///< Breaking any of them disconnects the drive.
    std::array<std::vector<std::uint32_t>, kZoneCount> zoneBeams;
    std::vector<std::vector<std::uint32_t>> suspensionBeams;  ///< Per wheel.

    // ---- cooling
    real ambientTempC = 22.0;
    real coolantCapacityL = 6.5;
    real thermostatOpenC = 88.0;
    real thermostatFullC = 98.0;
    real radiatorUA = 1500.0;        ///< W/K at full flow with ~25 m/s airflow.
    real radiatorBaseAirflow = 0.30; ///< Fraction of UA available at standstill without fan.
    real fanOnC = 101.0;             ///< Electric fan switches on above this coolant temperature.
    real fanAirflow = 0.55;          ///< Fan airflow equivalent (fraction of UA).
    real engineHeatFraction = 0.32;  ///< Share of fuel energy that ends up in the coolant.
    real engineThermalMass = 32000.0;///< J/K of block + coolant (with full coolant).
    real oilThermalMass = 9000.0;    ///< J/K
    // ---- engine damage limits
    real overheatPowerLossC = 118.0;  ///< Above this the ECU / physics start to cut power.
    real headGasketC = 128.0;         ///< Sustained above -> head gasket blows.
    real seizeC = 145.0;              ///< Engine seizes.
    real blockDeformLimit = 0.015;    ///< Mean relative block beam deformation -> fully damaged.
    // ---- fuel
    real fuelCapacityL = 50.0;
    real fuelL = 40.0;
    real bsfcGPerKWh = 255.0;
    real idleFuelLPerH = 0.8;
    real fuelDensity = 0.745;         ///< kg/L
    // ---- brakes
    real brakeHeatCapacity = 9000.0;  ///< J/K per disc + pad
    real brakeCoolingBase = 6.0;      ///< W/K at standstill
    real brakeCoolingSpeed = 2.4;     ///< Extra W/K per m/s
    real brakeFadeStartC = 450.0;
    real brakeFadeFullC = 800.0;
};

struct CarSystemsState {
    real coolantTempC = 22.0;
    real oilTempC = 22.0;
    real coolantLevel = 1.0;     ///< 0..1
    real oilLevel = 1.0;         ///< 0..1
    real oilPressureBar = 0.0;
    real fuelL = 40.0;
    real thermostat = 0.0;       ///< Opening 0..1
    bool fanOn = false;

    real radiatorDamage = 0.0;   ///< 0..1
    real oilPanDamage = 0.0;     ///< 0..1
    real fuelTankDamage = 0.0;   ///< 0..1
    real blockDamage = 0.0;      ///< 0..1 (structural)
    real wear = 0.0;             ///< 0..1 accumulated bearing / overheat wear
    bool headGasketBlown = false;
    /// Over-revving (engine dragged past redline, e.g. a "money shift" into a far too low gear):
    /// valve float wears it, bent valves misfire, a thrown connecting rod destroys the engine.
    real overRevDamage = 0.0;    ///< 0..1
    real peakOverRev = 0.0;      ///< Highest rpm / redline reached
    real overRevTimer = 0.0;     ///< Seconds above the bent-valve / thrown-rod limits
    bool valvesBent = false;
    bool rodBroken = false;
    /// Rod bearings: wiped by oil starvation (low pressure) and very hot, thin oil. The engine
    /// knocks louder and louder and finally throws a rod.
    real rodBearingWear = 0.0;   ///< 0..1
    /// Piston rings: scuffed by overheating and over-revving: lost compression, burns oil.
    real pistonRingDamage = 0.0; ///< 0..1
    real knock = 0.0;            ///< Output: audible bearing knock 0..1
    Vec3 lastVelocity{};         ///< For the horizontal acceleration that sloshes the oil away from the pickup
    real horizontalG = 0.0;      ///< Filtered horizontal acceleration (g)
    real accelTimer = 0.0;
    bool oilStarved = false;     ///< Oil pickup sucking air (low level + hard cornering / braking)
    bool seized = false;
    bool running = true;
    bool driveshaftBroken = false;
    int mountsBroken = 0;
    int mountsTotal = 0;
    real crankTimer = 0.0;

    std::vector<real> brakeTempC;   ///< Per wheel
    std::vector<real> suspensionDamage;  ///< Per wheel 0..1
    std::array<real, kZoneCount> zoneDamage{};

    real engineTorqueScale = 1.0;   ///< Output: multiplier the powertrain applies.
    real extraFrictionNm = 0.0;     ///< Output: extra engine friction from damage.
    real powerKw = 0.0;             ///< Last brake power
    real fuelRateLPerH = 0.0;
    std::string status;             ///< Short human readable status, e.g. "OVERHEATING".
};

class CarSystems {
public:
    CarSystems() = default;
    explicit CarSystems(CarSystemsSpec spec);

    /// Called by the SoftBody every physics step after the powertrain has produced torques.
    /// Applies brake fade to `brakeTorque` in place and updates all thermal / damage state.
    void step(SoftBody& body, Powertrain* pt, std::vector<real>& driveTorque,
              std::vector<real>& brakeTorque, const std::vector<real>& wheelOmega,
              bool ignition, bool starter, real throttle, real dt);

    /// Restores all systems to factory state (used by repair / reset).
    void repair();

    const CarSystemsSpec& spec() const { return spec_; }
    CarSystemsSpec& spec() { return spec_; }
    const CarSystemsState& state() const { return state_; }
    CarSystemsState& state() { return state_; }

private:
    static real beamGroupDamage(const SoftBody& body, const std::vector<std::uint32_t>& beams,
                                real fullDeform, int* outBroken = nullptr);
    void updateStructuralDamage(const SoftBody& body);

    CarSystemsSpec spec_;
    CarSystemsState state_;
    int structuralCounter_ = 0;
};

}  // namespace sb
