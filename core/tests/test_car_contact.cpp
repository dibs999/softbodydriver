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

TEST_CASE("two cars pressed into each other settle instead of pumping energy into their beams") {
    // After a crash two cars can stay interlocked with nodes deep inside each other. Pushing such a
    // node out by 2 cm every step against both sets of beams fed energy in: two wrecks locked
    // together gained ~1.5 MJ in ten seconds with no engine running and finally flew apart at
    // 320 km/h. Here a parked saloon's nose is set 20 cm into the flank of a parked hatch (before:
    // 26 kJ peak, still 9 kJ after 3 s, parts thrown 13 m apart).
    auto carA = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
    auto carB = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/meridian_sedan.car.json"));
    Vec3 lo, hi, blo, bhi;
    carA.body.aabb(lo, hi);
    for (auto& p : carB.body.positions()) p = {p.z, p.y, -p.x};   // nose (+x) turned towards -z
    carB.body.aabb(blo, bhi);
    carB.body.translate({0.5 * (lo.x + hi.x) - 0.5 * (blo.x + bhi.x), 0.0, hi.z - blo.z - 0.2});
    World world;
    world.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}));
    const auto ia = world.addBody(std::move(carA.body));
    const auto ib = world.addBody(std::move(carB.body));
    VehicleControls c;
    c.gear = 0;
    c.handbrake = 1.0;
    world.body(ia).setControls(c);
    world.body(ib).setControls(c);
    real late = 0.0;
    for (int k = 0; k < 100; ++k) {
        world.simulate(0.1);
        if (k >= 30) late = std::max(late, world.body(ia).kineticEnergy() + world.body(ib).kineticEnergy());
    }
    REQUIRE(world.stats().finite);
    MESSAGE("kinetic energy after 3 s at most " << late << " J");
    CHECK(late < 1000.0);
    for (const auto i : {ia, ib}) {
        world.body(i).aabb(lo, hi);
        CHECK(length(hi - lo) < 7.0);   // nothing torn off and thrown away
    }
}

