// sbsim - headless command line runner for the SoftBodyDriver physics core.
//
//   sbsim --list
//   sbsim --scene wall_crash [--duration 3] [--record out.json] [--fps 30]
//   sbsim --file content/vehicles/test_cube.sbeam.json --drop 2 --duration 3
//   sbsim --bench
//   sbsim --scene wall_crash --export-sbeam car.sbeam.json
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <string>

#include "sbcore/sbcore.hpp"

namespace {

void usage() {
    std::printf(
        "sbsim - SoftBodyDriver headless simulator\n\n"
        "  --list                     list built-in scenes\n"
        "  --scene NAME               run a built-in scene\n"
        "  --file PATH                load a .sbeam.json body and drop it on a ground plane\n"
        "  --drop H                   drop height in metres for --file (default 1)\n"
        "  --duration S               simulated seconds (default: scene suggestion)\n"
        "  --record OUT.json          record a replay (convert with tools/make_viewer.py)\n"
        "  --fps N                    replay frames per second (default 30)\n"
        "  --export-sbeam OUT         write the first body as .sbeam.json and exit\n"
        "  --bench                    benchmark all scenes\n"
        "  --quiet                    only print the summary\n");
}

double nowSeconds() {
    using clock = std::chrono::steady_clock;
    return std::chrono::duration<double>(clock::now().time_since_epoch()).count();
}

void printStats(const sb::World& w) {
    const auto s = w.stats();
    if (!w.bodies().empty() && (!w.bodies()[0].wheels().empty() || w.bodies()[0].hasPowertrain())) {
        const auto t = w.bodies()[0].telemetry();
        std::printf("  t=%6.3fs  v=%5.1f km/h  rpm=%4.0f  gear=%2d  steer=%+5.2f  deformed=%5zu  broken=%4zu%s\n",
                    s.time, t.speedKmh, t.engineRpm, t.gear, t.steer, s.deformedBeams, s.brokenBeams,
                    s.finite ? "" : "  !! NON-FINITE");
    } else {
        std::printf("  t=%6.3fs  KE=%11.1f J  elastic=%10.1f J  deformed=%6zu  broken=%5zu  contacts=%5zu%s\n", s.time,
                    s.kineticEnergy, s.elasticEnergy, s.deformedBeams, s.brokenBeams, s.contacts,
                    s.finite ? "" : "  !! NON-FINITE");
    }
}

int runScene(sb::Scene& sc, double duration, const char* recordPath, double fps, bool quiet) {
    sb::World& w = sc.world;
    std::size_t nodes = 0, beams = 0;
    for (const auto& b : w.bodies()) {
        nodes += b.nodeCount();
        beams += b.beamCount();
    }
    std::printf("scene '%s': %s\n", sc.name.c_str(), sc.description.c_str());
    std::printf("  %zu bodies, %zu nodes, %zu beams, dt=%.4f ms (%.0f Hz), stability ratio %.2f (<1 stable)\n",
                w.bodies().size(), nodes, beams, w.settings().dt * 1000.0, 1.0 / w.settings().dt,
                w.worstStabilityRatio());

    sb::Recorder* rec = nullptr;
    sb::Recorder recorder(w, sc.name, sc.description, fps);
    if (recordPath) rec = &recorder;

    const auto totalSteps = static_cast<long long>(duration / w.settings().dt + 0.5);
    const auto reportEvery = static_cast<long long>(0.5 / w.settings().dt + 0.5);
    const double t0 = nowSeconds();
    if (rec) rec->capture(w);
    for (long long i = 0; i < totalSteps; ++i) {
        sc.step();
        if (rec) rec->captureIfDue(w);
        if (!quiet && (i + 1) % reportEvery == 0) printStats(w);
    }
    const double wall = nowSeconds() - t0;
    const auto s = w.stats();
    std::printf("summary: simulated %.2fs in %.2fs wall -> %.2fx real time, %.0f steps/s; deformed=%zu broken=%zu %s\n",
                duration, wall, duration / wall, static_cast<double>(totalSteps) / wall, s.deformedBeams, s.brokenBeams,
                s.finite ? "OK" : "NON-FINITE!");
    if (rec) {
        rec->save(recordPath);
        std::printf("recorded %zu frames -> %s\n", rec->frameCount(), recordPath);
    }
    return s.finite ? 0 : 2;
}

}  // namespace

int main(int argc, char** argv) {
    std::string scene, file, exportPath;
    const char* recordPath = nullptr;
    double duration = -1, fps = 30, drop = 1.0;
    bool bench = false, list = false, quiet = false;

    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        auto next = [&]() -> const char* {
            if (i + 1 >= argc) {
                std::fprintf(stderr, "missing value for %s\n", a.c_str());
                std::exit(1);
            }
            return argv[++i];
        };
        if (a == "--list") list = true;
        else if (a == "--scene") scene = next();
        else if (a == "--file") file = next();
        else if (a == "--drop") drop = std::atof(next());
        else if (a == "--duration") duration = std::atof(next());
        else if (a == "--record") recordPath = next();
        else if (a == "--fps") fps = std::atof(next());
        else if (a == "--export-sbeam") exportPath = next();
        else if (a == "--bench") bench = true;
        else if (a == "--quiet") quiet = true;
        else if (a == "-h" || a == "--help") { usage(); return 0; }
        else { std::fprintf(stderr, "unknown argument: %s\n\n", a.c_str()); usage(); return 1; }
    }

    try {
        if (list) {
            for (const auto& n : sb::sceneNames()) {
                const sb::Scene sc = sb::makeScene(n);
                std::printf("%-18s %s\n", n.c_str(), sc.description.c_str());
            }
            return 0;
        }
        if (bench) {
            for (const auto& n : sb::sceneNames()) {
                sb::Scene sc = sb::makeScene(n);
                runScene(sc, 1.0, nullptr, fps, true);
            }
            return 0;
        }
        sb::Scene sc;
        if (!scene.empty()) {
            sc = sb::makeScene(scene);
        } else if (!file.empty()) {
            sb::SoftBody body = sb::loadSBeam(file);
            sb::Vec3 lo, hi;
            body.aabb(lo, hi);
            body.translate({0, drop - lo.y, 0});
            sc.name = body.name();
            sc.description = "loaded from " + file;
            sc.duration = 3.0;
            sc.world.addCollider(sb::StaticCollider::plane({0, 0, 0}, {0, 1, 0}, 0.9, "ground"));
            sc.world.addBody(std::move(body));
        } else {
            usage();
            return 1;
        }
        if (!exportPath.empty()) {
            sb::saveSBeam(sc.world.body(0), exportPath);
            std::printf("wrote %s\n", exportPath.c_str());
            return 0;
        }
        return runScene(sc, duration > 0 ? duration : sc.duration, recordPath, fps, quiet);
    } catch (const std::exception& e) {
        std::fprintf(stderr, "error: %s\n", e.what());
        return 1;
    }
}
