// cartest - automated driving / crash test bench for *.car.json vehicles.
//
//   cartest game/cars/kestrel_hatch.car.json            # all tests
//   cartest game/cars/vortex_gt.car.json --obj out.obj    # export the rest-pose visual model
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>

#include "sbcore/sbcore.hpp"

namespace {

double nowSeconds() {
    using clock = std::chrono::steady_clock;
    return std::chrono::duration<double>(clock::now().time_since_epoch()).count();
}

struct Bench {
    sb::World world;
    std::size_t idx = 0;
    sb::CarLayout layout;
};

Bench makeBench(const sb::CarDefinition& def, bool wall, double wallX = 60.0) {
    Bench b;
    b.world.addCollider(sb::StaticCollider::plane({0, 0, 0}, {0, 1, 0}, 1.0, "ground"));
    if (wall) b.world.addCollider(sb::StaticCollider::box({wallX + 1.0, 1.0, 0}, {1.0, 1.5, 4.0}, {}, 0.8, "wall"));
    sb::CarBuild cb = sb::buildCar(def);
    cb.body.translate({0, 0.02, 0});
    b.layout = cb.layout;
    b.idx = b.world.addBody(std::move(cb.body));
    return b;
}

double floorHeight(const sb::SoftBody& body, const sb::CarLayout& l) {
    const auto& p = body.positions();
    return 0.25 * (p[l.refFL].y + p[l.refFR].y + p[l.refRL].y + p[l.refRR].y);
}

void exportObj(const sb::CarBuild& cb, const std::string& path) {
    std::ofstream f(path);
    std::size_t base = 1;
    for (const auto& s : cb.visual.skinned) {
        f << "o " << s.material << "\n";
        for (std::size_t i = 0; i < s.positions.size(); i += 3)
            f << "v " << s.positions[i] << " " << s.positions[i + 1] << " " << s.positions[i + 2] << "\n";
        for (std::size_t i = 0; i < s.normals.size(); i += 3)
            f << "vn " << s.normals[i] << " " << s.normals[i + 1] << " " << s.normals[i + 2] << "\n";
        for (std::size_t i = 0; i + 2 < s.indices.size(); i += 3) {
            const std::size_t a = s.indices[i] + base, b = s.indices[i + 1] + base, c = s.indices[i + 2] + base;
            f << "f " << a << "//" << a << " " << b << "//" << b << " " << c << "//" << c << "\n";
        }
        base += s.positions.size() / 3;
    }
    std::printf("wrote %s\n", path.c_str());
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 2) {
        std::printf("usage: cartest CAR.car.json [--obj OUT.obj] [--quick]\n");
        return 1;
    }
    const std::string path = argv[1];
    const char* objPath = nullptr;
    bool quick = false;
    for (int i = 2; i < argc; ++i) {
        if (!std::strcmp(argv[i], "--obj") && i + 1 < argc) objPath = argv[++i];
        else if (!std::strcmp(argv[i], "--quick")) quick = true;
    }
    int failures = 0;
    try {
        const sb::CarDefinition def = sb::loadCarDefinition(path);
        const double t0 = nowSeconds();
        sb::CarBuild cb = sb::buildCar(def);
        const double buildMs = (nowSeconds() - t0) * 1000.0;
        std::size_t verts = 0, tris = 0;
        for (const auto& s : cb.visual.skinned) {
            verts += s.positions.size() / 3;
            tris += s.indices.size() / 3;
        }
        std::printf("== %s (%s)\n", def.name.c_str(), def.id.c_str());
        std::printf("   nodes %zu, beams %zu, coltris %zu, torsionbars %zu, mass %.0f kg (+tyres), stability %.2f, built in %.0f ms\n",
                    cb.body.nodeCount(), cb.body.beamCount(), cb.body.triangleCount(), cb.body.torsionbars().size(),
                    cb.body.totalMass(), cb.body.stabilityRatio(1.0 / 2000.0), buildMs);
        std::printf("   visual: %zu surfaces, %zu vertices, %zu triangles\n", cb.visual.skinned.size(), verts, tris);
        if (objPath) exportObj(cb, objPath);

        // ---------------------------------------------------------------- settle
        Bench b = makeBench(def, false);
        sb::SoftBody& car = b.world.body(b.idx);
        const double designFloor = floorHeight(car, b.layout);
        sb::VehicleControls c;
        c.brake = 1.0;
        car.setControls(c);
        const double ts = nowSeconds();
        b.world.simulate(3.0);
        const double rt = 3.0 / (nowSeconds() - ts);
        const auto st = b.world.stats();
        const double floorNow = floorHeight(car, b.layout);
        std::printf("   settle: floor %.3f m (design %.3f, delta %+.3f), %.1fx real time, deformed beams %zu %s\n",
                    floorNow, designFloor, floorNow - designFloor, rt, st.deformedBeams, st.finite ? "" : "NON-FINITE");
        if (!st.finite || std::abs(floorNow - designFloor) > 0.08) ++failures;

        // ---------------------------------------------------------------- acceleration
        c = {};
        c.throttle = 1.0;
        car.setControls(c);
        double t100 = -1, t = 0;
        double maxKmh = 0;
        const double accelTime = quick ? 12.0 : 30.0;
        while (t < accelTime) {
            b.world.simulate(0.05);
            t += 0.05;
            const double kmh = car.telemetry().speedKmh;
            maxKmh = std::max(maxKmh, kmh);
            if (t100 < 0 && kmh >= 100.0) t100 = t;
        }
        const auto tel = car.telemetry();
        std::printf("   accel: 0-100 km/h %.1f s, %.0f km/h after %.0f s (gear %d, %.0f rpm)\n", t100, maxKmh, accelTime,
                    tel.gear, tel.engineRpm);
        if (t100 < 0 || t100 > 14.0) ++failures;

        // ---------------------------------------------------------------- braking
        c = {};
        c.brake = 1.0;
        car.setControls(c);
        const sb::Vec3 p0 = car.centerOfMass();
        const double v0 = car.telemetry().speedKmh;
        t = 0;
        while (car.telemetry().speedKmh > 1.0 && t < 15.0) {
            b.world.simulate(0.02);
            t += 0.02;
        }
        const double dist = sb::length(car.centerOfMass() - p0);
        std::printf("   brake: %.0f -> 0 km/h in %.1f m (%.1f s); scaled 100-0: %.1f m\n", v0, dist, t,
                    dist * (100.0 / v0) * (100.0 / v0));

        // ---------------------------------------------------------------- cornering
        {
            Bench bc = makeBench(def, false);
            sb::SoftBody& cc = bc.world.body(bc.idx);
            sb::VehicleControls k;
            k.throttle = 0.6;
            cc.setControls(k);
            double tt = 0;
            while (cc.telemetry().speedKmh < 60.0 && tt < 15.0) {
                bc.world.simulate(0.05);
                tt += 0.05;
            }
            k.throttle = 0.25;
            k.steer = 0.35;
            cc.setControls(k);
            const sb::Vec3 va = cc.centerOfMassVelocity();
            bc.world.simulate(2.0);
            const sb::Vec3 vb = cc.centerOfMassVelocity();
            // Heading change of the velocity vector; + = left (towards -z).
            const double yaw = std::atan2(-(va.x * vb.z - va.z * vb.x), va.x * vb.x + va.z * vb.z);
            const double v = cc.telemetry().speedKmh / 3.6;
            const double yawRate = yaw / 2.0;
            const auto& p = cc.positions();
            const double roll = (p[bc.layout.refFL].y + p[bc.layout.refRL].y - p[bc.layout.refFR].y - p[bc.layout.refRR].y) * 0.5;
            std::printf("   corner: steer +0.35 @ %.0f km/h -> yaw %.0f deg/s (left = +), lateral %.2f g, roll offset %+.3f m\n",
                        v * 3.6, yawRate * 57.2958, std::abs(yawRate * v) / 9.81, roll);
            if (yawRate <= 0.05) ++failures;
            if (!bc.world.stats().finite) ++failures;
        }

        // ---------------------------------------------------------------- crash
        if (!quick) {
            Bench bw = makeBench(def, true, 45.0);
            sb::SoftBody& cw = bw.world.body(bw.idx);
            sb::VehicleControls k;
            k.throttle = 1.0;
            cw.setControls(k);
            double impact = 0.0;
            while (bw.world.time() < 25.0) {
                bw.world.simulate(0.01);
                const double kmh = cw.telemetry().speedKmh;
                if (kmh >= 50.0 && k.throttle > 0.0) { k.throttle = 0.0; cw.setControls(k); }
                if (bw.world.stats().bodyContacts > 0 || bw.world.stats().contacts > 0) {}
                sb::Vec3 lo, hi;
                cw.aabb(lo, hi);
                if (hi.x > 45.0 - 0.02 && impact == 0.0) impact = kmh;
                if (impact > 0.0 && kmh < 2.0) break;
            }
            bw.world.simulate(1.0);
            std::printf("   impact speed %.0f km/h\n", impact);
            // Let it sit at idle so the cooling system can react to the radiator damage.
            const auto& ss = cw.systems().state();
            const auto bs = cw.stats();
            std::printf("   crash (50 km/h, at t=%.1fs from 40 m): front %.0f%%, deformed beams %zu, broken %zu, radiator %.0f%%, engine block %.0f%%, mounts broken %d/%d\n",
                        bw.world.time(), ss.zoneDamage[sb::kZoneFront] * 100.0, bs.deformedBeams, bs.brokenBeams,
                        ss.radiatorDamage * 100.0, ss.blockDamage * 100.0, ss.mountsBroken, ss.mountsTotal);
            k.brake = 0.0;
            k.throttle = 0.35;
            k.gear = 0;
            cw.setControls(k);
            for (int i = 0; i < 6; ++i) {
                bw.world.simulate(10.0);
                std::printf("     +%3ds: coolant %5.1f C, level %3.0f%%, oil %3.0f%% %.1f bar, running %d, status '%s'\n",
                            (i + 1) * 10, ss.coolantTempC, ss.coolantLevel * 100.0, ss.oilLevel * 100.0, ss.oilPressureBar,
                            ss.running ? 1 : 0, ss.status.c_str());
            }
            if (!bw.world.stats().finite) ++failures;
        }
    } catch (const std::exception& e) {
        std::fprintf(stderr, "error: %s\n", e.what());
        return 2;
    }
    std::printf("%s\n", failures ? "RESULT: FAIL" : "RESULT: OK");
    return failures ? 1 : 0;
}
