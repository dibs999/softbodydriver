#include <doctest/doctest.h>
#include <algorithm>
#include <cmath>
#include <string>
#include "sbcore/sbcore.hpp"

using namespace sb;
namespace {
CarBuild referenceCar() {
    return buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
}
bool contains(const std::vector<std::uint32_t>& nodes, std::uint32_t n) {
    return std::find(nodes.begin(), nodes.end(), n) != nodes.end();
}
int attached(const SoftBody& body, const std::vector<std::uint32_t>& nodes) {
    int count = 0;
    for (const auto& beam : body.beams())
        if (!beam.broken && (contains(nodes, beam.a) != contains(nodes, beam.b))) ++count;
    return count;
}
bool connected(const SoftBody& body, const std::vector<std::uint32_t>& nodes) {
    std::vector<std::uint32_t> reached{nodes.front()};
    bool changed = true;
    while (changed) {
        changed = false;
        for (const auto& beam : body.beams()) {
            if (beam.broken || !contains(nodes, beam.a) || !contains(nodes, beam.b)) continue;
            if (contains(reached, beam.a) && !contains(reached, beam.b)) { reached.push_back(beam.b); changed = true; }
            if (contains(reached, beam.b) && !contains(reached, beam.a)) { reached.push_back(beam.a); changed = true; }
        }
    }
    return reached.size() == nodes.size();
}
}

TEST_CASE("reference bumpers have independent mass-budgeted cages and sacrificial attachments") {
    auto car = referenceCar();
    REQUIRE(car.layout.frontBumperNodes.size() == 8);
    REQUIRE(car.layout.rearBumperNodes.size() == 8);
    CHECK(car.body.totalMass() == doctest::Approx(car.def.chassis.curbMass).epsilon(1e-6));
    const real rearAxle = car.def.body.length - car.def.body.frontOverhang - car.def.body.wheelbase;
    CHECK((car.body.centerOfMass().x - rearAxle) / car.def.body.wheelbase == doctest::Approx(car.def.chassis.frontWeight).epsilon(0.005));
    REQUIRE(car.body.selfCollisionPanels().size() == 7);   // bonnet, two bumpers, four doors
    for (const auto& panel : car.body.selfCollisionPanels()) {
        CHECK_FALSE(car.body.selfCollisionActive(panel));
        CHECK_FALSE(panel.triangles.empty());
    }
    for (int end = 0; end < 2; ++end) {
        const auto& nodes = end == 0 ? car.layout.frontBumperNodes : car.layout.rearBumperNodes;
        const std::string group = end == 0 ? "bumper_front_mounts" : "bumper_rear_mounts";
        real mass = 0;
        for (auto n : nodes) mass += car.body.masses()[n];
        CHECK(mass == doctest::Approx(end == 0 ? 12.0 : 10.0));
        CHECK(attached(car.body, nodes) == 12);
        int internal = 0;
        for (const auto& beam : car.body.beams()) {
            const bool a = contains(nodes, beam.a), b = contains(nodes, beam.b);
            if (a && b) ++internal;
            if (a != b) {
                REQUIRE(beam.breakGroup >= 0);
                CHECK(car.body.breakGroupNames()[static_cast<std::size_t>(beam.breakGroup)].rfind(group + "_", 0) == 0);
            }
        }
        CHECK(internal == 28);
    }
    auto disabled = car.def;
    disabled.body.detachableBumpers = false;
    auto legacy = buildCar(disabled);
    CHECK(legacy.layout.frontBumperNodes.empty());
    CHECK(legacy.layout.rearBumperNodes.empty());
    CHECK(legacy.body.totalMass() == doctest::Approx(car.body.totalMass()).epsilon(1e-6));
    for (const auto& mesh : legacy.visual.skinned) CHECK(mesh.material.rfind("bumper_", 0) != 0);
}

TEST_CASE("bumper flexbody vertices rotate with only their own detached cage") {
    auto car = referenceCar();
    const auto original = car.body.positions();
    const real angle = 1.1;
    auto rotate = [&](const Vec3& p) {
        return Vec3{std::cos(angle) * p.x - std::sin(angle) * p.y,
                    std::sin(angle) * p.x + std::cos(angle) * p.y, p.z};
    };
    const Vec3 translation{3, 4, -2};
    for (int end = 0; end < 2; ++end) {
        auto positions = original;
        const auto& nodes = end == 0 ? car.layout.frontBumperNodes : car.layout.rearBumperNodes;
        const std::string prefix = end == 0 ? "bumper_front_" : "bumper_rear_";
        for (auto n : nodes) positions[n] = rotate(original[n]) + translation;
        std::vector<float> frames;
        computeNodeFrames(positions, car.visual, frames);
        std::size_t checked = 0;
        for (const auto& mesh : car.visual.skinned) {
            if (mesh.material.rfind(prefix, 0) != 0) continue;
            for (std::size_t i = 0; i < mesh.skin.size(); ++i) {
                const auto& skin = mesh.skin[i];
                REQUIRE(skin.weight[0] < 0);
                for (int j = 0; j < 3; ++j) REQUIRE(contains(nodes, skin.node[j]));
                const Vec3 rest{mesh.positions[i * 3], mesh.positions[i * 3 + 1], mesh.positions[i * 3 + 2]};
                CHECK(length(evalSkin(positions, frames, skin) - rotate(rest) - translation) < 2e-5);
                ++checked;
            }
        }
        CHECK(checked > 100);
    }
}

