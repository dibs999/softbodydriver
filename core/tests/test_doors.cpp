#include <doctest/doctest.h>
#include "sbcore/sbcore.hpp"
#include <algorithm>
#include <cmath>
#include <string>

using namespace sb;
namespace {
CarBuild doorCar() { return buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json")); }
// Door index as in SoftBody::doors(): 0/1 front left/right, 2/3 rear left/right.
real opening(const CarBuild& car, const SoftBody& body, std::size_t index) {
    std::vector<float> frames;
    computeNodeFrames(body.positions(), car.visual, frames);
    const auto& nodes = (index < 2 ? car.layout.frontDoors : car.layout.rearDoors)[index % 2].nodes;
    const Vec3 rest = normalize(car.restPositions[nodes[0]] - car.restPositions[nodes[4]]);
    const Vec3 rigid{frames[0]*rest.x + frames[1]*rest.y + frames[2]*rest.z,
                     frames[3]*rest.x + frames[4]*rest.y + frames[5]*rest.z,
                     frames[6]*rest.x + frames[7]*rest.y + frames[8]*rest.z};
    return std::acos(std::clamp(dot(rigid, normalize(body.positions()[nodes[0]] - body.positions()[nodes[4]])), -1.0, 1.0)) * 180.0 / 3.141592653589793;
}
}

TEST_CASE("front and rear doors preserve mass budget and disengage without structural damage") {
    auto car = doorCar();
    REQUIRE(car.body.doors().size() == 4);
    CHECK(car.body.totalMass() == doctest::Approx(car.def.chassis.curbMass).epsilon(1e-6));
    const real rearAxle = car.def.body.length - car.def.body.frontOverhang - car.def.body.wheelbase;
    CHECK((car.body.centerOfMass().x - rearAxle) / car.def.body.wheelbase == doctest::Approx(car.def.chassis.frontWeight).epsilon(0.005));
    for (std::size_t side = 0; side < 4; ++side) {
        const auto& door = car.body.doors()[side];
        real mass = 0;
        for (auto node : door.nodes) mass += car.body.masses()[node];
        CHECK(mass == doctest::Approx(30.0));
        REQUIRE(car.body.setDoorOpen(side, true));
        CHECK_FALSE(car.body.setDoorOpen(side, true));
        CHECK_FALSE(car.body.doors()[side].latched);
        for (auto index : door.latchBeams) {
            CHECK(car.body.beams()[index].disabled);
            CHECK_FALSE(car.body.beams()[index].broken);
        }
        // A door opened by hand swings on intact hinges: no contact with its own body (its
        // corner caught on the roof edge with imported hinge lines). A torn hinge enables it.
        CHECK_FALSE(car.body.selfCollisionActive(car.body.selfCollisionPanels()[3 + side]));
    }
    CHECK(car.body.stats().brokenBeams == 0);
    car.body.repair(car.restPositions);
    for (const auto& door : car.body.doors()) {
        CHECK(door.latched);
        CHECK_FALSE(door.requestedOpen);
        CHECK(car.body.input(door.inputChannel) == 0);
        for (auto index : door.latchBeams) CHECK_FALSE(car.body.beams()[index].disabled);
    }
    car.body.setVelocity({1, 0, 0});
    CHECK_FALSE(car.body.setDoorOpen(0, true));
    auto legacy = car.def; legacy.body.detachableDoors = false;
    CHECK(buildCar(legacy).body.doors().empty());
    // Imported models with rear door parts get all four doors, hinged on the model's own door
    // lines; without those parts the rear doors stay rigid body structure.
    const auto sedan = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/meridian_sedan.car.json"));
    CHECK(sedan.body.doors().size() == 4);
    CHECK(sedan.restPositions[sedan.layout.frontDoors[0].hingeNodes[0]].x == doctest::Approx(3.355).epsilon(1e-6));
    CHECK(sedan.restPositions[sedan.layout.rearDoors[0].hingeNodes[0]].x == doctest::Approx(2.255).epsilon(1e-6));
    CHECK(sedan.layout.rearDoors[0].rearX == doctest::Approx(1.275));
    CHECK(sedan.layout.frontDoors[0].rearX == doctest::Approx(2.277));
    const std::string json = R"({"id": "x", "visualModel": {"path": "m.glb", "parts": {"door_left": ["door_FL"]}},
        "body": {"doors": 4, "detachableDoors": true}})";
    CHECK(buildCar(parseCarDefinition(json)).body.doors().size() == 2);
}

