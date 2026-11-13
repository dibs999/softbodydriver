// Loader for *.car.json vehicle definitions. Unknown keys are rejected so typos are caught.
#include <fstream>
#include <sstream>
#include <stdexcept>

#include "nlohmann/json.hpp"
#include "sbcore/car.hpp"

namespace sb {

using json = nlohmann::json;

namespace {

template <typename F>
void forEach(const json& obj, const std::string& ctx, F&& f) {
    if (!obj.is_object()) throw std::runtime_error(ctx + ": expected an object");
    for (auto it = obj.begin(); it != obj.end(); ++it) {
        if (!it.key().empty() && it.key()[0] == '_') continue;  // comments
        if (!f(it.key(), it.value())) throw std::runtime_error(ctx + ": unknown key '" + it.key() + "'");
    }
}

#define SB_REAL(name, field) if (k == name) { field = v.get<real>(); return true; }
#define SB_INT(name, field) if (k == name) { field = v.get<int>(); return true; }
#define SB_BOOL(name, field) if (k == name) { field = v.get<bool>(); return true; }
#define SB_STR(name, field) if (k == name) { field = v.get<std::string>(); return true; }

void parseBody(CarBodyDef& b, const json& j) {
    forEach(j, "body", [&](const std::string& k, const json& v) {
        if (k == "style") {
            const std::string s = v.get<std::string>();
            if (s == "hatchback") b.style = BodyStyle::Hatchback;
            else if (s == "sedan") b.style = BodyStyle::Sedan;
            else if (s == "coupe") b.style = BodyStyle::Coupe;
            else if (s == "suv") b.style = BodyStyle::SUV;
            else throw std::runtime_error("body.style must be hatchback|sedan|coupe|suv");
            return true;
        }
        if (k == "paint") {
            for (std::size_t i = 0; i < 3 && i < v.size(); ++i) b.paint[i] = v[i].get<real>();
            return true;
        }
        SB_REAL("length", b.length) SB_REAL("width", b.width) SB_REAL("height", b.height)
        SB_REAL("wheelbase", b.wheelbase) SB_REAL("frontOverhang", b.frontOverhang)
        SB_REAL("trackFront", b.trackFront) SB_REAL("trackRear", b.trackRear)
        SB_REAL("groundClearance", b.groundClearance) SB_REAL("noseHeight", b.noseHeight)
        SB_REAL("hoodHeight", b.hoodHeight) SB_REAL("beltHeight", b.beltHeight)
        SB_REAL("tailHeight", b.tailHeight) SB_REAL("hoodLength", b.hoodLength)
        SB_REAL("windshieldRun", b.windshieldRun) SB_REAL("roofLength", b.roofLength)
        SB_REAL("rearWindowRun", b.rearWindowRun) SB_REAL("roofWidthRatio", b.roofWidthRatio)
        SB_REAL("cornerRadiusFront", b.cornerRadiusFront) SB_REAL("cornerRadiusRear", b.cornerRadiusRear)
        SB_REAL("archClearance", b.archClearance) SB_INT("doors", b.doors)
        SB_REAL("seatShift", b.seatShift) SB_REAL("rearSeatShift", b.rearSeatShift) SB_REAL("seatDrop", b.seatDrop)
        SB_REAL("frontDoorHingeX", b.frontDoorHingeX) SB_REAL("bPillarX", b.bPillarX)
        SB_REAL("rearDoorHingeX", b.rearDoorHingeX) SB_REAL("rearDoorRearX", b.rearDoorRearX)
        SB_REAL("tailgateHingeX", b.tailgateHingeX) SB_REAL("tailgateHingeY", b.tailgateHingeY)
        SB_REAL("tailgateLatchX", b.tailgateLatchX) SB_REAL("tailgateLatchY", b.tailgateLatchY)
        SB_REAL("tailgateHalfWidth", b.tailgateHalfWidth) SB_REAL("tailgateOpenDeg", b.tailgateOpenDeg)
        SB_REAL("tailgateMass", b.tailgateMass)
        SB_REAL("paintMetallic", b.paintMetallic)
        SB_REAL("dragCoefficient", b.dragCoefficient) SB_REAL("frontalArea", b.frontalArea)
        SB_REAL("rearWing", b.rearWing)
        SB_BOOL("bullbar", b.bullbar)
        SB_BOOL("detachableBumpers", b.detachableBumpers)
        SB_BOOL("detachableDoors", b.detachableDoors)
        SB_BOOL("detachableTailgate", b.detachableTailgate)
        return false;
    });
}

void parseAxle(AxleSuspensionDef& a, const json& j, const std::string& ctx) {
    forEach(j, ctx, [&](const std::string& k, const json& v) {
        SB_REAL("wheelRate", a.wheelRate) SB_REAL("bumpDamping", a.bumpDamping)
        SB_REAL("reboundDamping", a.reboundDamping) SB_REAL("antiRollRate", a.antiRollRate)
        SB_REAL("bumpTravel", a.bumpTravel) SB_REAL("droopTravel", a.droopTravel) SB_REAL("camber", a.camber) SB_REAL("toe", a.toe)
        return false;
    });
}

}  // namespace

CarDefinition parseCarDefinition(const std::string& text, const std::string& source) {
    json j;
    try {
        j = json::parse(text, nullptr, true, true);
    } catch (const std::exception& e) {
        throw std::runtime_error(source + ": JSON parse error: " + e.what());
    }
    CarDefinition d;
    bool noLidPart = false;
    try {
        forEach(j, source, [&](const std::string& k, const json& v) {
            SB_STR("id", d.id) SB_STR("name", d.name) SB_STR("brand", d.brand) SB_STR("description", d.description)
            if (k == "visualModel") {
                // Rendered by the game. A model without its own rear door parts keeps rigid rear
                // doors, so the physics does not open or shed a door the model cannot show.
                const bool rearParts = v.is_object() && v.contains("parts") && v["parts"].is_object() &&
                                       v["parts"].contains("rdoor_left") && v["parts"].contains("rdoor_right");
                if (!rearParts) d.body.detachableRearDoors = false;
                // Likewise a model without its own lid part keeps a rigid rear end.
                if (!(v.is_object() && v.contains("parts") && v["parts"].is_object() && v["parts"].contains("tailgate")))
                    noLidPart = true;
                return true;
            }
            if (k == "credits") return true;
            if (k == "body") { parseBody(d.body, v); return true; }
            if (k == "chassis") {
                forEach(v, "chassis", [&](const std::string& k2, const json& v2) {
                    const std::string& kk = k2;
                    if (kk == "curbMass") { d.chassis.curbMass = v2.get<real>(); return true; }
                    if (kk == "frontWeight") { d.chassis.frontWeight = v2.get<real>(); return true; }
                    if (kk == "bodyStiffness") { d.chassis.bodyStiffness = v2.get<real>(); return true; }
                    if (kk == "bodyStrength") { d.chassis.bodyStrength = v2.get<real>(); return true; }
                    return false;
                });
                return true;
            }
            if (k == "suspension") {
                forEach(v, "suspension", [&](const std::string& k2, const json& v2) {
                    if (k2 == "front") { parseAxle(d.front, v2, "suspension.front"); return true; }
                    if (k2 == "rear") { parseAxle(d.rear, v2, "suspension.rear"); return true; }
                    return false;
                });
                return true;
            }
            if (k == "tires") {
                forEach(v, "tires", [&](const std::string& k2, const json& v2) {
                    const std::string& kk = k2;
                    const json& vv = v2;
                    if (kk == "radius") { d.tires.radius = vv.get<real>(); return true; }
                    if (kk == "width") { d.tires.width = vv.get<real>(); return true; }
                    if (kk == "widthRear") { d.tires.widthRear = vv.get<real>(); return true; }
                    if (kk == "rimRadius") { d.tires.rimRadius = vv.get<real>(); return true; }
                    if (kk == "pressurePsi") { d.tires.pressurePsi = vv.get<real>(); return true; }
                    if (kk == "friction") { d.tires.friction = vv.get<real>(); return true; }
                    if (kk == "tireMass") { d.tires.tireMass = vv.get<real>(); return true; }
                    if (kk == "rimMass") { d.tires.rimMass = vv.get<real>(); return true; }
                    if (kk == "rays") { d.tires.rays = vv.get<int>(); return true; }
                    if (kk == "rimDesign") {
                        d.tires.rimDesign = vv.get<std::string>();
                        if (d.tires.rimDesign != "" && d.tires.rimDesign != "multispoke" && d.tires.rimDesign != "forged" &&
                            d.tires.rimDesign != "steel")
                            throw std::runtime_error("tires.rimDesign must be \"\", \"multispoke\", \"forged\" or \"steel\"");
                        return true;
                    }
                    if (kk == "tread") {
                        d.tires.tread = vv.get<std::string>();
                        if (d.tires.tread != "road" && d.tires.tread != "offroad")
                            throw std::runtime_error("tires.tread must be \"road\" or \"offroad\"");
                        return true;
                    }
                    return false;
                });
                return true;
            }
            if (k == "engine") {
                EngineDef& e = d.engine;
                forEach(v, "engine", [&](const std::string& kk, const json& vv) {
                    const std::string& k2 = kk;
                    const json& v2 = vv;
                    (void)k2;
                    if (kk == "torqueCurve") {
                        e.torqueCurve.clear();
                        for (const auto& p : vv) e.torqueCurve.push_back({p.at(0).get<real>(), p.at(1).get<real>()});
                        return true;
                    }
                    if (kk == "gears") { e.gears = vv.get<std::vector<real>>(); return true; }
                    if (kk == "name") { e.name = v2.get<std::string>(); return true; }
                    if (kk == "layout") { e.layout = v2.get<std::string>(); return true; }
                    if (kk == "position") {
                        e.position = v2.get<std::string>();
                        if (e.position != "front" && e.position != "mid")
                            throw std::runtime_error("engine.position must be front or mid");
                        return true;
                    }
                    if (kk == "automatic") { e.automatic = v2.get<bool>(); return true; }
                    if (kk == "type") {
                        e.type = v2.get<std::string>();
                        if (e.type != "combustion" && e.type != "electric")
                            throw std::runtime_error("engine.type must be combustion or electric");
                        return true;
                    }
                    if (kk == "cylinders") { e.cylinders = v2.get<int>(); return true; }
                    static const std::pair<const char*, real EngineDef::*> reals[] = {
                        {"idleRpm", &EngineDef::idleRpm}, {"regen", &EngineDef::regen}, {"redlineRpm", &EngineDef::redlineRpm},
                        {"inertia", &EngineDef::inertia}, {"friction", &EngineDef::friction},
                        {"engineBraking", &EngineDef::engineBraking}, {"mass", &EngineDef::mass},
                        {"reverse", &EngineDef::reverse}, {"finalDrive", &EngineDef::finalDrive},
                        {"shiftUpRpm", &EngineDef::shiftUpRpm}, {"shiftDownRpm", &EngineDef::shiftDownRpm},
                        {"maxBrakeTorque", &EngineDef::maxBrakeTorque}, {"frontBrakeBias", &EngineDef::frontBrakeBias},
                        {"handbrakeTorque", &EngineDef::handbrakeTorque}, {"lsd", &EngineDef::lsd},
                        {"fuelCapacity", &EngineDef::fuelCapacity}, {"bsfc", &EngineDef::bsfc},
                        {"radiatorUA", &EngineDef::radiatorUA}};
                    for (const auto& r : reals)
                        if (kk == r.first) { e.*(r.second) = v2.get<real>(); return true; }
                    return false;
                });
                return true;
            }
            return false;
        });
    } catch (const nlohmann::json::exception& e) {
        throw std::runtime_error(source + ": " + e.what());
    }
    if (noLidPart) d.body.detachableTailgate = false;
    if (d.engine.torqueCurve.empty())
        d.engine.torqueCurve = {{800, 120}, {1500, 200}, {2500, 240}, {4500, 240}, {6000, 200}, {6600, 0}};
    if (d.body.wheelbase + d.body.frontOverhang >= d.body.length)
        throw std::runtime_error(source + ": wheelbase + frontOverhang must be smaller than length");
    return d;
}

CarDefinition loadCarDefinition(const std::string& path) {
    std::ifstream f(path);
    if (!f) throw std::runtime_error("cannot open " + path);
    std::stringstream ss;
    ss << f.rdbuf();
    return parseCarDefinition(ss.str(), path);
}

}  // namespace sb
