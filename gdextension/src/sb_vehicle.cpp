#include "sb_vehicle.h"

#include <algorithm>
#include <cmath>
#include <cstring>

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include "sb_world.h"
#include "sbcore/render_motion.hpp"

namespace godot {

namespace {
// Plastic strain of a beam around a lamp at which the lamp counts as smashed (3 % crush).
constexpr double kLampBreakStrain = 0.03;
// Plastic strain of the frame around a pane at which the glass gives way (bonded glass does not
// follow more than about 1.5 % distortion of its aperture).
constexpr double kGlassBreakStrain = 0.015;

inline Vector3 toG(const sb::Vec3& v) { return Vector3(static_cast<real_t>(v.x), static_cast<real_t>(v.y), static_cast<real_t>(v.z)); }
inline sb::Vec3 toS(const Vector3& v) { return {v.x, v.y, v.z}; }

Color fallbackColor(const std::string& n) {
    if (n == "glass") return Color(0.08, 0.1, 0.12, 0.45);
    if (n == "chrome" || n == "rim") return Color(0.8, 0.8, 0.82);
    if (n == "tire") return Color(0.05, 0.05, 0.05);
    if (n == "headlight") return Color(0.95, 0.95, 0.9);
    if (n == "taillight") return Color(0.7, 0.02, 0.02);
    if (n == "plate") return Color(0.92, 0.92, 0.9);
    if (n == "interior") return Color(0.08, 0.08, 0.09);
    if (n == "headliner") return Color(0.56, 0.55, 0.52);
    if (n == "fabric") return Color(0.14, 0.14, 0.15);
    if (n == "carpet") return Color(0.05, 0.05, 0.055);
    if (n == "belt") return Color(0.04, 0.04, 0.045);
    if (n == "arch_liner") return Color(0.035, 0.035, 0.035);
    if (n == "underbody") return Color(0.11, 0.11, 0.115);
    if (n == "exhaust") return Color(0.30, 0.27, 0.24);
    if (n == "heatshield") return Color(0.62, 0.62, 0.60);
    if (n == "tank") return Color(0.10, 0.10, 0.105);
    if (n == "seat_frame") return Color(0.25, 0.25, 0.26);
    if (n == "seat_insert") return Color(0.07, 0.072, 0.08);
    if (n == "seat_belt") return Color(0.035, 0.035, 0.04);
    if (n == "spring") return Color(0.75, 0.1, 0.08);
    if (n == "caliper") return Color(0.8, 0.15, 0.1);
    if (n == "engine") return Color(0.35, 0.36, 0.38);
    if (n == "brake_disc") return Color(0.45, 0.44, 0.43);
    return Color(0.12, 0.12, 0.13);
}

}  // namespace

void SBVehicle::_bind_methods() {
    ClassDB::bind_method(D_METHOD("refuel", "litres"), &SBVehicle::refuel);
    ClassDB::bind_method(D_METHOD("release_bonnet"), &SBVehicle::release_bonnet);
    ClassDB::bind_method(D_METHOD("set_input", "throttle", "brake", "steer", "handbrake"), &SBVehicle::set_input);
    ClassDB::bind_method(D_METHOD("set_clutch", "clutch"), &SBVehicle::set_clutch);
    ClassDB::bind_method(D_METHOD("set_surface_grip", "grip"), &SBVehicle::set_surface_grip);
    ClassDB::bind_method(D_METHOD("set_gear", "gear"), &SBVehicle::set_gear);
    ClassDB::bind_method(D_METHOD("shift_up"), &SBVehicle::shift_up);
    ClassDB::bind_method(D_METHOD("shift_down"), &SBVehicle::shift_down);
    ClassDB::bind_method(D_METHOD("set_automatic", "automatic"), &SBVehicle::set_automatic);
    ClassDB::bind_method(D_METHOD("is_automatic"), &SBVehicle::is_automatic);
    ClassDB::bind_method(D_METHOD("set_ignition", "on"), &SBVehicle::set_ignition);
    ClassDB::bind_method(D_METHOD("start_engine"), &SBVehicle::start_engine);
    ClassDB::bind_method(D_METHOD("set_tcs", "on"), &SBVehicle::set_tcs);
    ClassDB::bind_method(D_METHOD("get_tcs"), &SBVehicle::get_tcs);
    ClassDB::bind_method(D_METHOD("set_abs", "on"), &SBVehicle::set_abs);
    ClassDB::bind_method(D_METHOD("get_abs"), &SBVehicle::get_abs);
    ClassDB::bind_method(D_METHOD("set_steer_rate", "rate"), &SBVehicle::set_steer_rate);
    ClassDB::bind_method(D_METHOD("reset_to", "xform"), &SBVehicle::reset_to);
    ClassDB::bind_method(D_METHOD("relocate_to", "xform"), &SBVehicle::relocate_to);
    ClassDB::bind_method(D_METHOD("service_repair"), &SBVehicle::service_repair);
    ClassDB::bind_method(D_METHOD("set_door_open", "index", "open"), &SBVehicle::set_door_open);
    ClassDB::bind_method(D_METHOD("toggle_door", "index"), &SBVehicle::toggle_door);
    ClassDB::bind_method(D_METHOD("get_door_states"), &SBVehicle::get_door_states);
    ClassDB::bind_method(D_METHOD("get_lamp_states"), &SBVehicle::get_lamp_states);
    ClassDB::bind_method(D_METHOD("get_glass_states"), &SBVehicle::get_glass_states);
    ClassDB::bind_method(D_METHOD("get_bumper_states"), &SBVehicle::get_bumper_states);
    ClassDB::bind_method(D_METHOD("repair_in_place"), &SBVehicle::repair_in_place);
    ClassDB::bind_method(D_METHOD("set_debug_view", "on"), &SBVehicle::set_debug_view);
    ClassDB::bind_method(D_METHOD("get_debug_view"), &SBVehicle::get_debug_view);
    ClassDB::bind_method(D_METHOD("set_body_visible", "on"), &SBVehicle::set_body_visible);
    ClassDB::bind_method(D_METHOD("get_telemetry"), &SBVehicle::get_telemetry);
    ClassDB::bind_method(D_METHOD("get_info"), &SBVehicle::get_info);
    ClassDB::bind_method(D_METHOD("get_position_ws"), &SBVehicle::get_position_ws);
    ClassDB::bind_method(D_METHOD("get_chase_target"), &SBVehicle::get_chase_target);
    ClassDB::bind_method(D_METHOD("get_driver_eye"), &SBVehicle::get_driver_eye);
    ClassDB::bind_method(D_METHOD("get_dashboard_transform"), &SBVehicle::get_dashboard_transform);
    ClassDB::bind_method(D_METHOD("get_mirror_surfaces"), &SBVehicle::get_mirror_surfaces);
    ClassDB::bind_method(D_METHOD("get_visual_basis"), &SBVehicle::get_visual_basis);
    ClassDB::bind_method(D_METHOD("get_forward"), &SBVehicle::get_forward);
    ClassDB::bind_method(D_METHOD("get_up"), &SBVehicle::get_up);
    ClassDB::bind_method(D_METHOD("get_right"), &SBVehicle::get_right);
    ClassDB::bind_method(D_METHOD("get_velocity"), &SBVehicle::get_velocity);
    ClassDB::bind_method(D_METHOD("get_speed_kmh"), &SBVehicle::get_speed_kmh);
    ClassDB::bind_method(D_METHOD("get_engine_rpm"), &SBVehicle::get_engine_rpm);
    ClassDB::bind_method(D_METHOD("get_wheel_slip"), &SBVehicle::get_wheel_slip);
    ClassDB::bind_method(D_METHOD("attach_model", "root", "to_build", "options"), &SBVehicle::attach_model);
    ClassDB::bind_method(D_METHOD("get_wheel_load"), &SBVehicle::get_wheel_load);
    ClassDB::bind_method(D_METHOD("get_effect_anchors"), &SBVehicle::get_effect_anchors);
    ClassDB::bind_method(D_METHOD("puncture_tire", "wheel", "leak_psi_per_second"), &SBVehicle::puncture_tire);
    ClassDB::bind_method(D_METHOD("take_impact"), &SBVehicle::take_impact);
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "debug_view"), "set_debug_view", "get_debug_view");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "tcs"), "set_tcs", "get_tcs");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "abs"), "set_abs", "get_abs");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "automatic"), "set_automatic", "is_automatic");
}

// ============================================================================ setup

void SBVehicle::setup(SBWorld* world, sb::CarBuild&& build, const Transform3D& xform, const Dictionary& materials) {
    world_ = world;
    def_ = build.def;
    visual_ = std::move(build.visual);
    layout_ = build.layout;
    restPositions_ = build.restPositions;
    sb::SoftBody body = std::move(build.body);
    body.controls().steerRate = ctl_.steerRate;
    bodyIndex_ = static_cast<int>(world_->world().addBody(std::move(body)));
    applyTransform(xform);
    pos_ = world_->world().body(static_cast<std::size_t>(bodyIndex_)).positions();
    vel_.assign(pos_.size(), {});
    for (const sb::Beam& bm : world_->world().body(static_cast<std::size_t>(bodyIndex_)).beams()) {
        beamPairs_.push_back(bm.a);
        beamPairs_.push_back(bm.b);
    }
    buildMeshes(materials);
    snapshotValid_ = true;
}

void SBVehicle::applyTransform(const Transform3D& xform) {
    sb::SoftBody& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
    const double xMid = 0.5 * (restPositions_[layout_.refFL].x + restPositions_[layout_.refRL].x);
    std::vector<sb::Vec3> p(restPositions_.size());
    for (std::size_t i = 0; i < p.size(); ++i) {
        const sb::Vec3& r = restPositions_[i];
        const Vector3 w = xform.xform(Vector3(static_cast<real_t>(r.x - xMid), static_cast<real_t>(r.y + 0.03), static_cast<real_t>(r.z)));
        p[i] = toS(w);
    }
    body.repair(p);
    bonnetOpenRequested_ = false;
    bonnetSupportTravel_ = 0.0;
    body.setInput(1, 0.0);
    visualResetPending_ = true;
}

Ref<Material> SBVehicle::materialFor(const std::string& name, const Dictionary& lib) const {
    std::string base = name;
    for (const std::string prefix : {"bumper_front_", "bumper_rear_", "door_left_", "door_right_"})
        if (base.rfind(prefix, 0) == 0) { base = base.substr(prefix.size()); break; }
    if (base == "mirror_left" || base == "mirror_right") base = "mirror";
    const String key(base == "bonnet" ? "paint" : base == "bonnet_inner" ? "interior" : base.c_str());
    Ref<Material> m;
    if (lib.has(key)) m = lib[key];
    if (base == "paint" || base == "bonnet") {
        Ref<StandardMaterial3D> pm;
        if (m.is_valid() && Object::cast_to<StandardMaterial3D>(m.ptr())) pm = m->duplicate();
        else {
            pm.instantiate();
            pm->set_roughness(0.25);
            pm->set_feature(BaseMaterial3D::FEATURE_CLEARCOAT, true);
            pm->set_clearcoat(0.9);
        }
        pm->set_albedo(Color(static_cast<float>(def_.body.paint[0]), static_cast<float>(def_.body.paint[1]),
                             static_cast<float>(def_.body.paint[2])));
        pm->set_metallic(static_cast<float>(def_.body.paintMetallic));
        return pm;
    }
    if (m.is_valid()) return m;
    Ref<StandardMaterial3D> sm;
    sm.instantiate();
    const Color c = fallbackColor(base);
    sm->set_albedo(c);
    if (c.a < 1.0f) sm->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
    if (base == "glass") sm->set_cull_mode(BaseMaterial3D::CULL_DISABLED);
    if (base == "headlight" || base == "taillight") {
        sm->set_feature(BaseMaterial3D::FEATURE_EMISSION, true);
        sm->set_emission(c);
        sm->set_emission_energy_multiplier(base == "headlight" ? 1.5f : 0.8f);
    }
    if (base == "chrome" || base == "rim") {
        sm->set_metallic(1.0);
        sm->set_roughness(0.15);
    }
    return sm;
}

