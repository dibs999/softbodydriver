// Loading / saving soft bodies in the ".sbeam.json" format.
//
// Format overview (see docs/SBEAM_FORMAT.md for the full reference):
//
//   {
//     "format": "sbeam", "version": 1, "name": "my_box",
//     "nodes": [
//       {"set": {"mass": 2.0, "friction": 0.9}},   // defaults for following rows
//       ["n0", 0.0, 0.0, 0.0],
//       ["n1", 1.0, 0.0, 0.0, {"fixed": true}]     // per-row override
//     ],
//     "beams": [
//       {"set": {"spring": 8e5, "damp": 120, "deform": 2e4, "strength": "inf"}},
//       ["n0", "n1"],
//       ["n0", "n2", {"type": "support"}]
//     ]
//   }
#pragma once

#include <string>

#include "sbcore/softbody.hpp"

namespace sb {

/// Parses sbeam JSON text. Throws std::runtime_error with a descriptive message on error.
SoftBody parseSBeam(const std::string& jsonText);
SoftBody loadSBeam(const std::string& path);

/// Serialises the *authoring* definition (spawn positions are the current positions).
std::string serializeSBeam(const SoftBody& body, int indent = 1);
void saveSBeam(const SoftBody& body, const std::string& path);

}  // namespace sb
