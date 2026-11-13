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

#include <algorithm>
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
    /// Cabin layout corrections (m): front seats forward (+) / back (-) from the position derived
    /// from the B pillar, rear bench likewise, and front seat height lowered by seatDrop. Used to
    /// fit the generated seats to the seat positions of imported models.
    real seatShift = 0.0, rearSeatShift = 0.0, seatDrop = 0.0;
    /// Door lines of the physical doors (m from the rear bumper, 0 = derived from the profile), so
    /// an imported model's doors swing about its own hinges: front door hinge line, B-pillar seam
    /// (front door rear edge), rear door hinge line and rear door rear edge.
    real frontDoorHingeX = 0.0, bPillarX = 0.0, rearDoorHingeX = 0.0, rearDoorRearX = 0.0;
    int doors = 4;
    std::array<real, 3> paint{0.62, 0.05, 0.04};
    real paintMetallic = 0.55;
    bool detachableDoors = false; ///< Opt-in physical front doors with reversible latches.
    bool detachableRearDoors = true; ///< Four-door bodies also get physical rear doors (off for imported models without rear door parts).
    bool detachableBumpers = false; ///< Opt-in independent front/rear lower fascia assemblies.
    /// Opt-in physical rear lid: the tailgate of a hatchback / estate / SUV or the boot lid of a
    /// saloon, with breakable hinges and latch and gas struts on input channel 6. Its hinge and
    /// latch lines (x from the rear bumper, y above the ground; 0 = derived from the profile) let an
    /// imported model's lid swing about its own hinges. Off for imported models without a
    /// "tailgate" part.
    bool detachableTailgate = false;
    real tailgateHingeX = 0.0, tailgateHingeY = 0.0, tailgateLatchX = 0.0, tailgateLatchY = 0.0;
    real tailgateHalfWidth = 0.0, tailgateOpenDeg = 0.0, tailgateMass = 0.0;
    /// Aerodynamics. The collision skin's per-triangle drag is calibrated so that the whole
    /// body produces exactly Cd * A head-on. 0 = typical value for the body style /
    /// 0.84 * width * (height - groundClearance).
    real dragCoefficient = 0.0;
    /// Bolt-on rear wing: angle of attack in degrees (0 = none). A flat plate on two struts over
    /// the rear deck; its downforce and drag come from the triangle aerodynamics like the body's.
    real rearWing = 0.0;
    /// Bolt-on steel bull bar ahead of the front bumper (~30 kg of tube on the chassis rails).
    bool bullbar = false;
    real frontalArea = 0.0;
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
    /// deg static toe per wheel, + = toe-in. < -90 = default (front 0, rear 0.25: rear toe-in
    /// keeps the rear axle stable at the grip limit and at autobahn speed).
    real toe = -999.0;
};

struct TireDef {
    real radius = 0.316;          ///< 205/55 R16
    real width = 0.205;
    real widthRear = 0.0;         ///< Staggered rear tyres (0 = same as width).
    real rearWidth() const { return widthRear > 0.0 ? widthRear : width; }
    /// Tyre mass for one axle. `tireMass` is the wider tyre's; with staggered widths the narrower
    /// tyre is lighter in proportion. A narrow front with the full rear-tyre mass had ~12 % less
    /// tread-ring wave speed (same mass, less membrane tension) and lost grip to the standing wave
    /// at ~320 km/h, which sent the Concept GT weaving at top speed.
    real massFor(bool front) const {
        const real w = front ? width : rearWidth();
        return tireMass * w / std::max(width, rearWidth());
    }
    /// Combined mass of all four tyres.
    real totalMass() const { return 2.0 * (massFor(true) + massFor(false)); }
    real rimRadius = 0.203;
    real pressurePsi = 33.0;
    real friction = 1.15;
    real tireMass = 9.5;
    real rimMass = 9.0;
    int rays = 20;
    /// Tread pattern: "road" or "offroad" (block tread). The physics takes it as given; the game
    /// gives a block tread more grip on loose ground (gravel, sand, grass), the friction value
    /// above already carries what it loses on tarmac.
    std::string tread = "road";
    /// Rim look: "" = by body style, "multispoke", "forged" (deep concave) or "steel" (visual only).
    std::string rimDesign;
};

struct EngineDef {
    std::string name = "1.4 I4 Turbo";
    /// "combustion" or "electric". An electric motor has no idle, no clutch and cannot stall;
    /// it pulls from standstill, recuperates on lift-off and runs off a battery: fuelCapacity is
    /// then the battery's usable energy in kWh.
    std::string type = "combustion";
    /// Electric: lift-off recuperation torque as a fraction of peak torque (more with the brake).
    real regen = 0.2;
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
    /// Rigid part whose frame carries this vertex (-1 = passenger cell). Set when all bound nodes
    /// belong to one separate part (bonnet, door, bumper) so it can swing open or fall off intact.
    std::int32_t part = -1;
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
    /// Lamp surfaces are split per side so a lamp can break on its own: -1 = left (-z), +1 = right.
    std::int8_t side = 0;
    /// Glass is split into panes that crack and shatter on their own: 0 none, 1 windscreen,
    /// 2 rear window, 3 left side, 4 right side.
    std::int8_t pane = 0;
};

