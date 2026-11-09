#include <doctest/doctest.h>
#include "sbcore/sbcore.hpp"
#include <algorithm>
#include <stdexcept>
#include <string>
using namespace sb;
namespace {
SoftBody contactFixture(bool fixed = true, bool registered = true, real height = 0.2) {
    SoftBody body("panel fixture");
    NodeParams target; target.group = "shell"; target.fixed = fixed;
    body.addNode("a", {-2, 0, -2}, target);
    body.addNode("b", {-2, 0, 2}, target);
    body.addNode("c", {2, 0, 0}, target);
    ColTriParams tri; tri.dragCoef = 0;
    body.addTriangle(0, 1, 2, tri);
    NodeParams panel; panel.group = "panel";
    body.addNode("panel", {0, height, 0}, panel);
    BeamParams latch; latch.spring = latch.damp = 0; latch.breakGroup = "latch";
    body.addBeam(3, 0, latch);
    if (registered) body.addSelfCollisionPanel("panel", {"shell"}, {"latch"});
    return body;
}
World contactWorld(SoftBody body, real dt = 0.0005) {
    WorldSettings settings; settings.gravity = {}; settings.airDensity = 0; settings.dt = dt;
    World world(settings); world.addBody(std::move(body)); return world;
}
Vec3 momentum(const SoftBody& body) {
    Vec3 p;
    for (std::size_t n = 0; n < body.nodeCount(); ++n) p += body.velocities()[n] * body.masses()[n];
    return p;
}
}
TEST_CASE("panel self-contact is opt-in and dormant until mount failure, including after repair") {
    auto fixture = contactFixture(true, true, 0.004);
    const auto rest = fixture.positions();
    auto world = contactWorld(std::move(fixture));
    world.step();
    CHECK(world.stats().selfContactCandidates == 0);
    CHECK(world.body(0).positions()[3].y == doctest::Approx(0.004));
    world.body(0).breakBeam(0); world.step();
    CHECK(world.stats().selfContacts == 1);
    CHECK(world.body(0).positions()[3].y == doctest::Approx(0.008));
    world.body(0).repair(rest); world.step();
    CHECK(world.stats().selfContactCandidates == 0);
    CHECK(world.body(0).positions()[3].y == doctest::Approx(0.004));
    auto unregistered = contactWorld(contactFixture(true, false));
    unregistered.body(0).breakBeam(0);
    unregistered.body(0).velocities()[3] = {0, -1000, 0};
    unregistered.step();
    CHECK(unregistered.body(0).positions()[3].y < 0);
    CHECK(unregistered.stats().selfContacts == 0);
}
TEST_CASE("released panel self-contact cannot tunnel through a thin own-body surface") {
    auto world = contactWorld(contactFixture());
    world.body(0).breakBeam(0);
    world.body(0).velocities()[3] = {0, -1000, 0}; // 0.5 m per step, larger than collision thickness.
    world.step();
    CHECK(world.stats().selfContacts == 1);
    CHECK(world.body(0).positions()[3].y == doctest::Approx(0.008));
    CHECK(world.body(0).velocities()[3].y == doctest::Approx(0.0));
    CHECK(world.stats().finite);
}
TEST_CASE("panel self-contact exchanges momentum without injecting kinetic energy") {
    auto world = contactWorld(contactFixture(false), 0.01);
    auto& body = world.body(0); body.breakBeam(0); body.velocities()[3] = {2, -40, 0};
    const auto before = momentum(body); const real energy = body.kineticEnergy();
    world.step();
    CHECK(world.stats().selfContacts == 1);
    CHECK(length(momentum(body) - before) < 1e-8);
    CHECK(body.kineticEnergy() < energy);
    const auto& p = body.positions();
    const Vec3 normal = normalize(cross(p[1] - p[0], p[2] - p[0]));
    CHECK(dot(p[3] - p[0], normal) > 0.007);
}
TEST_CASE("panel self-contact excludes live hinge neighbourhood on both thin skins") {
    auto fixture = contactFixture(true, false, 0.004);
    fixture.positions()[0] = {-0.02, 0, -0.02};
    fixture.positions()[1] = {-0.02, 0, 1}; fixture.positions()[2] = {1, 0, -0.02};
    NodeParams node; node.group = "panel";
    fixture.addNode("upper_skin", {0, 0.006, 0}, node);
    BeamParams hinge; hinge.spring = hinge.damp = 0; hinge.breakGroup = "hinge";
    const auto hingeIndex = fixture.addBeam(3, 0, hinge);
    fixture.addSelfCollisionPanel("panel", {"shell"}, {"latch", "hinge"});
    auto world = contactWorld(std::move(fixture));
    world.body(0).breakBeam(0); world.step();
    CHECK(world.stats().selfContacts == 0);
    CHECK(world.body(0).positions()[3].y == doctest::Approx(0.004));
    CHECK(world.body(0).positions()[4].y == doctest::Approx(0.006));
    world.body(0).breakBeam(hingeIndex); world.step();
    CHECK(world.stats().selfContacts == 2);
    CHECK(world.body(0).positions()[3].y == doctest::Approx(0.008));
    CHECK(world.body(0).positions()[4].y == doctest::Approx(0.008));
}
TEST_CASE("panel self-contact ignores broken targets and bounds candidate work independently of total nodes") {
    auto fixture = contactFixture(); NodeParams irrelevant; irrelevant.group = "unrelated";
    for (int i = 0; i < 1000; ++i) fixture.addNode("extra" + std::to_string(i), {0, 0.005, 0}, irrelevant);
    auto world = contactWorld(std::move(fixture)); auto& body = world.body(0);
    body.breakBeam(0); body.velocities()[3] = {0, -1000, 0}; world.step();
    CHECK(world.stats().selfContactCandidates == 1);
    CHECK(world.stats().selfContacts == 1);
    body.triangles()[0].broken = true; body.velocities()[3] = {0, -1000, 0}; world.step();
    CHECK(world.stats().selfContactCandidates == 0);
    CHECK(body.positions()[3].y < 0);
}
TEST_CASE("panel self-contact registration rejects ambiguous or missing topology") {
    auto body = contactFixture(true, false);
    CHECK_THROWS_AS(body.addSelfCollisionPanel("missing", {"shell"}, {}), std::invalid_argument);
    CHECK_THROWS_AS(body.addSelfCollisionPanel("panel", {"panel"}, {}), std::invalid_argument);
    CHECK_THROWS_AS(body.addSelfCollisionPanel("panel", {"shell"}, {"missing"}), std::invalid_argument);
    CHECK_THROWS_AS(body.addSelfCollisionPanel("shell", {"panel"}, {}), std::invalid_argument);
}