void SBVehicle::buildMeshes(const Dictionary& materials) {
    RenderingServer* rs = RenderingServer::get_singleton();
    for (const sb::MeshSurface& s : visual_.skinned) {
        SurfaceGpu g;
        g.mesh.instantiate();
        const std::size_t nv = s.positions.size() / 3;
        PackedVector3Array v, n;
        PackedVector2Array uv;
        v.resize(static_cast<int64_t>(nv));
        n.resize(static_cast<int64_t>(nv));
        uv.resize(static_cast<int64_t>(nv));
        for (std::size_t i = 0; i < nv; ++i) {
            const Vector3 p(s.positions[i * 3], s.positions[i * 3 + 1], s.positions[i * 3 + 2]);
            const Vector3 nr(s.normals[i * 3], s.normals[i * 3 + 1], s.normals[i * 3 + 2]);
            v[static_cast<int64_t>(i)] = p;
            n[static_cast<int64_t>(i)] = nr;
            // Box projection of the rest pose (metres): fabric and grain textures stay on the panel
            // while the vertices themselves are rewritten in world space every frame.
            const Vector3 a = nr.abs();
            uv[static_cast<int64_t>(i)] = a.x >= a.y && a.x >= a.z ? Vector2(p.z, p.y) : (a.y >= a.z ? Vector2(p.x, p.z) : Vector2(p.x, p.y));
        }
        PackedInt32Array idx;
        idx.resize(static_cast<int64_t>(s.indices.size()));
        // Godot uses clockwise front faces; our generator emits counter-clockwise -> swap.
        for (std::size_t i = 0; i + 2 < s.indices.size(); i += 3) {
            idx[static_cast<int64_t>(i)] = static_cast<int32_t>(s.indices[i]);
            idx[static_cast<int64_t>(i + 1)] = static_cast<int32_t>(s.indices[i + 2]);
            idx[static_cast<int64_t>(i + 2)] = static_cast<int32_t>(s.indices[i + 1]);
        }
        Array arrays;
        arrays.resize(Mesh::ARRAY_MAX);
        arrays[Mesh::ARRAY_VERTEX] = v;
        arrays[Mesh::ARRAY_NORMAL] = n;
        arrays[Mesh::ARRAY_TEX_UV] = uv;
        arrays[Mesh::ARRAY_INDEX] = idx;
        g.mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays, Array(), Dictionary(),
                                        Mesh::ARRAY_FLAG_USE_DYNAMIC_UPDATE);
        g.mesh->surface_set_material(0, materialFor(s.material, materials));
        g.format = static_cast<int64_t>(g.mesh->surface_get_format(0));
        const auto fmt = static_cast<BitField<RenderingServer::ArrayFormat>>(g.format);
        g.vertexStride = rs->mesh_surface_get_format_vertex_stride(fmt, static_cast<int>(nv));
        g.normalStride = rs->mesh_surface_get_format_normal_tangent_stride(fmt, static_cast<int>(nv));
        g.normalOffset = rs->mesh_surface_get_format_offset(fmt, static_cast<int>(nv), Mesh::ARRAY_NORMAL);
        g.buffer.resize(static_cast<int64_t>(g.normalOffset) + static_cast<int64_t>(nv) * g.normalStride);
        g.instance = memnew(MeshInstance3D);
        g.instance->set_mesh(g.mesh);
        static const char* paneNames[5] = {"", "_windscreen", "_rear", "_left", "_right"};
        g.instance->set_name(String(s.material.c_str()) + (s.side < 0 ? "_left" : s.side > 0 ? "_right" : "") +
                             (s.material == "glass" ? paneNames[std::clamp<int>(s.pane, 0, 4)] : ""));
        if (s.material == "glass" || s.material.ends_with("_glass"))
            g.instance->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
        add_child(g.instance);
        surfaces_.push_back(g);
    }

    // Wheels (wheel-local meshes, transformed every frame).
    const sb::SoftBody& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
    for (std::size_t w = 0; w < body.wheels().size(); ++w) {
        const sb::PressureWheel& pw = body.wheels()[w];
        WheelGpu wg;
        wg.hubL = pw.spec.hubLeft;
        wg.hubR = pw.spec.hubRight;
        wg.tread0 = pw.treadNodes.empty() ? pw.spec.hubLeft : pw.treadNodes[0];
        // "right" here = wheel on the +z side of the car (outward = -axis).
        const sb::Vec3 c = pw.center(body);
        const sb::Vec3 com = body.centerOfMass();
        const sb::Vec3 rgt = toS(get_right());
        wg.right = sb::dot(c - com, rgt) > 0.0;
        wg.width = pw.spec.width;
        wg.node = memnew(Node3D);
        wg.node->set_name(String(pw.spec.name.c_str()));
        add_child(wg.node);
        wg.tread = pw.treadNodes;
        wg.visualRimRadius = std::min(def_.tires.rimRadius + 0.012, 0.85 * def_.tires.radius);
        const std::size_t rays = wg.tread.size() / 2;
        wg.spinWeights.reserve(rays);
        for (std::size_t i = 0; i < rays; ++i) {
            const double angle = (wg.right ? -1.0 : 1.0) * 6.283185307179586 * static_cast<double>(i) / static_cast<double>(rays);
            wg.spinWeights.emplace_back(std::cos(angle), std::sin(angle));
        }
        {
            // Rest frame of the wheel in build coordinates (for imported wheel meshes).
            const sb::Vec3 cr = (restPositions_[wg.hubL] + restPositions_[wg.hubR]) * 0.5;
            const sb::Vec3 ar = sb::normalize(restPositions_[wg.hubL] - restPositions_[wg.hubR]);
            const sb::Vec3 outr = wg.right ? ar * -1.0 : ar;
            sb::Vec3 x0 = restPositions_[wg.tread0] - cr;
            wg.restX = sb::normalize(x0 - outr * sb::dot(x0, outr));
        }
        const auto& meshes = (w < 2) ? visual_.wheelFront : visual_.wheelRear;
        for (const sb::MeshSurface& s : meshes) {
            const std::size_t nv = s.positions.size() / 3;
            PackedVector3Array v, n;
            v.resize(static_cast<int64_t>(nv));
            n.resize(static_cast<int64_t>(nv));
            for (std::size_t i = 0; i < nv; ++i) {
                v[static_cast<int64_t>(i)] = Vector3(s.positions[i * 3], s.positions[i * 3 + 1], s.positions[i * 3 + 2]);
                n[static_cast<int64_t>(i)] = Vector3(s.normals[i * 3], s.normals[i * 3 + 1], s.normals[i * 3 + 2]);
            }
            PackedInt32Array idx;
            idx.resize(static_cast<int64_t>(s.indices.size()));
            for (std::size_t i = 0; i + 2 < s.indices.size(); i += 3) {
                idx[static_cast<int64_t>(i)] = static_cast<int32_t>(s.indices[i]);
                idx[static_cast<int64_t>(i + 1)] = static_cast<int32_t>(s.indices[i + 2]);
                idx[static_cast<int64_t>(i + 2)] = static_cast<int32_t>(s.indices[i + 1]);
            }
            addWheelSurface(wg, v, n, Array(), idx, materialFor(s.material, materials), s.material == "tire");
        }
        wheels_.push_back(wg);
    }
}

void SBVehicle::addWheelSurface(WheelGpu& wg, const PackedVector3Array& v, const PackedVector3Array& n, const Array& extra,
                                const PackedInt32Array& idx, const Ref<Material>& mat, bool deformable) {
    RenderingServer* rs = RenderingServer::get_singleton();
    WheelSurf ws;
    ws.mesh.instantiate();
    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    for (int k = 0; k < extra.size() && k < Mesh::ARRAY_MAX; ++k)
        if (extra[k].get_type() != Variant::NIL) arrays[k] = extra[k];
    arrays[Mesh::ARRAY_VERTEX] = v;
    arrays[Mesh::ARRAY_NORMAL] = n;
    arrays[Mesh::ARRAY_INDEX] = idx;
    ws.mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays, Array(), Dictionary(), Mesh::ARRAY_FLAG_USE_DYNAMIC_UPDATE);
    if (mat.is_valid()) ws.mesh->surface_set_material(0, mat);
    const int nv = static_cast<int>(v.size());
    const auto fmt = static_cast<BitField<RenderingServer::ArrayFormat>>(static_cast<int64_t>(ws.mesh->surface_get_format(0)));
    ws.vertexStride = rs->mesh_surface_get_format_vertex_stride(fmt, nv);
    ws.normalStride = rs->mesh_surface_get_format_normal_tangent_stride(fmt, nv);
    ws.normalOffset = rs->mesh_surface_get_format_offset(fmt, nv, Mesh::ARRAY_NORMAL);
    ws.restPos.resize(deformable ? static_cast<std::size_t>(nv) * 3 : 0);
    ws.restNrm.resize(ws.restPos.size());
    for (int i = 0; deformable && i < nv; ++i) {
        const Vector3 p = v[i], q = n[i];
        ws.restPos[static_cast<std::size_t>(i) * 3] = p.x;
        ws.restPos[static_cast<std::size_t>(i) * 3 + 1] = p.y;
        ws.restPos[static_cast<std::size_t>(i) * 3 + 2] = p.z;
        ws.restNrm[static_cast<std::size_t>(i) * 3] = q.x;
        ws.restNrm[static_cast<std::size_t>(i) * 3 + 1] = q.y;
        ws.restNrm[static_cast<std::size_t>(i) * 3 + 2] = q.z;
    }
    ws.instance = memnew(MeshInstance3D);
    ws.instance->set_mesh(ws.mesh);
    wg.node->add_child(ws.instance);
    wg.surfs.push_back(ws);
}