TEST_CASE("props stand still on the ground and a car knocks them over without tearing them up") {
    auto coast = [](bool withProp, PropKind kind, real* knocked, real offset = 0.3, real ahead = 6.0) {
        auto car = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
        auto prop = buildProp(kind);
        prop.body.translate({car.def.body.length + ahead, 0.0, offset});
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
            // The beacon's panel is only plugged into its foot and comes out by design.
            if (kind != PropKind::Beacon)
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
    // Strikes across the whole front. A light prop squashed between a tyre and the bumper must not
    // act as a chock: an off-centre cone was caught and cost up to 19 km/h, a road beacon's foot
    // jammed under a front tyre and was dragged (-24 km/h). Single positions are chaotic (a tiny
    // change decides whether a squashed cone slides out at once or is carried for a while), so the
    // spread is judged: the mean loss and how many strikes cost more than 2 km/h.
    for (const PropKind kind : {PropKind::Cone, PropKind::Beacon}) {
        const std::string name = kind == PropKind::Cone ? "cone" : "beacon";
        CAPTURE(name);
        real sum = 0.0, worst = 0.0;
        int bad = 0, strikes = 0;
        for (const real offset : {-0.9, -0.6, -0.45, -0.15, 0.1, 0.35, 0.55, 0.75, 1.0})
            for (const real ahead : {6.0, 6.5}) {
                real knocked = 0;
                const real loss = alone - coast(true, kind, &knocked, offset, ahead);
                sum += loss;
                worst = std::max(worst, loss);
                bad += loss > 2.0 ? 1 : 0;
                ++strikes;
            }
        MESSAGE(name << ": mean loss " << sum / strikes << " km/h, worst " << worst << ", " << bad << " of " << strikes << " over 2 km/h");
        CHECK(sum / strikes < (kind == PropKind::Cone ? 0.8 : 2.0));
        // A cone the rear tyre dragged up into the arch used to self-lock between tread and body
        // (up to 10-13 km/h, 2 of 18 strikes); with the geometric-mean contact friction at most one
        // strike of the chaotic tail may exceed 2 km/h.
        CHECK(bad <= (kind == PropKind::Cone ? 1 : 5));
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
    // Compared with the car's top speed over the last second: a shoved log may roll on for a
    // moment while the car slows to climb it; squeezed out under a tread it leaves far faster.
    real worstExcess = 0.0;
    std::vector<real> recent;
    for (int k = 0; k < 400; ++k) {
        world.simulate(0.02);
        const real logSpeed = length(world.body(ip).centerOfMassVelocity());
        recent.push_back(length(world.body(ic).centerOfMassVelocity()));
        if (recent.size() > 50) recent.erase(recent.begin());
        const real carSpeed = *std::max_element(recent.begin(), recent.end());
        worstExcess = std::max(worstExcess, logSpeed - carSpeed);
    }
    REQUIRE(world.stats().finite);
    MESSAGE("log faster than the car (its top speed over the last second) by at most " << worstExcess << " m/s");
    CHECK(worstExcess < 1.5);
}

TEST_CASE("a fallen branch is run over or pushed aside without catching in a wheel arch") {
    auto probe = buildProp(PropKind::Branch);
    CHECK(probe.body.totalMass() == doctest::Approx(14.2).epsilon(0.02));
    CHECK(probe.body.stabilityRatio(1.0 / 2000.0) < 0.9);
    auto coast = [](bool withBranch, real kmh, real yawDeg, real dz) {
        auto car = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
        auto prop = buildProp(PropKind::Branch);
        const real yaw = yawDeg * 3.14159265358979 / 180.0;
        for (auto& p : prop.body.positions()) p = {p.x * std::cos(yaw) - p.z * std::sin(yaw), p.y, p.x * std::sin(yaw) + p.z * std::cos(yaw)};
        prop.body.translate({car.def.body.length + 6.0, 0.0, dz});
        World world;
        world.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}));
        const auto ic = world.addBody(std::move(car.body));
        if (withBranch) world.addBody(std::move(prop.body));
        VehicleControls c;
        c.gear = 0;
        world.body(ic).setControls(c);
        world.simulate(1.0);
        for (auto& v : world.body(ic).velocities()) v = {kmh / 3.6, 0, 0};
        world.simulate(4.0);
        REQUIRE(world.stats().finite);
        return world.body(ic).telemetry().speedKmh;
    };
    // With bark at rubber-like friction a branch lying straight across at 70 km/h got its end
    // dragged up into a front wheel arch, half-locked the wheel and cost the car 27 km/h.
    for (const real kmh : {40.0, 70.0}) {
        CAPTURE(kmh);
        const real alone = coast(false, kmh, 0.0, 0.0);
        real sum = 0.0, worst = 0.0;
        int n = 0;
        for (const real yaw : {90.0, 60.0, 30.0, 120.0})
            for (const real dz : {-0.6, 0.0, 0.5}) {
                const real loss = alone - coast(true, kmh, yaw, dz);
                sum += loss;
                worst = std::max(worst, loss);
                ++n;
            }
        MESSAGE(kmh << " km/h over a branch: mean loss " << sum / n << " km/h, worst " << worst);
        CHECK(sum / n < 1.6);
        CHECK(worst < 4.0);
    }
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

