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
    if (gear_ == 0) return 0.0;
    if (gear_ < 0) return spec_.reverseRatio * spec_.finalDrive;
    const int idx = std::clamp(gear_ - 1, 0, static_cast<int>(spec_.forwardGears.size()) - 1);
    return spec_.forwardGears[static_cast<std::size_t>(idx)] * spec_.finalDrive;
}

void Powertrain::setGear(int g) {
    gear_ = std::clamp(g, -1, static_cast<int>(spec_.forwardGears.size()));
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

    if (in.requestedGear != -99) setGear(in.requestedGear);

    shiftTimer_ = std::max<real>(0.0, shiftTimer_ - dt);
    cooldownTimer_ = std::max<real>(0.0, cooldownTimer_ - dt);

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

    // Idle governor + rev limiter.
    real idleAssist = 0.0;
    if (rpm < spec_.idleRpm) {
        idleAssist = std::clamp((spec_.idleRpm - rpm) / 220.0, 0.0, 0.45);
    }
    real effThrottle = std::max(throttle, idleAssist);
    if (rpm >= spec_.redlineRpm) effThrottle = 0.0;
    if (shiftTimer_ > 0.0) effThrottle *= 0.15;  // torque cut during auto shift

    const real grossTorque = effThrottle * maxEngineTorqueAt(rpm);
    const real lossTorque = spec_.engineFrictionNm + spec_.engineBraking * std::max<real>(0.0, engineOmega_);
    const real netEngineTorque = grossTorque - (1.0 - 0.7 * effThrottle) * lossTorque;
    lastEngineTorque_ = netEngineTorque;

    // Clutch engagement: manual if >= 0, otherwise automatic launch curve.
    if (in.clutch >= 0.0) {
        clutchEngagement_ = std::clamp(in.clutch, 0.0, 1.0);
    } else if (curRatio == 0.0 || shiftTimer_ > 0.0) {
        clutchEngagement_ = 0.0;
    } else {
        // Engage smoothly as RPM rises above idle, or when already moving faster than idle speed.
        const real rpmEngage = std::clamp((rpm - (spec_.idleRpm + 40.0)) / 750.0, 0.0, 1.0);
        const real speedEngage = std::clamp((wheelReferredRpm - spec_.idleRpm) / 400.0, 0.0, 1.0);
        clutchEngagement_ = std::max(rpmEngage, speedEngage);
    }

    // Coupling between engine and driven axle.
    real clutchTorque = 0.0;
    if (curRatio != 0.0 && drivenCount > 0 && clutchEngagement_ > 0.0) {
        const real targetEngineOmega = avgDrivenOmega * curRatio;
        const real slip = engineOmega_ - targetEngineOmega;
        const real cap = clutchEngagement_ * spec_.clutchMaxTorque;
        // Damped spring-damper / Coulomb clutch model.
        const real raw = slip * spec_.clutchStiffness * clutchEngagement_ + 0.5 * clutchEngagement_ * netEngineTorque;
        clutchTorque = std::clamp(raw, -cap, cap);
    }

    engineOmega_ += ((netEngineTorque - clutchTorque) / spec_.engineInertia) * dt;
    const real minOmega = rpmToRad(spec_.idleRpm * 0.65);
    if (engineOmega_ < minOmega) engineOmega_ = minOmega;

    // Distribute axle torque across driven wheels + viscous LSD between left/right pairs.
    if (drivenCount > 0 && curRatio != 0.0) {
        const real totalAxleTorque = clutchTorque * curRatio * spec_.drivetrainEfficiency;
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