TEST_CASE("front and rear doors physically open hold and close with reversible intact latches") {
    auto car = doorCar();
    World world;
    world.addCollider(StaticCollider::plane({0,0,0}, {0,1,0}));
    world.addBody(car.body);
    world.simulate(0.6);
    auto& body = world.body(0);
    for (std::size_t side = 0; side < 4; ++side) REQUIRE(body.setDoorOpen(side, true));
    world.simulate(4.0);
    for (std::size_t side = 0; side < 4; ++side) {
        const real angle = opening(car, body, side);
        CAPTURE(side); CAPTURE(angle);
        CHECK(angle > 58);
        CHECK(angle < 78);
        CHECK_FALSE(body.doors()[side].latched);
        REQUIRE(body.setDoorOpen(side, false));
    }
    CHECK(world.stats().finite);
    CHECK(body.stats().brokenBeams == 0);
    world.simulate(5.0);
    for (std::size_t side = 0; side < 4; ++side) {
        const real angle = opening(car, body, side);
        CAPTURE(side); CAPTURE(angle);
        CHECK(angle < 3);
        CHECK(body.doors()[side].latched);
        for (auto index : body.doors()[side].latchBeams) CHECK_FALSE(body.beams()[index].disabled);
    }
    CHECK(body.stats().brokenBeams == 0);
    CHECK(body.stats().deformedBeams == 0);
}

TEST_CASE("door latch capture rejects moving or misaligned striker geometry") {
    auto car = doorCar();
    auto& body = car.body;
    REQUIRE(body.setDoorOpen(0, true));
    REQUIRE(body.setDoorOpen(0, false));
    const auto& door = body.doors()[0];
    for (auto node : door.nodes) body.velocities()[node] = {0, 0, 0.5};
    body.accumulateBeamForces(0.0005);
    CHECK_FALSE(body.doors()[0].latched);
    for (auto node : door.nodes) body.velocities()[node] = {};
    // Beyond the catch's reach (20 cm) a misaligned striker is not taken.
    const auto& striker = body.beams()[door.latchBeams.front()];
    body.positions()[striker.a] += normalize(body.positions()[striker.a] - body.positions()[striker.b]) * 0.25;
    body.accumulateBeamForces(0.0005);
    CHECK_FALSE(body.doors()[0].latched);
    CHECK(body.stats().brokenBeams == 0);
    for (auto beam : door.latchBeams) CHECK(body.beams()[beam].disabled);
    body.repair(car.restPositions);
    CHECK(body.doors()[0].latched);
}

TEST_CASE("crash detached doors cannot be relatched or healed by manual commands") {
    for (std::size_t side = 0; side < 2; ++side) {
        auto car = doorCar();
        World world;
        world.addCollider(StaticCollider::plane({0,0,0}, {0,1,0}));
        world.addBody(car.body);
        auto& body = world.body(0);
        world.simulate(0.6);
        REQUIRE(body.setDoorOpen(side, true));
        world.simulate(3.5);
        const real sign = side ? 1.0 : -1.0;
        world.addCollider(StaticCollider::plane({0,0,sign*2.0}, {0,0,-sign}));
        body.setVelocity({0,0,sign*18.0});
        world.simulate(0.5);
        CHECK(world.stats().finite);
        const auto& door = body.doors()[side];
        for (auto beam : door.hingeBeams) CHECK(body.beams()[beam].broken);
        for (auto beam : door.supportBeams) CHECK(body.beams()[beam].broken);
        const auto broken = body.stats().brokenBeams;
        CHECK_FALSE(body.setDoorOpen(side, false));
        CHECK(body.stats().brokenBeams == broken);
        body.repair(car.restPositions);
        CHECK(body.stats().brokenBeams == 0);
        CHECK(body.doors()[side].latched);
        CHECK(body.doors()[side].travel == 0);
    }
}

