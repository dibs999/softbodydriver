#include "sbcore/softbody.hpp"

#include <stdexcept>

namespace sb {
void SoftBody::addDoor(const DoorMechanism& door) {
    if (door.nodes.empty() || door.hingeBeams.empty() || door.latchBeams.empty() ||
        door.supportBeams.empty() || door.inputChannel < 2)
        throw std::invalid_argument("door mechanism requires panel, hinges, latch and actuator");
    for (auto node : door.nodes) if (node >= nodeCount()) throw std::invalid_argument("invalid door node");
    for (const auto* list : {&door.hingeBeams, &door.latchBeams, &door.supportBeams})
        for (auto beam : *list) if (beam >= beamCount()) throw std::invalid_argument("invalid door beam");
    setInput(door.inputChannel, 0);
    doors_.push_back(door);
}

bool SoftBody::setDoorOpen(std::size_t side, bool open) {
    if (side >= doors_.size()) return false;
    auto& door = doors_[side];
    if (open && length(centerOfMassVelocity()) > 0.55) return false;
    for (const auto* list : {&door.hingeBeams, &door.latchBeams, &door.supportBeams})
        for (auto index : *list) if (beams_[index].broken || beams_[index].plasticStrain() > 0.005) return false;
    if (door.requestedOpen == open) return false;
    door.requestedOpen = open;
    if (open) {
        door.latched = false;
        for (auto index : door.latchBeams) { beams_[index].disabled = true; beams_[index].lastForce = 0; }
    }
    return true;
}

void SoftBody::updateDoors(real dt) {
    for (auto& door : doors_) {
        bool damaged = false;
        for (const auto* list : {&door.hingeBeams, &door.latchBeams, &door.supportBeams})
            for (auto index : *list) damaged |= beams_[index].broken || beams_[index].plasticStrain() > 0.005;
        if (damaged) { door.latched = false; continue; }
        door.travel += std::clamp((door.requestedOpen ? 1.0 : 0.0) - door.travel, -dt / 1.5, dt / 1.5);
        setInput(door.inputChannel, door.travel);
        if (door.requestedOpen || door.latched || door.travel > 1e-6) continue;
        bool aligned = true;
        for (auto index : door.latchBeams) {
            const auto& beam = beams_[index];
            aligned &= std::abs(length(pos_[beam.a] - pos_[beam.b]) - beam.baseRestLength) < 0.015;
            aligned &= length(vel_[beam.a] - vel_[beam.b]) < 0.15;
        }
        if (aligned) {
            for (auto index : door.latchBeams) beams_[index].disabled = false;
            door.latched = true;
        }
    }
}
} // namespace sb