void SBVehicle::updateWheelMeshes(WheelGpu& w, const sb::Vec3& c, const sb::Vec3& rx, const sb::Vec3& ry, const sb::Vec3& out,
                                  double retention) {
    // Radius of the tread ring around the wheel (from the tread nodes): flat spots, bursts and
    // impacts squash the rendered tyre accordingly.
    const std::size_t nn = w.tread.size();
    if (nn < 12 || pos_.empty()) return;
    const std::size_t rays = nn / 2;
    const double R = def_.tires.radius;
    const double rim = w.visualRimRadius;
    const auto wi = static_cast<std::size_t>(&w - wheels_.data());
    const double pressure = wi < tel_.wheelPressurePsi.size() ? tel_.wheelPressurePsi[wi] : def_.tires.pressurePsi;
    const double flat = 1.0 - std::clamp(pressure / (def_.tires.pressurePsi * 0.65), 0.0, 1.0);
    if (w.treadRadii.size() != nn) w.treadRadii.assign(nn, R);
    auto* r0 = w.treadRadii.data();
    auto* r1 = r0 + rays;
    const auto filter = [retention](double previous, double radius) {
        const double change = previous - radius;
        return radius + change * retention * (1.0 - std::clamp(std::abs(change) / 0.032, 0.0, 1.0));
    };
    double z0 = 0.0, worst = 0.0, bottomDepth = rim + 0.01;
    for (std::size_t j = 0; j < rays; ++j) {
        const sb::Vec3 p0 = pos_[w.tread[j]] - c, p1 = pos_[w.tread[rays + j]] - c;
        r0[j] = filter(r0[j], std::hypot(sb::dot(p0, rx), sb::dot(p0, ry)));
        r1[j] = filter(r1[j], std::hypot(sb::dot(p1, rx), sb::dot(p1, ry)));
        z0 += sb::dot(p0, out);
        bottomDepth = std::max({bottomDepth, -p0.y, -p1.y});
        worst = std::max({worst, std::abs(r0[j] - R), std::abs(r1[j] - R)});
    }
    const bool ring0Outside = z0 > 0.0;
    const double sgn = w.right ? -1.0 : 1.0;
    const bool deformed = worst > 0.006 || flat > 0.01;
    const double halfW = 0.5 * w.width;
    for (WheelSurf& ws : w.surfs) {
        if (ws.restPos.empty()) continue;  // rims and brake discs are rigid
        if (!deformed && !ws.deformed) continue;
        const std::size_t nv = ws.restPos.size() / 3;
        uint8_t* dst = ws.buffer.size() ? ws.buffer.ptrw() : nullptr;
        if (!dst) {
            ws.buffer.resize(static_cast<int64_t>(ws.normalOffset) + static_cast<int64_t>(nv) * ws.normalStride);
            dst = ws.buffer.ptrw();
        }
        for (std::size_t i = 0; i < nv; ++i) {
            float x = ws.restPos[i * 3], y = ws.restPos[i * 3 + 1];
            float z = ws.restPos[i * 3 + 2];
            const double rv = std::sqrt(static_cast<double>(x) * x + static_cast<double>(y) * y);
            if (deformed && rv > rim && rv > 1e-4) {
                double ang = std::atan2(static_cast<double>(y), static_cast<double>(x)) * sgn;
                if (ang < 0) ang += 2.0 * 3.14159265358979;
                const double f = ang / (2.0 * 3.14159265358979) * static_cast<double>(rays);
                const std::size_t j0 = static_cast<std::size_t>(f) % rays, j1 = (j0 + 1) % rays;
                const double t = f - std::floor(f);
                const double ra = r0[j0] + (r0[j1] - r0[j0]) * t;
                const double rb = r1[j0] + (r1[j1] - r1[j0]) * t;
                double u = std::clamp(static_cast<double>(z) / (2.0 * halfW) + 0.5, 0.0, 1.0);
                if (!ring0Outside) u = 1.0 - u;
                double rr = rb + (ra - rb) * u;  // ring 0 at u = 1 (outside) when ring0Outside
                // Flatten towards the measured ground-contact plane. Do not shrink the
                // rubber above its physics contact point (which made flats look airborne).
                const double down = std::max(0.0, -(rx.y * x + ry.y * y) / rv);
                const double patch = flat * std::clamp((down - 0.55) / 0.35, 0.0, 1.0);
                const double contactRadius = std::clamp(bottomDepth / std::max(0.01, down), rim + 0.01, R * 1.06);
                rr += (contactRadius - rr) * patch;
                const double scale = (rim + (rv - rim) * std::max(0.05, (rr - rim) / (R - rim))) / rv;
                x = static_cast<float>(x * scale);
                y = static_cast<float>(y * scale);
                z *= static_cast<float>(1.0 + 0.38 * patch * std::clamp((rv - rim) / (R - rim), 0.0, 1.0));
            }
            float* pv = reinterpret_cast<float*>(dst + i * ws.vertexStride);
            pv[0] = x;
            pv[1] = y;
            pv[2] = z;
            const Vector2 oct = Vector3(ws.restNrm[i * 3], ws.restNrm[i * 3 + 1], ws.restNrm[i * 3 + 2]).octahedron_encode();
            uint16_t enc[2] = {static_cast<uint16_t>(std::clamp(oct.x * 65535.0f, 0.0f, 65535.0f)),
                               static_cast<uint16_t>(std::clamp(oct.y * 65535.0f, 0.0f, 65535.0f))};
            std::memcpy(dst + ws.normalOffset + i * ws.normalStride, enc, 4);
        }
        ws.mesh->surface_update_vertex_region(0, 0, ws.buffer);
        ws.deformed = deformed;
    }
}

namespace {
bool nameMatches(const String& name, const Array& patterns) {
    for (int i = 0; i < patterns.size(); ++i)
        if (name.findn(String(patterns[i])) >= 0) return true;
    return false;
}

struct ModelPart {
    MeshInstance3D* mi;
    Transform3D xf;      // model -> build
    int wheel;           // -1 = body
};

void collectParts(Node* n, const Transform3D& parent, const Dictionary& wheels, const Array& hide, int wheel,
                  std::vector<ModelPart>& out, bool isRoot) {
    Transform3D xf = parent;
    Node3D* n3 = Object::cast_to<Node3D>(n);
    if (n3 && !isRoot) xf = parent * n3->get_transform();
    const String name = n->get_name();
    if (!isRoot && nameMatches(name, hide)) return;
    const Array keys = wheels.keys();
    for (int k = 0; k < keys.size(); ++k) {
        // A wheel is one node name, or a list of names (rim, tyre and disc as separate nodes).
        const Variant entry = wheels[keys[k]];
        bool match = false;
        if (entry.get_type() == Variant::ARRAY) {
            const Array names = entry;
            for (int a = 0; a < names.size() && !match; ++a) match = name == String(names[a]);
        } else {
            match = name == String(entry);
        }
        if (match) {
            const String key = keys[k];
            wheel = key == "FL" ? 0 : (key == "FR" ? 1 : (key == "RL" ? 2 : 3));
        }
    }
    if (MeshInstance3D* mi = Object::cast_to<MeshInstance3D>(n)) {
        if (mi->get_mesh().is_valid()) out.push_back({mi, xf, wheel});
    }
    for (int i = 0; i < n->get_child_count(); ++i) collectParts(n->get_child(i), xf, wheels, hide, wheel, out, false);
}
}  // namespace

