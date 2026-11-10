// Tests for the realistic car generator, suspension elements and vehicle systems.
#include <doctest/doctest.h>

#include <cmath>
#include <algorithm>
#include <string>

#include "sbcore/sbcore.hpp"
#include "sbcore/render_motion.hpp"

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

TEST_CASE("visual filtering survives highway speed and missed render frames") {
    // Previously a fixed four-metre threshold disabled all body filtering at
    // 216 km/h and 15 FPS, although the simulation had not teleported.
    for (const double speed : {0.0, 30.0, 60.0, 90.0}) {
        for (const double dt : {1.0 / 120.0, 1.0 / 30.0, 1.0 / 15.0, 0.1}) {
            const Vec3 velocity{speed, 0.0, 0.0};
            CHECK_FALSE(visualMotionDiscontinuity(velocity * dt, velocity, dt));
            CHECK_FALSE(visualMotionDiscontinuity(velocity * dt + Vec3{0, 0.03, 0}, velocity, dt));
            CHECK(visualMotionDiscontinuity({100, 0, 0}, velocity, dt));
        }
    }
    CHECK(visualMotionDiscontinuity({5, 0, 0}, {}, 1.0 / 60.0));
    CHECK(visualMotionDiscontinuity({}, {}, 0.0));
}

TEST_CASE("bonnet latch and hinges release a separate physical panel and repair restores it") {
    auto cb = buildCar(loadCarDefinition(carPath("kestrel_hatch")));
    CHECK(cb.body.totalMass() == doctest::Approx(cb.def.chassis.curbMass).epsilon(0.001));
    const real rearAxle = cb.def.body.length - cb.def.body.frontOverhang - cb.def.body.wheelbase;
    const real frontWeight = (cb.body.centerOfMass().x - rearAxle) / cb.def.body.wheelbase;
    CHECK(frontWeight == doctest::Approx(cb.def.chassis.frontWeight).epsilon(0.005));
    const auto bonnet = cb.layout.bonnetNodes;
    REQUIRE(bonnet.size() == 8);
    const auto rest = cb.body.positions();
    auto release = [&](const std::string& group) {
        for (std::size_t i = 0; i < cb.body.beams().size(); ++i) {
            const auto& b = cb.body.beams()[i];
            if (b.breakGroup >= 0 && cb.body.breakGroupNames()[static_cast<std::size_t>(b.breakGroup)] == group)
                cb.body.breakBeam(static_cast<std::uint32_t>(i));
        }
    };
    auto attachments = [&]() {
        int count = 0;
        for (const auto& b : cb.body.beams()) {
            const bool aPanel = std::find(bonnet.begin(), bonnet.end(), b.a) != bonnet.end();
            const bool bPanel = std::find(bonnet.begin(), bonnet.end(), b.b) != bonnet.end();
            if (aPanel != bPanel && !b.broken) ++count;
        }
        return count;
    };
    CHECK(attachments() == 14);
    release("bonnet_latch");
    CHECK(attachments() == 8);
    release("bonnet_hinge");
    CHECK(attachments() == 0);
    WorldSettings settings;
    settings.gravity = {};
    settings.airDensity = 0;
    World w(settings);
    for (auto n : bonnet) cb.body.velocities()[n] = {0, 10, 0};
    w.addBody(cb.body);
    w.simulate(0.05);
    REQUIRE(w.stats().finite);
    CHECK(w.body(0).positions()[bonnet[0]].y - rest[bonnet[0]].y == doctest::Approx(0.5).epsilon(0.02));
    cb.body.repair(rest);
    CHECK(attachments() == 14);
}

