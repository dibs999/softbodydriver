#include "sbcore/recorder.hpp"

#include <cmath>
#include <fstream>
#include <stdexcept>

#include <nlohmann/json.hpp>

namespace sb {

using json = nlohmann::json;

namespace {
json vec(const Vec3& v) { return json::array({v.x, v.y, v.z}); }
}  // namespace

Recorder::Recorder(const World& world, std::string sceneName, std::string description, real fps)
    : scene_(std::move(sceneName)), description_(std::move(description)), fps_(fps), dt_(world.settings().dt) {
    json colliders = json::array();
    for (const StaticCollider& c : world.colliders()) {
        json o;
        o["name"] = c.name;
        if (c.kind == StaticCollider::Kind::Plane) {
            o["kind"] = "plane";
            o["point"] = vec(c.point);
            o["normal"] = vec(c.normal);
        } else if (c.kind == StaticCollider::Kind::Box) {
            o["kind"] = "box";
            o["center"] = vec(c.center);
            o["half"] = vec(c.halfExtents);
            json r = json::array();
            for (int i = 0; i < 3; ++i)
                for (int j = 0; j < 3; ++j) r.push_back(c.rotation.m[i][j]);
            o["rot"] = r;
        } else if (c.kind == StaticCollider::Kind::Heightfield) {
            o["kind"] = "heightfield";
            o["origin"] = json::array({c.originX, 0.0, c.originZ});
            o["cellSizeX"] = c.cellSizeX;
            o["cellSizeZ"] = c.cellSizeZ;
            o["nx"] = c.nx;
            o["nz"] = c.nz;
            json h = json::array();
            for (real hv : c.heights) {
                if (std::isnan(hv)) h.push_back(nullptr);   // a hole
                else h.push_back(std::round(hv * 1000.0) / 1000.0);
            }
            o["heights"] = std::move(h);
            if (c.yaw != 0 || c.pivotX != 0 || c.pivotZ != 0 || std::isfinite(c.thickness)) {
                o["pivot"] = json::array({c.pivotX, 0.0, c.pivotZ});
                o["yaw"] = c.yaw;
                if (std::isfinite(c.thickness)) o["thickness"] = c.thickness;
            }
        }
        colliders.push_back(o);
    }
    json bodies = json::array();
    for (const SoftBody& b : world.bodies()) {
        json o;
        o["name"] = b.name();
        o["nodes"] = b.nodeCount();
        json beams = json::array();
        for (const Beam& bm : b.beams()) {
            beams.push_back(bm.a);
            beams.push_back(bm.b);
        }
        o["beams"] = beams;
        if (b.triangleCount() > 0) {
            json tris = json::array();
            for (const ColTri& t : b.triangles()) {
                tris.push_back(t.a);
                tris.push_back(t.b);
                tris.push_back(t.c);
            }
            o["triangles"] = std::move(tris);
        }
        json fixed = json::array();
        for (std::uint32_t i = 0; i < b.nodeCount(); ++i)
            if (b.isFixed(i)) fixed.push_back(i);
        o["fixed"] = fixed;
        if (!b.wheels().empty()) {
            json wb = json::array();
            for (const PressureWheel& w : b.wheels())
                for (std::uint32_t bi : w.beamIndices) wb.push_back(bi);
            o["wheelBeams"] = std::move(wb);
        }
        bodies.push_back(o);
        std::vector<char> br(b.beamCount(), 0);
        for (std::size_t i = 0; i < b.beamCount(); ++i) br[i] = b.beams()[i].broken ? 1 : 0;
        broken_.push_back(std::move(br));
        std::vector<char> brT(b.triangleCount(), 0);
        for (std::size_t i = 0; i < b.triangleCount(); ++i) brT[i] = b.triangles()[i].broken ? 1 : 0;
        brokenTris_.push_back(std::move(brT));
    }
    json s;
    s["colliders"] = colliders;
    s["bodies"] = bodies;
    staticJson_ = s.dump();
}

void Recorder::captureIfDue(const World& world) {
    if (world.time() + 0.5 * dt_ >= nextFrameTime_) capture(world);
}

void Recorder::capture(const World& world) {
    Frame f;
    f.time = world.time();
    if (!world.bodies().empty() &&
        (!world.bodies()[0].wheels().empty() || world.bodies()[0].hasPowertrain())) {
        const VehicleTelemetry t = world.bodies()[0].telemetry();
        f.hasTelemetry = true;
        f.rpm = static_cast<int>(std::lround(t.engineRpm));
        f.gear = t.gear;
        f.throttle = std::round(t.throttle * 100.0) / 100.0;
        f.brake = std::round(t.brake * 100.0) / 100.0;
        f.steer = std::round(t.steer * 100.0) / 100.0;
        f.speedKmh = std::round(t.speedKmh * 10.0) / 100.0 * 10.0;
    }
    for (std::size_t bi = 0; bi < world.bodies().size(); ++bi) {
        const SoftBody& b = world.bodies()[bi];
        std::vector<std::int32_t> p;
        p.reserve(b.nodeCount() * 3);
        for (const Vec3& v : b.positions()) {
            p.push_back(static_cast<std::int32_t>(std::lround(v.x * 1000.0)));
            p.push_back(static_cast<std::int32_t>(std::lround(v.y * 1000.0)));
            p.push_back(static_cast<std::int32_t>(std::lround(v.z * 1000.0)));
        }
        f.positionsMm.push_back(std::move(p));

        std::vector<std::uint32_t> nb;
        auto& state = broken_[bi];
        for (std::size_t i = 0; i < b.beamCount(); ++i) {
            if (b.beams()[i].broken && !state[i]) {
                state[i] = 1;
                nb.push_back(static_cast<std::uint32_t>(i));
            }
        }
        f.newlyBroken.push_back(std::move(nb));

        std::vector<std::uint32_t> nbt;
        auto& triState = brokenTris_[bi];
        for (std::size_t i = 0; i < b.triangleCount(); ++i) {
            if (b.triangles()[i].broken && !triState[i]) {
                triState[i] = 1;
                nbt.push_back(static_cast<std::uint32_t>(i));
            }
        }
        f.newlyBrokenTris.push_back(std::move(nbt));
    }
    frames_.push_back(std::move(f));
    nextFrameTime_ = world.time() + 1.0 / fps_;
}

std::string Recorder::toJson() const {
    json doc = json::parse(staticJson_);
    doc["version"] = 1;
    doc["scene"] = scene_;
    doc["description"] = description_;
    doc["fps"] = fps_;
    doc["dt"] = dt_;
    json frames = json::array();
    for (const Frame& f : frames_) {
        json o;
        o["t"] = std::round(f.time * 10000.0) / 10000.0;
        o["p"] = f.positionsMm;
        bool anyBroken = false;
        for (const auto& v : f.newlyBroken) anyBroken |= !v.empty();
        if (anyBroken) o["b"] = f.newlyBroken;
        bool anyBrokenTris = false;
        for (const auto& v : f.newlyBrokenTris) anyBrokenTris |= !v.empty();
        if (anyBrokenTris) o["bt"] = f.newlyBrokenTris;
        if (f.hasTelemetry) {
            o["tel"] = json::array({f.speedKmh, f.rpm, f.gear, f.throttle, f.brake, f.steer});
        }
        frames.push_back(std::move(o));
    }
    doc["frames"] = std::move(frames);
    return doc.dump();
}

void Recorder::save(const std::string& path) const {
    std::ofstream f(path, std::ios::binary);
    if (!f) throw std::runtime_error("recorder: cannot write " + path);
    f << toJson();
}

}  // namespace sb