struct CarVisual {
    std::vector<MeshSurface> skinned;              ///< Body + chassis parts (world space, skinned)
    std::vector<MeshSurface> wheelFront, wheelRear;///< Wheel-local: +Z = outward face, X/Y = wheel plane
    /// Skinning reference: rest positions of all nodes and four safety-cell floor nodes
    /// (FL, FR, RL, RR) whose motion defines the rigid frame of the car.
    std::vector<Vec3> restNodes;
    std::uint32_t frameRefs[4] = {0, 0, 0, 0};
    /// Separate rigid parts (node sets) and node -> part index (-1 = not in a part).
    std::vector<std::vector<std::uint32_t>> parts;
    std::vector<std::int32_t> nodePart;
    VertexSkin driverEye;                          ///< Cockpit camera anchor
    VertexSkin dashboard;                          ///< Instrument cluster centre
    VertexSkin steeringPivot;
    Vec3 steeringAxis{-1, 0, 0};                   ///< Points toward the driver in the build frame
    VertexSkin chaseTarget;                        ///< Look-at point for chase cameras
    /// Number plate centres on the outer face (front, rear); the game puts the lettering there.
    VertexSkin plateFront, plateRear;
    bool hasPlates = false;
};

struct DoorLayout {
    std::vector<std::uint32_t> nodes, hingeNodes; // corners: x(rear/front)*4+y(bottom/top)*2+z(inner/outer)
    std::vector<std::uint32_t> hingeBeams, latchBeams, supportBeams;
    real rearX = 0, frontX = 0;
    int inputChannel = -1;
};

struct CarLayout {
    /// Rear wing (CarBodyDef::rearWing): plate corners front-left, front-right, rear-left,
    /// rear-right, and the body nodes its struts stand on.
    std::vector<std::uint32_t> wingNodes, wingMounts;
    /// Bull bar (CarBodyDef::bullbar): 8 corner nodes, inner (bumper side) x first, as the bumpers.
    std::vector<std::uint32_t> bullbarNodes;
    std::array<DoorLayout, 2> frontDoors; // left, right
    std::array<DoorLayout, 2> rearDoors;  // left, right (four-door bodies with detachable doors)

    std::vector<std::uint32_t> bodyNodes;
    /// Floor nodes at the front / rear axle (left, right): forward = front - rear, right = R - L.
    std::uint32_t refFL = 0, refFR = 0, refRL = 0, refRR = 0;
    std::vector<std::uint32_t> engineNodes, radiatorNodes;
    real dragArea = 0.0;          ///< Calibrated Cd * A of the collision skin (m^2).
    // Independent eight-node bonnet: rear-left/right, front-left/right, lower then upper skin.
    std::vector<std::uint32_t> bonnetNodes;
    std::vector<std::uint32_t> bonnetStrutBeams; ///< Channel-1 lift supports; share the hinge breakgroup.
    // Optional eight-node rear lid (tailgate / boot lid): hinge-left/right, latch-left/right,
    // inner then outer skin. Gas struts on channel 6 share the hinge breakgroup.
    std::vector<std::uint32_t> tailgateNodes, tailgateStrutBeams;
    std::vector<std::uint32_t> frontBumperNodes, rearBumperNodes; // cuboid ix*4 + iy*2 + iz
    /// Where a tow ball goes (see addTowBar): the rear rail nodes it is braced to and its offset
    /// from their centre in car axes (x forward, y up, z right).
    std::vector<std::uint32_t> towRails;
    Vec3 towOffset{};
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

/// Fits the tow bar for a trailer: a 4 kg ball 10 cm behind the rear in the middle, at hitch
/// height, on steel braces to the rear rails that bend above 40 kN and tear off above 60 kN. It is
/// added to the running car (in its present pose) only when a trailer is coupled, so a car without
/// one is unchanged. Returns the ball's node (the existing one on a second call), -1 if the layout
/// has no tow position.
std::int64_t addTowBar(SoftBody& body, const CarLayout& layout);

/// Computes the skinning state (rigid frame + per-node displacements) into `frames`.
void computeNodeFrames(const std::vector<Vec3>& positions, const CarVisual& vis, std::vector<float>& frames);
/// Registers rigid parts (fills vis.nodePart) and tags every skinned vertex bound only to one part.
void setRigidParts(CarVisual& vis, const std::vector<std::vector<std::uint32_t>>& parts);
/// Tags vertices of one surface whose bound nodes all belong to the same rigid part.
void tagRigidPartVertices(const CarVisual& vis, MeshSurface& surf);
/// Frame (R row-major 3x3, t) that carries a vertex: the part frame or the passenger cell.
const float* skinFrame(const std::vector<float>& frames, std::size_t nodeCount, std::int32_t part);
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
