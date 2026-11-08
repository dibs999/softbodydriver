// Physics core unit tests (doctest).
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <cmath>

#include "sbcore/sbcore.hpp"

using namespace sb;

namespace {

constexpr real kPi = 3.14159265358979323846;

/// Two nodes, one fixed, connected by a beam, gravity off.
World springPair(const BeamParams& bp, real mass, real length = 1.0) {
    WorldSettings ws;
    ws.gravity = {0, 0, 0};
    World w(ws);
    SoftBody b("pair");
    NodeParams fixed;
    fixed.fixed = true;
    NodeParams free;
    free.mass = mass;
    b.addNode("a", {0, 0, 0}, fixed);
    b.addNode("b", {length, 0, 0}, free);
    b.addBeam("a", "b", bp);
    w.addBody(std::move(b));
    return w;
}

LatticeSpec smallCube() {
    LatticeSpec s;
    s.cellsX = s.cellsY = s.cellsZ = 3;
    s.cellSize = {0.25, 0.25, 0.25};
    s.totalMass = 100;
    s.edge.spring = 3e5;
    s.faceDiagonal.spring = 2e5;
    s.bodyDiagonal.spring = 1.5e5;
    for (BeamParams* p : {&s.edge, &s.faceDiagonal, &s.bodyDiagonal}) p->damp = 60;
    return s;
}

}  // namespace

TEST_CASE("free fall matches analytic solution") {
    World w;
    SoftBody b;
    b.addNode("n", {0, 10, 0});
    w.addBody(std::move(b));
    w.simulate(1.0);
    const real y = w.body(0).positions()[0].y;
    // Symplectic Euler error is O(dt); 0.5 * g * t^2 = 4.905 m
    CHECK(y == doctest::Approx(10.0 - 4.905).epsilon(0.001));
}

TEST_CASE("spring-mass oscillates with the analytic period") {
    BeamParams bp;
    bp.spring = 1.0e4;
    bp.damp = 0;
    const real m = 2.0;
    World w = springPair(bp, m);
    w.body(0).positions()[1].x = 1.1;  // stretch 10 cm

    // Measure time between successive maxima of x.
    real prev = 1.1, prevPrev = 1.1;
    std::vector<real> peaks;
    for (int i = 0; i < 4000 && peaks.size() < 3; ++i) {
        w.step();
        const real x = w.body(0).positions()[1].x;
        if (prev > prevPrev && prev >= x) peaks.push_back(w.time() - w.settings().dt);
        prevPrev = prev;
        prev = x;
    }
    REQUIRE(peaks.size() >= 2);
    const real period = peaks[1] - peaks[0];
    CHECK(period == doctest::Approx(2 * kPi * std::sqrt(m / bp.spring)).epsilon(0.01));
}

TEST_CASE("damping dissipates energy") {
    BeamParams bp;
    bp.spring = 1.0e4;
    bp.damp = 20;
    World w = springPair(bp, 2.0);
    w.body(0).positions()[1].x = 1.1;
    const real e0 = w.body(0).elasticEnergy();
    w.simulate(2.0);
    const real e1 = w.body(0).elasticEnergy() + w.body(0).kineticEnergy();
    CHECK(e1 < 0.05 * e0);
}

TEST_CASE("elastic load below deform threshold leaves no permanent deformation") {
    BeamParams bp;
    bp.spring = 1.0e5;
    bp.damp = 50;
    bp.deform = 5000;  // 5 cm of stretch
    World w = springPair(bp, 1.0);
    w.body(0).positions()[1].x = 1.03;  // 3000 N
    w.simulate(1.0);
    const Beam& beam = w.body(0).beams()[0];
    CHECK(beam.restLength == doctest::Approx(1.0));
    CHECK(w.body(0).stats().deformedBeams == 0);
}

TEST_CASE("load above deform threshold deforms permanently") {
    BeamParams bp;
    bp.spring = 1.0e5;
    bp.damp = 50;
    bp.deform = 5000;
    World w = springPair(bp, 1.0);
    w.body(0).positions()[1].x = 1.2;  // 20000 N >> 5000 N
    w.simulate(1.0);
    const Beam& beam = w.body(0).beams()[0];
    CHECK(beam.restLength > 1.1);
    CHECK(w.body(0).stats().deformedBeams == 1);
    // After settling the node rests at the new rest length.
    CHECK(w.body(0).positions()[1].x == doctest::Approx(beam.restLength).epsilon(0.001));
}

