// Tests for the realistic car generator, suspension elements and vehicle systems.
#include <doctest/doctest.h>

#include <cmath>
#include <string>

#include "sbcore/sbcore.hpp"

using namespace sb;

#ifndef SB_CARS_DIR
#define SB_CARS_DIR "game/cars"
#endif

namespace {

std::string carPath(const char* id) { return std::string(SB_CARS_DIR) + "/" + id + ".car.json"; }

World flatWorld() {
    World w;
    w.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}, 1.0));
    return w;
}

}  // namespace

TEST_CASE("shock beams damp rebound harder than bump") {
    auto run = [](real v0) {
        WorldSettings ws;
        ws.gravity = {0, 0, 0};
        World w(ws);
        SoftBody b("shock");
        NodeParams fixed;
        fixed.fixed = true;
        NodeParams m;
        m.mass = 10.0;
        b.addNode("a", {0, 0, 0}, fixed);
        b.addNode("b", {0.5, 0, 0}, m);
        BeamParams p;
        p.type = BeamType::Shock;
        p.spring = 0.0;
        p.damp = 100.0;
        p.dampRebound = 400.0;
        b.addBeam("a", "b", p);
        w.addBody(std::move(b));
        w.body(0).velocities()[1] = {v0, 0, 0};
        w.simulate(0.01);
        return std::abs(w.body(0).velocities()[1].x);
    };
    const real afterRebound = run(1.0);   // extending
    const real afterBump = run(-1.0);     // compressing
    CHECK(afterRebound < afterBump);
    CHECK(afterBump < 1.0);
}

TEST_CASE("torsion bar resists relative rotation and is linear for small angles") {
    WorldSettings ws;
    ws.gravity = {0, 0, 0};
    World w(ws);
    SoftBody b("tb");
    NodeParams fixed;
    fixed.fixed = true;
    NodeParams m;
    m.mass = 1.0;
    b.addNode("n1", {0.3, 0, -0.5}, fixed);
    b.addNode("n2", {0, 0, -0.5}, fixed);
    b.addNode("n3", {0, 0, 0.5}, fixed);
    b.addNode("n4", {0.3, 0, 0.5}, m);
    TorsionbarParams tp;
    tp.spring = 1000.0;
    tp.damp = 0.0;
    b.addTorsionbar(0, 1, 2, 3, tp);
    w.addBody(std::move(b));
    // Twist the free arm end upwards by 0.03 m -> restoring force must point down.
    w.body(0).positions()[3].y = 0.03;
    w.step();
    CHECK(w.body(0).velocities()[3].y < 0.0);
    const real torque = w.body(0).torsionbars()[0].lastTorque;
    CHECK(std::abs(std::abs(torque) - 1000.0 * std::atan2(0.03, 0.3)) < 5.0);
}

TEST_CASE("all shipped car definitions build, are stable and settle on their suspension") {
    for (const char* id : {"kestrel_hatch", "aurora_sedan", "vortex_gt", "basalt_suv"}) {
        CAPTURE(id);
        const CarDefinition def = loadCarDefinition(carPath(id));
        CarBuild cb = buildCar(def);
        CHECK(cb.body.nodeCount() > 250);
        CHECK(cb.body.wheels().size() == 4);
        CHECK(cb.body.torsionbars().size() == 2);
        CHECK(cb.body.stabilityRatio(1.0 / 2000.0) < 1.0);
        CHECK(cb.visual.skinned.size() > 8);
        CHECK(std::abs(cb.body.totalMass() - def.chassis.curbMass) < 0.06 * def.chassis.curbMass);

        World w = flatWorld();
        const CarLayout lay = cb.layout;
        const real floor0 = cb.body.positions()[lay.refFL].y;
        w.addBody(std::move(cb.body));
        VehicleControls c;
        c.brake = 1.0;
        w.body(0).setControls(c);
        w.simulate(2.0);
        REQUIRE(w.stats().finite);
        const real floor1 = w.body(0).positions()[lay.refFL].y;
        CHECK(floor1 > floor0 - 0.07);   // suspension carries the car close to design ride height
        CHECK(floor1 < floor0 + 0.03);
        CHECK(w.stats().deformedBeams == 0);
    }
}

TEST_CASE("realistic car accelerates straight, steers left with +steer and stops") {
    CarBuild cb = buildCar(loadCarDefinition(carPath("aurora_sedan")));
    World w = flatWorld();
    w.addBody(std::move(cb.body));
    SoftBody& car = w.body(0);
    VehicleControls c;
    c.throttle = 1.0;
    car.setControls(c);
    w.simulate(6.0);
    CHECK(car.telemetry().speedKmh > 60.0);
    CHECK(std::abs(car.centerOfMass().z) < 0.5);  // straight line
    c.throttle = 0.2;
    c.steer = 0.3;
    car.setControls(c);
    const real z0 = car.centerOfMass().z;
    w.simulate(1.5);
    CHECK(car.centerOfMass().z < z0 - 1.0);  // + steer = left = -z
    c = {};
    c.brake = 1.0;
    car.setControls(c);
    w.simulate(6.0);
    CHECK(car.telemetry().speedKmh < 2.0);
    CHECK(w.stats().finite);
}

TEST_CASE("a pierced radiator leaks coolant and the engine overheats and seizes") {
    CarBuild cb = buildCar(loadCarDefinition(carPath("kestrel_hatch")));
    World w = flatWorld();
    w.addBody(std::move(cb.body));
    SoftBody& car = w.body(0);
    REQUIRE(car.hasSystems());
    VehicleControls c;
    c.gear = 0;
    c.throttle = 0.4;  // revving in neutral -> lots of heat, little airflow
    car.setControls(c);
    w.simulate(2.0);
    CHECK(car.systems().state().coolantLevel > 0.99);
    CHECK(car.systems().state().running);
    for (std::uint32_t bi : car.systems().spec().radiatorBeams) {
        if (car.beams()[bi].type == BeamType::Normal) {
            car.breakBeam(bi);
            break;
        }
    }
    for (int i = 0; i < 240 && !car.systems().state().seized; ++i) w.simulate(0.5);
    const CarSystemsState& s = car.systems().state();
    CHECK(s.radiatorDamage > 0.3);
    CHECK(s.coolantLevel < 0.05);
    CHECK(s.seized);
    CHECK_FALSE(car.powertrain().running());
}

TEST_CASE("repair restores structure and systems") {
    CarBuild cb = buildCar(loadCarDefinition(carPath("kestrel_hatch")));
    const std::vector<Vec3> rest = cb.restPositions;
    SoftBody& car = cb.body;
    car.breakBeam(0);
    car.systems().state().seized = true;
    car.repair(rest);
    CHECK_FALSE(car.beams()[0].broken);
    CHECK_FALSE(car.systems().state().seized);
    CHECK(car.stats().deformedBeams == 0);
}
