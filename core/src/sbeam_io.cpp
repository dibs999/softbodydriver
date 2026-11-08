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
    return doc.dump(indent);
}

void saveSBeam(const SoftBody& body, const std::string& path) {
    std::ofstream f(path, std::ios::binary);
    if (!f) throw std::runtime_error("sbeam: cannot write " + path);
    f << serializeSBeam(body) << "\n";
}

}  // namespace sb