TEST_CASE("independent panels remain inside shipped vehicle mass and axle-load budgets") {
    for (const char* id : {"kestrel_hatch", "kestrel_rally", "aurora_sedan", "basalt_suv",
                           "vortex_gt", "vortex_sprint", "concept_gt"}) {
        const std::string carId(id);
        CAPTURE(carId);
        const auto car = buildCar(loadCarDefinition(carPath(id)));
        CHECK(car.body.totalMass() == doctest::Approx(car.def.chassis.curbMass).epsilon(0.000001));
        for (auto n : car.layout.bodyNodes) CHECK(car.body.masses()[n] >= 2.0);
        const real rearAxle = car.def.body.length - car.def.body.frontOverhang - car.def.body.wheelbase;
        const real frontWeight = (car.body.centerOfMass().x - rearAxle) / car.def.body.wheelbase;
        CHECK(std::abs(frontWeight - car.def.chassis.frontWeight) < 0.025);
    }
}

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
    for (const char* id : {"kestrel_hatch", "aurora_sedan", "vortex_gt", "basalt_suv", "meridian_sedan", "meridian_wagon",
                           "meridian_interceptor", "trailhead_4x4", "fastback_69"}) {
        CAPTURE(id);
        const CarDefinition def = loadCarDefinition(carPath(id));
        CarBuild cb = buildCar(def);
        CHECK(cb.body.nodeCount() > 250);
        CHECK(cb.body.wheels().size() == 4);
        const std::size_t bars = (def.front.antiRollRate > 0.0 ? 1u : 0u) + (def.rear.antiRollRate > 0.0 ? 1u : 0u);
        CHECK(cb.body.torsionbars().size() == bars);
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

TEST_CASE("Concept GT mid-engine packaging matches mass distribution and keeps front radiator separate") {
    const auto car = buildCar(loadCarDefinition(carPath("concept_gt")));
    REQUIRE(car.def.engine.position == "mid");
    REQUIRE(car.layout.engineNodes.size() == 8);
    const real rearAxle = car.def.body.length - car.def.body.frontOverhang - car.def.body.wheelbase;
    real engineFront = 0, engineRear = car.def.body.length;
    for (auto n : car.layout.engineNodes) {
        engineFront = std::max(engineFront, car.body.positions()[n].x);
        engineRear = std::min(engineRear, car.body.positions()[n].x);
    }
    CHECK(engineRear > rearAxle);
    CHECK(engineFront < rearAxle + 0.8);
    for (std::size_t n = 0; n < car.body.nodeCount(); ++n)
        if (car.body.groupNames()[car.body.nodeGroups()[n]] == "fueltank")
            CHECK(car.body.positions()[n].x > engineFront);
    for (const auto& beam : car.body.beams()) {
        const auto& ga = car.body.groupNames()[car.body.nodeGroups()[beam.a]];
        const auto& gb = car.body.groupNames()[car.body.nodeGroups()[beam.b]];
        const bool crossesCabin = (ga == "engine" && gb == "radiator") || (ga == "radiator" && gb == "engine");
        CHECK_FALSE(crossesCabin);
    }
    const auto conventional = buildCar(loadCarDefinition(carPath("kestrel_hatch")));
    CHECK(conventional.def.engine.position == "front");
    CHECK(conventional.body.positions()[conventional.layout.engineNodes[0]].x > conventional.def.body.length * 0.6);
}

TEST_CASE("Concept GT holds rear toe through highway lane changes in both directions") {
    const auto def = loadCarDefinition(carPath("concept_gt"));
    for (real initialKmh : {100.0, 200.0}) {
        for (real direction : {-1.0, 1.0}) {
            CAPTURE(initialKmh);
            CAPTURE(direction);
            World world = flatWorld();
            auto build = buildCar(def);
            const auto layout = build.layout;
            world.addBody(std::move(build.body));
            auto& car = world.body(0);
            world.simulate(2.0);
            const real speed = initialKmh / 3.6;
            car.setVelocity({speed, 0, 0});
            for (const auto& wheel : car.wheels()) {
                const auto center = wheel.center(car), axis = wheel.axis(car);
                for (auto node : wheel.treadNodes)
                    car.velocities()[node] += cross(axis, car.positions()[node] - center) * (speed / wheel.spec.radius);
            }
            VehicleControls controls;
            controls.gear = 0;
            controls.ignition = false;
            // 0.008 at 200 km/h is a real lane change (~0.5 g). The former 0.017 kinematically
            // demands ~1.2 g and only stayed below the grip limit while excessive rolling and air
            // drag bled the coasting car from 200 to 145 km/h within the 4 s window.
            controls.steer = direction * (initialKmh == 100.0 ? 0.07 : 0.008);
            car.setControls(controls);
            real peakToe = 0.0;
            for (int sample = 0; sample < 400; ++sample) {
                world.simulate(0.01);
                const auto& p = car.positions();
                const Vec3 forward = normalize(p[layout.refFL] + p[layout.refFR] - p[layout.refRL] - p[layout.refRR]);
                for (const auto& wheel : car.wheels())
                    if (!wheel.spec.steered) peakToe = std::max(peakToe, std::abs(dot(wheel.axis(car), forward)));
            }
            REQUIRE(world.stats().finite);
            CHECK(world.stats().brokenBeams == 0);
            CHECK(world.stats().deformedBeams == 0);
            // Much tighter than the extreme full-lock test: <=5.7 deg at the
            // high lateral-load 100 km/h corner, <=2 deg on the 200 km/h lane change.
            CHECK(peakToe < (initialKmh == 100.0 ? 0.10 : 0.035));
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

TEST_CASE("collision skin aerodynamics reproduce the specified drag area") {
    for (const char* id : {"kestrel_hatch", "basalt_suv", "concept_gt"}) {
        CAPTURE(id);
        CarBuild cb = buildCar(loadCarDefinition(carPath(id)));
        const real dragArea = cb.layout.dragArea;
        REQUIRE(dragArea > 0.4);
        REQUIRE(dragArea < 1.2);
        WorldSettings settings;
        settings.gravity = {0, 0, 0};
        World w(settings);
        w.addBody(std::move(cb.body));
        auto& car = w.body(0);
        const real v = 30.0;
        car.setVelocity({v, 0, 0});
        w.simulate(0.02);
        const real force = car.totalMass() * (v - car.centerOfMassVelocity().x) / 0.02;
        const real expected = 0.5 * settings.airDensity * dragArea * v * v;
        CHECK(force == doctest::Approx(expected).epsilon(0.05));
    }
}

TEST_CASE("coast-down resistance of the reference hatch stays in a realistic range") {
    // Rolling + aerodynamic resistance at 100 km/h. A real compact hatch needs ~400 N; rigid
    // contact, flat-plate aero and an untensioned tread ring needed ~1900 N, which capped the
    // 110 kW car at 113 km/h (now ~560 N and ~197 km/h).
    CarBuild cb = buildCar(loadCarDefinition(carPath("kestrel_hatch")));
    World w = flatWorld();
    w.addBody(std::move(cb.body));
    auto& car = w.body(0);
    VehicleControls controls;
    controls.gear = 0;
    controls.ignition = false;
    car.setControls(controls);
    w.simulate(3.0);
    const real v = 100.0 / 3.6;
    car.setVelocity({v, 0, 0});
    for (const auto& wheel : car.wheels()) {
        const auto center = wheel.center(car), axis = wheel.axis(car);
        for (auto node : wheel.treadNodes)
            car.velocities()[node] += cross(axis, car.positions()[node] - center) * (v / wheel.spec.radius);
    }
    w.simulate(1.0);
    const real v0 = car.centerOfMassVelocity().x;
    w.simulate(2.0);
    const real v1 = car.centerOfMassVelocity().x;
    const real resistance = car.totalMass() * (v0 - v1) / 2.0;
    CHECK(resistance > 250.0);
    CHECK(resistance < 560.0);
    CHECK(car.stats().deformedBeams == 0);
}

TEST_CASE("full throttle runs straight to autobahn top-speed range without steering input") {
    CarBuild cb = buildCar(loadCarDefinition(carPath("vortex_gt")));
    const auto layout = cb.layout;
    World w = flatWorld();
    w.addBody(std::move(cb.body));
    auto& car = w.body(0);
    VehicleControls controls;
    controls.gear = -99;
    car.setControls(controls);
    w.simulate(2.0);
    controls.throttle = 1.0;
    car.setControls(controls);
    real worstYaw = 0.0;
    for (int i = 0; i < 36; ++i) {
        w.simulate(1.0);
        const auto& p = car.positions();
        const Vec3 forward = normalize(p[layout.refFL] + p[layout.refFR] - p[layout.refRL] - p[layout.refRR]);
        worstYaw = std::max(worstYaw, std::abs(std::atan2(forward.z, forward.x)) * 180.0 / 3.14159265358979);
    }
    CHECK(car.telemetry().speedKmh > 210.0);
    CHECK(worstYaw < 4.0);
    CHECK(car.stats().brokenBeams == 0);
    CHECK(w.stats().finite);
}

// Largest and RMS distance of the body nodes from their best rigid fit to a reference pose.
// The rotation is the polar factor of the covariance, found by Newton iteration.
std::pair<real, real> bodyDeviation(const SoftBody& car, const std::vector<std::uint32_t>& nodes, const std::vector<Vec3>& ref) {
    Vec3 cc{0, 0, 0}, rc{0, 0, 0};
    for (std::size_t k = 0; k < nodes.size(); ++k) { cc += car.positions()[nodes[k]]; rc += ref[k]; }
    cc = cc * (1.0 / nodes.size());
    rc = rc * (1.0 / nodes.size());
    real X[3][3] = {};
    for (std::size_t k = 0; k < nodes.size(); ++k) {
        const Vec3 q = car.positions()[nodes[k]] - cc, p = ref[k] - rc;
        const real qv[3] = {q.x, q.y, q.z}, pv[3] = {p.x, p.y, p.z};
        for (int i = 0; i < 3; ++i) for (int j = 0; j < 3; ++j) X[i][j] += qv[i] * pv[j];
    }
    for (int it = 0; it < 40; ++it) {
        const real d = X[0][0] * (X[1][1] * X[2][2] - X[1][2] * X[2][1]) - X[0][1] * (X[1][0] * X[2][2] - X[1][2] * X[2][0]) +
                       X[0][2] * (X[1][0] * X[2][1] - X[1][1] * X[2][0]);
        real cof[3][3];
        for (int i = 0; i < 3; ++i)
            for (int j = 0; j < 3; ++j)
                cof[i][j] = X[(i + 1) % 3][(j + 1) % 3] * X[(i + 2) % 3][(j + 2) % 3] - X[(i + 1) % 3][(j + 2) % 3] * X[(i + 2) % 3][(j + 1) % 3];
        for (int i = 0; i < 3; ++i) for (int j = 0; j < 3; ++j) X[i][j] = 0.5 * (X[i][j] + cof[i][j] / d);  // (R + R^-T) / 2
    }
    real worst = 0, sum = 0;
    for (std::size_t k = 0; k < nodes.size(); ++k) {
        const Vec3 p = ref[k] - rc;
        const Vec3 fit{X[0][0] * p.x + X[0][1] * p.y + X[0][2] * p.z, X[1][0] * p.x + X[1][1] * p.y + X[1][2] * p.z,
                       X[2][0] * p.x + X[2][1] * p.y + X[2][2] * p.z};
        const real e = length(car.positions()[nodes[k]] - cc - fit);
        worst = std::max(worst, e);
        sum += e * e;
    }
    return {worst, std::sqrt(sum / nodes.size())};
}

TEST_CASE("body shell stays rigid while driving instead of wobbling like jelly") {
    // Unbraced cabin rings let the belt rail swing sideways: up to 92 mm on the Kestrel in a
    // 100 km/h steering step, visible as wobbling body sides and windows.
    for (const char* id : {"kestrel_hatch", "meridian_sedan"}) {
        CAPTURE(id);
        CarBuild cb = buildCar(loadCarDefinition(carPath(id)));
        const auto layout = cb.layout;
        World w = flatWorld();
        w.addBody(std::move(cb.body));
        auto& car = w.body(0);
        VehicleControls controls;
        controls.gear = -99;
        car.setControls(controls);
        w.simulate(2.0);
        std::vector<Vec3> ref;
        for (auto n : layout.bodyNodes) ref.push_back(car.positions()[n]);
        controls.throttle = 0.6;
        car.setControls(controls);
        while (car.telemetry().speedKmh < 100.0 && w.stats().time < 30.0) w.simulate(0.1);
        controls.throttle = 0.25;
        real worst = 0, rms = 0;
        for (int i = 0; i < 400; ++i) {
            controls.steer = i < 150 ? 0.04 : 0.05 * std::sin(i * 0.01 * 2.0 * 3.14159265358979 * 0.6);
            car.setControls(controls);
            w.simulate(0.01);
            const auto [maxDev, rmsDev] = bodyDeviation(car, layout.bodyNodes, ref);
            worst = std::max(worst, maxDev);
            rms = std::max(rms, rmsDev);
        }
        CHECK(worst < 0.030);
        CHECK(rms < 0.006);
        CHECK(car.stats().brokenBeams == 0);
    }
}

TEST_CASE("staggered tyres keep grip at top speed and the Concept GT runs straight beyond 320 km/h") {
    // The narrow fronts used to carry the rear tyre mass: less membrane tension per tread mass,
    // so their standing wave arrived near 320 km/h. Front grip faded, the car swung into a
    // self-sustained 0.5 g circle with up to 36 deg of yaw on a straight road.
    const auto def = loadCarDefinition(carPath("concept_gt"));
    CHECK(def.tires.massFor(true) < def.tires.massFor(false));
    CHECK(def.tires.massFor(false) == doctest::Approx(def.tires.tireMass));
    CarBuild cb = buildCar(def);
    const auto layout = cb.layout;
    World w = flatWorld();
    w.addBody(std::move(cb.body));
    auto& car = w.body(0);
    VehicleControls controls;
    controls.gear = -99;
    car.setControls(controls);
    w.simulate(2.0);
    controls.throttle = 1.0;
    car.setControls(controls);
    real worstYaw = 0.0, peak = 0.0;
    for (int i = 0; i < 60; ++i) {
        w.simulate(1.0);
        const auto& p = car.positions();
        const Vec3 forward = normalize(p[layout.refFL] + p[layout.refFR] - p[layout.refRL] - p[layout.refRR]);
        worstYaw = std::max(worstYaw, std::abs(std::atan2(forward.z, forward.x)) * 180.0 / 3.14159265358979);
        peak = std::max(peak, car.telemetry().speedKmh);
    }
    CHECK(peak > 320.0);
    CHECK(worstYaw < 4.0);
    CHECK(std::abs(car.centerOfMass().z) < 150.0);
    CHECK(w.stats().finite);
}

TEST_CASE("cars settle onto their tyres without body sag, toe-out or brake chatter") {
    // The body used to sink ~5 cm around soft strut-tower mounts (front toe-out up to 1.8 deg), and
    // a held brake that fought body pitch rocked a parked Concept GT with ~4 kJ.
    for (const char* id : {"kestrel_hatch", "vortex_gt", "basalt_suv", "concept_gt"}) {
        CAPTURE(id);
        CarBuild cb = buildCar(loadCarDefinition(carPath(id)));
        const auto layout = cb.layout;
        World w = flatWorld();
        w.addBody(std::move(cb.body));
        auto& car = w.body(0);
        const real designFloor = car.positions()[layout.refFL].y;
        VehicleControls controls;
        controls.brake = 1.0;
        car.setControls(controls);
        w.simulate(4.0);
        CHECK(designFloor - car.positions()[layout.refFL].y < 0.035);
        const auto& p = car.positions();
        const Vec3 forward = normalize(p[layout.refFL] + p[layout.refFR] - p[layout.refRL] - p[layout.refRR]);
        for (const auto& wheel : car.wheels())
            if (wheel.spec.steered) CHECK(std::abs(std::asin(dot(wheel.axis(car), forward))) * 180.0 / 3.14159265358979 < 0.6);
        real energy = 0.0;
        for (int i = 0; i < 20; ++i) {
            w.simulate(0.05);
            energy = std::max(energy, car.kineticEnergy());
        }
        CHECK(energy < 100.0);
        CHECK(car.stats().deformedBeams == 0);
    }
}

TEST_CASE("tyre tread has no standing-wave resonance below autobahn top speeds") {
    // Without the inflated-membrane hoop tension the tread ring's wave speed was ~40 m/s and the
    // rolling loss peaked near 145 km/h (~1800 N without air).
    CarBuild cb = buildCar(loadCarDefinition(carPath("kestrel_hatch")));
    WorldSettings settings;
    settings.airDensity = 0.0;
    World w(settings);
    w.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}, 1.0));
    w.addBody(std::move(cb.body));
    auto& car = w.body(0);
    VehicleControls controls;
    controls.gear = 0;
    car.setControls(controls);
    w.simulate(2.0);
    const real v = 145.0 / 3.6;
    car.setVelocity({v, 0, 0});
    for (const auto& wheel : car.wheels()) {
        const auto center = wheel.center(car), axis = wheel.axis(car);
        for (auto node : wheel.treadNodes)
            car.velocities()[node] += cross(axis, car.positions()[node] - center) * (v / wheel.spec.radius);
    }
    real tow = 0.0;
    int samples = 0;
    for (int s = 0; s < 8000; ++s) {
        const real dv = v - car.centerOfMassVelocity().x;
        car.addVelocity({dv, 0, 0});
        if (s >= 3000) { tow += dv; ++samples; }
        w.step();
    }
    const real force = car.totalMass() * tow / (samples * settings.dt);
    CHECK(force > 100.0);
    CHECK(force < 800.0);
    CHECK(w.stats().finite);
}

TEST_CASE("tail-heavy Concept GT on staggered tyres settles into steady cornering at 150 km/h") {
    CarBuild cb = buildCar(loadCarDefinition(carPath("concept_gt")));
    CHECK(cb.def.tires.rearWidth() > cb.def.tires.width);
    const auto layout = cb.layout;
    World w = flatWorld();
    w.addBody(std::move(cb.body));
    auto& car = w.body(0);
    VehicleControls controls;
    controls.gear = 0;
    car.setControls(controls);
    w.simulate(2.0);
    const real v = 150.0 / 3.6;
    car.setVelocity({v, 0, 0});
    for (const auto& wheel : car.wheels()) {
        const auto center = wheel.center(car), axis = wheel.axis(car);
        for (auto node : wheel.treadNodes)
            car.velocities()[node] += cross(axis, car.positions()[node] - center) * (v / wheel.spec.radius);
    }
    controls.steer = 0.012;
    car.setControls(controls);
    auto heading = [&] {
        const auto& p = car.positions();
        const Vec3 f = normalize(p[layout.refFL] + p[layout.refFR] - p[layout.refRL] - p[layout.refRR]);
        return std::atan2(f.z, f.x);
    };
    auto yawRateOver = [&](real seconds) {
        const real h0 = heading();
        for (int s = 0; s < static_cast<int>(seconds * 2000.0); ++s) {
            const Vec3 vc = car.centerOfMassVelocity();
            const real speed = std::sqrt(vc.x * vc.x + vc.z * vc.z);
            car.addVelocity(vc * ((v - speed) / std::max<real>(speed, 1.0)));
            w.step();
        }
        return (heading() - h0) / seconds;
    };
    yawRateOver(2.0);
    const real early = std::abs(yawRateOver(0.5));
    yawRateOver(0.5);
    const real late = std::abs(yawRateOver(0.5));
    CHECK(early > 0.02);
    CHECK(late < early * 1.15);  // converging, not an oversteer divergence
    CHECK(late * v < 0.6 * 9.81);
}

TEST_CASE("automatic cars pull away with a gentle throttle and stop fully under the brake") {
    for (const char* id : {"kestrel_hatch", "basalt_suv"}) {
        CAPTURE(id);
        CarBuild cb = buildCar(loadCarDefinition(carPath(id)));
        World w = flatWorld();
        w.addBody(std::move(cb.body));
        auto& car = w.body(0);
        VehicleControls controls;
        controls.gear = -99;
        car.setControls(controls);
        w.simulate(1.5);
        const Vec3 start = car.centerOfMass();
        controls.throttle = 0.25;
        car.setControls(controls);
        w.simulate(5.0);
        CHECK(car.powertrain().running());
        CHECK(length(car.centerOfMass() - start) > 3.0);
        controls.throttle = 0.0;
        controls.brake = 1.0;
        car.setControls(controls);
        w.simulate(4.0);
        CHECK(car.telemetry().speedKmh < 0.5);
        real worstSpin = 0.0;
        for (const auto& wheel : car.wheels()) worstSpin = std::max(worstSpin, std::abs(wheel.angularVelocity));
        CHECK(worstSpin < 0.3);  // a held brake does not chatter
    }
}

TEST_CASE("panels on their own rigid frame keep their shape when they swing open or come off") {
    // Imported panels are bound to their part's nodes; linear blending of node displacements
    // stretched a door or bonnet swinging through 60 degrees. Each separate part now carries its
    // vertices on a best-fit rigid frame of its own nodes.
    CarBuild cb = buildCar(loadCarDefinition(carPath("kestrel_hatch")));
    const CarVisual& vis = cb.visual;
    REQUIRE(vis.parts.size() >= 3);
    const auto& door = cb.layout.frontDoors[0].nodes;
    REQUIRE(door.size() == 8);
    // A door skin like the importer builds it: points spread over and beyond the cage.
    Vec3 lo{1e9, 1e9, 1e9}, hi{-1e9, -1e9, -1e9};
    for (auto n : door) {
        lo = Vec3{std::min(lo.x, vis.restNodes[n].x), std::min(lo.y, vis.restNodes[n].y), std::min(lo.z, vis.restNodes[n].z)};
        hi = Vec3{std::max(hi.x, vis.restNodes[n].x), std::max(hi.y, vis.restNodes[n].y), std::max(hi.z, vis.restNodes[n].z)};
    }
    MeshSurface surf;
    for (int ix = -1; ix <= 5; ++ix)
        for (int iy = -1; iy <= 5; ++iy) {
            const Vec3 p{lo.x + (hi.x - lo.x) * ix / 4.0, lo.y + (hi.y - lo.y) * iy / 4.0, lo.z - 0.02};
            surf.positions.insert(surf.positions.end(), {static_cast<float>(p.x), static_cast<float>(p.y), static_cast<float>(p.z)});
            surf.skin.push_back(bindToNodes(vis.restNodes, door, p));
        }
    tagRigidPartVertices(vis, surf);
    for (const auto& sk : surf.skin) REQUIRE(sk.part >= 0);
    // Swing the door cage 60 degrees about a vertical hinge at its front edge and lift it 5 cm.
    std::vector<Vec3> pos = vis.restNodes;
    const Vec3 hinge{hi.x, 0.0, lo.z};
    const real a = 60.0 * 3.14159265358979 / 180.0;
    auto swing = [&](const Vec3& q) {
        const Vec3 r = q - hinge;
        return hinge + Vec3{r.x * std::cos(a) - r.z * std::sin(a), r.y + 0.05, r.x * std::sin(a) + r.z * std::cos(a)};
    };
    for (auto n : door) pos[n] = swing(pos[n]);
    std::vector<float> frames;
    computeNodeFrames(pos, vis, frames);
    computeNodeFrames(pos, vis, frames);  // warm-started second evaluation must agree
    real worst = 0.0;
    for (std::size_t i = 0; i < surf.skin.size(); ++i) {
        const Vec3 rest{surf.positions[i * 3], surf.positions[i * 3 + 1], surf.positions[i * 3 + 2]};
        worst = std::max(worst, length(evalSkin(pos, frames, surf.skin[i]) - swing(rest)));
    }
    CHECK(worst < 0.002);
}

TEST_CASE("a money shift into 1st at speed blows the engine and hurts gearbox and clutch; a sane downshift does not") {
    auto shiftAt = [](real kmh, int gear) {
        auto build = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
        World world;
        world.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}));
        world.addBody(std::move(build.body));
        auto& car = world.body(0);
        VehicleControls c;
        c.throttle = 1.0;
        car.setControls(c);
        while (car.telemetry().speedKmh < kmh && world.time() < 60.0) world.simulate(0.1);
        car.powertrain().setAutomatic(false);
        c = {};
        c.gear = gear;
        car.setControls(c);
        world.simulate(0.05);
        c.gear = -99;
        car.setControls(c);
        world.simulate(2.0);
        REQUIRE(world.stats().finite);
        return std::make_pair(car.telemetry(), car.systems().state());
    };
    const auto [moneyTel, money] = shiftAt(150.0, 1);
    CHECK(money.rodBroken);
    CHECK(money.seized);
    CHECK(money.status == "ENGINE BLOWN");
    CHECK(money.peakOverRev > 1.6);
    CHECK(moneyTel.gearboxDamage > 0.4);
    CHECK(moneyTel.clutchWear > 0.05);
    const auto [saneTel, sane] = shiftAt(130.0, 3);
    CHECK_FALSE(sane.valvesBent);
    CHECK(sane.overRevDamage < 0.01);
    CHECK(saneTel.gearboxDamage < 0.05);
    CHECK(sane.running);
}