void SBVehicle::attach_model(Node3D* root, const Transform3D& toBuild, const Dictionary& options) {
    if (!root) return;
    const Dictionary wheels = options.get("wheels", Dictionary());
    const Array hide = options.get("hide", Array());
    const Array keep = options.get("keep_procedural", Array());
    const Dictionary overrides = options.get("material_overrides", Dictionary());
    const Dictionary physicsParts = options.get("parts", Dictionary());
    auto pickMaterial = [&](Ref<Material> m) -> Ref<Material> {
        if (m.is_valid()) {
            const String n = m->get_name();
            const Array keys = overrides.keys();
            for (int i = 0; i < keys.size(); ++i)
                if (n.findn(String(keys[i])) >= 0) return overrides[keys[i]];
        }
        // Some glTF import paths lose the occlusion texture's texCoord=1.
        // Restore that declared UV channel explicitly for models using a baked
        // AO atlas. Duplicate the material to avoid changing shared resources.
        if (static_cast<bool>(options.get("ao_on_uv2", false))) {
            Ref<BaseMaterial3D> base = m;
            if (base.is_valid() && base->get_feature(BaseMaterial3D::FEATURE_AMBIENT_OCCLUSION)) {
                Ref<BaseMaterial3D> local = base->duplicate();
                local->set_flag(BaseMaterial3D::FLAG_AO_ON_UV2, true);
                m = local;
            }
        }
        return m;
    };
    std::vector<ModelPart> parts;
    collectParts(root, toBuild, wheels, hide, -1, parts, true);
    const Variant driverEye = options.get("driver_eye", Variant());
    if (driverEye.get_type() == Variant::VECTOR3) {
        visual_.driverEye = sb::bindToNodes(restPositions_, layout_.bodyNodes, toS(static_cast<Vector3>(driverEye)));
    }
    const Variant dashboard = options.get("dashboard", Variant());
    dashboardAvailable_ = dashboard.get_type() == Variant::VECTOR3;
    if (dashboardAvailable_) {
        visual_.dashboard = sb::bindToNodes(restPositions_, layout_.bodyNodes, toS(static_cast<Vector3>(dashboard)));
    }
    const Dictionary steering = options.get("steering_wheel", Dictionary());
    const Array steeringParts = steering.get("parts", Array());
    if (!steeringParts.is_empty()) {
        visual_.steeringPivot = sb::bindToNodes(restPositions_, layout_.bodyNodes, toS(steering["pivot"]));
        visual_.steeringAxis = sb::normalize(toS(steering["axis"]));
    }

    // Hide the procedural body (keep e.g. suspension / calipers).
    for (std::size_t si = 0; si < surfaces_.size() && si < visual_.skinned.size(); ++si) {
        bool k = false;
        for (int i = 0; i < keep.size(); ++i)
            if (String(visual_.skinned[si].material.c_str()) == String(keep[i])) k = true;
        surfaces_[si].instance->set_visible(k);
    }

    RenderingServer* rs = RenderingServer::get_singleton();
    struct WheelPart {
        const ModelPart* part;
        int surface;
        bool rubber;
    };
    struct WheelAcc {
        std::vector<WheelPart> surfs;
        std::vector<Vector3> pts, rubberPts;
    };
    std::vector<WheelAcc> wacc(wheels_.size());
    for (const ModelPart& part : parts) {
        Ref<Mesh> mesh = part.mi->get_mesh();
        for (int s = 0; s < mesh->get_surface_count(); ++s) {
            if (part.wheel >= 0 && static_cast<std::size_t>(part.wheel) < wheels_.size()) {
                WheelAcc& acc = wacc[static_cast<std::size_t>(part.wheel)];
                Ref<Material> mat = part.mi->get_surface_override_material(s);
                if (mat.is_null()) mat = mesh->surface_get_material(s);
                const String name = String(part.mi->get_name()) + (mat.is_valid() ? mat->get_name() : String());
                const bool rubber = name.containsn("tire") || name.containsn("tyre") || name.containsn("rubber");
                acc.surfs.push_back({&part, s, rubber});
                const Array arr = mesh->surface_get_arrays(s);
                const PackedVector3Array v = arr[Mesh::ARRAY_VERTEX];
                for (int i = 0; i < v.size(); ++i) {
                    const Vector3 p = part.xf.xform(v[i]);
                    acc.pts.push_back(p);
                    if (rubber) acc.rubberPts.push_back(p);
                }
                continue;
            }
            const Array arr = mesh->surface_get_arrays(s);
            const PackedVector3Array v = arr[Mesh::ARRAY_VERTEX];
            if (v.size() < 3) continue;
            PackedVector3Array n = arr[Mesh::ARRAY_NORMAL];
            PackedInt32Array idx = arr[Mesh::ARRAY_INDEX];
            if (idx.size() == 0) {
                idx.resize(v.size());
                for (int i = 0; i < v.size(); ++i) idx[i] = i;
            }
            sb::MeshSurface ms;
            ms.material = "imported";
            const String partName = part.mi->get_name();
            // Panels that are separate physics parts (bonnet, front doors, bumpers) follow only that
            // part's nodes, so they open, dent and come off with it instead of staying with the shell.
            const std::vector<std::uint32_t>* bindCandidates = &layout_.bodyNodes;
            {
                const Array partKeys = physicsParts.keys();
                for (int k = 0; k < partKeys.size(); ++k) {
                    const String key = partKeys[k];
                    const std::vector<std::uint32_t>* nodes = nullptr;
                    if (key == "bonnet") nodes = &layout_.bonnetNodes;
                    else if (key == "door_left") nodes = &layout_.frontDoors[0].nodes;
                    else if (key == "door_right") nodes = &layout_.frontDoors[1].nodes;
                    else if (key == "bumper_front") nodes = &layout_.frontBumperNodes;
                    else if (key == "bumper_rear") nodes = &layout_.rearBumperNodes;
                    if (!nodes || nodes->size() < 4) continue;
                    const Array prefixes = physicsParts[key];
                    bool match = false;
                    for (int a = 0; a < prefixes.size() && !match; ++a) match = partName.begins_with(String(prefixes[a]));
                    if (match) {
                        bindCandidates = nodes;
                        if (key == "bonnet") importedBonnet_ = true;
                        if (key.begins_with("door_")) importedDoors_ = true;
                        break;
                    }
                }
            }
            for (int i = 0; i < steeringParts.size(); ++i) {
                if (partName.begins_with(String(steeringParts[i]))) {
                    ms.steeringWheel = true;
                    break;
                }
            }
            const int nv = static_cast<int>(v.size());
            ms.positions.resize(static_cast<std::size_t>(nv) * 3);
            ms.normals.resize(static_cast<std::size_t>(nv) * 3);
            ms.skin.resize(static_cast<std::size_t>(nv));
            const Basis nb = part.xf.basis.inverse().transposed();
            PackedVector3Array vb, nbv;
            vb.resize(nv);
            nbv.resize(nv);
            for (int i = 0; i < nv; ++i) {
                const Vector3 p = part.xf.xform(v[i]);
                Vector3 q = n.size() == nv ? (nb.xform(n[i])).normalized() : Vector3(0, 1, 0);
                vb[i] = p;
                nbv[i] = q;
                ms.positions[static_cast<std::size_t>(i) * 3] = p.x;
                ms.positions[static_cast<std::size_t>(i) * 3 + 1] = p.y;
                ms.positions[static_cast<std::size_t>(i) * 3 + 2] = p.z;
                ms.normals[static_cast<std::size_t>(i) * 3] = q.x;
                ms.normals[static_cast<std::size_t>(i) * 3 + 1] = q.y;
                ms.normals[static_cast<std::size_t>(i) * 3 + 2] = q.z;
                ms.skin[static_cast<std::size_t>(i)] = sb::bindToNodes(restPositions_, *bindCandidates, toS(p));
            }
            sb::tagRigidPartVertices(visual_, ms);
            // Our normal recomputation expects counter-clockwise triangles; Godot's are clockwise.
            ms.indices.resize(static_cast<std::size_t>(idx.size()));
            for (int i = 0; i + 2 < idx.size(); i += 3) {
                ms.indices[static_cast<std::size_t>(i)] = static_cast<std::uint32_t>(idx[i]);
                ms.indices[static_cast<std::size_t>(i) + 1] = static_cast<std::uint32_t>(idx[i + 2]);
                ms.indices[static_cast<std::size_t>(i) + 2] = static_cast<std::uint32_t>(idx[i + 1]);
            }
            Array garr;
            garr.resize(Mesh::ARRAY_MAX);
            garr[Mesh::ARRAY_VERTEX] = vb;
            garr[Mesh::ARRAY_NORMAL] = nbv;
            for (int k : {static_cast<int>(Mesh::ARRAY_COLOR), static_cast<int>(Mesh::ARRAY_TEX_UV),
                          static_cast<int>(Mesh::ARRAY_TEX_UV2)})
                if (arr[k].get_type() != Variant::NIL) garr[k] = arr[k];
            garr[Mesh::ARRAY_INDEX] = idx;
            SurfaceGpu g;
            // Transform source tangents with the imported geometry and retain them
            // for dynamic uploads; zero tangent bytes corrupt normal-map shading.
            if (arr[Mesh::ARRAY_TANGENT].get_type() != Variant::NIL) {
                const PackedFloat32Array source = arr[Mesh::ARRAY_TANGENT];
                if (source.size() == nv * 4) {
                    g.restTangents.resize(nv * 4);
                    const float handedness = part.xf.basis.determinant() < 0 ? -1.0f : 1.0f;
                    for (int i = 0; i < nv; ++i) {
                        Vector3 tangent = part.xf.basis.xform(Vector3(source[i * 4], source[i * 4 + 1], source[i * 4 + 2]));
                        tangent = (tangent - nbv[i] * tangent.dot(nbv[i])).normalized();
                        g.restTangents[i * 4] = tangent.x;
                        g.restTangents[i * 4 + 1] = tangent.y;
                        g.restTangents[i * 4 + 2] = tangent.z;
                        g.restTangents[i * 4 + 3] = source[i * 4 + 3] * handedness;
                    }
                    garr[Mesh::ARRAY_TANGENT] = g.restTangents;
                }
            }
            g.mesh.instantiate();
            g.mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, garr, Array(), Dictionary(), Mesh::ARRAY_FLAG_USE_DYNAMIC_UPDATE);
            Ref<Material> mat = part.mi->get_surface_override_material(s);
            if (mat.is_null()) mat = mesh->surface_get_material(s);
            mat = pickMaterial(mat);
            if (mat.is_valid()) g.mesh->surface_set_material(0, mat);
            g.arrays = garr;
            g.material = mat;
            g.torn.assign(static_cast<std::size_t>(idx.size() / 3), 0);
            g.format = static_cast<int64_t>(g.mesh->surface_get_format(0));
            const auto fmt = static_cast<BitField<RenderingServer::ArrayFormat>>(g.format);
            g.vertexStride = rs->mesh_surface_get_format_vertex_stride(fmt, nv);
            g.normalStride = rs->mesh_surface_get_format_normal_tangent_stride(fmt, nv);
            g.normalOffset = rs->mesh_surface_get_format_offset(fmt, nv, Mesh::ARRAY_NORMAL);
            g.buffer.resize(static_cast<int64_t>(g.normalOffset) + static_cast<int64_t>(nv) * g.normalStride);
            g.instance = memnew(MeshInstance3D);
            g.instance->set_mesh(g.mesh);
            g.instance->set_name(part.mi->get_name());
            add_child(g.instance);
            importedSurf_.push_back(std::move(ms));
            importedGpu_.push_back(g);
        }
    }

    // Wheels: find each wheel's centre and axle (smallest principal axis of its vertices), express it
    // in the physics wheel's rest frame and replace the procedural wheel meshes.
    for (std::size_t wi = 0; wi < wheels_.size(); ++wi) {
        WheelAcc& acc = wacc[wi];
        if (acc.surfs.empty() || acc.pts.size() < 10) continue;
        WheelGpu& wg = wheels_[wi];
        const auto& points = acc.rubberPts.empty() ? acc.pts : acc.rubberPts;
        Vector3 lo = points[0], hi = points[0];
        for (const Vector3& p : points) {
            lo = lo.min(p);
            hi = hi.max(p);
        }
        Vector3 cm = (lo + hi) * 0.5;
        double C[3][3] = {{0, 0, 0}, {0, 0, 0}, {0, 0, 0}};
        for (const Vector3& p : points) {
            const Vector3 d = p - cm;
            const double dv[3] = {d.x, d.y, d.z};
            for (int i = 0; i < 3; ++i)
                for (int j = 0; j < 3; ++j) C[i][j] += dv[i] * dv[j];
        }
        // Smallest eigenvector via power iteration on (trace * I - C).
        const double tr = C[0][0] + C[1][1] + C[2][2];
        double e[3] = {0, 0, 1};
        for (int it = 0; it < 60; ++it) {
            double ne[3];
            for (int i = 0; i < 3; ++i) ne[i] = tr * e[i] - (C[i][0] * e[0] + C[i][1] * e[1] + C[i][2] * e[2]);
            const double l = std::sqrt(ne[0] * ne[0] + ne[1] * ne[1] + ne[2] * ne[2]);
            if (l < 1e-12) break;
            for (int i = 0; i < 3; ++i) e[i] = ne[i] / l;
        }
        Vector3 zm(static_cast<real_t>(e[0]), static_cast<real_t>(e[1]), static_cast<real_t>(e[2]));
        const double side = wg.right ? 1.0 : -1.0;  // outward along build +z for right wheels
        if (zm.z * side < 0) zm = -zm;
        Vector3 xm = toG(wg.restX);
        xm = (xm - zm * xm.dot(zm)).normalized();
        const Vector3 ym = zm.cross(xm);
        const Basis toWheel = Basis(xm, ym, zm).transposed();
        lo = hi = toWheel.xform(points.front() - cm);
        for (const Vector3& p : points) {
            const Vector3 q = toWheel.xform(p - cm);
            lo = lo.min(q);
            hi = hi.max(q);
        }
        cm += toWheel.transposed().xform((lo + hi) * 0.5f);
        double maxRadius = 0.0, minRadius = sb::kInf;
        for (const Vector3& p : points) {
            const Vector3 q = toWheel.xform(p - cm);
            const double radius = std::hypot(q.x, q.y);
            maxRadius = std::max(maxRadius, radius);
            minRadius = std::min(minRadius, radius);
        }
        const double radialScale = maxRadius > 1e-4 ? def_.tires.radius / maxRadius : 1.0;
        const double width = hi.z - lo.z;
        const double widthScale = width > 1e-4 ? wg.width / width : 1.0;
        const Vector3 scale(radialScale, radialScale, widthScale);
        if (!acc.rubberPts.empty()) {
            wg.visualRimRadius = std::clamp(minRadius * radialScale, 0.50 * def_.tires.radius, 0.88 * def_.tires.radius);
        }
        // Remove the procedural wheel meshes.
        for (WheelSurf& ws : wg.surfs) ws.instance->queue_free();
        wg.surfs.clear();
        for (const auto& ps : acc.surfs) {
            Ref<Mesh> mesh = ps.part->mi->get_mesh();
            const Array arr = mesh->surface_get_arrays(ps.surface);
            const PackedVector3Array v = arr[Mesh::ARRAY_VERTEX];
            const PackedVector3Array n = arr[Mesh::ARRAY_NORMAL];
            PackedInt32Array idx = arr[Mesh::ARRAY_INDEX];
            if (idx.size() == 0) {
                idx.resize(v.size());
                for (int i = 0; i < v.size(); ++i) idx[i] = i;
            }
            const Basis nb = ps.part->xf.basis.inverse().transposed();
            PackedVector3Array lv, ln;
            lv.resize(v.size());
            ln.resize(v.size());
            for (int i = 0; i < v.size(); ++i) {
                const Vector3 d = ps.part->xf.xform(v[i]) - cm;
                lv[i] = toWheel.xform(d) * scale;
                const Vector3 q = n.size() == v.size() ? nb.xform(n[i]).normalized() : Vector3(0, 0, 1);
                ln[i] = (toWheel.xform(q) / scale).normalized();
            }
            Array extra;
            extra.resize(Mesh::ARRAY_MAX);
            for (int k : {static_cast<int>(Mesh::ARRAY_COLOR), static_cast<int>(Mesh::ARRAY_TEX_UV), static_cast<int>(Mesh::ARRAY_TEX_UV2)})
                if (arr[k].get_type() != Variant::NIL) extra[k] = arr[k];
            Ref<Material> mat = ps.part->mi->get_surface_override_material(ps.surface);
            if (mat.is_null()) mat = mesh->surface_get_material(ps.surface);
            addWheelSurface(wg, lv, ln, extra, idx, pickMaterial(mat), ps.rubber || acc.rubberPts.empty());
        }
    }
    hasImportedModel_ = true;
}

// ============================================================================ physics side

void SBVehicle::pre_step(double dt) {
    sb::SoftBody& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
    if (phys_.reset) {
        phys_.reset = false;
        applyTransform(phys_.resetXform);
    }
    sb::VehicleControls& c = body.controls();
    if (bonnetOpenRequested_) bonnetSupportTravel_ = std::min(1.0, bonnetSupportTravel_ + dt / 1.25);
    body.setInput(1, bonnetSupportTravel_);
    if (phys_.puncture >= 0 && static_cast<std::size_t>(phys_.puncture) < body.wheels().size()) {
        body.wheels()[static_cast<std::size_t>(phys_.puncture)].puncture(phys_.punctureLeak);
        phys_.puncture = -1;
    }
    c.throttle = phys_.throttle;
    c.brake = phys_.brake;
    c.steer = phys_.steer;
    c.handbrake = phys_.handbrake;
    c.clutch = phys_.clutch;
    for (std::size_t i = 0; i < body.wheels().size() && i < 4; ++i)
        body.wheels()[i].surfaceGrip = phys_.surfaceGrip[i];
    c.steerRate = phys_.steerRate;
    c.gear = -99;
    c.ignition = phys_.ignition;
    c.tcs = phys_.tcs;
    c.abs = phys_.abs;
    if (phys_.starter) {
        phys_.starter = false;
        starterTimer_ = 1.5;
    }
    c.starter = starterTimer_ > 0.0;
    if (starterTimer_ > 0.0) {
        starterTimer_ -= dt;
        if (body.hasPowertrain() && body.powertrain().running()) starterTimer_ = 0.0;
    }
    if (body.hasPowertrain()) {
        sb::Powertrain& pt = body.powertrain();
        if (phys_.automatic != pt.spec().automatic) pt.setAutomatic(phys_.automatic);
        if (phys_.gear != -99) {
            c.gear = phys_.gear;
            phys_.gear = -99;
        }
    }
}