TEST_CASE("a tyre rolls over a low heavy object lying on the road instead of shoving it") {
    // A tread node rests a few mm deep in the road, i.e. under the bottom face of anything lying
    // there; that contact lifted the object's edge until the tyre flipped and jammed on it: a car
    // could not roll over a 7 cm, 25 kg rubber block and lost 30 km/h shoving it 15 m along.
    auto car = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
    real wheelZ = 0;
    for (const auto& w : car.body.wheels()) wheelZ = std::max(wheelZ, std::abs(w.center(car.body).z));
    SoftBody block("block");
    NodeParams np;
    np.mass = 25.0 / 8;
    np.friction = 0.7;
    std::vector<std::uint32_t> n;
    for (int layer = 0; layer < 2; ++layer)
        for (int i = 0; i < 4; ++i) {
            const real hx = layer ? 0.15 : 0.20, hz = layer ? 0.30 : 0.40;   // ramped edges
            n.push_back(block.addNode("n" + std::to_string(layer * 4 + i),
                                      {(i & 1) ? hx : -hx, layer ? 0.07 : 0.01, ((i & 2) ? hz : -hz) + wheelZ}, np));
        }
    BeamParams rubber;
    rubber.spring = 1.0e6;
    rubber.damp = 400.0;
    for (std::size_t i = 0; i < n.size(); ++i)
        for (std::size_t j = i + 1; j < n.size(); ++j) block.addBeam(n[i], n[j], rubber);
    const int faces[6][4] = {{0, 1, 3, 2}, {4, 6, 7, 5}, {0, 4, 5, 1}, {2, 3, 7, 6}, {0, 2, 6, 4}, {1, 5, 7, 3}};
    const Vec3 centre{0, 0.04, wheelZ};
    for (const auto& f : faces)
        for (int k = 0; k < 2; ++k) {
            std::uint32_t a = n[static_cast<std::size_t>(f[0])], b = n[static_cast<std::size_t>(f[1 + k])], c = n[static_cast<std::size_t>(f[2 + k])];
            const auto& p = block.positions();
            if (dot(cross(p[b] - p[a], p[c] - p[a]), (p[a] + p[b] + p[c]) / 3.0 - centre) < 0) std::swap(b, c);
            block.addTriangle(a, b, c);
        }
    block.setContactThickness(0.035);
    block.setDownFacesPassive(true);
    block.translate({car.def.body.length + 6.0, 0.0, 0.0});
    World world;
    world.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}));
    const auto ic = world.addBody(std::move(car.body));
    const auto ib = world.addBody(std::move(block));
    VehicleControls c;
    c.gear = 0;
    world.body(ic).setControls(c);
    world.simulate(1.0);
    const Vec3 rest = world.body(ib).centerOfMass();
    for (auto& v : world.body(ic).velocities()) v = {40.0 / 3.6, 0, 0};
    world.simulate(3.0);
    REQUIRE(world.stats().finite);
    MESSAGE("car " << world.body(ic).telemetry().speedKmh << " km/h, block moved " << length(world.body(ib).centerOfMass() - rest) << " m");
    CHECK(world.body(ic).telemetry().speedKmh > 35.0);
    CHECK(length(world.body(ib).centerOfMass() - rest) < 1.0);   // run over, not bulldozed
}

TEST_CASE("a heavy tailgate stays latched in a 50 km/h frontal impact") {
    // The Trailhead's 40 kg tailgate (spare wheel on it) used to pop its latch from its own
    // inertia when the car hit a wall head-on; hinges and latch now scale with the lid's mass.
    auto car = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/trailhead_4x4.car.json"));
    const real L = car.def.body.length;
    World world;
    world.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}));
    world.addCollider(StaticCollider::box({L + 1.5, 1.0, 0.0}, {0.5, 1.0, 3.0}, {0, 0, 0}, 0.8));
    const auto ic = world.addBody(std::move(car.body));
    world.simulate(1.0);
    for (auto& v : world.body(ic).velocities()) v = {50.0 / 3.6, 0, 0};
    VehicleControls c;
    c.gear = 0;
    world.body(ic).setControls(c);
    world.simulate(2.0);
    REQUIRE(world.stats().finite);
    const SoftBody& body = world.body(ic);
    int frontDamage = 0, lidBroken = 0;
    for (const Beam& b : body.beams()) {
        const std::string group = b.breakGroup >= 0 ? body.breakGroupNames()[static_cast<std::size_t>(b.breakGroup)] : "";
        if (b.broken && (group == "tailgate_latch" || group == "tailgate_hinge")) ++lidBroken;
        if (std::abs(b.restLength - b.baseRestLength) > 0.01 * b.baseRestLength) ++frontDamage;
    }
    MESSAGE("bent beams " << frontDamage << ", broken tailgate mounts " << lidBroken);
    CHECK(frontDamage > 50);   // it really was a hard frontal crash
    CHECK(lidBroken == 0);
}

