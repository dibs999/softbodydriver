#include "sbcore/powertrain.hpp"

#include <algorithm>
#include <cmath>

namespace sb {

namespace {
constexpr real kPi = 3.14159265358979323846;
constexpr real rpmToRad(real rpm) { return rpm * (2.0 * kPi / 60.0); }
constexpr real radToRpm(real rad) { return rad * (60.0 / (2.0 * kPi)); }
}  // namespace

Powertrain::Powertrain(PowertrainSpec spec) : spec_(std::move(spec)) {
    engineOmega_ = rpmToRad(spec_.idleRpm);
}

real Powertrain::maxEngineTorqueAt(real rpm) const {
    const auto& c = spec_.torqueCurve;
    if (c.empty()) return 200.0;
    if (rpm <= c.front().first) return c.front().second;
    if (rpm >= c.back().first) return c.back().second;
    for (std::size_t i = 0; i + 1 < c.size(); ++i) {
        if (rpm >= c[i].first && rpm <= c[i + 1].first) {
            const real t = (rpm - c[i].first) / (c[i + 1].first - c[i].first);
            return c[i].second + t * (c[i + 1].second - c[i].second);
        }
    }
    return c.back().second;
}

real Powertrain::currentTotalRatio() const {
    if (gear_ == 0 || gearboxDamage_ >= 1.0) return 0.0;
    if (gear_ < 0) return spec_.reverseRatio * spec_.finalDrive;
    const int idx = std::clamp(gear_ - 1, 0, static_cast<int>(spec_.forwardGears.size()) - 1);
    return spec_.forwardGears[static_cast<std::size_t>(idx)] * spec_.finalDrive;
}

void Powertrain::setRunning(bool r) {
    if (r && !running_ && !cond_.seized) engineOmega_ = std::max(engineOmega_, rpmToRad(spec_.idleRpm));
    running_ = r && !cond_.seized;
}

void Powertrain::setGear(int g) {
    gear_ = std::clamp(g, -1, static_cast<int>(spec_.forwardGears.size()));
}

void Powertrain::repair() {
    // Preserve the chosen transmission mode and wheel inertia.
    engineOmega_ = rpmToRad(spec_.idleRpm);
    gear_ = 1;
    clutchEngagement_ = shiftTimer_ = cooldownTimer_ = 0.0;
    lastEngineTorque_ = lastEnginePower_ = 0.0;
    clutchTempC_ = 45.0;
    clutchWear_ = gearboxDamage_ = clutchSlipRpm_ = grind_ = 0.0;
    cond_ = {};
    running_ = true;
}

void Powertrain::step(const PowertrainInputs& in,
                      const std::vector<real>& wheelOmega,
                      const std::vector<bool>& wheelDriven,
                      const std::vector<bool>& wheelSteered,
                      const std::vector<bool>& wheelBraked,
                      const std::vector<bool>& wheelHandbraked,
                      std::vector<real>& outDriveTorque,
                      std::vector<real>& outBrakeTorque,
                      real dt) {
    const std::size_t n = wheelOmega.size();
    outDriveTorque.assign(n, 0.0);
    outBrakeTorque.assign(n, 0.0);

    const real throttle = std::clamp(in.throttle, 0.0, 1.0);
    const real brake = std::clamp(in.brake, 0.0, 1.0);
    const real handbrake = std::clamp(in.handbrake, 0.0, 1.0);

    shiftTimer_ = std::max<real>(0.0, shiftTimer_ - dt);
    cooldownTimer_ = std::max<real>(0.0, cooldownTimer_ - dt);
    grind_ = std::max<real>(0.0, grind_ - dt * 3.0);

    // Average angular velocity of driven wheels.
    real avgDrivenOmega = 0.0;
    int drivenCount = 0;
    for (std::size_t i = 0; i < n; ++i) {
        if (wheelDriven[i]) {
            avgDrivenOmega += wheelOmega[i];
            ++drivenCount;
        }
    }
    if (drivenCount > 0) avgDrivenOmega /= static_cast<real>(drivenCount);

    if (in.requestedGear != -99 && in.requestedGear != gear_) {
        const int oldGear = gear_;
        setGear(in.requestedGear);
        const real targetRpm = radToRpm(avgDrivenOmega * currentTotalRatio());
        const real mismatch = std::abs(targetRpm - engineRpm());
        // Auto mode refuses destructive downshifts/direction changes. In manual mode,
        // synchronisers can tolerate rev-matching, but not repeated loaded shifts.
        const bool overspeed = std::abs(targetRpm) > spec_.redlineRpm * 1.12;
        const bool wrongDirection = targetRpm < -500.0;
        if (spec_.automatic && (overspeed || wrongDirection)) {
            gear_ = oldGear;
        } else {
            if (!spec_.automatic && gear_ != 0) {
                const real engaged = in.clutch >= 0.0 ? in.clutch : clutchEngagement_;
                const real forced = std::clamp((mismatch - 650.0) / 2800.0, 0.0, 1.0) * engaged;
                const real abuse = forced * (0.25 + 0.75 * throttle) + (overspeed || wrongDirection ? 0.75 : 0.0);
                gearboxDamage_ = std::min<real>(1.0, gearboxDamage_ + 0.10 * abuse);
                grind_ = std::min<real>(1.0, abuse);
            }
            shiftTimer_ = spec_.shiftDuration * (1.0 + gearboxDamage_ * 2.0);
            cooldownTimer_ = spec_.shiftCooldown;
        }
    }
    if (gearboxDamage_ >= 1.0) gear_ = 0;

    // Automatic transmission shift logic ( based on wheel-referred RPM so wheelspin / clutch slip stays sane ).
    const real ratio = currentTotalRatio();
    const real wheelReferredRpm = std::abs(avgDrivenOmega * ratio) * (60.0 / (2.0 * kPi));
    if (spec_.automatic && in.requestedGear == -99 && gear_ >= 1 && cooldownTimer_ <= 0.0) {
        if (gear_ < static_cast<int>(spec_.forwardGears.size()) &&
            wheelReferredRpm > spec_.shiftUpRpm && throttle > 0.2) {
            ++gear_;
            shiftTimer_ = spec_.shiftDuration;
            cooldownTimer_ = spec_.shiftCooldown;
        } else if (gear_ > 1 && wheelReferredRpm < spec_.shiftDownRpm) {
            --gear_;
            shiftTimer_ = spec_.shiftDuration * 0.7;
            cooldownTimer_ = spec_.shiftCooldown;
        }
    }

    const real curRatio = currentTotalRatio();
    const real rpm = radToRpm(engineOmega_);

    if (cond_.seized) running_ = false;

    // Idle governor + rev limiter.
    real idleAssist = 0.0;
    if (running_ && rpm < spec_.idleRpm) {
        idleAssist = std::clamp((spec_.idleRpm - rpm) / 220.0, 0.0, 0.45);
    }
    real effThrottle = running_ ? std::max(throttle, idleAssist) : 0.0;
    if (rpm >= spec_.redlineRpm) effThrottle = 0.0;
    if (shiftTimer_ > 0.0) effThrottle *= 0.15;  // torque cut during auto shift

    const real grossTorque = effThrottle * maxEngineTorqueAt(rpm) * std::max<real>(0.0, cond_.torqueScale);
    const real lossTorque = spec_.engineFrictionNm + cond_.extraFrictionNm +
                            spec_.engineBraking * std::max<real>(0.0, engineOmega_);
    real netEngineTorque = grossTorque - (1.0 - 0.7 * effThrottle) * lossTorque;
    // Friction never drives the crank backwards.
    if (engineOmega_ <= 0.0 && netEngineTorque < 0.0) netEngineTorque = 0.0;
    lastEngineTorque_ = netEngineTorque;
    lastEnginePower_ = std::max<real>(0.0, grossTorque * engineOmega_);

    // Clutch engagement: manual if >= 0, otherwise automatic launch curve.
    if (shiftTimer_ > 0.0 || clutchWear_ >= 1.0) {
        clutchEngagement_ = 0.0;
    } else if (in.clutch >= 0.0) {
        clutchEngagement_ = std::clamp(in.clutch, 0.0, 1.0);
    } else if (cond_.seized || (!running_ && rpm < spec_.idleRpm * 0.5)) {
        clutchEngagement_ = 0.0;
    } else if (curRatio == 0.0 || shiftTimer_ > 0.0) {
        clutchEngagement_ = 0.0;
    } else {
        // Engage smoothly as RPM rises above idle, or when already moving faster than idle speed.
        const real rpmEngage = std::clamp((rpm - (spec_.idleRpm + 40.0)) / 750.0, 0.0, 1.0);
        const real speedEngage = std::clamp((wheelReferredRpm - spec_.idleRpm) / 400.0, 0.0, 1.0);
        // Pulling away with little throttle: the clutch bites in proportion to the pedal (the idle
        // governor keeps the engine alive). Purely rpm-based engagement balanced the engine at idle
        // against a 5 % clutch and a gentle 25 % throttle never moved the car.
        const real pedalEngage = throttle > 0.05 ? 0.4 * throttle : 0.0;
        clutchEngagement_ = std::max({rpmEngage, speedEngage, pedalEngage});
    }

    // Coupling between engine and driven axle.
    real clutchTorque = 0.0;
    real slipPower = 0.0;
    clutchSlipRpm_ = 0.0;
    if (curRatio != 0.0 && drivenCount > 0 && clutchEngagement_ > 0.0 && cond_.driveConnected) {
        const real targetEngineOmega = avgDrivenOmega * curRatio;
        const real slip = engineOmega_ - targetEngineOmega;
        const real fade = 1.0 - 0.75 * std::clamp((clutchTempC_ - 180.0) / 180.0, 0.0, 1.0);
        const real cap = clutchEngagement_ * spec_.clutchMaxTorque * fade * (1.0 - clutchWear_);
        // Viscous clutch coupling. Explicit integration is only stable while
        // dt * k * (ratio^2 / I_wheels + 1 / I_engine) stays well below 1, so the coupling is
        // softened automatically in low gears with light wheels.
        real k = spec_.clutchStiffness * clutchEngagement_;
        const real r2 = curRatio * curRatio * spec_.drivetrainEfficiency;
        const real invI = (drivenInertia_ > 1e-6 ? r2 / drivenInertia_ : 0.0) + 1.0 / spec_.engineInertia;
        k = std::min(k, 0.45 / (dt * invI));
        const real raw = slip * k + 0.5 * clutchEngagement_ * netEngineTorque;
        clutchTorque = std::clamp(raw, -cap, cap);
        clutchSlipRpm_ = std::abs(radToRpm(slip));
        // Ignore the small numerical creep of the stable viscous coupling.
        slipPower = std::abs(clutchTorque) * std::max<real>(0.0, std::abs(slip) - rpmToRad(120.0));
    }
    const real cooling = (spec_.clutchCooling + std::abs(avgDrivenOmega) * 0.6) * (clutchTempC_ - 25.0);
    clutchTempC_ = std::max<real>(25.0, clutchTempC_ + (slipPower - cooling) / std::max<real>(1.0, spec_.clutchHeatCapacity) * dt);
    if (clutchTempC_ > 230.0)
        clutchWear_ = std::min<real>(1.0, clutchWear_ + (clutchTempC_ - 230.0) * 0.00012 * dt);

    if (cond_.seized) {
        engineOmega_ = 0.0;
    } else {
        engineOmega_ += ((netEngineTorque - clutchTorque) / spec_.engineInertia) * dt;
        if (running_) {
            // A running engine can still be stalled by lugging it with the clutch engaged.
            if (engineOmega_ < rpmToRad(spec_.idleRpm * 0.30) && clutchEngagement_ > 0.6) running_ = false;
            const real minOmega = rpmToRad(spec_.idleRpm * 0.65);
            if (running_ && engineOmega_ < minOmega && clutchEngagement_ < 0.6) engineOmega_ = minOmega;
        }
        if (engineOmega_ < 0.0) engineOmega_ = 0.0;
    }

    // Distribute axle torque across driven wheels + viscous LSD between left/right pairs.
    if (drivenCount > 0 && curRatio != 0.0 && cond_.driveConnected) {
        const real totalAxleTorque = clutchTorque * curRatio * spec_.drivetrainEfficiency * (1.0 - 0.45 * gearboxDamage_);
        const real perWheel = totalAxleTorque / static_cast<real>(drivenCount);
        for (std::size_t i = 0; i < n; ++i) {
            if (wheelDriven[i]) outDriveTorque[i] = perWheel;
        }
        // Pairwise viscous LSD for driven (2*k, 2*k+1) left/right axle pairs.
        for (std::size_t i = 0; i + 1 < n; i += 2) {
            if (wheelDriven[i] && wheelDriven[i + 1]) {
                const real diff = wheelOmega[i] - wheelOmega[i + 1];
                const real lock = std::clamp(diff * spec_.lsdLockingCoeff, -400.0, 400.0);
                outDriveTorque[i] -= lock;
                outDriveTorque[i + 1] += lock;
            }
        }
    }

    // Service brakes (split by front/rear bias) + handbrake.
    for (std::size_t i = 0; i < n; ++i) {
        real b = 0.0;
        if (wheelBraked[i]) {
            const real bias = wheelSteered[i] ? spec_.frontBrakeBias : (1.0 - spec_.frontBrakeBias);
            b += brake * spec_.maxBrakeTorque * (2.0 * bias);
        }
        if (wheelHandbraked[i]) {
            b += handbrake * spec_.handbrakeTorque;
        }
        outBrakeTorque[i] = b;
    }
}

}  // namespace sb