void SBVehicle::sync_from_world() {
    // Hand the latest controls to the physics thread (one-shot requests are consumed here).
    {
        const bool keepStarter = phys_.starter, keepReset = phys_.reset;
        const int keepGear = phys_.gear;
        const int keepPuncture = phys_.puncture;
        const double keepLeak = phys_.punctureLeak;
        const Transform3D keepXf = phys_.resetXform;
        phys_ = ctl_;
        if (!ctl_.starter) phys_.starter = keepStarter;
        if (!ctl_.reset) { phys_.reset = keepReset; phys_.resetXform = keepXf; }
        if (ctl_.gear == -99) phys_.gear = keepGear;
        if (ctl_.puncture < 0) { phys_.puncture = keepPuncture; phys_.punctureLeak = keepLeak; }
        ctl_.puncture = -1;
        ctl_.starter = false;
        ctl_.reset = false;
        ctl_.gear = -99;
    }
    const sb::SoftBody& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
    pos_ = body.positions();
    vel_ = body.velocities();
    visualReset_ = visualReset_ || visualResetPending_;
    visualResetPending_ = false;
    tel_ = body.telemetry();
    if (body.hasSystems()) sys_ = body.systems().state();
    // Wheel slip / contact.
    const std::size_t nw = body.wheels().size();
    slip_.assign(nw, 0.0f);
    contact_.assign(nw, 0.0f);
    contactPoints_.resize(nw);
    contactNormals_.resize(nw);
    for (std::size_t i = 0; i < nw; ++i) {
        const sb::PressureWheel& w = body.wheels()[i];
        slip_[i] = static_cast<float>(w.slipSpeed);
        contact_[i] = w.contactAge < 0.025 ? static_cast<float>(std::clamp(w.load / 2200.0, 0.0, 1.0)) : 0.0f;
        contactPoints_.set(i, toG(w.contactPoint));
        contactNormals_.set(i, toG(w.contactNormal));
    }
    // Damage events for crash audio / camera shake.
    const std::size_t d = tel_.deformedBeams, b = tel_.brokenBeams;
    if (d > lastDeformed_ || b > lastBroken_) {
        impactAccum_ += static_cast<double>(d > lastDeformed_ ? d - lastDeformed_ : 0) +
                        6.0 * static_cast<double>(b > lastBroken_ ? b - lastBroken_ : 0);
    }
    lastDeformed_ = d;
    lastBroken_ = b;
    if (debugView_) {
        beamStrain_.resize(body.beamCount());
        for (std::size_t i = 0; i < body.beamCount(); ++i) {
            const sb::Beam& bm = body.beams()[i];
            beamStrain_[i] = bm.broken ? -1.0f : static_cast<float>(bm.plasticStrain());
        }
    }
    snapshotValid_ = true;
}

// ============================================================================ rendering

// Sheet metal tears where the nodes it is bound to have been ripped apart: triangles whose edges
// stretch to more than 2.2x their rest length (and by more than 6 cm) are removed instead of being
// drawn as long slivers between a torn-off node and the body. Repair restores them.
void SBVehicle::tearOverstretched(SurfaceGpu& g, const sb::MeshSurface& s, bool reset) {
    if (g.torn.empty() || g.arrays.is_empty()) return;
    bool changed = false;
    if (reset) {
        if (g.tornCount > 0) {
            std::fill(g.torn.begin(), g.torn.end(), 0);
            g.tornCount = 0;
            changed = true;
        }
    } else {
        const std::size_t nt = std::min(g.torn.size(), s.indices.size() / 3);
        for (std::size_t t = 0; t < nt; ++t) {
            if (g.torn[t]) continue;
            for (int e = 0; e < 3; ++e) {
                const std::uint32_t a = s.indices[t * 3 + static_cast<std::size_t>(e)], b = s.indices[t * 3 + static_cast<std::size_t>((e + 1) % 3)];
                const float rx = s.positions[a * 3] - s.positions[b * 3], ry = s.positions[a * 3 + 1] - s.positions[b * 3 + 1],
                            rz = s.positions[a * 3 + 2] - s.positions[b * 3 + 2];
                const float cx = tmpPos_[a * 3] - tmpPos_[b * 3], cy = tmpPos_[a * 3 + 1] - tmpPos_[b * 3 + 1],
                            cz = tmpPos_[a * 3 + 2] - tmpPos_[b * 3 + 2];
                const float rest = std::sqrt(rx * rx + ry * ry + rz * rz), now = std::sqrt(cx * cx + cy * cy + cz * cz);
                if (now > 2.2f * rest && now - rest > 0.06f) {
                    g.torn[t] = 1;
                    ++g.tornCount;
                    changed = true;
                    break;
                }
            }
        }
    }
    if (!changed) return;
    const PackedInt32Array source = g.arrays[Mesh::ARRAY_INDEX];
    PackedInt32Array kept;
    kept.resize(source.size() - static_cast<int64_t>(g.tornCount) * 3);
    int64_t w = 0;
    for (std::size_t t = 0; t < g.torn.size(); ++t) {
        if (g.torn[t]) continue;
        kept[w++] = source[static_cast<int64_t>(t) * 3];
        kept[w++] = source[static_cast<int64_t>(t) * 3 + 1];
        kept[w++] = source[static_cast<int64_t>(t) * 3 + 2];
    }
    Array arrays = g.arrays.duplicate();
    arrays[Mesh::ARRAY_INDEX] = kept;
    g.mesh->clear_surfaces();
    if (kept.size() == 0) return;
    g.mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays, Array(), Dictionary(), Mesh::ARRAY_FLAG_USE_DYNAMIC_UPDATE);
    if (g.material.is_valid()) g.mesh->surface_set_material(0, g.material);
}

void SBVehicle::update_visual(double delta) {
    if (!snapshotValid_ || pos_.empty()) return;
    const sb::Vec3 reference = (pos_[layout_.refFL] + pos_[layout_.refFR] + pos_[layout_.refRL] + pos_[layout_.refRR]) * 0.25;
    const sb::Vec3 movement = reference - renderReference_;
    const bool snap = visualReset_ || renderPos_.size() != pos_.size() ||
                      sb::visualMotionDiscontinuity(movement, tel_.velocity, delta);
    visualReset_ = false;
    if (snap) {
        renderPos_ = pos_;
    } else {
        const double bodyRetention = std::exp(-24.0 * delta);
        // Follow horizontal travel immediately. Filter only short vertical and relative movements.
        const sb::Vec3 advance{movement.x, 0.0, movement.z};
        for (std::size_t i = 0; i < pos_.size(); ++i) {
            const sb::Vec3 residual = renderPos_[i] + advance - pos_[i];
            const double distance = sb::length(residual);
            // Large displacements (impacts, detached parts) pass straight through.
            const double weight = bodyRetention * (1.0 - std::clamp(distance / 0.20, 0.0, 1.0));
            renderPos_[i] = pos_[i] + residual * weight;
        }
    }
    renderReference_ = reference;
    sb::computeNodeFrames(renderPos_, visual_, frames_);
    const auto& axis = visual_.steeringAxis;
    const Vector3 steeringAxis = toG({frames_[0] * axis.x + frames_[1] * axis.y + frames_[2] * axis.z,
                                     frames_[3] * axis.x + frames_[4] * axis.y + frames_[5] * axis.z,
                                     frames_[6] * axis.x + frames_[7] * axis.y + frames_[8] * axis.z}).normalized();
    const Vector3 steeringPivot = toG(sb::evalSkin(renderPos_, frames_, visual_.steeringPivot));
    const Basis steeringRotation(steeringAxis, tel_.steer * 4.71238898038469);
    const Transform3D steeringTransform(steeringRotation, steeringPivot - steeringRotation.xform(steeringPivot));

    // AABB of the whole car (vertices are in world space; this node stays at the origin).
    Vector3 lo = toG(pos_[0]), hi = lo;
    for (const sb::Vec3& p : pos_) {
        lo = Vector3(std::min<real_t>(lo.x, p.x), std::min<real_t>(lo.y, p.y), std::min<real_t>(lo.z, p.z));
        hi = Vector3(std::max<real_t>(hi.x, p.x), std::max<real_t>(hi.y, p.y), std::max<real_t>(hi.z, p.z));
    }
    const AABB box(lo - Vector3(0.5, 0.5, 0.5), (hi - lo) + Vector3(1, 1, 1));

    for (std::size_t si = 0; si < surfaces_.size() && si < visual_.skinned.size(); ++si) {
        SurfaceGpu& g = surfaces_[si];
        if (!g.instance->is_visible()) continue;
        const sb::MeshSurface& s = visual_.skinned[si];
        if (s.steeringWheel) g.instance->set_transform(steeringTransform);
        if (s.material == "paint" || s.material == "glass" || s.material == "interior" || s.material == "trim")
            sb::deformSurfaceBlended(renderPos_, frames_, s, tmpPos_, tmpNrm_);
        else sb::deformSurface(renderPos_, frames_, s, tmpPos_, tmpNrm_);
        const std::size_t nv = s.skin.size();
        uint8_t* dst = g.buffer.ptrw();
        for (std::size_t i = 0; i < nv; ++i) {
            float* pv = reinterpret_cast<float*>(dst + i * g.vertexStride);
            pv[0] = tmpPos_[i * 3];
            pv[1] = tmpPos_[i * 3 + 1];
            pv[2] = tmpPos_[i * 3 + 2];
            const Vector2 oct = Vector3(tmpNrm_[i * 3], tmpNrm_[i * 3 + 1], tmpNrm_[i * 3 + 2]).octahedron_encode();
            uint16_t enc[2] = {static_cast<uint16_t>(std::clamp(oct.x * 65535.0f, 0.0f, 65535.0f)),
                               static_cast<uint16_t>(std::clamp(oct.y * 65535.0f, 0.0f, 65535.0f))};
            std::memcpy(dst + g.normalOffset + i * g.normalStride, enc, 4);
        }
        g.mesh->surface_update_vertex_region(0, 0, g.buffer);
        g.mesh->set_custom_aabb(box);
    }

    // Wheels: origin at the spindle centre, Z = outward axle. Fit the spin phase to both tread rings.
    const double tireRetention = snap ? 0.0 : std::exp(-36.0 * delta);
    for (WheelGpu& w : wheels_) {
        const sb::Vec3 hl = pos_[w.hubL], hr = pos_[w.hubR];
        const sb::Vec3 c = (hl + hr) * 0.5;
        const sb::Vec3 axis = sb::normalize(hl - hr);
        const sb::Vec3 out = w.right ? axis * -1.0 : axis;
        const std::size_t rays = w.spinWeights.size();
        sb::Vec3 along{}, across{};
        for (std::size_t i = 0; i < rays; ++i) {
            const sb::Vec3 pair = (pos_[w.tread[i]] - c) + (pos_[w.tread[rays + i]] - c);
            along += pair * w.spinWeights[i].first;
            across += pair * w.spinWeights[i].second;
        }
        sb::Vec3 rx = along - sb::cross(out, across);
        rx -= out * sb::dot(rx, out);
        if (sb::lengthSq(rx) < 1e-8) {
            rx = pos_[w.tread0] - c;
            rx -= out * sb::dot(rx, out);
        }
        rx = sb::normalize(rx);
        const sb::Vec3 ry = sb::cross(out, rx);
        const sb::Vec3& hubL = renderPos_[w.hubL];
        const sb::Vec3& hubR = renderPos_[w.hubR];
        const sb::Vec3 axle = w.right ? hubR - hubL : hubL - hubR;
        const sb::Vec3 renderOut = sb::lengthSq(axle) > 1e-8 ? sb::normalize(axle) : out;
        const sb::Vec3 renderRx = sb::normalize(rx - renderOut * sb::dot(rx, renderOut));
        Basis bs;
        bs.set_column(0, toG(renderRx));
        bs.set_column(1, toG(sb::cross(renderOut, renderRx)));
        bs.set_column(2, toG(renderOut));
        w.node->set_transform(Transform3D(bs, toG((hubL + hubR) * 0.5)));
        updateWheelMeshes(w, c, rx, ry, out, tireRetention);
    }

    for (std::size_t si = 0; si < importedGpu_.size(); ++si) {
        SurfaceGpu& g = importedGpu_[si];
        const sb::MeshSurface& s = importedSurf_[si];
        if (s.steeringWheel) g.instance->set_transform(steeringTransform);
        sb::deformSurfaceBlended(renderPos_, frames_, s, tmpPos_, tmpNrm_);
        if (snap || (++tearCheckCounter_ % 8) == 0) tearOverstretched(g, s, snap && tel_.brokenBeams == 0);
        const std::size_t nv = s.skin.size();
        uint8_t* dst = g.buffer.ptrw();
        for (std::size_t i = 0; i < nv; ++i) {
            float* pv = reinterpret_cast<float*>(dst + i * g.vertexStride);
            pv[0] = tmpPos_[i * 3];
            pv[1] = tmpPos_[i * 3 + 1];
            pv[2] = tmpPos_[i * 3 + 2];
            const Vector2 oct = Vector3(tmpNrm_[i * 3], tmpNrm_[i * 3 + 1], tmpNrm_[i * 3 + 2]).octahedron_encode();
            uint16_t enc[2] = {static_cast<uint16_t>(std::clamp(oct.x * 65535.0f, 0.0f, 65535.0f)),
                               static_cast<uint16_t>(std::clamp(oct.y * 65535.0f, 0.0f, 65535.0f))};
            std::memcpy(dst + g.normalOffset + i * g.normalStride, enc, 4);
            if (g.restTangents.size() == static_cast<int64_t>(nv * 4) && g.normalStride >= 8) {
                const Vector3 rest(g.restTangents[i * 4], g.restTangents[i * 4 + 1], g.restTangents[i * 4 + 2]);
                const float* F = sb::skinFrame(frames_, renderPos_.size(), s.skin[i].part);
                Vector3 tangent(F[0] * rest.x + F[1] * rest.y + F[2] * rest.z,
                                F[3] * rest.x + F[4] * rest.y + F[5] * rest.z,
                                F[6] * rest.x + F[7] * rest.y + F[8] * rest.z);
                const Vector3 normal(tmpNrm_[i * 3], tmpNrm_[i * 3 + 1], tmpNrm_[i * 3 + 2]);
                tangent = (tangent - normal * tangent.dot(normal)).normalized();
                const Vector2 octT = tangent.octahedron_tangent_encode(g.restTangents[i * 4 + 3]);
                const uint16_t packed[2] = {static_cast<uint16_t>(std::clamp(octT.x * 65535.0f, 0.0f, 65535.0f)),
                                            static_cast<uint16_t>(std::clamp(octT.y * 65535.0f, 0.0f, 65535.0f))};
                std::memcpy(dst + g.normalOffset + i * g.normalStride + 4, packed, 4);
            }
        }
        if (g.mesh->get_surface_count() > 0) g.mesh->surface_update_vertex_region(0, 0, g.buffer);
        g.mesh->set_custom_aabb(box);
    }

    if (debugView_ && debugMesh_.is_valid()) {
        debugMesh_->clear_surfaces();
        debugMesh_->surface_begin(Mesh::PRIMITIVE_LINES, debugMaterial_);
        for (std::size_t i = 0; i + 1 < beamPairs_.size(); i += 2) {
            const std::size_t bi = i / 2;
            const float st = bi < beamStrain_.size() ? beamStrain_[bi] : 0.0f;
            if (st < 0.0f) continue;
            const float t = std::clamp(st / 0.05f, 0.0f, 1.0f);
            const Color col = t <= 0.0f ? Color(0.2f, 0.95f, 0.35f) : Color(1.0f, 1.0f - t, 0.1f);
            debugMesh_->surface_set_color(col);
            debugMesh_->surface_add_vertex(toG(pos_[beamPairs_[i]]));
            debugMesh_->surface_set_color(col);
            debugMesh_->surface_add_vertex(toG(pos_[beamPairs_[i + 1]]));
        }
        debugMesh_->surface_end();
    }
}