TEST_CASE("deform limit caps plastic deformation") {
    BeamParams bp;
    bp.spring = 1.0e5;
    bp.damp = 50;
    bp.deform = 1000;
    bp.deformLimitExpansion = 0.05;
    World w = springPair(bp, 1.0);
    w.body(0).positions()[1].x = 1.5;
    w.step();
    CHECK(w.body(0).beams()[0].restLength == doctest::Approx(1.05));
}

TEST_CASE("beam breaks above strength and takes its break group along") {
    WorldSettings ws;
    ws.gravity = {0, 0, 0};
    World w(ws);
    SoftBody b;
    NodeParams fixed;
    fixed.fixed = true;
    b.addNode("a", {0, 0, 0}, fixed);
    b.addNode("b", {1, 0, 0});
    b.addNode("c", {0, 1, 0}, fixed);
    b.addNode("d", {1, 1, 0});
    BeamParams weak;
    weak.spring = 1e5;
    weak.strength = 1000;
    weak.breakGroup = "door";
    BeamParams strong = weak;
    strong.strength = kInf;
    b.addBeam("a", "b", weak);
    b.addBeam("c", "d", strong);  // unbreakable itself, but in the same group
    BeamParams other;
    other.spring = 1e5;
    b.addBeam("b", "d", other);   // not in the group
    w.addBody(std::move(b));
    w.body(0).positions()[1].x = 1.1;  // 10 kN on the weak beam
    w.step();
    const auto& beams = w.body(0).beams();
    CHECK(beams[0].broken);
    CHECK(beams[1].broken);
    CHECK_FALSE(beams[2].broken);
}

TEST_CASE("support beams only resist compression") {
    BeamParams bp;
    bp.type = BeamType::Support;
    bp.spring = 1e5;
    bp.damp = 0;
    World w = springPair(bp, 1.0);
    w.body(0).positions()[1].x = 1.1;
    w.step();
    CHECK(w.body(0).beams()[0].lastForce == 0.0);
    CHECK(w.body(0).velocities()[1].x == 0.0);
    w.body(0).positions()[1].x = 0.9;
    w.step();
    CHECK(w.body(0).beams()[0].lastForce < 0.0);
    CHECK(w.body(0).velocities()[1].x > 0.0);  // pushed back out
}

TEST_CASE("anisotropic beams use expansion stiffness when stretched") {
    BeamParams bp;
    bp.type = BeamType::Anisotropic;
    bp.spring = 1e4;
    bp.springExpansion = 1e5;
    bp.damp = 0;
    World w = springPair(bp, 1.0);
    w.body(0).positions()[1].x = 1.01;
    w.step();
    CHECK(w.body(0).beams()[0].lastForce == doctest::Approx(1000.0).epsilon(0.01));
    w.body(0).positions()[1].x = 0.99;
    w.body(0).velocities()[1] = {};
    w.step();
    CHECK(w.body(0).beams()[0].lastForce == doctest::Approx(-100.0).epsilon(0.02));
}

TEST_CASE("hydro beams follow their input channel") {
    BeamParams bp;
    bp.type = BeamType::Hydro;
    bp.spring = 1e5;
    bp.damp = 200;
    bp.hydroInput = 0;
    bp.hydroRatio = 0.2;
    World w = springPair(bp, 1.0);
    w.body(0).setInput(0, 1.0);
    w.simulate(1.0);
    CHECK(w.body(0).positions()[1].x == doctest::Approx(1.2).epsilon(0.001));
    w.body(0).setInput(0, -0.5);
    w.simulate(1.0);
    CHECK(w.body(0).positions()[1].x == doctest::Approx(0.9).epsilon(0.001));
}

TEST_CASE("lattice builder produces expected topology") {
    LatticeSpec s;
    s.cellsX = 2;
    s.cellsY = 1;
    s.cellsZ = 1;
    const SoftBody b = buildLattice(s);
    CHECK(b.nodeCount() == 12);
    // edges: 3*2*2 + 2*3*2 + 2*2*3 = 12+12+... computed: x-edges 2*2*2=8, y-edges 3*2=6, z-edges 3*2=6 -> 20
    // face diagonals: 2 per face; faces: x-normal 3, y-normal 2*2, z-normal 2*2 -> 11 faces -> 22
    // body diagonals: 4 per cell -> 8
    CHECK(b.beamCount() == 20 + 22 + 8);
}