TEST_CASE("an engine run without oil knocks first and then throws a rod") {
    auto build = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
    World world;
    world.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}));
    world.addBody(std::move(build.body));
    auto& car = world.body(0);
    VehicleControls c;
    c.throttle = 0.6;
    car.setControls(c);
    world.simulate(3.0);
    car.systems().state().oilLevel = 0.05;   // sump drained
    real firstKnock = -1.0, blown = -1.0;
    for (int k = 0; k < 900 && blown < 0.0; ++k) {
        world.simulate(0.1);
        const auto& s = car.systems().state();
        if (firstKnock < 0.0 && s.knock > 0.05) firstKnock = 0.1 * k;
        if (s.seized) blown = 0.1 * k;
    }
    MESSAGE("knock after " << firstKnock << " s, engine dead after " << blown << " s");
    CHECK(firstKnock > 2.0);
    CHECK(blown > firstKnock + 5.0);
    CHECK(blown < 90.0);
}

TEST_CASE("low oil and hard cornering starve the oil pump; a full sump does not") {
    auto circle = [](real oilLevel) {
        auto build = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
        World world;
        world.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}));
        world.addBody(std::move(build.body));
        auto& car = world.body(0);
        VehicleControls c;
        c.throttle = 1.0;
        car.setControls(c);
        while (car.telemetry().speedKmh < 70.0 && world.time() < 30.0) world.simulate(0.1);
        car.systems().state().oilLevel = oilLevel;
        c.throttle = 0.45;
        c.steer = 0.45;
        car.setControls(c);
        real starved = 0.0, peakG = 0.0;
        for (int k = 0; k < 80; ++k) {
            world.simulate(0.05);
            peakG = std::max(peakG, car.systems().state().horizontalG);
            if (car.systems().state().oilStarved) starved += 0.05;
        }
        MESSAGE("oil " << oilLevel << ": peak " << peakG << " g, starved " << starved << " s, pressure "
                << car.systems().state().oilPressureBar << " bar");
        return starved;
    };
    CHECK(circle(1.0) == doctest::Approx(0.0));
    CHECK(circle(0.38) > 0.5);
}

