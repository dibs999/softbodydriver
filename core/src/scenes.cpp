#include "sbcore/scenes.hpp"

#include <cmath>
#include <memory>
#include <stdexcept>

#include "sbcore/builders.hpp"
#include "sbcore/vehicle.hpp"

namespace sb {

namespace {
constexpr real kPi = 3.14159265358979323846;
constexpr real deg(real d) { return d * kPi / 180.0; }
}  // namespace

void Scene::step() {
    if (update) update(world);
    world.step();
}

void Scene::run(real seconds) {
    const auto n = static_cast<long long>(std::llround(seconds / world.settings().dt));
    for (long long i = 0; i < n; ++i) step();
}

std::vector<std::string> sceneNames() {
    return {"accel_brake", "slalom", "curb_impact", "wall_crash", "ramp_jump", "bridge_overload", "cube_drop"};
}

SoftBody buildTestCar(const std::string& name) {
    // 14 x 4 x 6 cells of 0.3 m: lower body 0.6 m high over the full length,
    // cabin (another 0.6 m) between x = 1.2 m and 3.3 m. X is forward.
    LatticeSpec s;
    s.name = name;
    s.cellsX = 14;
    s.cellsY = 4;
    s.cellsZ = 6;
    s.cellSize = {0.3, 0.3, 0.3};
    s.origin = {0.0, 0.0, -0.9};
    s.totalMass = 1300.0;
    s.includeCell = [](int i, int j, int) { return j < 2 || (i >= 4 && i < 11); };
    s.node.friction = 0.03;  // no wheels yet: low friction approximates rolling

    s.edge.spring = 5.0e5;
    s.faceDiagonal.spring = 3.5e5;
    s.bodyDiagonal.spring = 2.5e5;
    for (BeamParams* p : {&s.edge, &s.faceDiagonal, &s.bodyDiagonal}) {
        p->damp = 190;
        p->deform = 9.0e3;
        p->hardening = 0.05;
        p->deformLimit = 0.65;
        p->deformLimitExpansion = 0.4;
        p->strength = 2.8e4;
    }
    const real length = 14 * 0.3;
    s.customizeBeam = [length](BeamParams& p, const Vec3& mid, LatticeBeamKind) {
        if (mid.x > length - 1.2) {          // front crumple zone
            p.deform *= 0.25;
            p.strength *= 0.32;
        } else if (mid.x < 0.9) {            // rear crumple zone
            p.deform *= 0.45;
        } else if (mid.y > 0.6) {            // cabin / safety cage
            p.deform *= 2.5;
            p.strength *= 2.5;
        }
    };
    return buildLattice(s);
}

namespace {

void addGround(World& w, real friction = 0.9) {
    w.addCollider(StaticCollider::plane({0, 0, 0}, {0, 1, 0}, friction, "ground"));
}

Scene cubeDrop() {
    Scene sc;
    sc.name = "cube_drop";
    sc.description = "1 m Gitterwuerfel (200 kg) faellt aus 3 m Hoehe auf eine Kante und verbeult.";
    sc.duration = 4.0;
    addGround(sc.world);

    LatticeSpec s;
    s.name = "cube";
    s.cellsX = s.cellsY = s.cellsZ = 4;
    s.cellSize = {0.25, 0.25, 0.25};
    s.origin = {-0.5, -0.5, -0.5};
    s.totalMass = 200.0;
    s.node.friction = 0.8;
    s.edge.spring = 3.0e5;
    s.faceDiagonal.spring = 2.0e5;
    s.bodyDiagonal.spring = 1.5e5;
    for (BeamParams* p : {&s.edge, &s.faceDiagonal, &s.bodyDiagonal}) {
        p->damp = 60;
        p->deform = 4.0e3;
        p->hardening = 0.3;
        p->deformLimit = 0.5;
        p->deformLimitExpansion = 0.5;
    }
    SoftBody cube = buildLattice(s);
    rotateBody(cube, Mat3::fromEuler(deg(35), deg(20), deg(10)), {0, 0, 0});
    cube.translate({0, 3.0, 0});
    sc.world.addBody(std::move(cube));
    return sc;
}

Scene wallCrash() {
    Scene sc;
    sc.name = "wall_crash";
    sc.description = "Auto-Rumpf (1300 kg) faehrt mit 50 km/h frontal gegen eine Betonwand. Knautschzone vorne weich, Fahrgastzelle steif.";
    sc.duration = 3.0;
    addGround(sc.world);
    SoftBody car = buildTestCar();
    car.translate({-6.0, 0.0, 0.0});
    car.setVelocity({50.0 / 3.6, 0, 0});
    sc.world.addBody(std::move(car));
    sc.world.addCollider(StaticCollider::box({0.6, 1.5, 0.0}, {0.5, 1.5, 4.0}, {}, 0.6, "wall"));
    return sc;
}

Scene rampJump() {
    Scene sc;
    sc.name = "ramp_jump";
    sc.description = "Auto-Rumpf faehrt mit 80 km/h ueber eine Rampe, fliegt und landet hart.";
    sc.duration = 4.0;
    addGround(sc.world, 0.9);
    SoftBody car = buildTestCar();
    car.translate({-14.0, 0.0, 0.0});
    car.setVelocity({80.0 / 3.6, 0, 0});
    sc.world.addBody(std::move(car));
    // Ramp: a box tilted 14 degrees around Z, its top surface starting at ground level.
    const real angle = deg(14);
    const Vec3 half{3.0, 0.5, 2.5};
    // Place the box so that the top face's rear edge touches the ground at x = -3.
    const real cx = -3.0 + half.x * std::cos(angle) + half.y * std::sin(angle);
    const real cy = half.x * std::sin(angle) - half.y * std::cos(angle);
    sc.world.addCollider(StaticCollider::box({cx, cy, 0.0}, half, {0, 0, angle}, 0.9, "ramp"));
    return sc;
}

Scene bridgeOverload() {
    Scene sc;
    sc.name = "bridge_overload";
    sc.description = "8 m Fachwerkbruecke, an den Enden gelagert. Die Last in der Mitte steigt, bis die Streben reissen.";
    sc.duration = 8.0;
    addGround(sc.world);

    LatticeSpec s;
    s.name = "bridge";
    s.cellsX = 16;
    s.cellsY = 2;
    s.cellsZ = 2;
    s.cellSize = {0.5, 0.5, 0.5};
    s.origin = {-4.0, 3.0, -0.5};
    s.totalMass = 1200.0;
    s.bodyDiagonals = false;
    s.edge.spring = 1.0e6;
    s.faceDiagonal.spring = 8.0e5;
    for (BeamParams* p : {&s.edge, &s.faceDiagonal}) {
        p->damp = 150;
        p->deform = 4.0e4;
        p->hardening = 0.1;
        p->strength = 5.5e4;
        p->deformLimit = 0.15;
        p->deformLimitExpansion = 0.1;
    }
    s.customizeNode = [](NodeParams& np, const Vec3& p) {
        if ((p.x < -3.99 || p.x > 3.99) && p.y < 3.01) np.fixed = true;
    };
    SoftBody bridge = buildLattice(s);

    // Load nodes: top layer within 1 m of the centre.
    auto loadNodes = std::make_shared<std::vector<std::uint32_t>>();
    for (std::uint32_t i = 0; i < bridge.nodeCount(); ++i) {
        const Vec3& p = bridge.positions()[i];
        if (std::abs(p.x) <= 0.51 && p.y > 3.99) loadNodes->push_back(i);
    }
    sc.world.addBody(std::move(bridge));
    sc.world.addCollider(StaticCollider::box({-4.5, 1.5, 0.0}, {0.5, 1.5, 1.0}, {}, 0.9, "pillar_left"));
    sc.world.addCollider(StaticCollider::box({4.5, 1.5, 0.0}, {0.5, 1.5, 1.0}, {}, 0.9, "pillar_right"));

    sc.update = [loadNodes](World& w) {
        // Ramp the total load from 0 to 60 t over 7 seconds.
        const real t = w.time();
        const real total = 60000.0 * std::min<real>(1.0, t / 7.0);
        const real perNode = std::max<real>(8.0, total / static_cast<real>(loadNodes->size()));
        SoftBody& b = w.body(0);
        for (std::uint32_t i : *loadNodes) b.setNodeMass(i, perNode);
    };
    return sc;
}

Scene accelBrake() {
    Scene sc;
    sc.name = "accel_brake";
    sc.description = "Fahrbares Auto (4 Pressure-Wheels, Federung, 5-Gang-Automatik): Vollgas-Sprint (Schaltvorgang 1->2) und Vollbremsung bis zum Stillstand.";
    sc.duration = 5.2;
    addGround(sc.world, 1.0);
    SoftBody car = buildDrivableCar();
    car.translate({-2.0, 0.01, 0.0});
    sc.world.addBody(std::move(car));
    sc.update = [](World& w) {
        const real t = w.time();
        VehicleControls c;
        if (t >= 0.15 && t < 3.6) {
            c.throttle = 1.0;
        } else if (t >= 3.6) {
            c.throttle = 0.0;
            c.brake = 1.0;
        }
        w.body(0).setControls(c);
    };
    return sc;
}

Scene slalom() {
    Scene sc;
    sc.name = "slalom";
    sc.description = "Fahrbares Auto lenkt per Hydro-Spurstangen im Slalom um drei Pylonen (Fahrwerks-Wanken & Reifenwalken sichtbar).";
    sc.duration = 4.8;
    addGround(sc.world, 1.05);
    SoftBody car = buildDrivableCar();
    car.translate({-2.0, 0.01, 0.0});
    sc.world.addBody(std::move(car));
    sc.world.addCollider(StaticCollider::box({12.0, 0.5,  0.9}, {0.35, 0.5, 0.35}, {}, 0.8, "pylon_1"));
    sc.world.addCollider(StaticCollider::box({24.0, 0.5, -0.9}, {0.35, 0.5, 0.35}, {}, 0.8, "pylon_2"));
    sc.world.addCollider(StaticCollider::box({36.0, 0.5,  0.9}, {0.35, 0.5, 0.35}, {}, 0.8, "pylon_3"));
    sc.update = [](World& w) {
        const real t = w.time();
        VehicleControls c;
        c.throttle = t < 4.2 ? 0.85 : 0.0;
        if (t > 0.6 && t < 4.2) {
            c.steer = 0.85 * std::sin((t - 0.6) * (2.0 * kPi / 2.2));
        }
        w.body(0).setControls(c);
    };
    return sc;
}

Scene curbImpact() {
    Scene sc;
    sc.name = "curb_impact";
    sc.description = "Fahrbares Auto beschleunigt auf ein einseitiges Hindernis (rechts): Radaufhaengung & Kotfluegel verformen sich beim Einschlag.";
    sc.duration = 3.6;
    addGround(sc.world, 1.0);
    SoftBody car = buildDrivableCar();
    car.translate({-2.0, 0.01, 0.0});
    sc.world.addBody(std::move(car));
    sc.world.addCollider(StaticCollider::box({16.5, 0.28, 0.85}, {0.45, 0.28, 0.65}, {}, 0.85, "curb_block"));
    sc.update = [](World& w) {
        const real t = w.time();
        VehicleControls c;
        c.throttle = t < 2.1 ? 1.0 : 0.0;
        c.brake = t >= 2.4 ? 0.7 : 0.0;
        w.body(0).setControls(c);
    };
    return sc;
}

}  // namespace

Scene makeScene(const std::string& name) {
    if (name == "accel_brake") return accelBrake();
    if (name == "slalom") return slalom();
    if (name == "curb_impact") return curbImpact();
    if (name == "cube_drop") return cubeDrop();
    if (name == "wall_crash") return wallCrash();
    if (name == "ramp_jump") return rampJump();
    if (name == "bridge_overload") return bridgeOverload();
    throw std::invalid_argument("unknown scene: " + name);
}

}  // namespace sb
