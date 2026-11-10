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
