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

TEST_CASE("procedural tyre tread and sidewalls face outward") {
    const CarBuild car = buildCar(loadCarDefinition(carPath("kestrel_hatch")));
    const MeshSurface& mesh = car.visual.wheelFront.front();
    REQUIRE(mesh.material == "tire");
    const auto vertex = [&](std::size_t triangleIndex) {
        const std::size_t offset = 3 * static_cast<std::size_t>(mesh.indices[triangleIndex]);
        return Vec3{mesh.positions[offset], mesh.positions[offset + 1], mesh.positions[offset + 2]};
    };
    const TireDef& tire = car.def.tires;
    bool sawTread = false, sawInnerSidewall = false, sawOuterSidewall = false;
    for (std::size_t i = 0; i < mesh.indices.size(); i += 3) {
        const Vec3 a = vertex(i), b = vertex(i + 1), c = vertex(i + 2);
        const Vec3 face = cross(b - a, c - a);
        const Vec3 center = (a + b + c) / 3.0;
        const Vec3 radial{center.x, center.y, 0.0};
        if (std::abs(center.z) < tire.width * 0.2 && length(radial) > tire.radius - 0.005) {
            CHECK(dot(face, radial) > 0.0);
            sawTread = true;
        }
        if (std::abs(center.z) > tire.width * 0.45 && length(radial) < tire.radius - 0.05) {
            CHECK(face.z * center.z > 0.0);
            sawInnerSidewall |= center.z < 0.0;
            sawOuterSidewall |= center.z > 0.0;
        }
    }
    CHECK(sawTread);
    CHECK(sawInnerSidewall);
    CHECK(sawOuterSidewall);
}