TEST_CASE("a dropped lattice cube comes to rest on the ground without exploding") {
    World w;
    w.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}, 0.8));
    LatticeSpec s = smallCube();
    SoftBody cube = buildLattice(s);
    cube.translate({0, 1.0, 0});
    w.addBody(std::move(cube));
    CHECK(w.worstStabilityRatio() < 0.8);
    w.simulate(3.0);
    const WorldStats st = w.stats();
    CHECK(st.finite);
    CHECK(st.kineticEnergy < 1.0);
    Vec3 lo, hi;
    w.body(0).aabb(lo, hi);
    CHECK(lo.y > -0.01);
    CHECK(lo.y < 0.01);
    CHECK(hi.y == doctest::Approx(0.75).epsilon(0.03));
}

TEST_CASE("friction: block sticks on a gentle slope and slides on ice") {
    auto run = [](real friction) {
        World w;
        const real angle = 20.0 * kPi / 180.0;  // tan(20deg) = 0.36
        w.addCollider(StaticCollider::plane({0, 0, 0}, {-std::sin(angle), std::cos(angle), 0}, friction));
        LatticeSpec s = smallCube();
        s.node.friction = 1.0;
        SoftBody cube = buildLattice(s);
        rotateBody(cube, Mat3::fromEuler(0, 0, angle), {0, 0, 0});
        cube.translate({0, 0.02, 0});
        w.addBody(std::move(cube));
        w.simulate(2.0);
        return length(w.body(0).centerOfMass() - Vec3{0, 0, 0});
    };
    const real sticky = run(0.8);
    const real icy = run(0.1);
    CHECK(sticky < 1.0);
    CHECK(icy > 3.0);
}

TEST_CASE("oriented box collider pushes nodes out along the shallowest axis") {
    const auto box = StaticCollider::box({0, 0, 0}, {1, 0.5, 1});
    Vec3 n;
    real d;
    REQUIRE(box.contact({0.2, 0.4, 0.1}, n, d));
    CHECK(n.y == doctest::Approx(1.0));
    CHECK(d == doctest::Approx(0.1));
    CHECK_FALSE(box.contact({0, 0.6, 0}, n, d));
}

TEST_CASE("simulation is deterministic") {
    auto run = []() {
        Scene sc = makeScene("cube_drop");
        sc.run(1.0);
        return sc.world.body(0).positions();
    };
    const auto a = run();
    const auto b = run();
    REQUIRE(a.size() == b.size());
    bool same = true;
    for (std::size_t i = 0; i < a.size(); ++i)
        same &= a[i].x == b[i].x && a[i].y == b[i].y && a[i].z == b[i].z;
    CHECK(same);
}

TEST_CASE("sbeam JSON round trip preserves topology and parameters") {
    const char* text = R"({
      "format": "sbeam", "version": 1, "name": "tri",
      // comments are allowed
      "nodes": [
        {"set": {"mass": 2.5, "friction": 0.7}},
        ["a", 0, 0, 0],
        ["b", 1, 0, 0],
        ["c", 0, 1, 0, {"fixed": true}]
      ],
      "beams": [
        {"set": {"spring": 5e5, "damp": 80, "deform": 1.5e4, "strength": "inf"}},
        ["a", "b"],
        ["b", "c", {"type": "support", "breakGroup": "g1"}],
        {"set": {"type": "anisotropic", "springExpansion": 1e6}},
        ["c", "a"]
      ]
    })";
    const SoftBody b = parseSBeam(text);
    CHECK(b.name() == "tri");
    CHECK(b.nodeCount() == 3);
    CHECK(b.beamCount() == 3);
    CHECK(b.masses()[0] == doctest::Approx(2.5));
    CHECK(b.isFixed(2));
    CHECK(b.beams()[1].type == BeamType::Support);
    CHECK(b.beams()[2].type == BeamType::Anisotropic);
    CHECK(b.beams()[2].springExp == doctest::Approx(1e6));
    CHECK(std::isinf(b.beams()[0].strength));

    const SoftBody b2 = parseSBeam(serializeSBeam(b));
    REQUIRE(b2.nodeCount() == b.nodeCount());
    REQUIRE(b2.beamCount() == b.beamCount());
    for (std::size_t i = 0; i < b.beamCount(); ++i) {
        CHECK(b2.beams()[i].a == b.beams()[i].a);
        CHECK(b2.beams()[i].spring == doctest::Approx(b.beams()[i].spring));
        CHECK(b2.beams()[i].deformThreshold == doctest::Approx(b.beams()[i].deformThreshold));
        CHECK(b2.beams()[i].type == b.beams()[i].type);
        CHECK(b2.beams()[i].params.breakGroup == b.beams()[i].params.breakGroup);
    }
    CHECK(b2.isFixed(2));
}