// ============================================================================ GDScript API

void SBVehicle::set_input(double throttle, double brake, double steer, double handbrake) {
    ctl_.throttle = std::clamp(throttle, 0.0, 1.0);
    ctl_.brake = std::clamp(brake, 0.0, 1.0);
    ctl_.steer = std::clamp(steer, -1.0, 1.0);
    ctl_.handbrake = std::clamp(handbrake, 0.0, 1.0);
}

void SBVehicle::set_clutch(double clutch) { ctl_.clutch = clutch; }

void SBVehicle::set_surface_grip(const PackedFloat32Array& grip) {
    if (grip.size() != 4) return;
    for (int i = 0; i < 4; ++i)
        if (std::isfinite(grip[i])) ctl_.surfaceGrip[static_cast<std::size_t>(i)] = std::clamp<double>(grip[i], 0.35, 1.2);
}

void SBVehicle::set_gear(int gear) { ctl_.gear = gear; }

void SBVehicle::shift_up() {
    const int maxG = static_cast<int>(def_.engine.gears.size());
    ctl_.gear = std::min(tel_.gear + 1, maxG);
}

void SBVehicle::shift_down() { ctl_.gear = std::max(tel_.gear - 1, -1); }

void SBVehicle::set_automatic(bool a) { ctl_.automatic = a; }

void SBVehicle::set_ignition(bool on) { ctl_.ignition = on; }

void SBVehicle::start_engine() {
    ctl_.ignition = true;
    ctl_.starter = true;
}

void SBVehicle::reset_to(const Transform3D& xform) {
    ctl_.reset = true;
    ctl_.resetXform = xform;
    lastDeformed_ = 0;
    lastBroken_ = 0;
    impactAccum_ = 0.0;
}

bool SBVehicle::relocate_to(const Transform3D& xform) {
    if (!world_ || bodyIndex_ < 0 || !xform.is_finite()) return false;
    // Recovery is a rigid motion: reject scales/reflections rather than changing
    // beam lengths, tyre geometry or deformation with an invalid destination.
    const double determinant = xform.basis.determinant();
    if (!std::isfinite(determinant) || determinant <= 1e-8) return false;
    const Basis destination = xform.basis.orthonormalized();
    for (int axis = 0; axis < 3; ++axis)
        if ((xform.basis.get_column(axis) - destination.get_column(axis)).length_squared() > 1e-6) return false;
    {
        std::lock_guard<std::mutex> lock(world_->mutex());
        auto& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
        auto& p = body.positions();
        const sb::Vec3 center = (p[layout_.refFL] + p[layout_.refFR] + p[layout_.refRL] + p[layout_.refRR]) * 0.25;
        const Vector3 forward = toG(forwardOf(p));
        const Vector3 right = toG((p[layout_.refFR] + p[layout_.refRR]) - (p[layout_.refFL] + p[layout_.refRL])).normalized();
        const Vector3 up = right.cross(forward).normalized();
        if (forward.length_squared() < 0.5 || up.length_squared() < 0.5) return false;
        const Basis source(forward, up, forward.cross(up));
        const Basis rotation = destination * source.transposed();
        const double floorY = (restPositions_[layout_.refFL].y + restPositions_[layout_.refFR].y +
                               restPositions_[layout_.refRL].y + restPositions_[layout_.refRR].y) * 0.25 + 0.03;
        const Vector3 target = xform.origin + destination.xform(Vector3(0, static_cast<real_t>(floorY), 0));
        for (auto& node : p) node = toS(target + rotation.xform(toG(node - center)));
        body.setVelocity({});
        body.clearContacts();
        for (auto& wheel : body.wheels()) {
            wheel.angularVelocity = 0.0;
            wheel.load = wheel.slipSpeed = 0.0;
            wheel.contactAge = 1.0;
            wheel.contactPoint = wheel.center(body);
            wheel.contactNormal = toS(destination.get_column(1));
        }
        // A queued sandbox reset must never silently repair the recovered car.
        ctl_.reset = phys_.reset = false;
        ctl_.starter = phys_.starter = false;
        starterTimer_ = 0.0;
        ctl_.throttle = phys_.throttle = 0.0;
        body.controls().throttle = 0.0;
        visualResetPending_ = true;
        impactAccum_ = 0.0;
        sync_from_world();
    }
    update_visual(0.0);
    return true;
}

bool SBVehicle::service_repair() {
    if (!world_ || bodyIndex_ < 0) return false;
    {
        std::lock_guard<std::mutex> lock(world_->mutex());
        auto& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
        const auto& p = body.positions();
        if (p.empty()) return false;
        Vector3 forward = toG(forwardOf(p));
        forward.y = 0;
        forward = forward.length_squared() > 1e-6 ? forward.normalized() : Vector3(1, 0, 0);
        Vector3 center = toG((p[layout_.refFL] + p[layout_.refFR] + p[layout_.refRL] + p[layout_.refRR]) * 0.25);
        double groundY = center.y;
        for (const auto& wheel : body.wheels()) groundY = std::min(groundY, wheel.center(body).y - def_.tires.radius);
        center.y = static_cast<real_t>(std::max(groundY, static_cast<double>(center.y) - 0.6) + 0.05);
        const double fuel = body.hasSystems() ? body.systems().state().fuelL : 0.0;
        const Vector3 up(0, 1, 0);
        applyTransform(Transform3D(Basis(forward, up, forward.cross(up)), center));
        if (body.hasSystems()) {
            body.systems().state().fuelL = fuel;
            body.systems().state().running = false;
        }
        if (body.hasPowertrain()) body.powertrain().setRunning(false);
        ctl_.ignition = phys_.ignition = false;
        ctl_.starter = phys_.starter = false;
        ctl_.reset = phys_.reset = false;
        ctl_.puncture = phys_.puncture = -1;
        ctl_.throttle = phys_.throttle = 0.0;
        body.controls().ignition = body.controls().starter = false;
        body.controls().throttle = 0.0;
        starterTimer_ = 0.0;
        lastBroken_ = lastDeformed_ = 0;
        impactAccum_ = 0.0;
        sync_from_world();
    }
    update_visual(0.0);
    return true;
}

bool SBVehicle::set_door_open(int index, bool open) {
    if (!world_ || bodyIndex_ < 0 || index < 0 || (hasImportedModel_ && !importedDoors_)) return false;
    std::lock_guard<std::mutex> lock(world_->mutex());
    auto& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
    if (static_cast<std::size_t>(index) >= body.doors().size() || body.telemetry().speedKmh > 2.0) return false;
    return body.setDoorOpen(static_cast<std::size_t>(index), open);
}

bool SBVehicle::toggle_door(int index) {
    if (!world_ || bodyIndex_ < 0 || index < 0 || (hasImportedModel_ && !importedDoors_)) return false;
    std::lock_guard<std::mutex> lock(world_->mutex());
    auto& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
    if (static_cast<std::size_t>(index) >= body.doors().size() || body.telemetry().speedKmh > 2.0) return false;
    return body.setDoorOpen(static_cast<std::size_t>(index), !body.doors()[static_cast<std::size_t>(index)].requestedOpen);
}

Array SBVehicle::get_door_states() const {
    Array result;
    if (!world_ || bodyIndex_ < 0 || (hasImportedModel_ && !importedDoors_)) return result;
    std::lock_guard<std::mutex> lock(world_->mutex());
    const auto& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
    const auto& positions = body.positions();
    const Vector3 forward = toG(forwardOf(positions)).normalized();
    const Vector3 right = toG((positions[layout_.refFR] + positions[layout_.refRR]) - (positions[layout_.refFL] + positions[layout_.refRL])).normalized();
    for (std::size_t side = 0; side < body.doors().size(); ++side) {
        const auto& door = body.doors()[side];
        bool attached = false, damaged = false;
        auto inspect = [&](const auto& indices) {
            for (auto index : indices) {
                if (index >= body.beams().size()) { damaged = true; continue; }
                const auto& beam = body.beams()[index];
                attached = attached || (!beam.broken && !beam.disabled);
                damaged = damaged || beam.broken || beam.plasticStrain() > 0.005; // Same service threshold as core door mechanism.
            }
        };
        inspect(door.hingeBeams); inspect(door.latchBeams); inspect(door.supportBeams);
        double angle = 0.0;
        if (door.nodes.size() >= 8) {
            sb::Vec3 rear{}, front{}, restRear{}, restFront{};
            for (int k = 0; k < 4; ++k) {
                const auto rearIndex = door.nodes[static_cast<std::size_t>(k)];
                const auto frontIndex = door.nodes[static_cast<std::size_t>(k + 4)];
                rear += positions[rearIndex];
                front += positions[frontIndex];
                restRear += restPositions_[rearIndex];
                restFront += restPositions_[frontIndex];
            }
            const Vector3 along = toG(front - rear).normalized();
            const sb::Vec3 restAlong = restFront - restRear;
            // The authored body can taper at the door. Measure opening relative
            // to that closed shape, rather than assuming every door lies on +X.
            const double rotation = std::atan2(along.dot(right), along.dot(forward)) - std::atan2(restAlong.z, restAlong.x);
            angle = std::abs(std::atan2(std::sin(rotation), std::cos(rotation))) * 180.0 / 3.141592653589793;
        }
        Dictionary state;
        state["index"] = static_cast<int>(side);
        state["requested_open"] = door.requestedOpen;
        state["travel"] = door.travel;
        state["latched"] = door.latched;
        state["attached"] = attached;
        state["missing"] = !attached;
        state["damaged"] = damaged;
        state["angle_degrees"] = angle;
        state["open"] = !door.latched || angle > 3.0 || !attached;
        result.push_back(state);
    }
    return result;
}