TEST_CASE("Concept GT suspension holds alignment under driving loads and can still bend on impact") {
    const auto def = loadCarDefinition(carPath("concept_gt"));
    enum Scenario { Landing, FastTurn, WallImpact };
    for (const Scenario scenario : {Landing, FastTurn, WallImpact}) {
        CAPTURE(scenario);
        World world = flatWorld();
        if (scenario == WallImpact) {
            world.addCollider(StaticCollider::box({12.0, 0.75, -def.body.trackFront * 0.5}, {0.8, 0.75, 0.45}));
        }
        CarBuild build = buildCar(def);
        const CarLayout layout = build.layout;
        world.addBody(std::move(build.body));
        auto& car = world.body(0);
        world.simulate(0.7);
        if (scenario == Landing) {
            const Vec3 pivot = car.centerOfMass();
            for (Vec3& p : car.positions()) {
                const Vec3 d = p - pivot;
                p.y = pivot.y + d.y * std::cos(0.17) - d.z * std::sin(0.17) + 0.95;
                p.z = pivot.z + d.y * std::sin(0.17) + d.z * std::cos(0.17);
            }
        }
        const real speedKmh = scenario == Landing ? 100.0 : (scenario == FastTurn ? 130.0 : 120.0);
        const real speed = speedKmh / 3.6;
        car.setVelocity({speed, 0, 0});
        for (const auto& wheel : car.wheels()) {
            const Vec3 center = wheel.center(car), axis = wheel.axis(car);
            for (auto node : wheel.treadNodes) {
                car.velocities()[node] += cross(axis, car.positions()[node] - center) * (speed / wheel.spec.radius);
            }
        }
        VehicleControls controls;
        if (scenario == FastTurn) controls.steer = 0.5;
        car.setControls(controls);
        world.simulate(2.5);
        REQUIRE(world.stats().finite);
        real worst = 0.0;
        bool broken = false;
        for (const auto& group : car.systems().spec().suspensionBeams) {
            for (auto id : group) {
                worst = std::max(worst, car.beams()[id].plasticStrain());
                broken |= car.beams()[id].broken;
            }
        }
        if (scenario == WallImpact) {
            CHECK((broken || worst > 0.02));
        } else {
            CHECK_FALSE(broken);
            CHECK(worst < 0.02);
            const auto& p = car.positions();
            const Vec3 forward = normalize((p[layout.refFL] + p[layout.refFR]) - (p[layout.refRL] + p[layout.refRR]));
            const Vec3 right = (p[layout.refFR] + p[layout.refRR]) - (p[layout.refFL] + p[layout.refRL]);
            const Vec3 up = normalize(cross(right, forward));
            for (const auto& wheel : car.wheels()) {
                CHECK(std::abs(dot(wheel.axis(car), up)) < 0.45);
                if (!wheel.spec.steered) {
                    CHECK(std::abs(dot(wheel.axis(car), forward)) < (scenario == Landing ? 0.12 : 0.30));
                }
            }
        }
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
    CHECK(car.powertrain().clutchWear() == 0.0);
    CHECK(car.powertrain().gearboxDamage() == 0.0);
    CHECK(car.powertrain().engineRpm() == doctest::Approx(car.powertrain().spec().idleRpm));
}

TEST_CASE("clutch overheats under sustained slip, loses drive and repairs") {
    Powertrain pt;
    pt.setDrivenInertia(4.0);
    PowertrainInputs in;
    in.throttle = 1.0;
    in.clutch = 0.20;
    const std::vector<real> omega(4, 0.0);
    const std::vector<bool> driven{false, false, true, true}, front{true, true, false, false}, all(4, true);
    std::vector<real> drive, brake;
    for (int i = 0; i < 240000 && pt.clutchWear() < 1.0; ++i)
        pt.step(in, omega, driven, front, all, driven, drive, brake, 0.001);
    CHECK(pt.clutchTemperature() > 230.0);
    REQUIRE(pt.clutchWear() == 1.0);
    pt.step(in, omega, driven, front, all, driven, drive, brake, 0.001);
    CHECK(std::abs(drive[2]) < 0.001);
    pt.repair();
    CHECK(pt.clutchWear() == 0.0);
    CHECK(pt.clutchTemperature() == 45.0);
    CHECK(pt.running());
}

TEST_CASE("normal coupling and clutch-assisted shifts preserve transmission; abusive shifts break it") {
    PowertrainSpec spec;
    spec.automatic = false;
    Powertrain pt(spec);
    pt.setDrivenInertia(4.0);
    PowertrainInputs in;
    in.throttle = 0.6;
    in.clutch = 1.0;
    const std::vector<bool> driven{false, false, true, true}, front{true, true, false, false}, all(4, true);
    std::vector<real> drive, brake;
    for (int i = 0; i < 60000; ++i) {
        const std::vector<real> omega(4, pt.engineOmega() / pt.currentTotalRatio());
        pt.step(in, omega, driven, front, all, driven, drive, brake, 0.001);
    }
    CHECK(pt.clutchWear() == 0.0);
    CHECK(pt.clutchTemperature() < 80.0);
    for (int i = 0; i < 50; ++i) {
        in.requestedGear = i % 2 == 0 ? 2 : 3;
        in.clutch = 0.0;
        pt.step(in, std::vector<real>(4, 25.0), driven, front, all, driven, drive, brake, 0.001);
    }
    CHECK(pt.gearboxDamage() == 0.0);
    for (int i = 0; i < 30; ++i) {
        in.requestedGear = i % 2 == 0 ? 1 : 3;
        in.clutch = 1.0;
        in.throttle = 1.0;
        pt.step(in, std::vector<real>(4, 100.0), driven, front, all, driven, drive, brake, 0.001);
    }
    CHECK(pt.gearboxDamage() == 1.0);
    CHECK(pt.gear() == 0);
    CHECK(pt.currentTotalRatio() == 0.0);
    CHECK(drive[2] == 0.0);
    pt.repair();
    CHECK(pt.gearboxDamage() == 0.0);
    CHECK(pt.currentTotalRatio() > 0.0);
}

TEST_CASE("automatic shift protection rejects destructive downshift") {
    Powertrain pt;
    pt.setGear(5);
    PowertrainInputs in;
    in.requestedGear = 1;
    const std::vector<bool> driven{false, false, true, true}, front{true, true, false, false}, all(4, true);
    std::vector<real> drive, brake;
    pt.step(in, std::vector<real>(4, 90.0), driven, front, all, driven, drive, brake, 0.001);
    CHECK(pt.gear() == 5);
    CHECK(pt.gearboxDamage() == 0.0);
}

TEST_CASE("tyres heat up, wear out and burst under sustained wheelspin") {
    CarBuild cb = buildCar(loadCarDefinition(carPath("aurora_sedan")));
    for (PressureWheel& w : cb.body.wheels()) w.spec.wearRate = 14.0;  // accelerated test
    World w = flatWorld();
    w.addBody(std::move(cb.body));
    SoftBody& car = w.body(0);
    w.simulate(1.0);
    VehicleControls c;
    c.throttle = 1.0;
    c.tcs = false;
    c.steer = 0.6;
    car.setControls(c);
    bool burst = false;
    for (int i = 0; i < 60 && !burst; ++i) {
        w.simulate(1.0);
        burst = car.wheels()[2].burst || car.wheels()[3].burst;
    }
    CHECK(burst);
    CHECK(std::max(car.wheels()[2].wear, car.wheels()[3].wear) > 0.5);
    CHECK(car.wheels()[0].wear < 0.2);  // undriven front tyres barely wear
    CHECK(w.stats().finite);
}

TEST_CASE("a punctured tyre deflates, goes flat and is restored by repair") {
    CarBuild cb = buildCar(loadCarDefinition(carPath("kestrel_hatch")));
    const std::vector<Vec3> rest = cb.restPositions;
    World w = flatWorld();
    w.addBody(std::move(cb.body));
    SoftBody& car = w.body(0);
    VehicleControls c;
    c.brake = 1.0;
    car.setControls(c);
    w.simulate(1.5);
    const real y0 = car.wheels()[0].center(car).y;
    car.wheels()[0].puncture(4.0);
    w.simulate(12.0);
    CHECK(car.wheels()[0].pressurePsi < 1.0);
    CHECK(car.wheels()[0].center(car).y < y0 - 0.03);
    car.repair(rest);
    CHECK(car.wheels()[0].pressurePsi > 30.0);
    CHECK(car.wheels()[0].leakPsiPerS == 0.0);
}

TEST_CASE("wheel contact measures supported weight and clears in flight") {
    CarBuild cb = buildCar(loadCarDefinition(carPath("kestrel_hatch")));
    World w = flatWorld();
    w.addBody(std::move(cb.body));
    auto& car = w.body(0);
    w.simulate(2.0);
    real force = 0.0;
    for (const auto& tire : car.wheels()) {
        force += tire.load;
        CHECK(tire.contactAge < 0.025);
        CHECK(tire.contactNormal.y > 0.95);
    }
    CHECK(force > car.totalMass() * 9.81 * 0.75);
    CHECK(force < car.totalMass() * 9.81 * 1.25);
    car.translate({0, 5, 0});
    car.setVelocity({15, 0, 0});
    w.simulate(0.15);
    for (const auto& tire : car.wheels()) {
        CHECK(tire.contactAge > 0.1);
        CHECK(tire.load < 50.0);
        CHECK(tire.slipSpeed == 0.0);
    }
}

TEST_CASE("reference hatch survives braking, a lane change and low speed bumps") {
    CarBuild cb = buildCar(loadCarDefinition(carPath("kestrel_hatch")));
    World w = flatWorld();
    w.addBody(std::move(cb.body));
    auto& car = w.body(0);
    w.simulate(1.0);
    VehicleControls controls;
    controls.throttle = 1.0;
    car.setControls(controls);
    w.simulate(7.0);
    CHECK(car.telemetry().speedKmh > 65.0);
    controls.throttle = 0.2;
    controls.steer = 0.12;
    car.setControls(controls);
    w.simulate(0.5);
    controls.steer = -0.12;
    car.setControls(controls);
    w.simulate(0.5);
    controls = {};
    controls.brake = 1.0;
    car.setControls(controls);
    const Vec3 brakeStart = car.centerOfMass();
    w.simulate(5.0);
    CHECK(car.telemetry().speedKmh < 2.0);
    CHECK(length(car.centerOfMass() - brakeStart) < 70.0);
    CHECK(car.stats().brokenBeams == 0);
    CHECK(w.stats().finite);
    for (const auto& tire : car.wheels()) CHECK_FALSE(tire.burst);
    car.repair(cb.restPositions);
    car.setVelocity({8, 0, 0});
    w.addCollider(StaticCollider::box({8, 0.025, 0}, {0.30, 0.025, 3}, {}, 1.0));
    car.setControls({});
    w.simulate(2.0);
    CHECK(car.stats().brokenBeams == 0);
    CHECK(w.stats().finite);
}

TEST_CASE("fast rolling tyres do not mistake carcass flex for a burnout") {
    CarBuild cb = buildCar(loadCarDefinition(carPath("vortex_gt")));
    World w = flatWorld();
    w.addBody(std::move(cb.body));
    auto& car = w.body(0);
    w.simulate(1.0);
    VehicleControls controls;
    controls.throttle = 1.0;
    car.setControls(controls);
    w.simulate(28.5);
    CHECK(car.telemetry().speedKmh > 135.0);
    CHECK(car.stats().brokenBeams == 0);
    for (const auto& tyre : car.wheels()) {
        CHECK_FALSE(tyre.burst);
        CHECK(tyre.wear < 0.025);
        CHECK(tyre.tempC < 55.0);
    }
}

TEST_CASE("road surface grip changes tyre friction independently of camera distance") {
    CarBuild cb = buildCar(loadCarDefinition(carPath("kestrel_hatch")));
    World w = flatWorld();
    w.addBody(std::move(cb.body));
    auto& car = w.body(0);
    w.simulate(1.0);
    const real asphaltGrip = car.wheels()[0].grip;
    car.wheels()[0].surfaceGrip = 0.66;
    w.simulate(0.1);
    CHECK(car.wheels()[0].grip < asphaltGrip * 0.7);
    CHECK(car.wheels()[1].grip > asphaltGrip * 0.95);
    CHECK(car.frictions()[car.wheels()[0].treadNodes[0]] < car.frictions()[car.wheels()[1].treadNodes[0]] * 0.7);
}
