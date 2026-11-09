#include <doctest/doctest.h>
#include <algorithm>
#include <cmath>
#include <set>
#include <string>
#include <tuple>
#include "sbcore/sbcore.hpp"
#include "../src/car_profile.hpp"

using namespace sb;
namespace {
using PointKey = std::tuple<long, long, long>;
PointKey key(const Vec3& p) { return {std::lround(p.x * 100000), std::lround(p.y * 100000), std::lround(p.z * 100000)}; }
}

TEST_CASE("door visual skin glass cards and mirrors follow only their own detached cage") {
    auto car = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
    const auto rest = car.body.positions();
    const real angle = 0.9;
    auto rotate = [&](const Vec3& p) { return Vec3{std::cos(angle) * p.x - std::sin(angle) * p.z, p.y,
                                                 std::sin(angle) * p.x + std::cos(angle) * p.z}; };
    const Vec3 translation{2, 1, -3};
    for (int side = 0; side < 2; ++side) {
        const auto& door = car.layout.frontDoors[static_cast<std::size_t>(side)];
        REQUIRE(door.nodes.size() == 8);
        const std::string prefix = side == 0 ? "door_left_" : "door_right_";
        auto pos = rest;
        for (auto n : door.nodes) pos[n] = rotate(rest[n]) + translation;
        std::vector<float> frames;
        computeNodeFrames(pos, car.visual, frames);
        std::set<std::string> materials;
        std::size_t vertices = 0;
        for (const auto& mesh : car.visual.skinned) {
            if (mesh.material.rfind(prefix, 0) != 0) continue;
            materials.insert(mesh.material.substr(prefix.size()));
            if (mesh.material == prefix + "glass") CHECK(mesh.doubleSided);
            for (std::size_t i = 0; i < mesh.skin.size(); ++i) {
                const auto& skin = mesh.skin[i];
                REQUIRE(skin.weight[0] < 0);
                for (int j = 0; j < 3; ++j)
                    REQUIRE(std::find(door.nodes.begin(), door.nodes.end(), skin.node[j]) != door.nodes.end());
                const Vec3 p{mesh.positions[i * 3], mesh.positions[i * 3 + 1], mesh.positions[i * 3 + 2]};
                CHECK(length(evalSkin(pos, frames, skin) - rotate(p) - translation) < 2e-5);
                ++vertices;
            }
        }
        for (const std::string expected : {"paint", "glass", "interior", "trim", "chrome", "mirror", "upholstery"})
            CHECK(materials.count(expected) == 1);
        CHECK(vertices > 1000);
    }
}

TEST_CASE("opening door has no duplicated fixed exterior skin and each mirror has one face") {
    const auto car = buildCar(loadCarDefinition(std::string(SB_CARS_DIR) + "/kestrel_hatch.car.json"));
    const detail::Profile profile(car.def.body, car.def.tires);
    std::set<PointKey> fixed;
    for (const auto& mesh : car.visual.skinned) {
        if (mesh.material != "paint" && mesh.material != "glass" && mesh.material != "interior") continue;
        for (std::size_t i = 0; i < mesh.positions.size(); i += 3)
            fixed.insert(key({mesh.positions[i], mesh.positions[i + 1], mesh.positions[i + 2]}));
    }
    std::size_t checked = 0;
    int mirrors = 0;
    for (int side = 0; side < 2; ++side) {
        const auto& door = car.layout.frontDoors[static_cast<std::size_t>(side)];
        const std::string prefix = side == 0 ? "door_left_" : "door_right_";
        for (const auto& mesh : car.visual.skinned) {
            if (mesh.material == prefix + "mirror") {
                ++mirrors;
                CHECK(mesh.positions.size() == 41 * 3);
                CHECK(mesh.indices.size() == 40 * 3);
                std::vector<float> frames;
                computeNodeFrames(car.body, car.visual, frames);
                const Vec3 center{mesh.positions[0], mesh.positions[1], mesh.positions[2]};
                const Vec3 eye = evalSkin(car.body.positions(), frames, car.visual.driverEye);
                const Vec3 toEye = normalize(eye - center);
                const Vec3 normal = normalize(Vec3{mesh.normals[0], mesh.normals[1], mesh.normals[2]});
                const Vec3 reflected = -toEye + normal * (2.0 * dot(toEye, normal));
                // Reflection at the driver's authored position sees the rear
                // horizon, rather than asphalt a few metres beside the car.
                CHECK(reflected.x < -0.98);
                CHECK(std::abs(reflected.y) < 1e-4);
                CHECK(reflected.z * (side == 0 ? -1.0 : 1.0) > 0.10);
            }
            if (mesh.material != prefix + "paint" && mesh.material != prefix + "glass") continue;
            for (std::size_t i = 0; i < mesh.positions.size(); i += 3) {
                const Vec3 p{mesh.positions[i], mesh.positions[i + 1], mesh.positions[i + 2]};
                // The closed perimeter intentionally touches the fixed aperture;
                // check vertices strictly inside the opening away from sill/header.
                if (p.x <= door.rearX + 0.03 || p.x >= door.frontX - 0.03 || p.y < profile.ySill(p.x) + 0.035 || p.y > profile.yRoofRail(p.x) - 0.035) continue;
                CAPTURE(p.x); CAPTURE(p.y); CAPTURE(p.z); CAPTURE(mesh.material);
                CHECK(fixed.count(key(p)) == 0);
                ++checked;
            }
        }
    }
    CHECK(mirrors == 2);
    CHECK(checked > 100);
    for (const auto& mesh : car.visual.skinned) CHECK(mesh.material != "mirror");
    auto disabled = car.def;
    disabled.body.detachableDoors = false;
    const auto legacy = buildCar(disabled);
    std::set<std::string> mirrorNames;
    for (const auto& mesh : legacy.visual.skinned) {
        CHECK(mesh.material.rfind("door_", 0) != 0);
        if (mesh.material.rfind("mirror_", 0) == 0) mirrorNames.insert(mesh.material);
    }
    const std::set<std::string> expectedMirrorNames{"mirror_left", "mirror_right"};
    CHECK(mirrorNames == expectedMirrorNames);
}