Array SBVehicle::get_lamp_states() const {
    Array result;
    if (!world_ || bodyIndex_ < 0 || restPositions_.empty()) return result;
    std::lock_guard<std::mutex> lock(world_->mutex());
    const auto& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
    const auto& beams = body.beams();
    if (lampBeams_.empty()) {
        // The outer 0.4 m at each end of the body shell, left and right of the centre: the panels and
        // structure the lamp is mounted on. Bumpers are separate parts; a bumper torn off by the
        // impact at the other end must not count as a smashed lamp.
        const std::vector<std::uint32_t>& nodes = layout_.bodyNodes;
        double xMin = 1e9, xMax = -1e9;
        for (auto n : nodes) {
            xMin = std::min(xMin, restPositions_[n].x);
            xMax = std::max(xMax, restPositions_[n].x);
        }
        std::vector<int> corner(restPositions_.size(), -1);
        for (auto n : nodes) {
            const sb::Vec3& r = restPositions_[n];
            const int end = r.x > xMax - 0.40 ? 0 : r.x < xMin + 0.40 ? 1 : -1;
            if (end < 0 || std::abs(r.z) < 0.15) continue;
            corner[n] = end * 2 + (r.z > 0.0 ? 1 : 0);
        }
        lampBeams_.assign(4, {});
        for (std::size_t i = 0; i < beams.size(); ++i) {
            const int ca = corner[beams[i].a], cb = corner[beams[i].b];
            if (ca >= 0 && ca == cb) lampBeams_[static_cast<std::size_t>(ca)].push_back(static_cast<std::uint32_t>(i));
        }
    }
    static const char* names[4] = {"head_left", "head_right", "tail_left", "tail_right"};
    for (int c = 0; c < 4; ++c) {
        double damage = 0.0, strain = 0.0;
        int torn = 0;
        for (auto bi : lampBeams_[static_cast<std::size_t>(c)]) {
            if (bi >= beams.size()) continue;
            const auto& beam = beams[bi];
            if (beam.broken) ++torn;
            else strain = std::max(strain, beam.plasticStrain());
            damage = std::max(damage, beam.broken ? 1.0 : std::min(1.0, beam.plasticStrain() / kLampBreakStrain));
        }
        sb::Vec3 centre{};
        std::size_t count = 0;
        for (auto bi : lampBeams_[static_cast<std::size_t>(c)]) {
            if (bi >= beams.size()) continue;
            centre += body.positions()[beams[bi].a];
            ++count;
        }
        Dictionary state;
        state["name"] = names[c];
        state["center"] = count ? toG(centre / static_cast<double>(count)) : get_position_ws();
        state["front"] = c < 2;
        state["side"] = c % 2 == 0 ? -1 : 1;
        state["damage"] = damage;
        state["strain"] = strain;
        state["torn_beams"] = torn;
        state["beams"] = static_cast<int>(lampBeams_[static_cast<std::size_t>(c)].size());
        state["broken"] = damage >= 1.0;
        result.push_back(state);
    }
    return result;
}

Array SBVehicle::get_glass_states() const {
    Array result;
    if (!world_ || bodyIndex_ < 0 || hasImportedModel_) return result;
    std::lock_guard<std::mutex> lock(world_->mutex());
    const auto& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
    const auto& beams = body.beams();
    if (!glassPanesBuilt_) {
        glassPanesBuilt_ = true;
        // The frame a pane is bonded to: every node its vertices are skinned to, and every beam
        // attached to those nodes (the aperture also distorts through the cowl and pillar feet).
        for (std::size_t si = 0; si < visual_.skinned.size() && si < surfaces_.size(); ++si) {
            const sb::MeshSurface& s = visual_.skinned[si];
            if (s.pane == 0) continue;
            std::vector<char> in(restPositions_.size(), 0);
            GlassPane pane;
            pane.surface = si;
            for (const auto& sk : s.skin)
                for (int k = 0; k < 4; ++k)
                    if (sk.weight[k] > 0.0f && sk.node[k] < in.size() && !in[sk.node[k]]) {
                        in[sk.node[k]] = 1;
                        pane.nodes.push_back(sk.node[k]);
                    }
            for (std::size_t i = 0; i < beams.size(); ++i)
                if (beams[i].a < in.size() && beams[i].b < in.size() && (in[beams[i].a] || in[beams[i].b])) {
                    pane.beams.push_back(static_cast<std::uint32_t>(i));
                    pane.bonded.push_back(in[beams[i].a] && in[beams[i].b]);
                }
            glassPanes_.push_back(std::move(pane));
        }
    }
    static const char* names[5] = {"", "windscreen", "rear", "left", "right"};
    for (const GlassPane& pane : glassPanes_) {
        double damage = 0.0;
        std::uint32_t worst = pane.beams.empty() ? 0 : pane.beams.front();
        for (std::size_t k = 0; k < pane.beams.size(); ++k) {
            const auto bi = pane.beams[k];
            if (bi >= beams.size()) continue;
            const auto& beam = beams[bi];
            // Beams of the frame itself count fully; members only attached to it (crush zones,
            // pillars' lower ends) a quarter, so a crumpled bonnet alone does not burst the glass.
            const double weight = pane.bonded[k] ? 1.0 : 0.25;
            const double d = beam.broken ? (pane.bonded[k] ? 1.5 : 0.5) : weight * beam.plasticStrain() / kGlassBreakStrain;
            if (d > damage) { damage = d; worst = bi; }
        }
        // Fracture origin in the pane's texture space (rest pose, box projection as in buildMeshes).
        Vector2 originUv;
        if (worst < beams.size()) {
            const sb::Vec3 p = (restPositions_[beams[worst].a] + restPositions_[beams[worst].b]) * 0.5;
            const sb::MeshSurface& ps = visual_.skinned[pane.surface];
            double nx = 0, ny = 0, nz = 0;
            for (std::size_t i = 0; i + 2 < ps.normals.size(); i += 3) { nx += std::abs(ps.normals[i]); ny += std::abs(ps.normals[i + 1]); nz += std::abs(ps.normals[i + 2]); }
            originUv = nx >= ny && nx >= nz ? Vector2(p.z, p.y) : (ny >= nz ? Vector2(p.x, p.z) : Vector2(p.x, p.y));
        }
        sb::Vec3 c{};
        for (auto n : pane.nodes) c += body.positions()[n];
        if (!pane.nodes.empty()) c = c / static_cast<double>(pane.nodes.size());
        const sb::MeshSurface& s = visual_.skinned[pane.surface];
        Dictionary state;
        state["name"] = s.material == "glass" ? String(names[std::clamp<int>(s.pane, 0, 4)]) : String(s.material.c_str());
        state["instance"] = surfaces_[pane.surface].instance;
        state["damage"] = damage;
        state["center"] = toG(c);
        state["origin_uv"] = originUv;
        result.push_back(state);
    }
    return result;
}

Array SBVehicle::get_bumper_states() const {
    Array result;
    if (!world_ || bodyIndex_ < 0) return result;
    std::lock_guard<std::mutex> lock(world_->mutex());
    const auto& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
    const auto& names = body.breakGroupNames();
    for (int end = 0; end < 2; ++end) {
        const auto& nodes = end == 0 ? layout_.frontBumperNodes : layout_.rearBumperNodes;
        if (nodes.empty()) continue;
        const std::string prefix = end == 0 ? "bumper_front_mounts_" : "bumper_rear_mounts_";
        std::array<bool, 4> intact{false, false, false, false};
        for (const auto& beam : body.beams()) {
            if (beam.breakGroup < 0 || beam.broken) continue;
            const std::string& g = names[static_cast<std::size_t>(beam.breakGroup)];
            if (g.rfind(prefix, 0) == 0 && g.size() == prefix.size() + 1) {
                const int c = g.back() - '0';
                if (c >= 0 && c < 4) intact[static_cast<std::size_t>(c)] = true;
            }
        }
        sb::Vec3 c{};
        for (auto n : nodes) c += body.positions()[n];
        Dictionary state;
        state["name"] = end == 0 ? "front" : "rear";
        state["clips"] = static_cast<int>(intact[0]) + intact[1] + intact[2] + intact[3];
        state["center"] = toG(c / static_cast<double>(nodes.size()));
        result.push_back(state);
    }
    return result;
}

bool SBVehicle::release_bonnet() {
    if (!world_ || bodyIndex_ < 0 || layout_.bonnetNodes.size() != 8 || (hasImportedModel_ && !importedBonnet_)) return false;
    std::lock_guard<std::mutex> lock(world_->mutex());
    auto& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
    if (body.telemetry().speedKmh > 2.0) return false;
    bool released = false;
    for (std::size_t i = 0; i < body.beams().size(); ++i) {
        const auto& beam = body.beams()[i];
        if (!beam.broken && beam.breakGroup >= 0 && body.breakGroupNames()[static_cast<std::size_t>(beam.breakGroup)] == "bonnet_latch") {
            body.breakBeam(static_cast<std::uint32_t>(i));
            released = true;
        }
    }
    if (released) {
        // The damped, breakable support struts lift the panel through channel 1.
        // Do not add an instantaneous kick on top of the controlled stroke.
        bonnetOpenRequested_ = true;
    }
    return released;
}

double SBVehicle::refuel(double litres) {
    if (!world_ || bodyIndex_ < 0 || !std::isfinite(litres) || litres <= 0 || get_velocity().length() > 0.25) return 0.0;
    std::lock_guard<std::mutex> lock(world_->mutex());
    auto& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
    if (!body.hasSystems() || body.systems().state().running) return 0.0;
    auto& systems = body.systems();
    const double added = std::clamp(litres, 0.0, std::max(0.0, systems.spec().fuelCapacityL - systems.state().fuelL));
    systems.state().fuelL += added;
    sys_.fuelL = systems.state().fuelL;
    return added;
}

void SBVehicle::repair_in_place() {
    if (pos_.empty()) return;
    Vector3 f = get_forward();
    f.y = 0;
    if (f.length() < 1e-3) f = Vector3(1, 0, 0);
    f = f.normalized();
    const Vector3 up(0, 1, 0);
    const Vector3 r = f.cross(up);
    double minY = 1e9;
    for (const auto& w : wheels_) minY = std::min(minY, std::min(pos_[w.hubL].y, pos_[w.hubR].y) - def_.tires.radius);
    Vector3 o = get_position_ws();
    o.y = static_cast<real_t>(std::max(minY, static_cast<double>(o.y) - 0.6)) + 0.05f;
    Basis b;
    b.set_column(0, f);
    b.set_column(1, up);
    b.set_column(2, r);
    reset_to(Transform3D(b, o));
}

