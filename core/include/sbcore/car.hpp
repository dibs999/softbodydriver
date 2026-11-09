// Data-driven realistic car generator.
//
// A car is described by a `CarDefinition` (loaded from content/vehicles/*.car.json): real
// exterior dimensions and side/plan profile (hood, windshield, roof, rear window, deck),
// chassis mass and weight distribution, double-wishbone suspension (wheel rates, bump /
// rebound damping, anti-roll bars, travel), tyres, engine + gearbox and cooling.
//
// `buildCar()` turns that into
//   * a node-beam SoftBody: shell structure with crumple zones and a stiff safety cell,
//     subframe, double wishbones with uprights, coilovers (spring + bump/rebound damper +
//     bump stop + droop strap), tie rods (hydro steering), torsion-bar anti-roll bars,
//     pressure wheels, engine block on breakable mounts, radiator, oil pan, fuel tank,
//     driveshaft, ColTri collision skin and the CarSystems (cooling, damage, fuel, brakes);
//   * a high-resolution visual model (paint, glass, lights, grille, trim, interior, chassis
//     parts, coil springs ...) whose vertices are *skinned* to the nodes (flexbody), so every
//     dent in the physics structure appears on the rendered car;
//   * rotating wheel meshes (tyre + rim + brake disc) in wheel-local coordinates.
#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "sbcore/softbody.hpp"

namespace sb {

enum class BodyStyle { Hatchback, Sedan, Coupe, SUV };

struct CarBodyDef {
    BodyStyle style = BodyStyle::Hatchback;
    real length = 4.26, width = 1.79, height = 1.45;
    real wheelbase = 2.62, frontOverhang = 0.89;
    real trackFront = 1.54, trackRear = 1.52;
    real groundClearance = 0.14;
    real noseHeight = 0.70;      ///< Top of the front fascia at the bumper.
    real hoodHeight = 0.98;      ///< Hood at the windshield base.
    real beltHeight = 1.00;      ///< Side window sill.
    real tailHeight = 0.98;      ///< Top of the rear fascia.
    real hoodLength = 1.15;      ///< Front bumper -> windshield base (horizontal).
    real windshieldRun = 0.80;   ///< Horizontal length of the windshield.
    real roofLength = 1.25;
    real rearWindowRun = 0.45;
    real roofWidthRatio = 0.78;  ///< Roof width / body width.
    real cornerRadiusFront = 0.32;
    real cornerRadiusRear = 0.26;
    real archClearance = 0.06;   ///< Wheel arch radius = tyre radius + this.
    int doors = 4;
    std::array<real, 3> paint{0.62, 0.05, 0.04};
    real paintMetallic = 0.55;
    bool detachableDoors = false; ///< Opt-in physical front doors with reversible latches.
    bool detachableBumpers = false; ///< Opt-in independent front/rear lower fascia assemblies.
};

struct CarChassisDef {
    real curbMass = 1280.0;       ///< kg incl. fluids, ~90 % fuel.
    real frontWeight = 0.60;      ///< Static front axle load fraction.
    real bodyStiffness = 1.0;     ///< Scales body beam springs.
    real bodyStrength = 1.0;      ///< Scales deform / break thresholds of the shell.
};

struct AxleSuspensionDef {
    real wheelRate = 30000.0;     ///< N/m at the wheel
    real bumpDamping = 2100.0;    ///< N*s/m at the wheel (compression)
    real reboundDamping = 4200.0; ///< N*s/m at the wheel (extension)
    real antiRollRate = 12000.0;  ///< N/m at the wheel, roll stiffness of the bar
    real bumpTravel = 0.085;      ///< m until the bump stop engages
    real droopTravel = 0.11;      ///< m until the droop strap limits extension
    real camber = -0.8;           ///< deg static camber (informational / visual)
};

struct TireDef {
    real radius = 0.316;          ///< 205/55 R16
    real width = 0.205;
    real rimRadius = 0.203;
    real pressurePsi = 33.0;
    real friction = 1.15;
    real tireMass = 9.5;
    real rimMass = 9.0;
    int rays = 16;
};

struct EngineDef {
    std::string name = "1.4 I4 Turbo";
    std::string layout = "FWD";   ///< FWD | RWD | AWD
    std::string position = "front"; ///< front | mid; independent of driven axle layout.
    std::vector<std::pair<real, real>> torqueCurve;  ///< (rpm, Nm)
    real idleRpm = 800, redlineRpm = 6200;
    real inertia = 0.16;
    real friction = 18.0;
    real engineBraking = 0.035;
    real mass = 135.0;            ///< Engine + gearbox
    int cylinders = 4;
    std::vector<real> gears{3.62, 2.09, 1.38, 1.03, 0.84, 0.70};
    real reverse = -3.45;
    real finalDrive = 3.94;
    bool automatic = true;
    real shiftUpRpm = 5600, shiftDownRpm = 1900;
    real maxBrakeTorque = 2200;
    real frontBrakeBias = 0.68;
    real handbrakeTorque = 1700;
    real lsd = 6.0;
    real fuelCapacity = 50.0;
    real bsfc = 245.0;
    real radiatorUA = 1500.0;
};

struct CarDefinition {
    std::string id = "car";
    std::string name = "Car";
    std::string brand = "";
    std::string description = "";
    CarBodyDef body;
    CarChassisDef chassis;
    AxleSuspensionDef front, rear;
    TireDef tires;
    EngineDef engine;
};

CarDefinition loadCarDefinition(const std::string& path);
CarDefinition parseCarDefinition(const std::string& jsonText, const std::string& sourceName = "car");

// ---------------------------------------------------------------------------- visuals

/// How one rendered vertex follows the node-beam structure.
///  * Node skin (weight[0] >= 0): v = R * rest + t + sum_k weight[k] * displacement(node[k]), where (R, t)
///    is the rigid motion of the passenger cell and displacement = node position minus its rigidly
///    transformed rest position. local[0] holds the rest position. Dents interpolate smoothly and no
///    per-node rotation noise reaches the surface.
///  * Line skin (weight[0] < 0): follows the segment node[0] -> node[1] (struts, springs, shafts).
struct VertexSkin {
    std::uint32_t node[4] = {0, 0, 0, 0};
    float weight[4] = {0, 0, 0, 0};
    float local[4][3] = {{0, 0, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0}};
};

struct MeshSurface {
    std::string material;          ///< paint, glass, chrome, trim, rubber, grille, headlight, taillight,
                                   ///< interior, chassis, spring, rim, tire, brake_disc, caliper, plate, mirror
    std::vector<float> positions;  ///< xyz (rest pose for skinned, wheel-local for wheel meshes)
    std::vector<float> normals;    ///< xyz
    std::vector<std::uint32_t> indices;
    std::vector<VertexSkin> skin;  ///< Empty for wheel meshes.
    bool doubleSided = false;
    bool steeringWheel = false;
};

struct CarVisual {
    std::vector<MeshSurface> skinned;              ///< Body + chassis parts (world space, skinned)
    std::vector<MeshSurface> wheelFront, wheelRear;///< Wheel-local: +Z = outward face, X/Y = wheel plane
    /// Skinning reference: rest positions of all nodes and four safety-cell floor nodes
    /// (FL, FR, RL, RR) whose motion defines the rigid frame of the car.
    std::vector<Vec3> restNodes;
    std::uint32_t frameRefs[4] = {0, 0, 0, 0};
    VertexSkin driverEye;                          ///< Cockpit camera anchor
    VertexSkin dashboard;                          ///< Instrument cluster centre
    VertexSkin steeringPivot;
    Vec3 steeringAxis{-1, 0, 0};                   ///< Points toward the driver in the build frame
    VertexSkin chaseTarget;                        ///< Look-at point for chase cameras
};

struct DoorLayout {
    std::vector<std::uint32_t> nodes, hingeNodes; // corners: x(rear/front)*4+y(bottom/top)*2+z(inner/outer)
    std::vector<std::uint32_t> hingeBeams, latchBeams, supportBeams;
    real rearX = 0, frontX = 0;
    int inputChannel = -1;
};

struct CarLayout {
    std::array<DoorLayout, 2> frontDoors; // left, right

