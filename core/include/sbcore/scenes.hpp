// Built-in demo / regression scenes for phase 1 (no wheels or powertrain yet).
#pragma once

#include <functional>
#include <string>
#include <vector>

#include "sbcore/world.hpp"

namespace sb {

struct Scene {
    std::string name;
    std::string description;
    World world;
    real duration = 5.0;  ///< Suggested simulation length in seconds.
    /// Optional hook called before every physics step (scripted loads, inputs ...).
    std::function<void(World&)> update;

    /// Runs `seconds` of simulation including the update hook.
    void run(real seconds);
    /// Single step including the update hook.
    void step();
};

std::vector<std::string> sceneNames();
/// Creates a scene by name. Throws std::invalid_argument for unknown names.
Scene makeScene(const std::string& name);

/// The car-shaped test hull used in several scenes (~1300 kg, 4.2 m long, X = forward).
SoftBody buildTestCar(const std::string& name = "test_car");

}  // namespace sb
