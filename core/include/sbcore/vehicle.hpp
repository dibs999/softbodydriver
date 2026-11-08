// Procedural builder for a complete drivable node-beam car:
//   * Braced chassis with wheel-arch cutouts, soft front/rear crumple zones and
//     a reinforced passenger safety cell
//   * 4 independent suspension corners (horizontal lower A-arms to the frame
//     rails + vertical coilover struts to the shock towers + bump-stop support beams)
//   * Rack-and-pinion-style Hydro steering on the front spindles
//   * 4 BeamNG-style PressureWheels + 5-speed Powertrain
#pragma once

#include <string>

#include "sbcore/softbody.hpp"

namespace sb {

struct CarSpec {
    std::string name = "compact_car";
    real chassisMass = 1080.0;        ///< kg (plus 4x ~42 kg wheels+hubs -> ~1250 kg total)
    real wheelRadius = 0.33;          ///< m
    real wheelWidth = 0.22;           ///< m
    int wheelRays = 12;
    real tireMass = 18.0;             ///< kg per tire ring
    real hubMass = 12.0;              ///< kg per spindle node (2 per wheel)
    real tireFriction = 1.30;
    real tirePressurePsi = 32.0;
    real suspensionSpring = 6.5e4;    ///< N/m per coilover strut
    real suspensionDamp = 3200.0;     ///< N*s/m per coilover strut
    real suspensionPrecompression = 1.07;
    real steerHydroRatio = 0.068;     ///< Tie-rod length change at full lock (~22 deg)
    DriveLayout driveLayout = DriveLayout::AWD;
    PowertrainSpec powertrain;
};

SoftBody buildDrivableCar(const CarSpec& spec = {});

}  // namespace sb
