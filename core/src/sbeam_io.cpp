#include "sbcore/sbeam_io.hpp"

#include <cmath>
#include <fstream>
#include <sstream>
#include <stdexcept>

#include <nlohmann/json.hpp>

namespace sb {

using json = nlohmann::json;

namespace {

real readReal(const json& v, const std::string& key) {
    if (v.is_number()) return v.get<real>();
    if (v.is_string()) {
        const auto s = v.get<std::string>();
        if (s == "inf" || s == "FLT_MAX" || s == "infinity" || s == "Infinity") return kInf;
    }
    throw std::runtime_error("property '" + key + "' must be a number or \"inf\"");
}

json writeReal(real v) {
    if (std::isinf(v)) return "inf";
    return v;
}

void applyNodeProps(NodeParams& p, const json& obj, const std::string& ctx) {
    for (auto it = obj.begin(); it != obj.end(); ++it) {
        const std::string& k = it.key();
        if (k == "mass") p.mass = readReal(*it, k);
        else if (k == "friction") p.friction = readReal(*it, k);
        else if (k == "fixed") p.fixed = it->get<bool>();
        else if (k == "collision") p.collision = it->get<bool>();
        else throw std::runtime_error(ctx + ": unknown node property '" + k + "'");
    }
}

void applyBeamProps(BeamParams& p, const json& obj, const std::string& ctx) {
    for (auto it = obj.begin(); it != obj.end(); ++it) {
        const std::string& k = it.key();
        if (k == "type") {
            if (!beamTypeFromString(it->get<std::string>(), p.type))
                throw std::runtime_error(ctx + ": unknown beam type '" + it->get<std::string>() + "'");
        } else if (k == "spring") p.spring = readReal(*it, k);
        else if (k == "damp") p.damp = readReal(*it, k);
        else if (k == "deform") p.deform = readReal(*it, k);
        else if (k == "strength") p.strength = readReal(*it, k);
        else if (k == "deformLimit") p.deformLimit = readReal(*it, k);
        else if (k == "deformLimitExpansion") p.deformLimitExpansion = readReal(*it, k);
        else if (k == "hardening") p.hardening = readReal(*it, k);
        else if (k == "precompression") p.precompression = readReal(*it, k);
        else if (k == "springExpansion") p.springExpansion = readReal(*it, k);
        else if (k == "dampExpansion") p.dampExpansion = readReal(*it, k);
        else if (k == "hydroInput") p.hydroInput = it->get<int>();
        else if (k == "hydroRatio") p.hydroRatio = readReal(*it, k);
        else if (k == "breakGroup") p.breakGroup = it->is_null() ? "" : it->get<std::string>();
        else throw std::runtime_error(ctx + ": unknown beam property '" + k + "'");
    }
}

json nodePropsToJson(const NodeParams& p) {
    json o = json::object();
    o["mass"] = writeReal(p.mass);
    o["friction"] = writeReal(p.friction);
    if (p.fixed) o["fixed"] = true;
    if (!p.collision) o["collision"] = false;
    return o;
}

json beamPropsToJson(const BeamParams& p) {
    const BeamParams d;
    json o = json::object();
    if (p.type != BeamType::Normal) o["type"] = beamTypeToString(p.type);
    o["spring"] = writeReal(p.spring);
    o["damp"] = writeReal(p.damp);
    o["deform"] = writeReal(p.deform);
    o["strength"] = writeReal(p.strength);
    if (!std::isinf(p.deformLimit)) o["deformLimit"] = p.deformLimit;
    if (!std::isinf(p.deformLimitExpansion)) o["deformLimitExpansion"] = p.deformLimitExpansion;
    if (p.hardening != d.hardening) o["hardening"] = p.hardening;
    if (p.precompression != d.precompression) o["precompression"] = p.precompression;
    if (p.springExpansion >= 0) o["springExpansion"] = writeReal(p.springExpansion);
    if (p.dampExpansion >= 0) o["dampExpansion"] = writeReal(p.dampExpansion);
    if (p.hydroInput >= 0) {
        o["hydroInput"] = p.hydroInput;
        o["hydroRatio"] = p.hydroRatio;
    }
    if (!p.breakGroup.empty()) o["breakGroup"] = p.breakGroup;
    return o;
}

void applyTriProps(ColTriParams& p, const json& obj, const std::string& ctx) {
    for (auto it = obj.begin(); it != obj.end(); ++it) {
        const std::string& k = it.key();
        if (k == "friction") p.friction = readReal(*it, k);
        else if (k == "dragCoef") p.dragCoef = readReal(*it, k);
        else if (k == "breakable") p.breakable = it->get<bool>();
        else if (k == "breakGroup") p.breakGroup = it->is_null() ? "" : it->get<std::string>();
        else throw std::runtime_error(ctx + ": unknown triangle property '" + k + "'");
    }
}

json triPropsToJson(const ColTriParams& p) {
    const ColTriParams d;
    json o = json::object();
    o["friction"] = writeReal(p.friction);
    o["dragCoef"] = writeReal(p.dragCoef);
    if (p.breakable != d.breakable) o["breakable"] = p.breakable;
    if (!p.breakGroup.empty()) o["breakGroup"] = p.breakGroup;
    return o;
}

}  // namespace

SoftBody parseSBeam(const std::string& jsonText) {
    json doc;
    try {
        doc = json::parse(jsonText, nullptr, true, /*ignore_comments=*/true);
    } catch (const json::parse_error& e) {
        throw std::runtime_error(std::string("sbeam: JSON parse error: ") + e.what());
    }
    if (!doc.is_object()) throw std::runtime_error("sbeam: root must be an object");
    if (doc.contains("format") && doc["format"] != "sbeam") throw std::runtime_error("sbeam: 'format' must be \"sbeam\"");
    const int version = doc.value("version", 1);
    if (version != 1) throw std::runtime_error("sbeam: unsupported version " + std::to_string(version));

    SoftBody body(doc.value("name", std::string("body")));

    try {
        NodeParams nodeDefaults;
        const json& nodes = doc.at("nodes");
        if (!nodes.is_array()) throw std::runtime_error("sbeam: 'nodes' must be an array");
        std::size_t row = 0;
        for (const json& e : nodes) {
            const std::string ctx = "nodes[" + std::to_string(row++) + "]";
            if (e.is_object()) {
                if (e.value("reset", false)) nodeDefaults = NodeParams{};
                if (e.contains("set")) applyNodeProps(nodeDefaults, e["set"], ctx);
                continue;
            }
            if (!e.is_array() || e.size() < 4) throw std::runtime_error(ctx + ": expected [id, x, y, z, {props}?]");
            NodeParams p = nodeDefaults;
            if (e.size() >= 5) applyNodeProps(p, e[4], ctx);
            body.addNode(e[0].get<std::string>(), {e[1].get<real>(), e[2].get<real>(), e[3].get<real>()}, p);
        }

        BeamParams beamDefaults;
        if (doc.contains("beams")) {
            const json& beams = doc["beams"];
            if (!beams.is_array()) throw std::runtime_error("sbeam: 'beams' must be an array");
            row = 0;
            for (const json& e : beams) {
                const std::string ctx = "beams[" + std::to_string(row++) + "]";
                if (e.is_object()) {
                    if (e.value("reset", false)) beamDefaults = BeamParams{};
                    if (e.contains("set")) applyBeamProps(beamDefaults, e["set"], ctx);
                    continue;
                }
                if (!e.is_array() || e.size() < 2) throw std::runtime_error(ctx + ": expected [idA, idB, {props}?]");
                BeamParams p = beamDefaults;
                if (e.size() >= 3) applyBeamProps(p, e[2], ctx);
                try {
                    body.addBeam(e[0].get<std::string>(), e[1].get<std::string>(), p);
                } catch (const std::invalid_argument& ex) {
                    throw std::runtime_error(ctx + ": " + ex.what());
                }
            }
        }
        if (doc.contains("triangles")) {
            ColTriParams triDefaults;
            const json& tris = doc["triangles"];
            if (!tris.is_array()) throw std::runtime_error("sbeam: 'triangles' must be an array");
            row = 0;
            for (const json& e : tris) {
                const std::string ctx = "triangles[" + std::to_string(row++) + "]";
                if (e.is_object()) {
                    if (e.value("reset", false)) triDefaults = ColTriParams{};
                    if (e.contains("set")) applyTriProps(triDefaults, e["set"], ctx);
                    continue;
                }
                if (!e.is_array() || e.size() < 3)
                    throw std::runtime_error(ctx + ": expected [idA, idB, idC, {props}?]");
                ColTriParams p = triDefaults;
                if (e.size() >= 4) applyTriProps(p, e[3], ctx);
                try {
                    body.addTriangle(e[0].get<std::string>(), e[1].get<std::string>(), e[2].get<std::string>(), p);
                } catch (const std::invalid_argument& ex) {
                    throw std::runtime_error(ctx + ": " + ex.what());
                }
            }
        }
        if (doc.contains("wheels")) {
            const json& wheels = doc["wheels"];
            if (!wheels.is_array()) throw std::runtime_error("sbeam: 'wheels' must be an array");
            row = 0;
            for (const json& wj : wheels) {
                const std::string ctx = "wheels[" + std::to_string(row++) + "]";
                auto resolveNode = [&](const json& v) -> std::uint32_t {
                    if (v.is_number_unsigned()) return v.get<std::uint32_t>();
                    const auto id = v.get<std::string>();
                    const auto idx = body.findNode(id);
                    if (idx < 0) throw std::runtime_error(ctx + ": unknown hub node '" + id + "'");
                    return static_cast<std::uint32_t>(idx);
                };
                PressureWheelSpec ws;
                ws.name = wj.value("name", "wheel");
                ws.hubRight = resolveNode(wj.at("hubRight"));
                ws.hubLeft = resolveNode(wj.at("hubLeft"));
                ws.radius = wj.value("radius", ws.radius);
                ws.width = wj.value("width", ws.width);
                ws.numRays = wj.value("numRays", ws.numRays);
                ws.tireMass = wj.value("tireMass", ws.tireMass);
                ws.friction = wj.value("friction", ws.friction);
                ws.pressurePsi = wj.value("pressurePsi", ws.pressurePsi);
                ws.spokeSpring = wj.value("spokeSpring", ws.spokeSpring);
                ws.spokeDamp = wj.value("spokeDamp", ws.spokeDamp);
                ws.treadSpring = wj.value("treadSpring", ws.treadSpring);
                ws.treadDamp = wj.value("treadDamp", ws.treadDamp);
                ws.driven = wj.value("driven", ws.driven);
                ws.steered = wj.value("steered", ws.steered);
                ws.braked = wj.value("braked", ws.braked);
                ws.handbraked = wj.value("handbraked", ws.handbraked);
                if (wj.contains("treadNodes")) {
                    PressureWheel pw;
                    pw.spec = ws;
                    pw.treadNodes = wj["treadNodes"].get<std::vector<std::uint32_t>>();
                    if (wj.contains("beamIndices"))
                        pw.beamIndices = wj["beamIndices"].get<std::vector<std::uint32_t>>();
                    body.wheels().push_back(std::move(pw));
                } else {
                    body.addWheel(ws);
                }
            }
        }

        if (doc.contains("powertrain")) {
            const json& pj = doc["powertrain"];
            PowertrainSpec pt;
            const std::string layout = pj.value("layout", "AWD");
            if (layout == "RWD") pt.layout = DriveLayout::RWD;
            else if (layout == "FWD") pt.layout = DriveLayout::FWD;
            else pt.layout = DriveLayout::AWD;
            pt.idleRpm = pj.value("idleRpm", pt.idleRpm);
            pt.redlineRpm = pj.value("redlineRpm", pt.redlineRpm);
            pt.finalDrive = pj.value("finalDrive", pt.finalDrive);
            pt.automatic = pj.value("automatic", pt.automatic);
            pt.maxBrakeTorque = pj.value("maxBrakeTorque", pt.maxBrakeTorque);
            if (pj.contains("forwardGears")) pt.forwardGears = pj["forwardGears"].get<std::vector<real>>();
            body.setPowertrain(pt);
        }
    } catch (const json::exception& e) {
        throw std::runtime_error(std::string("sbeam: ") + e.what());
    } catch (const std::invalid_argument& e) {
        throw std::runtime_error(std::string("sbeam: ") + e.what());
    }
    return body;
}

SoftBody loadSBeam(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) throw std::runtime_error("sbeam: cannot open " + path);
    std::stringstream ss;
    ss << f.rdbuf();
    try {
        return parseSBeam(ss.str());
    } catch (const std::runtime_error& e) {
        throw std::runtime_error(path + ": " + e.what());
    }
}