TEST_CASE("panel face self-contact catches a narrow engine between the corner nodes") {
    SoftBody body;
    NodeParams engine; engine.group = "engine"; engine.fixed = true;
    body.addNode("ea", {-0.3, 0, -0.3}, engine);
    body.addNode("eb", {-0.3, 0, 0.3}, engine);
    body.addNode("ec", {0.3, 0, 0}, engine);
    ColTriParams surface; surface.dragCoef = 0;
    body.addTriangle(0, 1, 2, surface);
    NodeParams panel; panel.group = "bonnet";
    body.addNode("pa", {-1, 0.1, -1}, panel);
    body.addNode("pb", {-1, 0.1, 1}, panel);
    body.addNode("pc", {2, 0.1, 0}, panel);
    body.addTriangle(3, 4, 5, surface);
    body.addSelfCollisionPanel("bonnet", {"engine"}, {});
    auto world = contactWorld(std::move(body));
    for (std::size_t n = 3; n < 6; ++n) world.body(0).velocities()[n] = {0, -400, 0};
    world.step();
    CHECK(world.stats().selfContacts == 1);
    const auto& p = world.body(0).positions();
    CHECK((p[3].y + p[4].y + p[5].y) / 3 == doctest::Approx(0.008));
    CHECK(world.body(0).kineticEnergy() < 1e-10);
    // A torn panel face must not retain a ghost contact patch spanning its pieces.
    world.body(0).triangles()[1].broken = true;
    for (std::size_t n = 3; n < 6; ++n) world.body(0).velocities()[n] = {0, -400, 0};
    world.step();
    CHECK(world.stats().selfContacts == 0);
    CHECK((p[3].y + p[4].y + p[5].y) / 3 < 0);
}