TEST_CASE("sbeam parser reports helpful errors") {
    CHECK_THROWS_WITH_AS(parseSBeam(R"({"nodes":[["a",0,0,0]],"beams":[["a","x"]]})"),
                         doctest::Contains("unknown node: x"), std::runtime_error);
    CHECK_THROWS_WITH_AS(parseSBeam(R"({"nodes":[["a",0,0,0],["b",1,0,0]],"beams":[["a","b",{"sprnig":1}]]})"),
                         doctest::Contains("unknown beam property 'sprnig'"), std::runtime_error);
}

TEST_CASE("all built-in scenes are stable") {
    for (const auto& name : sceneNames()) {
        CAPTURE(name);
        Scene sc = makeScene(name);
        CHECK(sc.world.worstStabilityRatio() < 0.9);
        sc.run(sc.duration);
        const WorldStats st = sc.world.stats();
        CHECK(st.finite);
        if (name != "slalom" && name != "accel_brake") {
            CHECK(st.deformedBeams + st.brokenBeams > 0);
        }
    }
}

TEST_CASE("wall crash: front crumples much more than the cabin") {
    Scene sc = makeScene("wall_crash");
    sc.run(1.5);
    const SoftBody& car = sc.world.body(0);
    std::size_t front = 0, frontTotal = 0, cabin = 0, cabinTotal = 0;
    const real carFrontX = 14 * 0.3;
    for (const Beam& bm : car.beams()) {
        const auto& ida = car.nodeIds()[bm.a];
        int i = 0, j = 0, k = 0;
        std::sscanf(ida.c_str(), "n_%d_%d_%d", &i, &j, &k);
        const real x = i * 0.3, y = j * 0.3;
        const bool deformed = bm.broken || std::abs(bm.restLength - bm.baseRestLength) > 1e-3 * bm.baseRestLength;
        if (x > carFrontX - 1.0) { ++frontTotal; front += deformed; }
        else if (y > 0.65 && x > 1.5 && x < 3.0) { ++cabinTotal; cabin += deformed; }
    }
    REQUIRE(frontTotal > 0);
    REQUIRE(cabinTotal > 0);
    const double frontRatio = static_cast<double>(front) / static_cast<double>(frontTotal);
    const double cabinRatio = static_cast<double>(cabin) / static_cast<double>(cabinTotal);
    MESSAGE("front deformed ratio " << frontRatio << ", cabin deformed ratio " << cabinRatio);
    CHECK(frontRatio > 0.3);
    CHECK(cabinRatio < frontRatio * 0.5);
    CHECK(length(car.velocities()[0]) < 3.0);
}