TEST_CASE("a side impact leaves the far door shut and the struck door on its hinges") {
    auto car = doorCar();
    World world;
    world.addCollider(StaticCollider::plane({0,0,0}, {0,1,0}));
    world.addBody(car.body);
    auto& body = world.body(0);
    world.simulate(0.6);
    // 30 km/h sideways into a wall on the left (-z) side.
    world.addCollider(StaticCollider::plane({0,0,-1.6}, {0,0,1}));
    body.setVelocity({0,0,-8.3});
    world.simulate(0.8);
    REQUIRE(world.stats().finite);
    const auto& struck = body.doors()[0];
    const auto& far = body.doors()[1];
    int struckIntact = 0;
    for (auto beam : struck.hingeBeams) struckIntact += body.beams()[beam].broken ? 0 : 1;
    CHECK(struckIntact >= static_cast<int>(struck.hingeBeams.size() / 2));
    for (auto beam : far.hingeBeams) CHECK_FALSE(body.beams()[beam].broken);
    for (auto beam : far.latchBeams) CHECK_FALSE(body.beams()[beam].broken);
    CHECK(far.latched);
}


TEST_CASE("doors of the imported four-door bodies close and latch again, brakes held or not") {
    // With the imported hinge lines the Meridian doors stopped 2-60 degrees short (the check
    // strap sat on the hinge axis, a rear door's corner caught on the roof edge) and the
    // Trailhead rear doors were caught 10 degrees out (all strikers outboard in one plane).
    for (const char* name : {"meridian_sedan", "meridian_wagon", "trailhead_4x4"}) {
        for (const bool braked : {false, true}) {
            CAPTURE(name); CAPTURE(braked);
            auto car = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/" + name + ".car.json"));
            World world;
            world.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}));
            world.addBody(car.body);
            auto& body = world.body(0);
            VehicleControls c;
            c.gear = 0;
            c.brake = braked ? 1.0 : 0.0;
            c.handbrake = braked ? 1.0 : 0.0;
            body.setControls(c);
            world.simulate(0.6);
            REQUIRE(body.doors().size() == 4);
            for (std::size_t side = 0; side < 4; ++side) REQUIRE(body.setDoorOpen(side, true));
            world.simulate(4.0);
            for (std::size_t side = 0; side < 4; ++side) {
                CAPTURE(side);
                CHECK(opening(car, body, side) > 35.0);
                REQUIRE(body.setDoorOpen(side, false));
            }
            world.simulate(6.0);
            for (std::size_t side = 0; side < 4; ++side) {
                CAPTURE(side);
                CHECK(body.doors()[side].latched);
                CHECK(opening(car, body, side) < 3.0);
            }
            CHECK(body.stats().brokenBeams == 0);
        }
    }
}

TEST_CASE("tyre tread pattern is read from the car file and checked") {
    CHECK(parseCarDefinition(R"({"id": "x"})").tires.tread == "road");
    CHECK(parseCarDefinition(R"({"id": "x", "tires": {"tread": "offroad"}})").tires.tread == "offroad");
    CHECK_THROWS(parseCarDefinition(R"({"id": "x", "tires": {"tread": "slick"}})"));
    CHECK(loadCarDefinition(std::string(SB_CARS_DIR) + "/trailhead_4x4.car.json").tires.tread == "offroad");
}