    std::vector<std::uint32_t> bodyNodes;
    /// Floor nodes at the front / rear axle (left, right): forward = front - rear, right = R - L.
    std::uint32_t refFL = 0, refFR = 0, refRL = 0, refRR = 0;
    std::vector<std::uint32_t> engineNodes, radiatorNodes;
    // Independent eight-node bonnet: rear-left/right, front-left/right, lower then upper skin.
    std::vector<std::uint32_t> bonnetNodes;
    std::vector<std::uint32_t> bonnetStrutBeams; ///< Channel-1 lift supports; share the hinge breakgroup.
    std::vector<std::uint32_t> frontBumperNodes, rearBumperNodes; // cuboid ix*4 + iy*2 + iz
    real length = 0, width = 0, height = 0;
};

struct CarBuild {
    CarDefinition def;
    SoftBody body;
    CarVisual visual;
    CarLayout layout;
    std::vector<Vec3> restPositions;   ///< Positions at build time (for repair / reset)
};

/// Builds the complete car with the rear bumper at x = 0, ground at y = 0, centred on z = 0,
/// facing +X. Call body.translate() to place it.
CarBuild buildCar(const CarDefinition& def);

/// Computes the skinning state (rigid frame + per-node displacements) into `frames`.
void computeNodeFrames(const std::vector<Vec3>& positions, const CarVisual& vis, std::vector<float>& frames);
/// Deforms one skinned surface. `frames` from computeNodeFrames. Writes positions + normals.
void deformSurface(const std::vector<Vec3>& positions, const std::vector<float>& frames, const MeshSurface& surf,
                   std::vector<float>& outPositions, std::vector<float>& outNormals);
/// Evaluates a single skin binding (camera anchors).
Vec3 evalSkin(const std::vector<Vec3>& positions, const std::vector<float>& frames, const VertexSkin& s);

/// Binds a point (in the car's build coordinates) to the 4 nearest candidate nodes.
VertexSkin bindToNodes(const std::vector<Vec3>& restNodes, const std::vector<std::uint32_t>& candidates, const Vec3& p);
/// Like deformSurface, but normals come from the rigidly rotated rest normals and only switch to the
/// recomputed geometric normals where the surface is actually dented (for imported meshes with UV seams).
void deformSurfaceBlended(const std::vector<Vec3>& positions, const std::vector<float>& frames, const MeshSurface& surf,
                          std::vector<float>& outPositions, std::vector<float>& outNormals);

inline void computeNodeFrames(const SoftBody& body, const CarVisual& vis, std::vector<float>& frames) {
    computeNodeFrames(body.positions(), vis, frames);
}
inline void deformSurface(const SoftBody& body, const std::vector<float>& frames, const MeshSurface& surf,
                          std::vector<float>& outPositions, std::vector<float>& outNormals) {
    deformSurface(body.positions(), frames, surf, outPositions, outNormals);
}
inline Vec3 evalSkin(const SoftBody& body, const std::vector<float>& frames, const VertexSkin& s) {
    return evalSkin(body.positions(), frames, s);
}

}  // namespace sb
