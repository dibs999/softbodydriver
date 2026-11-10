#include <doctest/doctest.h>
#include <algorithm>
#include <string>
#include "sbcore/sbcore.hpp"

using namespace sb;

namespace {
// Front car cruises at vFront, the rear car runs into it at vRear, pushes for 3 s and then brakes
// hard. Returns the gap between the two bodies (shells only) 5 s after the rear car started braking.
real rearEndGap(const char* front, const char* rear, real vFront, real vRear) {
    auto a = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/" + front + ".car.json"));
    auto b = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/" + rear + ".car.json"));
    a.body.translate({b.def.body.length + 4.0, 0.0, 0.0});
    for (auto& v : a.body.velocities()) v = {vFront / 3.6, 0, 0};
    for (auto& v : b.body.velocities()) v = {vRear / 3.6, 0, 0};
    World world;
    world.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}));
    const auto ia = world.addBody(std::move(a.body));
    const auto ib = world.addBody(std::move(b.body));
    auto drive = [](SoftBody& car, real target) {
        VehicleControls c;
        const real e = target / 3.6 - car.telemetry().speedKmh / 3.6;
        c.throttle = target > 0.0 ? std::clamp(e * 0.6, 0.0, 1.0) : 0.0;
        c.brake = target > 0.0 ? std::clamp(-e * 0.4, 0.0, 1.0) : 1.0;
        car.setControls(c);
    };
    auto extent = [](const SoftBody& s, bool front) {
        real m = front ? -1e9 : 1e9;
        for (std::size_t i = 0; i < s.nodeCount(); ++i)
            if (s.groupNames()[s.nodeGroups()[i]] == "body") m = front ? std::max(m, s.positions()[i].x) : std::min(m, s.positions()[i].x);
        return m;
    };
    real contact = -1.0, t = 0.0;
    while (t < 20.0) {
        const bool braking = contact >= 0.0 && t > contact + 3.0;
        if (braking && t > contact + 8.0) break;
        drive(world.body(ia), vFront);
        drive(world.body(ib), braking ? 0.0 : vRear);
        world.simulate(0.05);
        t += 0.05;
        if (contact < 0.0 && world.stats().bodyContacts > 0) contact = t;
    }
    REQUIRE(contact >= 0.0);
    REQUIRE(world.stats().finite);
    CHECK(world.body(ia).telemetry().speedKmh < 130.0);
    return extent(world.body(ia), false) - extent(world.body(ib), true);
}
}  // namespace

TEST_CASE("a rear-ended car drives away: bodies do not hook together after the impact") {
    // Both used to stay hooked: a node of the rear car caught in a crease of the front car's skin
    // (opposed faces, and sliver triangles at the tail facing into the car) towed the front car.
    CHECK(rearEndGap("meridian_sedan", "kestrel_hatch", 80.0, 97.0) > 20.0);
    CHECK(rearEndGap("kestrel_hatch", "kestrel_hatch", 50.0, 75.0) > 20.0);
}

TEST_CASE("props stand still on the ground and a car knocks them over without tearing them up") {
    auto coast = [](bool withProp, PropKind kind, real* knocked, real offset = 0.3) {
        auto car = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
        auto prop = buildProp(kind);
        prop.body.translate({car.def.body.length + 6.0, 0.0, offset});
        const Vec3 start = prop.body.positions()[prop.frameY];
        World world;
        world.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}));
        const auto ic = world.addBody(std::move(car.body));
        std::size_t ip = 0;
        if (withProp) ip = world.addBody(std::move(prop.body));
        VehicleControls c;
        c.gear = 0;   // coasting in neutral
        world.body(ic).setControls(c);
        world.simulate(1.0);
        if (withProp) CHECK(length(world.body(ip).positions()[prop.frameY] - start) < 0.03);  // upright, at rest
        for (auto& v : world.body(ic).velocities()) v = {40.0 / 3.6, 0, 0};
        world.simulate(3.0);
        REQUIRE(world.stats().finite);
        if (withProp) {
            *knocked = length(world.body(ip).positions()[prop.frameY] - start);
            for (const auto& beam : world.body(ip).beams()) CHECK_FALSE(beam.broken);
        }
        return world.body(ic).telemetry().speedKmh;
    };
    const real alone = coast(false, PropKind::Cone, nullptr);
    for (const PropKind kind : {PropKind::Cone, PropKind::Barrel, PropKind::Bin}) {
        const std::string name = kind == PropKind::Cone ? "cone" : kind == PropKind::Barrel ? "barrel" : "bin";
        CAPTURE(name);
        auto prop = buildProp(kind);
        CHECK(prop.body.stabilityRatio(1.0 / 2000.0) < 0.9);
        const real mass = kind == PropKind::Cone ? 4.5 : kind == PropKind::Barrel ? 20.0 : 15.0;
        CHECK(prop.body.totalMass() == doctest::Approx(mass).epsilon(0.02));
        real knocked = 0;
        const real speed = coast(true, kind, &knocked);
        MESSAGE(name << " knocked " << knocked << " m, car " << speed << " km/h (alone " << alone << ")");
        CHECK(knocked > 3.0);
        // A light prop barely slows a 1.3 t car: momentum alone allows < 1 km/h (cone) / 2.5 km/h (drum).
        CHECK(alone - speed < (kind == PropKind::Cone ? 2.0 : 5.0));
    }
    // Struck off-centre a cone used to be caught: through holes in the nose skin, or stretched over
    // the bumper with its base under a front tyre, it lifted the nose and cost up to 19 km/h.
    for (const real offset : {0.45, 0.75, -0.75}) {
        CAPTURE(offset);
        real knocked = 0;
        const real speed = coast(true, PropKind::Cone, &knocked, offset);
        CHECK(alone - speed < 2.0);
    }
}