TEST_CASE("a box trailer stands on its drawbar alone and follows the car on the tow bar") {
    auto trailer = buildProp(PropKind::Trailer);
    CHECK(trailer.hitch >= 0);
    CHECK(trailer.body.stabilityRatio(1.0 / 2000.0) < 0.9);
    // Alone it tips onto its drawbar: the centre of mass is ahead of the axle.
    {
        auto alone = buildProp(PropKind::Trailer);
        World w;
        w.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}));
        const auto i = w.addBody(std::move(alone.body));
        w.simulate(4.0);
        REQUIRE(w.stats().finite);
        CHECK(w.body(i).positions()[static_cast<std::size_t>(alone.hitch)].y < 0.05);
    }
    auto car = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
    const real curb = car.body.totalMass();
    const std::size_t nodes = car.body.nodeCount();
    World w;
    w.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}));
    const auto ic = w.addBody(std::move(car.body));
    w.simulate(1.0);
    // The tow bar is fitted to the running car only now: before, the car is exactly as built.
    CHECK(w.body(ic).nodeCount() == nodes);
    const auto towNode = addTowBar(w.body(ic), car.layout);
    REQUIRE(towNode >= 0);
    const auto tow = static_cast<std::uint32_t>(towNode);
    CHECK(addTowBar(w.body(ic), car.layout) == towNode);   // a second call finds it
    CHECK(w.body(ic).totalMass() == doctest::Approx(curb + 4.0));
    trailer.body.translate(w.body(ic).positions()[tow] - trailer.body.positions()[static_cast<std::size_t>(trailer.hitch)]);
    const auto it = w.addBody(std::move(trailer.body));
    BodyLink link;
    link.bodyA = ic; link.nodeA = tow;
    link.bodyB = it; link.nodeB = static_cast<std::uint32_t>(trailer.hitch);
    w.addLink(link);
    VehicleControls c;
    c.gear = 1;
    w.body(ic).setControls(c);
    w.simulate(2.0);
    // At rest the hitch carries the tongue load (~220 N), not a fight with the car's skin.
    MESSAGE("tongue load at rest " << w.links()[0].force << " N");
    CHECK(w.links()[0].force > 80.0);
    CHECK(w.links()[0].force < 600.0);
    c.throttle = 0.6;
    w.body(ic).setControls(c);
    real worstGap = 0.0, worstForce = 0.0;
    for (int i = 0; i < 80; ++i) {
        w.simulate(0.1);
        const real gap = std::abs(w.body(ic).telemetry().speedKmh - length(w.body(it).centerOfMassVelocity()) * 3.6);
        if (w.time() > 3.5) worstGap = std::max(worstGap, gap);
        worstForce = std::max(worstForce, w.links()[0].force);
    }
    const real kmh = w.body(ic).telemetry().speedKmh;
    MESSAGE("towed to " << kmh << " km/h; trailer speed off by at most " << worstGap << " km/h, peak pull " << worstForce << " N");
    CHECK(kmh > 40.0);
    CHECK(worstGap < 2.0);
    CHECK_FALSE(w.links()[0].broken);
    // Braking (the trailer's overrun brake follows the car's): both stop, coupled, upright.
    c.throttle = 0.0;
    c.brake = 1.0;
    w.body(ic).setControls(c);
    auto tc = w.body(it).controls();
    tc.brake = 1.0;
    w.body(it).setControls(tc);
    w.simulate(3.0);
    REQUIRE(w.stats().finite);
    CHECK(length(w.body(it).centerOfMassVelocity()) < 0.5);
    CHECK_FALSE(w.links()[0].broken);
    const auto& tp = w.body(it).positions();
    CHECK(std::abs(tp[trailer.frameOrigin].y - tp[trailer.frameX].y) < 0.15);   // level, not jack-knifed onto its side
    // Removing the trailer takes its link with it.
    w.removeBody(it);
    CHECK(w.links().empty());
}

TEST_CASE("a body link tears apart above its break force") {
    World w;
    auto a = buildProp(PropKind::Barrel);
    auto b = buildProp(PropKind::Barrel);
    b.body.translate({3.0, 0.0, 0.0});
    const auto ia = w.addBody(std::move(a.body));
    const auto ib = w.addBody(std::move(b.body));
    BodyLink l;
    l.bodyA = ia; l.bodyB = ib; l.nodeA = 0; l.nodeB = 0;   // 3 m apart: 6e5 N on the spring
    w.addLink(l);
    w.step();
    CHECK(w.links()[0].broken);
}

TEST_CASE("a tow bar fitted after the build leaves the body skin and its rigid parts in place") {
    auto car = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
    std::vector<float> before, after;
    computeNodeFrames(car.body.positions(), car.visual, before);
    const auto tow = addTowBar(car.body, car.layout);
    REQUIRE(tow >= 0);
    REQUIRE(car.body.nodeCount() == car.visual.restNodes.size() + 1);
    computeNodeFrames(car.body.positions(), car.visual, after);
    // The same panel frames (doors, bumpers, lids) as before, only one more node offset slot.
    const std::size_t n0 = car.visual.restNodes.size();
    REQUIRE(!car.visual.parts.empty());
    REQUIRE(after.size() == before.size() + 3);
    for (std::size_t i = 0; i < 12; ++i) CHECK(after[i] == doctest::Approx(before[i]));
    for (std::size_t p = 0; p < 16 * car.visual.parts.size(); ++p)
        CHECK(after[12 + (n0 + 1) * 3 + p] == doctest::Approx(before[12 + n0 * 3 + p]).epsilon(1e-4));
}