TEST_CASE("front and rear impact release bumper mounts and repair restores the complete assembly") {
    for (int end = 0; end < 2; ++end) {
        CAPTURE(end);
        auto car = referenceCar();
        const auto rest = car.body.positions();
        const auto nodes = end == 0 ? car.layout.frontBumperNodes : car.layout.rearBumperNodes;
        const real direction = end == 0 ? 1.0 : -1.0;
        WorldSettings settings;
        settings.gravity = {};
        settings.airDensity = 0;
        World world(settings);
        for (auto& v : car.body.velocities()) v = {direction * 18.0, 0, 0};
        world.addBody(std::move(car.body));
        world.addCollider(StaticCollider::plane({end == 0 ? car.def.body.length + 0.25 : -0.25, 0, 0}, {-direction, 0, 0}, 0.0));
        const auto farNodes = end == 0 ? car.layout.rearBumperNodes : car.layout.frontBumperNodes;
        world.simulate(0.12);
        REQUIRE(world.stats().finite);
        // The struck bumper tears loose clip by clip (at least half its clips at 65 km/h); the
        // bumper at the other end stays on despite the deceleration spike.
        MESSAGE("clip beams still attached at the struck end: " << attached(world.body(0), nodes));
        CHECK(attached(world.body(0), nodes) <= 6);
        CHECK(attached(world.body(0), farNodes) == 12);
        CHECK(connected(world.body(0), nodes)); // A released bumper remains a physical part, not eight loose particles.
        world.body(0).repair(rest);
        CHECK(attached(world.body(0), nodes) == 12);
        for (auto n : nodes) CHECK(length(world.body(0).positions()[n] - rest[n]) < 1e-10);
        for (const auto& panel : world.body(0).selfCollisionPanels()) CHECK_FALSE(world.body(0).selfCollisionActive(panel));
    }
}

TEST_CASE("bonnet inspection supports lift and hold a useful angle without breaking hinges") {
    auto car = referenceCar();
    const auto bonnet = car.layout.bonnetNodes;
    REQUIRE(car.layout.bonnetStrutBeams.size() == 2);
    for (auto index : car.layout.bonnetStrutBeams) {
        const auto& beam = car.body.beams()[index];
        CHECK(beam.type == BeamType::Hydro);
        CHECK(beam.hydroInput == 1);
        CHECK(beam.hydroRatio > 0.0);
    }
    World world;
    world.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}));
    world.addBody(car.body);
    world.simulate(0.6);
    auto& body = world.body(0);
    for (std::size_t i = 0; i < body.beamCount(); ++i) {
        const auto& beam = body.beams()[i];
        if (beam.breakGroup >= 0 && body.breakGroupNames()[static_cast<std::size_t>(beam.breakGroup)] == "bonnet_latch")
            body.breakBeam(static_cast<std::uint32_t>(i));
    }
    for (int tick = 1; tick <= 100; ++tick) {
        body.setInput(1, static_cast<real>(tick) / 100.0);
        world.simulate(0.01);
    }
    world.simulate(2.5);
    auto opening = [&]() {
        std::vector<float> frames;
        computeNodeFrames(body.positions(), car.visual, frames);
        const Vec3 rest = normalize(car.restPositions[bonnet[2]] - car.restPositions[bonnet[0]]);
        const Vec3 rigid{frames[0] * rest.x + frames[1] * rest.y + frames[2] * rest.z,
                         frames[3] * rest.x + frames[4] * rest.y + frames[5] * rest.z,
                         frames[6] * rest.x + frames[7] * rest.y + frames[8] * rest.z};
        const Vec3 actual = normalize(body.positions()[bonnet[2]] - body.positions()[bonnet[0]]);
        return std::acos(std::clamp(dot(rigid, actual), -1.0, 1.0)) * 180.0 / 3.141592653589793;
    };
    const real angle = opening();
    CAPTURE(angle);
    CHECK(world.stats().finite);
    CHECK(angle > 55.0);
    CHECK(angle < 72.0);
    CHECK(attached(body, bonnet) == 8);
    world.simulate(0.6);
    CHECK(std::abs(opening() - angle) < 3.0);
    for (auto index : car.layout.bonnetStrutBeams) CHECK_FALSE(body.beams()[index].broken);
    body.repair(car.restPositions);
    CHECK(body.input(1) == doctest::Approx(0.0));
    CHECK(attached(body, bonnet) == 14);
    CHECK(opening() < 0.01);
    world.simulate(0.1);
    CHECK(opening() < 2.0);
    CHECK(attached(body, bonnet) == 14);
}
