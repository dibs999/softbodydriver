#include "sbcore/softbody.hpp"

#include <stdexcept>

namespace sb {
namespace {
bool mechanismDamaged(const std::vector<Beam>& beams, const DoorMechanism& m) {
    for (const auto* list : {&m.hingeBeams, &m.latchBeams, &m.supportBeams})
        for (auto index : *list) {
            if (beams[index].broken) return true;
            // A catching latch is shortened on purpose, that is not a bent striker.
            if (!(m.catching && list == &m.latchBeams) && beams[index].plasticStrain() > 0.005) return true;
        }
    return false;
}
}  // namespace

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

void SoftBody::addLid(const DoorMechanism& lid) {
    if (lid.nodes.empty() || lid.hingeBeams.empty() || lid.latchBeams.empty() ||
        lid.supportBeams.empty() || lid.inputChannel < 1)
        throw std::invalid_argument("lid mechanism requires panel, hinges, latch and struts");
    for (auto node : lid.nodes) if (node >= nodeCount()) throw std::invalid_argument("invalid lid node");
    for (const auto* list : {&lid.hingeBeams, &lid.latchBeams, &lid.supportBeams})
        for (auto beam : *list) if (beam >= beamCount()) throw std::invalid_argument("invalid lid beam");
    setInput(lid.inputChannel, 0);
    lids_.push_back(lid);
}

bool SoftBody::requestOpen(DoorMechanism& m, bool open) {
    if (open && length(centerOfMassVelocity()) > 0.55) return false;
    if (mechanismDamaged(beams_, m)) return false;
    if (m.requestedOpen == open) return false;
    m.requestedOpen = open;
    if (open) {
        m.latched = false;
        for (auto index : m.latchBeams) { beams_[index].disabled = true; beams_[index].lastForce = 0; }
    }
    return true;
}

bool SoftBody::setDoorOpen(std::size_t side, bool open) {
    return side < doors_.size() && requestOpen(doors_[side], open);
}

bool SoftBody::setLidOpen(std::size_t index, bool open) {
    return index < lids_.size() && requestOpen(lids_[index], open);
}

void SoftBody::updateDoors(real dt) {
    for (auto* list : {&doors_, &lids_}) {
        for (auto& door : *list) {
            // A torn or bent mechanism no longer moves on its actuator.
            if (mechanismDamaged(beams_, door)) { door.latched = false; continue; }
            door.travel += std::clamp((door.requestedOpen ? 1.0 : 0.0) - door.travel, -dt / door.stroke, dt / door.stroke);
            setInput(door.inputChannel, door.travel);
            if (door.catching) {
                // The caught latch draws the panel in to exactly shut.
                bool shut = true;
                for (auto index : door.latchBeams) {
                    Beam& beam = beams_[index];
                    beam.restLength += std::clamp(beam.baseRestLength - beam.restLength, -dt * door.catchSpeed, dt * door.catchSpeed);
                    shut &= std::abs(beam.restLength - beam.baseRestLength) < 1e-6;
                }
                if (shut) { door.catching = false; door.latched = true; }
                continue;
            }
            if (door.requestedOpen || door.latched || door.travel > 1e-6) continue;
            bool aligned = true, near = door.catchTolerance > 0.0;
            for (auto index : door.latchBeams) {
                const auto& beam = beams_[index];
                const real error = std::abs(length(pos_[beam.a] - pos_[beam.b]) - beam.baseRestLength);
                const bool still = length(vel_[beam.a] - vel_[beam.b]) < 0.15;
                aligned &= error < door.latchTolerance && still;
                // A slammed lid is caught on its way down, it does not have to come to rest first.
                near &= error < door.catchTolerance && length(vel_[beam.a] - vel_[beam.b]) < door.catchMaxSpeed;
            }
            if (aligned) {
                for (auto index : door.latchBeams) beams_[index].disabled = false;
                door.latched = true;
            } else if (near) {
                for (auto index : door.latchBeams) {
                    Beam& beam = beams_[index];
                    beam.restLength = length(pos_[beam.a] - pos_[beam.b]);
                    beam.disabled = false;
                }
                door.catching = true;
            }
        }
    }
}
} // namespace sb
