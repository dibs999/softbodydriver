#include "sbcore/vehicle.hpp"

#include <algorithm>
#include <cmath>

#include "sbcore/builders.hpp"

namespace sb {

SoftBody buildDrivableCar(const CarSpec& spec) {
    // Grid: 12 cells along X (12 * 0.34 m = 4.08 m long),
    //        3 cells along Y (floor y=0.35..0.69..1.03..1.37 m),
    //        4 cells along Z (-0.68..+0.68 m, step 0.34 m).
    // Rear axle at i = 2 (x = 0.68 m), front axle at i = 10 (x = 3.40 m), wheelbase = 2.72 m.
    constexpr int kCellsX = 12, kCellsY = 3, kCellsZ = 4;
    constexpr real dx = 0.34, dy = 0.34, dz = 0.34;
    constexpr real yFloor = 0.35;
    constexpr int iRear = 2, iFront = 10;

    LatticeSpec ls;
    ls.name = spec.name;
    ls.cellsX = kCellsX;
    ls.cellsY = kCellsY;
    ls.cellsZ = kCellsZ;
    ls.cellSize = {dx, dy, dz};
    ls.origin = {0.0, yFloor, -0.5 * kCellsZ * dz};
    ls.totalMass = spec.chassisMass;
    ls.node.friction = 0.45;  // body panel / underbody sliding friction

    // Cut out the outer lower cells at the wheel arches (j == 0, k == 0 or 3, around iRear / iFront),
    // and only include the cabin greenhouse (j == 2) between i = 3 and i = 8.
    ls.includeCell = [](int i, int j, int k) {
        if (j == 2) return i >= 3 && i < 9;
        if (j == 0 && (k == 0 || k == kCellsZ - 1)) {
            if (std::abs(i - iRear) <= 1 || std::abs(i - iFront) <= 1) return false;
        }
        return true;
    };

    ls.edge.spring = 4.5e5;
    ls.faceDiagonal.spring = 3.2e5;
    ls.bodyDiagonal.spring = 2.2e5;
    for (BeamParams* p : {&ls.edge, &ls.faceDiagonal, &ls.bodyDiagonal}) {
        p->damp = 160;
        p->deform = 1.2e4;
        p->hardening = 0.06;
        p->deformLimit = 0.6;
        p->deformLimitExpansion = 0.35;
        p->strength = 3.6e4;
    }
    const real totalLen = kCellsX * dx;
    ls.customizeBeam = [totalLen](BeamParams& p, const Vec3& mid, LatticeBeamKind) {
        if (mid.x > totalLen - 1.0) {        // front crumple zone
            p.deform *= 0.28;
            p.strength *= 0.35;
        } else if (mid.x < 0.75) {           // rear crumple zone
            p.deform *= 0.45;
        } else if (mid.y > 0.75) {           // cabin safety cell
            p.deform *= 2.4;
            p.strength *= 2.4;
        }
    };

    SoftBody car = buildLattice(ls);

    auto cNode = [&](int i, int j, int k) -> std::uint32_t {
        const auto idx = car.findNode("n_" + std::to_string(i) + "_" + std::to_string(j) + "_" + std::to_string(k));
        return static_cast<std::uint32_t>(idx);
    };

    // Suspension beam templates.
    BeamParams spindleBeam;
    spindleBeam.spring = 3.8e5;
    spindleBeam.damp = 140.0;
    spindleBeam.deform = 4.5e4;
    spindleBeam.strength = 1.2e5;

    BeamParams wishbone;
    wishbone.spring = 3.2e5;
    wishbone.damp = 130.0;
    wishbone.deform = 3.2e4;
    wishbone.strength = 8.5e4;

    BeamParams strut;
    strut.spring = spec.suspensionSpring;
    strut.damp = spec.suspensionDamp * 0.12;  // split across multiple strut links; keeps explicit dt*c/m safe
    strut.deform = 3.5e4;
    strut.strength = 9.0e4;
    strut.precompression = spec.suspensionPrecompression;

    BeamParams bumpStop;
    bumpStop.type = BeamType::Support;
    bumpStop.spring = 2.2e5;
    bumpStop.damp = 180.0;
    bumpStop.precompression = 0.82;  // engages only after ~18% compression

    struct Corner {
        const char* name;
        int iAxle;
        bool rightSide;
        bool front;
    };
    const Corner corners[4] = {
        {"FL", iFront, false, true},
        {"FR", iFront, true,  true},
        {"RL", iRear,  false, false},
        {"RR", iRear,  true,  false},
    };

    for (const Corner& c : corners) {
        const real sign = c.rightSide ? 1.0 : -1.0;
        const int kRail = c.rightSide ? 3 : 1;   // inboard frame rail at z = +-0.34 m
        const int kTower = c.rightSide ? 4 : 0;  // upper shock tower rail at z = +-0.68 m
        const real xAxle = c.iAxle * dx;
        const real yHub = spec.wheelRadius;
        const real zIn = sign * 0.66;
        const real zOut = sign * 0.88;

        NodeParams hubNp;
        hubNp.mass = spec.hubMass;
        hubNp.friction = 0.6;
        hubNp.collision = true;

        const std::uint32_t hubIn = car.addNode(std::string(c.name) + "_hub_in", {xAxle, yHub, zIn}, hubNp);
        const std::uint32_t hubOut = car.addNode(std::string(c.name) + "_hub_out", {xAxle, yHub, zOut}, hubNp);

        // Rigid spindle bar between hubIn and hubOut.
        car.addBeam(hubIn, hubOut, spindleBeam);

        // Lower A-arm (wishbone) from hubIn to the inboard frame rail (j = 0, y = yFloor)
        // plus upper lateral links from the upper rail (j = 1) so hubIn stays upright while moving vertically.
        const std::uint32_t railRear = cNode(c.iAxle - 1, 0, kRail);
        const std::uint32_t railMid  = cNode(c.iAxle,     0, kRail);
        const std::uint32_t railFwd  = cNode(c.iAxle + 1, 0, kRail);
        car.addBeam(hubIn, railRear, wishbone);
        car.addBeam(hubIn, railMid,  wishbone);
        car.addBeam(hubIn, railFwd,  wishbone);
        // Cross-link hubOut to railMid so spindle roll is coupled to the suspension.
        car.addBeam(hubOut, railMid, strut);

        // Coilover struts from hubIn and hubOut up to the shock tower (j = 1, y = yFloor + dy).
        const std::uint32_t towerRear = cNode(c.iAxle - 1, 1, kTower);
        const std::uint32_t towerMid  = cNode(c.iAxle,     1, kTower);
        const std::uint32_t towerFwd  = cNode(c.iAxle + 1, 1, kTower);
        car.addBeam(hubIn,  towerMid,  strut);
        car.addBeam(hubOut, towerMid,  strut);
        car.addBeam(hubIn,  towerRear, strut);
        car.addBeam(hubIn,  towerFwd,  strut);

        // Progressive bump stops to prevent excessive upward travel on hard landings.
        car.addBeam(hubIn,  towerMid, bumpStop);
        car.addBeam(hubOut, towerMid, bumpStop);

        // Fore-aft control of hubOut:
        //   * Rear axle: fixed toe-control links to railRear and railFwd.
        //   * Front axle: opposing Hydro steering tie-rods (channel 0).
        //     For positive steer (+ = turn left toward -Z):
        //       - Left wheel (FL): hubOut moves rearward (-X) -> front tie-rod lengthens (+), rear shortens (-).
        //       - Right wheel (FR): hubOut moves forward (+X) -> front tie-rod shortens (-), rear lengthens (+).
        if (!c.front) {
            car.addBeam(hubOut, railRear, wishbone);
            car.addBeam(hubOut, railFwd,  wishbone);
            car.addBeam(hubOut, towerRear, strut);
            car.addBeam(hubOut, towerFwd,  strut);
        } else {
            BeamParams tieFwd = wishbone;
            tieFwd.type = BeamType::Hydro;
            tieFwd.hydroInput = 0;
            tieFwd.hydroRatio = c.rightSide ? -spec.steerHydroRatio : +spec.steerHydroRatio;

            BeamParams tieRear = wishbone;
            tieRear.type = BeamType::Hydro;
            tieRear.hydroInput = 0;
            tieRear.hydroRatio = c.rightSide ? +spec.steerHydroRatio : -spec.steerHydroRatio;

            car.addBeam(hubOut, railFwd,  tieFwd);
            car.addBeam(hubOut, railRear, tieRear);
        }

        // Build the PressureWheel around (hubRight, hubLeft) so axis = normalize(hubLeft - hubRight) ~ (0, 0, -1).
        PressureWheelSpec ws;
        ws.name = c.name;
        ws.hubRight = c.rightSide ? hubOut : hubIn;
        ws.hubLeft  = c.rightSide ? hubIn  : hubOut;
        ws.radius = spec.wheelRadius;
        ws.width = spec.wheelWidth;
        ws.numRays = spec.wheelRays;
        ws.tireMass = spec.tireMass;
        ws.friction = spec.tireFriction;
        ws.pressurePsi = spec.tirePressurePsi;
        ws.steered = c.front;
        ws.braked = true;
        ws.handbraked = !c.front;
        ws.driven = (spec.driveLayout == DriveLayout::AWD) ||
                    (spec.driveLayout == DriveLayout::FWD && c.front) ||
                    (spec.driveLayout == DriveLayout::RWD && !c.front);
        car.addWheel(ws);
    }

    PowertrainSpec pt = spec.powertrain;
    pt.layout = spec.driveLayout;
    car.setPowertrain(pt);
    return car;
}

}  // namespace sb