TEST_CASE("released Kestrel bonnet lands on its own roof with bounded contact work and repairs cleanly") {
    auto build = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
    const auto bonnet = build.layout.bonnetNodes;
    const auto rest = build.body.positions();
    REQUIRE(bonnet.size() == 8);
    REQUIRE_FALSE(build.body.selfCollisionPanels().empty());
    World world;
    world.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}, 1));
    world.addBody(std::move(build.body));
    auto& car = world.body(0);
    car.controls().brake = car.controls().handbrake = 1;
    world.simulate(0.7);
    CHECK(world.stats().selfContactCandidates == 0);
    for (std::size_t i = 0; i < car.beamCount(); ++i) {
        const auto group = car.beams()[i].breakGroup;
        if (group >= 0 && (car.breakGroupNames()[group] == "bonnet_latch" || car.breakGroupNames()[group] == "bonnet_hinge"))
            car.breakBeam(static_cast<std::uint32_t>(i));
    }
    for (auto n : bonnet) { car.positions()[n] += Vec3{-1.65, 1.6, 0}; car.velocities()[n] = {}; }
    std::size_t totalContacts = 0, maxCandidates = 0, candidateBudget = 0;
    for (const auto& panel : car.selfCollisionPanels()) candidateBudget += panel.points.size() * panel.triangles.size();
    for (int step = 0; step < 2000; ++step) {
        world.step();
        totalContacts += world.stats().selfContacts;
        maxCandidates = std::max(maxCandidates, world.stats().selfContactCandidates);
    }
    CHECK(world.stats().finite);
    CHECK(totalContacts > 0);
    CHECK(maxCandidates <= candidateBudget);
    real panelHeight = 0;
    for (auto n : bonnet) panelHeight += car.positions()[n].y / static_cast<real>(bonnet.size());
    INFO("bonnet mean height after roof drop: " << panelHeight << "; contacts " << totalContacts);
    CHECK(panelHeight > 1.05);
    car.repair(rest);
    world.step();
    CHECK(world.stats().selfContactCandidates == 0);
    CHECK(world.stats().brokenBeams == 0);
}

TEST_CASE("released Kestrel bonnet face contacts its own engine when its corners straddle the block") {
    auto build = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
    const auto bonnet = build.layout.bonnetNodes;
    World world;
    world.settings().airDensity = 0;
    world.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}, 1));
    world.addBody(std::move(build.body));
    auto& car = world.body(0);
    car.controls().brake = car.controls().handbrake = 1;
    world.simulate(0.5);
    // Isolate the engine collision target from the roof/fenders; retain actual
    // physical engine nodes, mounts and the bonnet's own face sample topology.
    for (auto& tri : car.triangles()) {
        const auto& group = car.groupNames()[car.nodeGroups()[tri.a]];
        if (group != "engine" && group != "bonnet") tri.broken = true;
    }
    for (std::size_t i = 0; i < car.beamCount(); ++i) {
        const auto group = car.beams()[i].breakGroup;
        if (group >= 0 && (car.breakGroupNames()[group] == "bonnet_latch" || car.breakGroupNames()[group] == "bonnet_hinge"))
            car.breakBeam(static_cast<std::uint32_t>(i));
    }
    for (auto n : bonnet) { car.positions()[n] += Vec3{-0.5, 0.5, 0}; car.velocities()[n] = {}; }
    std::size_t totalContacts = 0;
    for (int step = 0; step < 1200; ++step) { world.step(); totalContacts += world.stats().selfContacts; }
    CHECK(world.stats().finite);
    CHECK(totalContacts > 0);
}
