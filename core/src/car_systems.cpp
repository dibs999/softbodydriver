#include "sbcore/car_systems.hpp"

#include <algorithm>
#include <cmath>

#include "sbcore/powertrain.hpp"
#include "sbcore/softbody.hpp"

namespace sb {

namespace {
constexpr real kFuelLhv = 43.0e6;  // J/kg
inline real clamp01(real v) { return std::clamp<real>(v, 0.0, 1.0); }
}  // namespace

CarSystems::CarSystems(CarSystemsSpec spec) : spec_(std::move(spec)) {
    repair();
}

void CarSystems::repair() {
    CarSystemsState s;
    s.coolantTempC = spec_.ambientTempC + 63.0;  // engine already warm: we start "in the parking lot"
    s.oilTempC = spec_.ambientTempC + 58.0;
    s.fuelL = std::min(spec_.fuelL, spec_.fuelCapacityL);
    s.mountsTotal = static_cast<int>(spec_.engineMountBeams.size());
    s.brakeTempC.assign(spec_.suspensionBeams.size(), spec_.ambientTempC + 20.0);
    s.suspensionDamage.assign(spec_.suspensionBeams.size(), 0.0);
    state_ = s;
    structuralCounter_ = 0;
}

real CarSystems::beamGroupDamage(const SoftBody& body, const std::vector<std::uint32_t>& beams,
                                 real fullDeform, int* outBroken) {
    if (beams.empty()) return 0.0;
    const auto& bm = body.beams();
    real sum = 0.0;
    int broken = 0;
    for (std::uint32_t i : beams) {
        if (i >= bm.size()) continue;
        const Beam& b = bm[i];
        if (b.broken) {
            sum += 1.0;
            ++broken;
            continue;
        }
        sum += clamp01(b.plasticStrain() / fullDeform);
    }
    if (outBroken) *outBroken = broken;
    return clamp01(sum / static_cast<real>(beams.size()));
}

void CarSystems::updateStructuralDamage(const SoftBody& body) {
    CarSystemsState& s = state_;
    // Radiator: a few % of core deformation already cracks tubes; a broken beam means it is pierced.
    int radBroken = 0;
    s.radiatorDamage = std::max(s.radiatorDamage, beamGroupDamage(body, spec_.radiatorBeams, 0.06, &radBroken));
    if (radBroken > 0) s.radiatorDamage = std::max<real>(s.radiatorDamage, 0.35 + 0.1 * radBroken);
    s.radiatorDamage = clamp01(s.radiatorDamage);

    int panBroken = 0;
    s.oilPanDamage = std::max(s.oilPanDamage, beamGroupDamage(body, spec_.oilPanBeams, 0.08, &panBroken));
    if (panBroken > 0) s.oilPanDamage = std::max<real>(s.oilPanDamage, 0.5);

    int tankBroken = 0;
    s.fuelTankDamage = std::max(s.fuelTankDamage, beamGroupDamage(body, spec_.fuelTankBeams, 0.10, &tankBroken));
    if (tankBroken > 0) s.fuelTankDamage = std::max<real>(s.fuelTankDamage, 0.5);

    s.blockDamage = std::max(s.blockDamage, beamGroupDamage(body, spec_.engineBlockBeams, spec_.blockDeformLimit));

    int mountsBroken = 0;
    for (std::uint32_t i : spec_.engineMountBeams)
        if (i < body.beams().size() && body.beams()[i].broken) ++mountsBroken;
    s.mountsBroken = mountsBroken;

    bool shaft = false;
    for (std::uint32_t i : spec_.driveshaftBeams)
        if (i < body.beams().size() && body.beams()[i].broken) shaft = true;
    if (s.mountsTotal > 0 && mountsBroken >= s.mountsTotal - 1 && s.mountsTotal >= 2) shaft = true;
    s.driveshaftBroken = shaft;

    for (int z = 0; z < kZoneCount; ++z)
        s.zoneDamage[static_cast<std::size_t>(z)] = beamGroupDamage(body, spec_.zoneBeams[static_cast<std::size_t>(z)], 0.06);
    for (std::size_t w = 0; w < spec_.suspensionBeams.size() && w < s.suspensionDamage.size(); ++w)
        s.suspensionDamage[w] = beamGroupDamage(body, spec_.suspensionBeams[w], 0.03);
}

void CarSystems::step(SoftBody& body, Powertrain* pt, std::vector<real>& driveTorque,
                      std::vector<real>& brakeTorque, const std::vector<real>& wheelOmega,
                      bool ignition, bool starter, real throttle, real dt) {
    (void)driveTorque;
    CarSystemsState& s = state_;
    const real amb = spec_.ambientTempC;

    if (structuralCounter_-- <= 0) {
        structuralCounter_ = 19;  // ~100 Hz at 2000 Hz physics
        updateStructuralDamage(body);
    }

    // Vehicle speed estimate from the wheels (cheap, good enough for airflow).
    real wheelSpeed = 0.0;
    if (!wheelOmega.empty()) {
        for (std::size_t i = 0; i < wheelOmega.size(); ++i)
            wheelSpeed += std::abs(wheelOmega[i]) * body.wheels()[i].spec.radius;
        wheelSpeed /= static_cast<real>(wheelOmega.size());
    }

    // ------------------------------------------------------------------ brakes
    if (s.brakeTempC.size() != brakeTorque.size()) s.brakeTempC.assign(brakeTorque.size(), amb + 20.0);
    for (std::size_t i = 0; i < brakeTorque.size(); ++i) {
        real& T = s.brakeTempC[i];
        real fade = 1.0;
        if (T > spec_.brakeFadeStartC)
            fade = 1.0 - 0.55 * clamp01((T - spec_.brakeFadeStartC) / (spec_.brakeFadeFullC - spec_.brakeFadeStartC));
        brakeTorque[i] *= fade;
        const real omega = i < wheelOmega.size() ? std::abs(wheelOmega[i]) : 0.0;
        const real heat = brakeTorque[i] * omega;
        const real cool = (spec_.brakeCoolingBase + spec_.brakeCoolingSpeed * wheelSpeed) * (T - amb);
        T += (heat - cool) / spec_.brakeHeatCapacity * dt;
    }

    if (!pt) return;

    // ------------------------------------------------------------------ engine run state
    const real rpm = pt->engineRpm();
    if (!ignition && pt->running()) pt->setRunning(false);
    if (s.fuelL <= 0.0 && pt->running()) pt->setRunning(false);
    if (!pt->running() && ignition && starter && !s.seized && s.fuelL > 0.0) {
        s.crankTimer += dt;
        if (s.crankTimer > 0.7) {
            pt->setRunning(true);
            s.crankTimer = 0.0;
        }
    } else if (pt->running() || !starter) {
        s.crankTimer = 0.0;
    }
    s.running = pt->running();

    // ------------------------------------------------------------------ fuel
    const real power = s.running ? pt->lastEnginePower() : 0.0;
    s.powerKw = power * 1e-3;
    real fuelKgPerS = 0.0;
    if (s.running) {
        fuelKgPerS = (s.powerKw * spec_.bsfcGPerKWh) / 3.6e6 + spec_.idleFuelLPerH * spec_.fuelDensity / 3600.0;
    }
    s.fuelRateLPerH = fuelKgPerS / spec_.fuelDensity * 3600.0;
    real fuelLoss = fuelKgPerS / spec_.fuelDensity * dt;
    if (s.fuelTankDamage > 0.05) fuelLoss += (0.02 + 0.3 * s.fuelTankDamage) * dt;
    s.fuelL = std::max<real>(0.0, s.fuelL - fuelLoss);

    // ------------------------------------------------------------------ cooling circuit
    const real fuelPower = fuelKgPerS * kFuelLhv;
    real heatIn = spec_.engineHeatFraction * fuelPower;
    if (s.headGasketBlown && s.running) heatIn *= 1.35;           // combustion gas into the coolant
    if (s.running && s.oilPressureBar < 0.5) heatIn += 6000.0 * (rpm / 3000.0);  // metal-on-metal friction

    s.thermostat = clamp01((s.coolantTempC - spec_.thermostatOpenC) / (spec_.thermostatFullC - spec_.thermostatOpenC));
    const real flow = std::max<real>(0.03, s.thermostat);
    if (!s.fanOn && s.coolantTempC > spec_.fanOnC) s.fanOn = true;
    if (s.fanOn && s.coolantTempC < spec_.fanOnC - 5.0) s.fanOn = false;
    real airflow = spec_.radiatorBaseAirflow + (1.0 - spec_.radiatorBaseAirflow) * clamp01(wheelSpeed / 25.0);
    if (s.fanOn) airflow = std::max(airflow, spec_.fanAirflow);
    const real pumpFactor = s.running ? clamp01(s.coolantLevel / 0.55) : 0.15;
    const real radiatorEff = 1.0 - 0.85 * s.radiatorDamage;
    const real qRad = spec_.radiatorUA * flow * airflow * radiatorEff * pumpFactor * (s.coolantTempC - amb);
    const real qBlock = 35.0 * (s.coolantTempC - amb);
    const real thermalMass = spec_.engineThermalMass * (0.35 + 0.65 * s.coolantLevel);
    s.coolantTempC += (heatIn - qRad - qBlock) / thermalMass * dt;

    // Leaks: radiator damage, blown head gasket, boiling over when extremely hot.
    real coolantLoss = 0.0;
    if (s.radiatorDamage > 0.04) coolantLoss += 0.003 + 0.05 * s.radiatorDamage;
    if (s.headGasketBlown && s.running) coolantLoss += 0.004;
    if (s.coolantTempC > 125.0) coolantLoss += 0.002;
    s.coolantLevel = std::max<real>(0.0, s.coolantLevel - coolantLoss * dt);

    // ------------------------------------------------------------------ lubrication
    // A dented sump does not leak; a crack loses oil over minutes, a torn-off sump in about a minute.
    if (s.oilPanDamage > 0.15) s.oilLevel = std::max<real>(0.0, s.oilLevel - (0.002 + 0.06 * s.oilPanDamage * s.oilPanDamage) * dt);
    const real oilFactor = clamp01((s.oilLevel - 0.12) / 0.3);
    s.oilPressureBar = (rpm > 200.0) ? (0.8 + 4.2 * std::min<real>(rpm, 5500.0) / 5500.0) * oilFactor : 0.0;
    const real load = clamp01(throttle);
    const real oilTarget = s.coolantTempC + 8.0 + 18.0 * load * clamp01(rpm / 6000.0);
    s.oilTempC += (oilTarget - s.oilTempC) * std::min<real>(1.0, 0.08 * dt);

    // ------------------------------------------------------------------ damage accumulation
    if (s.running) {
        if (s.oilPressureBar < 0.5) s.wear += dt * 0.035 * std::max<real>(0.3, rpm / 3000.0);
        if (s.coolantTempC > 124.0) s.wear += dt * 0.0015 * (s.coolantTempC - 124.0);
        if (s.oilTempC > 150.0) s.wear += dt * 0.002 * (s.oilTempC - 150.0);
    }
    if (!s.headGasketBlown && s.coolantTempC > spec_.headGasketC) s.headGasketBlown = true;
    s.wear = clamp01(s.wear);
    if (s.coolantTempC > spec_.seizeC || s.wear >= 1.0 || s.blockDamage >= 1.0) s.seized = true;

    real scale = 1.0;
    if (s.coolantTempC > spec_.overheatPowerLossC)
        scale *= std::clamp<real>(1.0 - (s.coolantTempC - spec_.overheatPowerLossC) / 30.0, 0.35, 1.0);
    if (s.headGasketBlown) scale *= 0.72;
    scale *= 1.0 - 0.75 * s.blockDamage;
    scale *= 1.0 - 0.5 * s.wear;
    s.engineTorqueScale = std::max<real>(0.0, scale);
    s.extraFrictionNm = 45.0 * s.blockDamage + 90.0 * s.wear;

    EngineCondition c;
    c.torqueScale = s.engineTorqueScale;
    c.extraFrictionNm = s.extraFrictionNm;
    c.seized = s.seized;
    c.driveConnected = !s.driveshaftBroken;
    pt->setCondition(c);

    // ------------------------------------------------------------------ status text (priority order)
    if (structuralCounter_ == 0) {
        if (s.seized) s.status = "ENGINE SEIZED";
        else if (s.fuelL <= 0.0) s.status = "OUT OF FUEL";
        else if (s.driveshaftBroken) s.status = "DRIVESHAFT BROKEN";
        else if (s.headGasketBlown) s.status = "HEAD GASKET BLOWN";
        else if (s.coolantTempC > 115.0) s.status = "OVERHEATING";
        else if (s.running && s.oilPressureBar < 0.6) s.status = "LOW OIL PRESSURE";
        else if (s.coolantLevel < 0.35) s.status = "LOW COOLANT";
        else if (s.radiatorDamage > 0.04 && s.coolantLevel > 0.0) s.status = "COOLANT LEAK";
        else if (s.oilPanDamage > 0.15 && s.oilLevel > 0.0) s.status = "OIL LEAK";
        else if (s.fuelTankDamage > 0.05 && s.fuelL > 0.0) s.status = "FUEL LEAK";
        else if (!s.running) s.status = "ENGINE OFF";
        else s.status.clear();
    }
}

}  // namespace sb