TEST_CASE("sliding a wheel into a kerb bends the rim and lets the air out; a gentle touch does not") {
    auto slide = [](real kmh) {
        auto build = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
        World world;
        world.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}));
        world.addCollider(StaticCollider::box({2.0, 0.06, -2.4}, {20.0, 0.06, 0.25}, {0, 0, 0}, 0.8));
        world.addBody(std::move(build.body));
        auto& car = world.body(0);
        world.simulate(0.5);
        for (auto& v : car.velocities()) v = {0, 0, -kmh / 3.6};
        world.simulate(4.0);
        REQUIRE(world.stats().finite);
        return std::make_pair(car.wheels()[0].rimDamage, car.wheels()[0].pressurePsi);  // front left leads
    };
    const auto [gentleRim, gentlePsi] = slide(12.0);
    CHECK(gentleRim == doctest::Approx(0.0));
    CHECK(gentlePsi > 30.0);
    const auto [hardRim, hardPsi] = slide(30.0);
    MESSAGE("kerb strike at 30 km/h: rim damage " << hardRim << ", " << hardPsi << " psi left");
    CHECK(hardRim > 0.3);
    CHECK(hardPsi < 20.0);
}

TEST_CASE("a water-filled barrier stands, takes a hit, slides and squashes without exploding") {
    auto prop = buildProp(PropKind::Barrier);
    CHECK(prop.body.totalMass() == doctest::Approx(300.0));
    CHECK(prop.body.stabilityRatio(1.0 / 2000.0) < 0.9);
    auto car = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
    // Broadside on to the car (long axis across the lane).
    for (auto& p : prop.body.positions()) p = {car.def.body.length + 6.0 - p.z, p.y, p.x};
    const Vec3 start = prop.body.positions()[prop.frameY];
    World world;
    world.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}));
    const auto ic = world.addBody(std::move(car.body));
    const auto ip = world.addBody(std::move(prop.body));
    VehicleControls c;
    c.gear = 0;
    world.body(ic).setControls(c);
    world.simulate(1.0);
    CHECK(length(world.body(ip).positions()[prop.frameY] - start) < 0.03);
    for (auto& v : world.body(ic).velocities()) v = {40.0 / 3.6, 0, 0};
    world.simulate(3.0);
    REQUIRE(world.stats().finite);
    const real moved = length(world.body(ip).positions()[prop.frameY] - start);
    std::size_t squashed = 0;
    for (const auto& beam : world.body(ip).beams()) squashed += beam.plasticStrain() > 0.01 ? 1 : 0;
    MESSAGE("barrier moved " << moved << " m, squashed beams " << squashed << ", car " << world.body(ic).telemetry().speedKmh << " km/h");
    CHECK(moved > 1.0);
    CHECK(moved < 30.0);
    CHECK(world.body(ic).telemetry().speedKmh < 34.0);   // 300 kg of water take real momentum
}

TEST_CASE("a felled log is shoved or climbed, never flung faster than the car") {
    auto prop = buildProp(PropKind::Log);
    CHECK(prop.body.totalMass() == doctest::Approx(380.0));
    CHECK(prop.body.stabilityRatio(1.0 / 2000.0) < 0.9);
    auto car = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/trailhead_4x4.car.json"));
    for (auto& p : prop.body.positions()) p = {car.def.body.length + 5.0 + p.z, p.y, p.x};   // across the path
    const Vec3 start = prop.body.positions()[prop.frameY];
    World world;
    world.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}));
    const auto ic = world.addBody(std::move(car.body));
    const auto ip = world.addBody(std::move(prop.body));
    world.simulate(1.0);
    CHECK(length(world.body(ip).positions()[prop.frameY] - start) < 0.03);
    VehicleControls c;
    c.throttle = 0.6;
    world.body(ic).setControls(c);
    real worstExcess = 0.0;
    for (int k = 0; k < 400; ++k) {
        world.simulate(0.02);
        const real logSpeed = length(world.body(ip).centerOfMassVelocity());
        const real carSpeed = length(world.body(ic).centerOfMassVelocity());
        worstExcess = std::max(worstExcess, logSpeed - carSpeed);
    }
    REQUIRE(world.stats().finite);
    MESSAGE("log faster than the car by at most " << worstExcess << " m/s");
    CHECK(worstExcess < 1.5);
}

TEST_CASE("resting props fall asleep, a car wakes them, and they settle back to sleep") {
    auto car = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
    auto cone = buildProp(PropKind::Cone);
    auto drum = buildProp(PropKind::Barrel);
    cone.body.translate({car.def.body.length + 6.0, 0.0, 0.3});
    drum.body.translate({car.def.body.length + 6.0, 0.0, 6.0});   // off the car's path
    World world;
    world.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}));
    const auto ic = world.addBody(std::move(car.body));
    const auto ip = world.addBody(std::move(cone.body));
    const auto id = world.addBody(std::move(drum.body));
    VehicleControls c;
    c.gear = 0;
    world.body(ic).setControls(c);
    world.simulate(3.0);
    CHECK(world.body(ip).asleep());
    CHECK(world.body(id).asleep());
    CHECK_FALSE(world.body(ic).asleep());   // cars never sleep
    const Vec3 rest = world.body(ip).centerOfMass();
    for (auto& v : world.body(ic).velocities()) v = {30.0 / 3.6, 0, 0};
    world.simulate(2.0);
    CHECK(length(world.body(ip).centerOfMass() - rest) > 3.0);   // woken and knocked away
    CHECK(world.body(id).asleep());                              // the far drum slept through it
    world.body(ic).translate({0.0, 0.0, 40.0});   // the car leaves
    world.simulate(6.0);
    CHECK(world.body(ip).asleep());   // at rest again
    REQUIRE(world.stats().finite);
}
