#include "sbcore/softbody.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <stdexcept>

namespace sb {

const char* beamTypeToString(BeamType t) {
    switch (t) {
        case BeamType::Normal: return "normal";
        case BeamType::Support: return "support";
        case BeamType::Anisotropic: return "anisotropic";
        case BeamType::Hydro: return "hydro";
    }
    return "normal";
}

bool beamTypeFromString(const std::string& s, BeamType& out) {
    std::string l;
    l.reserve(s.size());
    for (char c : s) l.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
    if (l == "normal") { out = BeamType::Normal; return true; }
    if (l == "support") { out = BeamType::Support; return true; }
    if (l == "anisotropic") { out = BeamType::Anisotropic; return true; }
    if (l == "hydro") { out = BeamType::Hydro; return true; }
    return false;
}

std::uint32_t SoftBody::addNode(const std::string& id, const Vec3& pos, const NodeParams& p) {
    if (!id.empty() && nodeLookup_.count(id)) throw std::invalid_argument("duplicate node id: " + id);
    if (!(p.mass > 0) && !p.fixed) throw std::invalid_argument("node mass must be > 0: " + id);
    const auto idx = static_cast<std::uint32_t>(pos_.size());
    pos_.push_back(pos);
    vel_.push_back({});
    force_.push_back({});
    mass_.push_back(p.mass);
    invMass_.push_back(p.fixed ? 0.0 : 1.0 / p.mass);
    friction_.push_back(p.friction);
    collision_.push_back(p.collision ? 1 : 0);
    std::string name = id;
    if (name.empty()) {
        name = "n";
        name += std::to_string(idx);
    }
    nodeIds_.push_back(name);
    nodeParams_.push_back(p);
    nodeLookup_[name] = idx;
    return idx;
}

std::int64_t SoftBody::findNode(const std::string& id) const {
    auto it = nodeLookup_.find(id);
    return it == nodeLookup_.end() ? -1 : static_cast<std::int64_t>(it->second);
}

std::int32_t SoftBody::breakGroupIndex(const std::string& name) {
    for (std::size_t i = 0; i < breakGroupNames_.size(); ++i)
        if (breakGroupNames_[i] == name) return static_cast<std::int32_t>(i);
    breakGroupNames_.push_back(name);
    breakGroupMembers_.emplace_back();
    return static_cast<std::int32_t>(breakGroupNames_.size() - 1);
}

std::uint32_t SoftBody::addBeam(std::uint32_t a, std::uint32_t b, const BeamParams& p) {
    if (a >= pos_.size() || b >= pos_.size()) throw std::invalid_argument("beam node index out of range");
    if (a == b) throw std::invalid_argument("beam connects a node to itself");
    const real len = length(pos_[b] - pos_[a]);
    if (len < 1e-6) throw std::invalid_argument("beam with zero length: " + nodeIds_[a] + "-" + nodeIds_[b]);
    if (p.spring < 0 || p.damp < 0) throw std::invalid_argument("beam spring/damp must be >= 0");

    Beam bm;
    bm.a = a;
    bm.b = b;
    bm.type = p.type;
    bm.spring = p.spring;
    bm.damp = p.damp;
    bm.springExp = p.springExpansion >= 0 ? p.springExpansion : p.spring;
    bm.dampExp = p.dampExpansion >= 0 ? p.dampExpansion : p.damp;
    bm.baseRestLength = len * p.precompression;
    bm.restLength = bm.baseRestLength;
    bm.deformThreshold = p.deform;
    bm.hardening = p.hardening;
    bm.strength = p.strength;
    bm.minRest = std::isinf(p.deformLimit) ? 0.0 : bm.baseRestLength * std::max<real>(0.0, 1.0 - p.deformLimit);
    bm.maxRest = std::isinf(p.deformLimitExpansion) ? kInf : bm.baseRestLength * (1.0 + p.deformLimitExpansion);
    bm.hydroInput = p.type == BeamType::Hydro ? p.hydroInput : -1;
    bm.hydroRatio = p.hydroRatio;
    bm.params = p;

    const auto idx = static_cast<std::uint32_t>(beams_.size());
    if (!p.breakGroup.empty()) {
        bm.breakGroup = breakGroupIndex(p.breakGroup);
        breakGroupMembers_[static_cast<std::size_t>(bm.breakGroup)].push_back(idx);
    }
    if (bm.hydroInput >= 0 && static_cast<std::size_t>(bm.hydroInput) >= inputs_.size())
        inputs_.resize(static_cast<std::size_t>(bm.hydroInput) + 1, 0.0);
    beams_.push_back(bm);
    return idx;
}

std::uint32_t SoftBody::addBeam(const std::string& a, const std::string& b, const BeamParams& p) {
    const auto ia = findNode(a), ib = findNode(b);
    if (ia < 0) throw std::invalid_argument("unknown node: " + a);
    if (ib < 0) throw std::invalid_argument("unknown node: " + b);
    return addBeam(static_cast<std::uint32_t>(ia), static_cast<std::uint32_t>(ib), p);
}

std::int32_t SoftBody::findBeamBetween(std::uint32_t u, std::uint32_t v) const {
    for (std::size_t i = 0; i < beams_.size(); ++i) {
        if ((beams_[i].a == u && beams_[i].b == v) || (beams_[i].a == v && beams_[i].b == u))
            return static_cast<std::int32_t>(i);
    }
    return -1;
}

std::uint32_t SoftBody::addTriangle(std::uint32_t a, std::uint32_t b, std::uint32_t c, const ColTriParams& p) {
    if (a >= pos_.size() || b >= pos_.size() || c >= pos_.size())
        throw std::invalid_argument("triangle node index out of range");
    if (a == b || b == c || c == a)
        throw std::invalid_argument("degenerate triangle with duplicate vertices");

    ColTri t;
    t.a = a;
    t.b = b;
    t.c = c;
    t.friction = p.friction;
    t.dragCoef = p.dragCoef;
    t.breakable = p.breakable;
    if (!p.breakGroup.empty()) t.breakGroup = breakGroupIndex(p.breakGroup);
    t.edgeBeams[0] = findBeamBetween(a, b);
    t.edgeBeams[1] = findBeamBetween(b, c);
    t.edgeBeams[2] = findBeamBetween(c, a);
    t.params = p;

    const auto idx = static_cast<std::uint32_t>(triangles_.size());
    triangles_.push_back(t);
    return idx;
}

std::uint32_t SoftBody::addTriangle(const std::string& a, const std::string& b, const std::string& c,
                                    const ColTriParams& p) {
    const auto ia = findNode(a), ib = findNode(b), ic = findNode(c);
    if (ia < 0) throw std::invalid_argument("unknown node: " + a);
    if (ib < 0) throw std::invalid_argument("unknown node: " + b);
    if (ic < 0) throw std::invalid_argument("unknown node: " + c);
    return addTriangle(static_cast<std::uint32_t>(ia), static_cast<std::uint32_t>(ib), static_cast<std::uint32_t>(ic), p);
}

void SoftBody::setInput(int channel, real value) {
    if (channel < 0) return;
    if (static_cast<std::size_t>(channel) >= inputs_.size()) inputs_.resize(static_cast<std::size_t>(channel) + 1, 0.0);
    inputs_[static_cast<std::size_t>(channel)] = value;
}

real SoftBody::input(int channel) const {
    if (channel < 0 || static_cast<std::size_t>(channel) >= inputs_.size()) return 0.0;
    return inputs_[static_cast<std::size_t>(channel)];
}

void SoftBody::breakBeam(std::uint32_t beamIndex) {
    if (beamIndex >= beams_.size() || beams_[beamIndex].broken) return;
    pendingBreaks_.push_back(beamIndex);
    processPendingBreaks();
}

void SoftBody::processPendingBreaks() {
    while (!pendingBreaks_.empty()) {
        const std::uint32_t i = pendingBreaks_.back();
        pendingBreaks_.pop_back();
        Beam& bm = beams_[i];
        if (bm.broken) continue;
        bm.broken = true;
        bm.lastForce = 0;
        if (bm.breakGroup >= 0) {
            for (std::uint32_t other : breakGroupMembers_[static_cast<std::size_t>(bm.breakGroup)])
                if (!beams_[other].broken) pendingBreaks_.push_back(other);
        }
    }
    for (ColTri& tri : triangles_) {
        if (tri.broken) continue;
        if (tri.breakGroup >= 0) {
            for (std::uint32_t bIdx : breakGroupMembers_[static_cast<std::size_t>(tri.breakGroup)]) {
                if (beams_[bIdx].broken) {
                    tri.broken = true;
                    break;
                }
            }
        }
        if (!tri.broken && tri.breakable) {
            for (int e = 0; e < 3; ++e) {
                if (tri.edgeBeams[e] >= 0 && beams_[static_cast<std::size_t>(tri.edgeBeams[e])].broken) {
                    tri.broken = true;
                    break;
                }
            }
        }
    }
}

std::size_t SoftBody::addWheel(const PressureWheelSpec& spec) {
    wheels_.push_back(addPressureWheel(*this, spec));
    return wheels_.size() - 1;
}

void SoftBody::setPowertrain(const PowertrainSpec& spec) {
    powertrain_.emplace(spec);
}

void SoftBody::stepDrivetrain(real dt) {
    if (wheels_.empty() && !powertrain_) return;

    const std::size_t nw = wheels_.size();
    std::vector<real> omega(nw, 0.0);
    std::vector<bool> driven(nw, false), steered(nw, false), braked(nw, false), handbraked(nw, false);
    for (std::size_t i = 0; i < nw; ++i) {
        omega[i] = wheels_[i].measureAngularVelocity(*this);
        driven[i] = wheels_[i].spec.driven;
        steered[i] = wheels_[i].spec.steered;
        braked[i] = wheels_[i].spec.braked;
        handbraked[i] = wheels_[i].spec.handbraked;
    }

    std::vector<real> driveTorque(nw, 0.0), brakeTorque(nw, 0.0);
    if (powertrain_) {
        PowertrainInputs pin;
        pin.throttle = controls_.throttle;
        pin.brake = controls_.brake;
        pin.handbrake = controls_.handbrake;
        pin.clutch = controls_.clutch;
        pin.requestedGear = controls_.gear;
        powertrain_->step(pin, omega, driven, steered, braked, handbraked, driveTorque, brakeTorque, dt);
    } else {
        for (std::size_t i = 0; i < nw; ++i) {
            if (braked[i]) brakeTorque[i] += std::clamp(controls_.brake, 0.0, 1.0) * 1800.0;
            if (handbraked[i]) brakeTorque[i] += std::clamp(controls_.handbrake, 0.0, 1.0) * 1500.0;
        }
    }

    for (std::size_t i = 0; i < nw; ++i) {
        wheels_[i].step(*this, driveTorque[i], brakeTorque[i], dt);
    }
}

void SoftBody::accumulateBeamForces(real dt) {
    if (!wheels_.empty() || powertrain_) {
        const real targetSteer = std::clamp(controls_.steer, -1.0, 1.0);
        if (controls_.steerRate > 0.0 && dt > 0.0) {
            const real maxDelta = controls_.steerRate * dt;
            smoothedSteer_ += std::clamp(targetSteer - smoothedSteer_, -maxDelta, maxDelta);
        } else {
            smoothedSteer_ = targetSteer;
        }
        setInput(0, smoothedSteer_);
    }

    const std::size_t n = beams_.size();
    Vec3* force = force_.data();
    const Vec3* pos = pos_.data();
    const Vec3* vel = vel_.data();

    for (std::size_t i = 0; i < n; ++i) {
        Beam& bm = beams_[i];
        if (bm.broken) continue;

        const Vec3 d = pos[bm.b] - pos[bm.a];
        const real len = length(d);
        if (len < 1e-9) continue;
        const Vec3 dir = d / len;
        const real lenRate = dot(vel[bm.b] - vel[bm.a], dir);  // dL/dt

        if (bm.hydroInput >= 0) {
            const real in = inputs_[static_cast<std::size_t>(bm.hydroInput)];
            bm.restLength = bm.baseRestLength * (1.0 + bm.hydroRatio * in) + bm.hydroOffset;
        }

        real ext = len - bm.restLength;  // > 0: stretched
        real k = bm.spring, c = bm.damp;
        if (bm.type == BeamType::Anisotropic && ext > 0) {
            k = bm.springExp;
            c = bm.dampExp;
        } else if (bm.type == BeamType::Support && ext > 0) {
            bm.lastForce = 0;  // support beams never pull
            continue;
        }

        real fs = k * ext;
        // --- plasticity: move the rest length so that the spring force stays at the threshold
        if (k > 0 && std::abs(fs) > bm.deformThreshold) {
            const real oldRest = bm.restLength;
            real newRest = fs > 0 ? len - bm.deformThreshold / k : len + bm.deformThreshold / k;
            newRest = std::clamp(newRest, bm.minRest, bm.maxRest);
            const real delta = newRest - oldRest;
            bm.restLength = newRest;
            if (bm.hydroInput >= 0) bm.hydroOffset += delta;
            if (bm.hardening > 0) bm.deformThreshold += bm.hardening * k * std::abs(delta);
            ext = len - bm.restLength;
            fs = k * ext;
        }

        // --- breaking (spring force only, so damping spikes don't snap beams)
        if (std::abs(fs) > bm.strength) {
            pendingBreaks_.push_back(static_cast<std::uint32_t>(i));
            bm.lastForce = fs;
            continue;
        }

        const real f = fs + c * lenRate;  // + tension
        bm.lastForce = f;
        const Vec3 fv = dir * f;
        force[bm.a] += fv;
        force[bm.b] -= fv;
    }
    if (!pendingBreaks_.empty()) processPendingBreaks();
    if (!wheels_.empty() || powertrain_) stepDrivetrain(dt);
}

void SoftBody::translate(const Vec3& d) {
    for (auto& p : pos_) p += d;
}

void SoftBody::setVelocity(const Vec3& v) {
    for (std::size_t i = 0; i < vel_.size(); ++i) vel_[i] = invMass_[i] > 0 ? v : Vec3{};
}

void SoftBody::addVelocity(const Vec3& v) {
    for (std::size_t i = 0; i < vel_.size(); ++i)
        if (invMass_[i] > 0) vel_[i] += v;
}

void SoftBody::setNodeMass(std::uint32_t i, real mass) {
    if (i >= mass_.size() || !(mass > 0)) return;
    mass_[i] = mass;
    if (invMass_[i] != 0) invMass_[i] = 1.0 / mass;
    nodeParams_[i].mass = mass;
}

real SoftBody::totalMass() const {
    real m = 0;
    for (real x : mass_) m += x;
    return m;
}

Vec3 SoftBody::centerOfMass() const {
    Vec3 c;
    real m = 0;
    for (std::size_t i = 0; i < pos_.size(); ++i) {
        c += pos_[i] * mass_[i];
        m += mass_[i];
    }
    return m > 0 ? c / m : c;
}

Vec3 SoftBody::centerOfMassVelocity() const {
    Vec3 v;
    real m = 0;
    for (std::size_t i = 0; i < vel_.size(); ++i) {
        v += vel_[i] * mass_[i];
        m += mass_[i];
    }
    return m > 0 ? v / m : v;
}

VehicleTelemetry SoftBody::telemetry() const {
    VehicleTelemetry t;
    t.velocity = centerOfMassVelocity();
    t.speedKmh = length(t.velocity) * 3.6;
    if (powertrain_) {
        t.engineRpm = powertrain_->engineRpm();
        t.gear = powertrain_->gear();
        t.clutch = powertrain_->clutchEngagement();
    }
    t.throttle = controls_.throttle;
    t.brake = controls_.brake;
    t.steer = smoothedSteer_;
    for (const PressureWheel& w : wheels_) {
        t.wheelOmega.push_back(w.angularVelocity);
        t.wheelBurst.push_back(w.burst);
    }
    const BodyStats bs = stats();
    t.deformedBeams = bs.deformedBeams;
    t.brokenBeams = bs.brokenBeams;
    return t;
}

void SoftBody::aabb(Vec3& lo, Vec3& hi) const {
    lo = {kInf, kInf, kInf};
    hi = {-kInf, -kInf, -kInf};
    for (const auto& p : pos_) {
        lo = {std::min(lo.x, p.x), std::min(lo.y, p.y), std::min(lo.z, p.z)};
        hi = {std::max(hi.x, p.x), std::max(hi.y, p.y), std::max(hi.z, p.z)};
    }
}

real SoftBody::kineticEnergy() const {
    real e = 0;
    for (std::size_t i = 0; i < pos_.size(); ++i)
        if (invMass_[i] > 0) e += 0.5 * mass_[i] * lengthSq(vel_[i]);
    return e;
}

real SoftBody::elasticEnergy() const {
    real e = 0;
    for (const Beam& bm : beams_) {
        if (bm.broken) continue;
        const real ext = length(pos_[bm.b] - pos_[bm.a]) - bm.restLength;
        if (bm.type == BeamType::Support && ext > 0) continue;
        const real k = (bm.type == BeamType::Anisotropic && ext > 0) ? bm.springExp : bm.spring;
        e += 0.5 * k * ext * ext;
    }
    return e;
}

real SoftBody::potentialEnergy(const Vec3& gravity) const {
    real e = 0;
    for (std::size_t i = 0; i < pos_.size(); ++i)
        if (invMass_[i] > 0) e -= mass_[i] * dot(gravity, pos_[i]);
    return e;
}

BodyStats SoftBody::stats() const {
    BodyStats s;
    s.nodes = pos_.size();
    s.beams = beams_.size();
    s.triangles = triangles_.size();
    for (const Beam& bm : beams_) {
        if (bm.broken) ++s.brokenBeams;
        else if (std::abs(bm.restLength - bm.hydroOffset - bm.baseRestLength) > 1e-3 * bm.baseRestLength &&
                 bm.hydroInput < 0)
            ++s.deformedBeams;
    }
    for (const ColTri& tri : triangles_) {
        if (tri.broken) ++s.brokenTriangles;
    }
    s.totalMass = totalMass();
    s.kineticEnergy = kineticEnergy();
    s.elasticEnergy = elasticEnergy();
    return s;
}

real SoftBody::stabilityRatio(real dt) const {
    std::vector<real> sumK(pos_.size(), 0.0), sumC(pos_.size(), 0.0);
    for (const Beam& bm : beams_) {
        if (bm.broken) continue;
        const real k = std::max(bm.spring, bm.springExp);
        const real c = std::max(bm.damp, bm.dampExp);
        sumK[bm.a] += k; sumK[bm.b] += k;
        sumC[bm.a] += c; sumC[bm.b] += c;
    }
    real worst = 0;
    for (std::size_t i = 0; i < pos_.size(); ++i) {
        if (invMass_[i] == 0) continue;
        // Gershgorin bound for the largest eigenvalue of M^-1 K: ~ 2*sum(k)/m.
        const real omega = std::sqrt(2.0 * sumK[i] * invMass_[i]);
        const real springRatio = dt * omega / 2.0;
        const real dampRatio = dt * 2.0 * sumC[i] * invMass_[i] / 2.0;
        worst = std::max({worst, springRatio, dampRatio});
    }
    return worst;
}

}  // namespace sb