void SBVehicle::set_debug_view(bool on) {
    debugView_ = on;
    if (on && !debugInstance_) {
        debugMesh_.instantiate();
        debugMaterial_.instantiate();
        debugMaterial_->set_shading_mode(BaseMaterial3D::SHADING_MODE_UNSHADED);
        debugMaterial_->set_flag(BaseMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
        debugMaterial_->set_flag(BaseMaterial3D::FLAG_DISABLE_DEPTH_TEST, true);
        debugInstance_ = memnew(MeshInstance3D);
        debugInstance_->set_mesh(debugMesh_);
        debugInstance_->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
        add_child(debugInstance_);
    }
    if (debugInstance_) debugInstance_->set_visible(on);
}

void SBVehicle::set_body_visible(bool on) {
    if (!hasImportedModel_)
        for (SurfaceGpu& g : surfaces_) g.instance->set_visible(on);
    for (SurfaceGpu& g : importedGpu_) g.instance->set_visible(on);
}

Dictionary SBVehicle::get_telemetry() const {
    Dictionary d;
    d["speed_kmh"] = tel_.speedKmh;
    d["rpm"] = tel_.engineRpm;
    d["gear"] = tel_.gear;
    d["clutch"] = tel_.clutch;
    d["clutch_temp"] = tel_.clutchTempC;
    d["clutch_wear"] = tel_.clutchWear;
    d["gearbox_damage"] = tel_.gearboxDamage;
    d["shift_remaining"] = tel_.shiftRemaining;
    d["clutch_slip_rpm"] = tel_.clutchSlipRpm;
    d["gear_grind"] = tel_.gearGrind;
    d["throttle"] = tel_.throttle;
    d["brake"] = tel_.brake;
    d["steer"] = tel_.steer;
    d["tcs_active"] = tel_.tcsActive;
    d["abs_active"] = tel_.absActive;
    d["deformed_beams"] = static_cast<int64_t>(tel_.deformedBeams);
    d["broken_beams"] = static_cast<int64_t>(tel_.brokenBeams);
    Array burst;
    for (bool b : tel_.wheelBurst) burst.push_back(b);
    d["wheel_burst"] = burst;
    Array wear, ttemp, press;
    for (double v : tel_.wheelWear) wear.push_back(v);
    for (double v : tel_.wheelTempC) ttemp.push_back(v);
    for (double v : tel_.wheelPressurePsi) press.push_back(v);
    d["tire_wear"] = wear;
    d["tire_temp"] = ttemp;
    d["tire_pressure"] = press;
    d["coolant_temp"] = sys_.coolantTempC;
    d["oil_temp"] = sys_.oilTempC;
    d["coolant_level"] = sys_.coolantLevel;
    d["oil_level"] = sys_.oilLevel;
    d["oil_pressure"] = sys_.oilPressureBar;
    d["fuel_l"] = sys_.fuelL;
    d["fuel_rate"] = sys_.fuelRateLPerH;
    d["thermostat"] = sys_.thermostat;
    d["fan_on"] = sys_.fanOn;
    d["running"] = sys_.running;
    d["seized"] = sys_.seized;
    d["head_gasket"] = sys_.headGasketBlown;
    d["driveshaft_broken"] = sys_.driveshaftBroken;
    d["mounts_broken"] = sys_.mountsBroken;
    d["radiator_damage"] = sys_.radiatorDamage;
    d["oilpan_damage"] = sys_.oilPanDamage;
    d["fueltank_damage"] = sys_.fuelTankDamage;
    d["engine_damage"] = std::max(sys_.blockDamage, sys_.wear);
    d["power_kw"] = sys_.powerKw;
    d["status"] = String(sys_.status.c_str());
    if (!sys_.seized && !sys_.driveshaftBroken) {
        if (tel_.gearboxDamage >= 1.0) d["status"] = "GEARBOX FAILED";
        else if (tel_.clutchWear >= 1.0) d["status"] = "CLUTCH FAILED";
        else if (tel_.clutchTempC > 200.0) d["status"] = "CLUTCH OVERHEATING";
    }
    Array zones;
    for (double z : sys_.zoneDamage) zones.push_back(z);
    d["zones"] = zones;
    Array brakes, susp;
    for (double t : sys_.brakeTempC) brakes.push_back(t);
    for (double s : sys_.suspensionDamage) susp.push_back(s);
    d["brake_temps"] = brakes;
    d["suspension_damage"] = susp;
    return d;
}

void SBVehicle::puncture_tire(int wheel, double leak) {
    if (wheel < 0 || static_cast<std::size_t>(wheel) >= wheels_.size() || !std::isfinite(leak)) return;
    ctl_.puncture = wheel;
    ctl_.punctureLeak = std::clamp(leak, 0.1, 100.0);
}

Dictionary SBVehicle::get_effect_anchors() const {
    Dictionary d;
    PackedVector3Array centers;
    for (const auto& w : wheels_) centers.push_back(w.node->get_global_position());
    d["wheels"] = centers;
    d["contacts"] = contactPoints_;
    d["normals"] = contactNormals_;
    d["radius"] = def_.tires.radius;
    const auto& points = renderPos_.empty() ? pos_ : renderPos_;
    sb::Vec3 engine{};
    for (auto i : layout_.engineNodes) if (i < points.size()) engine += points[i];
    if (!layout_.engineNodes.empty()) engine *= 1.0 / static_cast<double>(layout_.engineNodes.size());
    d["engine"] = toG(engine) + get_up() * 0.3;
    d["exhaust"] = get_position_ws() - get_forward() * (def_.body.length * 0.48) + get_up() * 0.12;
    return d;
}

Dictionary SBVehicle::get_info() const {
    Dictionary d;
    d["id"] = String(def_.id.c_str());
    d["name"] = String(def_.name.c_str());
    d["brand"] = String(def_.brand.c_str());
    d["description"] = String::utf8(def_.description.c_str());
    d["engine"] = String(def_.engine.name.c_str());
    d["layout"] = String(def_.engine.layout.c_str());
    d["cylinders"] = def_.engine.cylinders;
    d["idle_rpm"] = def_.engine.idleRpm;
    d["redline_rpm"] = def_.engine.redlineRpm;
    d["gears"] = static_cast<int64_t>(def_.engine.gears.size());
    d["fuel_capacity"] = def_.engine.fuelCapacity;
    d["mass"] = def_.chassis.curbMass;
    d["length"] = def_.body.length;
    d["wheelbase"] = def_.body.wheelbase;
    d["width"] = def_.body.width;
    d["height"] = def_.body.height;
    d["bonnet_supported"] = !hasImportedModel_ || importedBonnet_;
    double peakT = 0, peakP = 0;
    for (const auto& tq : def_.engine.torqueCurve) {
        peakT = std::max(peakT, tq.second);
        peakP = std::max(peakP, tq.second * tq.first * 2.0 * 3.14159265 / 60.0 / 1000.0);
    }
    d["peak_torque"] = peakT;
    d["peak_power_kw"] = peakP;
    return d;
}

sb::Vec3 SBVehicle::forwardOf(const std::vector<sb::Vec3>& p) const {
    return sb::normalize((p[layout_.refFL] + p[layout_.refFR]) - (p[layout_.refRL] + p[layout_.refRR]));
}

Vector3 SBVehicle::get_position_ws() const {
    if (pos_.empty()) return Vector3();
    return toG((pos_[layout_.refFL] + pos_[layout_.refFR] + pos_[layout_.refRL] + pos_[layout_.refRR]) * 0.25);
}

Vector3 SBVehicle::get_chase_target() const {
    if (pos_.empty() || frames_.empty()) return get_position_ws();
    return toG(sb::evalSkin(renderPos_, frames_, visual_.chaseTarget));
}

Vector3 SBVehicle::get_driver_eye() const {
    if (pos_.empty() || frames_.empty()) return get_position_ws();
    return toG(sb::evalSkin(renderPos_, frames_, visual_.driverEye));
}

Variant SBVehicle::get_dashboard_transform() const {
    if (!dashboardAvailable_ || frames_.empty()) return Variant();
    return Transform3D(get_visual_basis(), toG(sb::evalSkin(renderPos_, frames_, visual_.dashboard)));
}

Array SBVehicle::get_mirror_surfaces() const {
    Array result;
    if (renderPos_.empty() || frames_.empty()) return result;
    auto append = [&](const sb::MeshSurface& surface, const SurfaceGpu& gpu, int side) {
        if (!gpu.instance || !gpu.instance->is_visible() || surface.skin.size() < 3) return;
        const std::size_t count = surface.skin.size();
        std::vector<Vector3> points;
        points.reserve(count);
        Vector3 center;
        double restY = 0, restZ = 0;
        for (std::size_t i = 0; i < count; ++i) {
            const Vector3 point = toG(sb::evalSkin(renderPos_, frames_, surface.skin[i]));
            if (!point.is_finite()) return;
            points.push_back(point);
            center += point;
            restY += surface.positions[i * 3 + 1];
            restZ += surface.positions[i * 3 + 2];
        }
        center /= static_cast<real_t>(count);
        restY /= static_cast<double>(count);
        restZ /= static_cast<double>(count);
        // Correlate the authored vertical/lateral coordinates with the current
        // bound vertices. This follows a swinging or torn door, not the chassis
        // transform or the intentionally oversized whole-vehicle render AABB.
        Vector3 up, right;
        for (std::size_t i = 0; i < count; ++i) {
            const Vector3 delta = points[i] - center;
            up += delta * static_cast<real_t>(surface.positions[i * 3 + 1] - restY);
            right += delta * static_cast<real_t>(surface.positions[i * 3 + 2] - restZ);
        }
        if (up.length_squared() < 1e-14 || right.length_squared() < 1e-14) return;
        right.normalize();
        Vector3 normal = right.cross(up).normalized();
        if (!normal.is_finite() || normal.length_squared() < 0.5) return;
        up = normal.cross(right).normalized();
        double minX = 1e20, maxX = -1e20, minY = 1e20, maxY = -1e20;
        for (const Vector3& point : points) {
            const Vector3 delta = point - center;
            const double x = delta.dot(right), y = delta.dot(up);
            minX = std::min(minX, x); maxX = std::max(maxX, x);
            minY = std::min(minY, y); maxY = std::max(maxY, y);
        }
        center += right * static_cast<real_t>((minX + maxX) * 0.5) + up * static_cast<real_t>((minY + maxY) * 0.5);
        Dictionary entry;
        entry["mesh"] = gpu.instance;
        entry["side"] = side;
        entry["center"] = center;
        entry["normal"] = normal;
        entry["up"] = up;
        entry["half_extents"] = Vector2(static_cast<real_t>((maxX - minX) * 0.5), static_cast<real_t>((maxY - minY) * 0.5));
        result.append(entry);
    };
    for (std::size_t i = 0; i < visual_.skinned.size() && i < surfaces_.size(); ++i) {
        const auto& surface = visual_.skinned[i];
        if (surface.material == "mirror_left" || surface.material == "door_left_mirror") append(surface, surfaces_[i], 0);
        else if (surface.material == "mirror_right" || surface.material == "door_right_mirror") append(surface, surfaces_[i], 1);
    }
    for (std::size_t i = 0; i < importedSurf_.size() && i < importedGpu_.size(); ++i) {
        const String name = importedGpu_[i].instance->get_name();
        if (name == "BodyDoorLMirror") append(importedSurf_[i], importedGpu_[i], 0);
        else if (name == "BodyDoorRMirror") append(importedSurf_[i], importedGpu_[i], 1);
    }
    return result;
}

Basis SBVehicle::get_visual_basis() const {
    if (renderPos_.empty()) return Basis(get_right(), get_up(), -get_forward()).orthonormalized();
    const Vector3 forward = toG(forwardOf(renderPos_));
    const Vector3 right = toG(sb::normalize((renderPos_[layout_.refFR] + renderPos_[layout_.refRR]) -
                                           (renderPos_[layout_.refFL] + renderPos_[layout_.refRL])));
    return Basis(right, right.cross(forward).normalized(), -forward).orthonormalized();
}
Vector3 SBVehicle::get_forward() const {
    if (pos_.empty()) return Vector3(1, 0, 0);
    return toG(forwardOf(pos_));
}

Vector3 SBVehicle::get_right() const {
    if (pos_.empty()) return Vector3(0, 0, 1);
    return toG(sb::normalize((pos_[layout_.refFR] + pos_[layout_.refRR]) - (pos_[layout_.refFL] + pos_[layout_.refRL])));
}

Vector3 SBVehicle::get_up() const {
    return get_right().cross(get_forward()).normalized();
}

Vector3 SBVehicle::get_velocity() const { return toG(tel_.velocity); }

double SBVehicle::get_speed_kmh() const { return tel_.speedKmh; }
double SBVehicle::get_engine_rpm() const { return tel_.engineRpm; }

PackedFloat32Array SBVehicle::get_wheel_slip() const {
    PackedFloat32Array a;
    for (float s : slip_) a.push_back(s);
    return a;
}

PackedFloat32Array SBVehicle::get_wheel_load() const {
    PackedFloat32Array a;
    for (float s : contact_) a.push_back(s);
    return a;
}

double SBVehicle::take_impact() {
    const double v = impactAccum_;
    impactAccum_ = 0.0;
    return v;
}

}  // namespace godot