std::string serializeSBeam(const SoftBody& body, int indent) {
    json doc;
    doc["format"] = "sbeam";
    doc["version"] = 1;
    doc["name"] = body.name();

    json nodes = json::array();
    json lastNode;
    const auto& pos = body.positions();
    for (std::uint32_t i = 0; i < body.nodeCount(); ++i) {
        json props = nodePropsToJson(body.nodeParams(i));
        if (props != lastNode) {
            nodes.push_back({{"reset", true}, {"set", props}});
            lastNode = props;
        }
        nodes.push_back({body.nodeIds()[i], pos[i].x, pos[i].y, pos[i].z});
    }
    doc["nodes"] = nodes;

    json beams = json::array();
    json lastBeam;
    for (const Beam& bm : body.beams()) {
        json props = beamPropsToJson(bm.params);
        if (props != lastBeam) {
            beams.push_back({{"reset", true}, {"set", props}});
            lastBeam = props;
        }
        beams.push_back({body.nodeIds()[bm.a], body.nodeIds()[bm.b]});
    }
    doc["beams"] = beams;

    if (!body.triangles().empty()) {
        json tris = json::array();
        json lastTri;
        for (const ColTri& t : body.triangles()) {
            json props = triPropsToJson(t.params);
            if (props != lastTri) {
                tris.push_back({{"reset", true}, {"set", props}});
                lastTri = props;
            }
            tris.push_back({body.nodeIds()[t.a], body.nodeIds()[t.b], body.nodeIds()[t.c]});
        }
        doc["triangles"] = std::move(tris);
    }

    if (!body.wheels().empty()) {
        json wheels = json::array();
        for (const PressureWheel& w : body.wheels()) {
            const auto& ws = w.spec;
            json wj;
            wj["name"] = ws.name;
            wj["hubRight"] = body.nodeIds()[ws.hubRight];
            wj["hubLeft"] = body.nodeIds()[ws.hubLeft];
            wj["radius"] = ws.radius;
            wj["width"] = ws.width;
            wj["numRays"] = ws.numRays;
            wj["tireMass"] = ws.tireMass;
            wj["friction"] = ws.friction;
            wj["pressurePsi"] = ws.pressurePsi;
            wj["spokeSpring"] = ws.spokeSpring;
            wj["spokeDamp"] = ws.spokeDamp;
            wj["treadSpring"] = ws.treadSpring;
            wj["treadDamp"] = ws.treadDamp;
            wj["driven"] = ws.driven;
            wj["steered"] = ws.steered;
            wj["braked"] = ws.braked;
            wj["handbraked"] = ws.handbraked;
            wj["treadNodes"] = w.treadNodes;
            wj["beamIndices"] = w.beamIndices;
            wheels.push_back(std::move(wj));
        }
        doc["wheels"] = std::move(wheels);
    }

    if (body.hasPowertrain()) {
        const auto& pt = body.powertrain().spec();
        json pj;
        pj["layout"] = pt.layout == DriveLayout::RWD ? "RWD" : (pt.layout == DriveLayout::FWD ? "FWD" : "AWD");
        pj["idleRpm"] = pt.idleRpm;
        pj["redlineRpm"] = pt.redlineRpm;
        pj["finalDrive"] = pt.finalDrive;
        pj["automatic"] = pt.automatic;
        pj["maxBrakeTorque"] = pt.maxBrakeTorque;
        pj["forwardGears"] = pt.forwardGears;
        doc["powertrain"] = std::move(pj);
    }

    return doc.dump(indent);
}

void saveSBeam(const SoftBody& body, const std::string& path) {
    std::ofstream f(path, std::ios::binary);
    if (!f) throw std::runtime_error("sbeam: cannot write " + path);
    f << serializeSBeam(body) << "\n";
}

}  // namespace sb