TEST_CASE("oil on a hot engine can catch fire; a healthy hot engine does not") {
    auto run = [](bool leaking) {
        auto build = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
        World world;
        world.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}));
        world.addBody(std::move(build.body));
        auto& car = world.body(0);
        VehicleControls c;
        c.brake = 1.0;
        car.setControls(c);
        real ignited = -1.0;
        // Hot but intact: 60 s (well before 150 degC oil wipes the rod bearings and throws a rod).
        for (int k = 0; k < (leaking ? 2400 : 600) && ignited < 0.0; ++k) {
            auto& s = car.systems().state();
            s.oilTempC = 150.0;
            if (leaking) { s.oilPanDamage = 0.5; s.oilLevel = 1.0; }
            world.simulate(0.1);
            if (car.systems().state().fire > 0.0) ignited = 0.1 * k;
        }
        if (ignited >= 0.0) world.simulate(20.0);
        return std::make_pair(ignited, car.systems().state());
    };
    const auto [healthyAt, healthy] = run(false);
    CHECK(healthyAt < 0.0);
    CHECK(healthy.fire == 0.0);
    const auto [leakAt, burning] = run(true);
    MESSAGE("oil-soaked hot engine ignited after " << leakAt << " s; 20 s later fire " << burning.fire << ", running " << burning.running);
    CHECK(leakAt >= 0.0);
    CHECK(burning.fire > 0.5);
    CHECK_FALSE(burning.running);
    CHECK(burning.status == "ENGINE FIRE");
}