TEST_CASE("pressure wheel spins freely around its spindle and brakes to a stop") {
    WorldSettings ws;
    ws.gravity = {0, 0, 0};
    World w(ws);
    SoftBody b("wheel_rig");
    NodeParams fixed;
    fixed.fixed = true;
    const auto hr = b.addNode("hr", {0, 0,  0.11}, fixed);
    const auto hl = b.addNode("hl", {0, 0, -0.11}, fixed);

    PressureWheelSpec pws;
    pws.name = "W";
    pws.hubRight = hr;
    pws.hubLeft = hl;
    pws.driven = true;
    pws.braked = true;
    b.addWheel(pws);
    w.addBody(std::move(b));

    // Apply 200 Nm of drive torque for 0.5 s directly via PressureWheel::step
    for (int i = 0; i < 1000; ++i) {
        SoftBody& body = w.body(0);
        for (auto& f : body.forces()) f = {};
        body.accumulateBeamForces(ws.dt);
        body.wheels()[0].step(body, 200.0, 0.0, ws.dt);
        for (std::size_t n = 0; n < body.nodeCount(); ++n) {
            if (body.invMasses()[n] == 0) continue;
            body.velocities()[n] += body.forces()[n] * (body.invMasses()[n] * ws.dt);
            body.positions()[n] += body.velocities()[n] * ws.dt;
        }
    }
    const real omegaSpin = w.body(0).wheels()[0].measureAngularVelocity(w.body(0));
    CHECK(omegaSpin > 40.0);
    // Spinning a wheel around its spindle must not plastically deform any spoke/tread beam.
    CHECK(w.body(0).stats().deformedBeams == 0);

    // Now brake with 500 Nm for 0.5 s -> wheel stops without reversing.
    for (int i = 0; i < 1000; ++i) {
        SoftBody& body = w.body(0);
        for (auto& f : body.forces()) f = {};
        body.accumulateBeamForces(ws.dt);
        body.wheels()[0].step(body, 0.0, 500.0, ws.dt);
        for (std::size_t n = 0; n < body.nodeCount(); ++n) {
            if (body.invMasses()[n] == 0) continue;
            body.velocities()[n] += body.forces()[n] * (body.invMasses()[n] * ws.dt);
            body.positions()[n] += body.velocities()[n] * ws.dt;
        }
    }
    CHECK( std::abs(w.body(0).wheels()[0].measureAngularVelocity(w.body(0))) < 0.5 );

    // Breaking a wheel beam punctures the tire.
    w.body(0).breakBeam(w.body(0).wheels()[0].beamIndices[0]);
    w.step();
    CHECK(w.body(0).wheels()[0].burst);
}

TEST_CASE("drivable car accelerates, shifts into 2nd gear, and stops under braking") {
    Scene sc = makeScene("accel_brake");
    sc.run(3.55);
    const VehicleTelemetry peak = sc.world.body(0).telemetry();
    CHECK(peak.speedKmh > 45.0);
    CHECK(peak.gear >= 2);
    CHECK(sc.world.body(0).centerOfMass().x > 18.0);

    sc.run(1.65);
    const VehicleTelemetry stopped = sc.world.body(0).telemetry();
    CHECK(stopped.speedKmh < 1.5);
    CHECK(stopped.engineRpm > 600.0);  // engine idles without stalling
}

TEST_CASE("hydro steering turns the drivable car left (+steer) and right (-steer)") {
    auto driveWithSteer = [](real steerVal) {
        World w;
        w.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}, 1.0));
        SoftBody car = buildDrivableCar();
        car.translate({0, 0.01, 0});
        VehicleControls c;
        c.throttle = 0.75;
        c.steer = steerVal;
        car.setControls(c);
        w.addBody(std::move(car));
        w.simulate(2.2);
        return w.body(0).centerOfMass().z;
    };
    const real zLeft = driveWithSteer(+0.85);   // +steer -> left (-Z)
    const real zRight = driveWithSteer(-0.85);  // -steer -> right (+Z)
    CHECK(zLeft < -1.0);
    CHECK(zRight > +1.0);
}

TEST_CASE("drivable car round-trips through sbeam JSON with wheels and powertrain") {
    const SoftBody car = buildDrivableCar();
    const std::string jsonText = serializeSBeam(car);
    const SoftBody car2 = parseSBeam(jsonText);
    CHECK(car2.nodeCount() == car.nodeCount());
    CHECK(car2.beamCount() == car.beamCount());
    CHECK(car2.wheels().size() == 4);
    CHECK(car2.hasPowertrain());
}

TEST_CASE("C ABI spawns drivable car and advances telemetry") {
    sb_world_t* w = sb_world_create(1.0 / 2000.0);
    sb_world_add_ground_plane(w, 1.0);
    const int32_t car = sb_world_spawn_drivable_car(w, 0.0, 0.01, 0.0);
    REQUIRE(car == 0);
    sb_body_set_controls(w, car, 1.0, 0.0, 0.0, 0.0, -99);
    sb_world_step(w, 2000);
    sb_telemetry_c tel{};
    sb_body_get_telemetry(w, car, &tel);
    CHECK(tel.speed_kmh > 10.0);
    CHECK(tel.engine_rpm > 1000.0);
    CHECK(sb_body_node_count(w, car) > 300);
    sb_world_destroy(w);
}

