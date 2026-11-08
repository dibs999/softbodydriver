// Records a simulation into a compact JSON file for offline viewing
// (tools/make_viewer.py turns it into a standalone HTML 3D replay).
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "sbcore/world.hpp"

namespace sb {

class Recorder {
public:
    Recorder(const World& world, std::string sceneName, std::string description, real fps = 30.0);

    /// Captures a frame if at least 1/fps has passed since the last captured frame.
    void captureIfDue(const World& world);
    /// Unconditionally captures a frame.
    void capture(const World& world);

    std::size_t frameCount() const { return frames_.size(); }
    std::string toJson() const;
    void save(const std::string& path) const;

private:
    struct Frame {
        real time = 0;
        std::vector<std::vector<std::int32_t>> positionsMm;      // per body, xyz interleaved
        std::vector<std::vector<std::uint32_t>> newlyBroken;    // per body
    };

    std::string scene_, description_;
    real fps_;
    real dt_;
    real nextFrameTime_ = 0;
    std::string staticJson_;  // colliders + body topology, captured at construction
    std::vector<std::vector<char>> broken_;
    std::vector<Frame> frames_;
};

}  // namespace sb
