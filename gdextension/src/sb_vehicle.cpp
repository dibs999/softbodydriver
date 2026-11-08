#include "sb_vehicle.h"

#include <algorithm>
#include <cmath>
#include <cstring>

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include "sb_world.h"

namespace godot {

namespace {

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
    if (n == "spring") return Color(0.75, 0.1, 0.08);
    if (n == "caliper") return Color(0.8, 0.15, 0.1);
    if (n == "engine") return Color(0.35, 0.36, 0.38);
    if (n == "brake_disc") return Color(0.45, 0.44, 0.43);
    return Color(0.12, 0.12, 0.13);
}

}  // namespace

void SBVehicle::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_input", "throttle", "brake", "steer", "handbrake"), &SBVehicle::set_input);
    ClassDB::bind_method(D_METHOD("set_clutch", "clutch"), &SBVehicle::set_clutch);
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
    ClassDB::bind_method(D_METHOD("repair_in_place"), &SBVehicle::repair_in_place);
    ClassDB::bind_method(D_METHOD("set_debug_view", "on"), &SBVehicle::set_debug_view);
    ClassDB::bind_method(D_METHOD("get_debug_view"), &SBVehicle::get_debug_view);
    ClassDB::bind_method(D_METHOD("set_body_visible", "on"), &SBVehicle::set_body_visible);
    ClassDB::bind_method(D_METHOD("get_telemetry"), &SBVehicle::get_telemetry);
    ClassDB::bind_method(D_METHOD("get_info"), &SBVehicle::get_info);
    ClassDB::bind_method(D_METHOD("get_position_ws"), &SBVehicle::get_position_ws);
    ClassDB::bind_method(D_METHOD("get_chase_target"), &SBVehicle::get_chase_target);
    ClassDB::bind_method(D_METHOD("get_driver_eye"), &SBVehicle::get_driver_eye);
    ClassDB::bind_method(D_METHOD("get_forward"), &SBVehicle::get_forward);
    ClassDB::bind_method(D_METHOD("get_up"), &SBVehicle::get_up);
    ClassDB::bind_method(D_METHOD("get_right"), &SBVehicle::get_right);
    ClassDB::bind_method(D_METHOD("get_velocity"), &SBVehicle::get_velocity);
    ClassDB::bind_method(D_METHOD("get_speed_kmh"), &SBVehicle::get_speed_kmh);
    ClassDB::bind_method(D_METHOD("get_wheel_slip"), &SBVehicle::get_wheel_slip);
    ClassDB::bind_method(D_METHOD("attach_model", "root", "to_build", "options"), &SBVehicle::attach_model);
    ClassDB::bind_method(D_METHOD("get_wheel_load"), &SBVehicle::get_wheel_load);
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
}

Ref<Material> SBVehicle::materialFor(const std::string& name, const Dictionary& lib) const {
    const String key(name.c_str());
    Ref<Material> m;
    if (lib.has(key)) m = lib[key];
    if (name == "paint") {
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
    const Color c = fallbackColor(name);
    sm->set_albedo(c);
    if (c.a < 1.0f) sm->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
    if (name == "glass") sm->set_cull_mode(BaseMaterial3D::CULL_DISABLED);
    if (name == "headlight" || name == "taillight") {
        sm->set_feature(BaseMaterial3D::FEATURE_EMISSION, true);
        sm->set_emission(c);
        sm->set_emission_energy_multiplier(name == "headlight" ? 1.5f : 0.8f);
    }
    if (name == "chrome" || name == "rim") {
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
        v.resize(static_cast<int64_t>(nv));
        n.resize(static_cast<int64_t>(nv));
        for (std::size_t i = 0; i < nv; ++i) {
            v[static_cast<int64_t>(i)] = Vector3(s.positions[i * 3], s.positions[i * 3 + 1], s.positions[i * 3 + 2]);
            n[static_cast<int64_t>(i)] = Vector3(s.normals[i * 3], s.normals[i * 3 + 1], s.normals[i * 3 + 2]);
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
        g.instance->set_name(String(s.material.c_str()));
        if (s.material == "glass") g.instance->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
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
        wg.right = body.positions()[pw.spec.hubRight].z > body.positions()[pw.spec.hubLeft].z ? false : true;
        // "right" here = wheel on the +z side of the car (outward = -axis).
        const sb::Vec3 c = pw.center(body);
        const sb::Vec3 com = body.centerOfMass();
        const sb::Vec3 rgt = toS(get_right());
        wg.right = sb::dot(c - com, rgt) > 0.0;
        wg.node = memnew(Node3D);
        wg.node->set_name(String(pw.spec.name.c_str()));
        add_child(wg.node);
        wg.tread = pw.treadNodes;
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
            addWheelSurface(wg, v, n, Array(), idx, materialFor(s.material, materials));
        }
        wheels_.push_back(wg);
    }
}

void SBVehicle::addWheelSurface(WheelGpu& wg, const PackedVector3Array& v, const PackedVector3Array& n, const Array& extra,
                                const PackedInt32Array& idx, const Ref<Material>& mat) {
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
    ws.restPos.resize(static_cast<std::size_t>(nv) * 3);
    ws.restNrm.resize(static_cast<std::size_t>(nv) * 3);
    for (int i = 0; i < nv; ++i) {
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

void SBVehicle::updateWheelMeshes(WheelGpu& w, const sb::Vec3& c, const sb::Vec3& rx, const sb::Vec3& ry, const sb::Vec3& out) {
    // Radius of the tread ring around the wheel (from the tread nodes): flat spots, bursts and
    // impacts squash the rendered tyre accordingly.
    const std::size_t nn = w.tread.size();
    if (nn < 12 || pos_.empty()) return;
    const std::size_t rays = nn / 2;
    const double R = def_.tires.radius;
    const double rim = std::min(def_.tires.rimRadius + 0.012, 0.85 * R);
    std::vector<double> r0(rays), r1(rays);
    double z0 = 0.0, worst = 0.0;
    for (std::size_t j = 0; j < rays; ++j) {
        const sb::Vec3 p0 = pos_[w.tread[j]] - c, p1 = pos_[w.tread[rays + j]] - c;
        r0[j] = std::sqrt(sb::dot(p0, rx) * sb::dot(p0, rx) + sb::dot(p0, ry) * sb::dot(p0, ry));
        r1[j] = std::sqrt(sb::dot(p1, rx) * sb::dot(p1, rx) + sb::dot(p1, ry) * sb::dot(p1, ry));
        z0 += sb::dot(p0, out);
        worst = std::max({worst, std::abs(r0[j] - R), std::abs(r1[j] - R)});
    }
    const bool ring0Outside = z0 > 0.0;
    // Direction in which the node index increases (angle of node 1 relative to node 0 = rx).
    const sb::Vec3 p1 = pos_[w.tread[1]] - c;
    const double sgn = std::atan2(sb::dot(p1, ry), sb::dot(p1, rx)) >= 0.0 ? 1.0 : -1.0;
    const bool deformed = worst > 0.006;
    const double halfW = 0.5 * def_.tires.width;
    for (WheelSurf& ws : w.surfs) {
        if (!deformed && !ws.deformed) continue;
        const std::size_t nv = ws.restPos.size() / 3;
        uint8_t* dst = ws.buffer.size() ? ws.buffer.ptrw() : nullptr;
        if (!dst) {
            ws.buffer.resize(static_cast<int64_t>(ws.normalOffset) + static_cast<int64_t>(nv) * ws.normalStride);
            dst = ws.buffer.ptrw();
        }
        for (std::size_t i = 0; i < nv; ++i) {
            float x = ws.restPos[i * 3], y = ws.restPos[i * 3 + 1];
            const float z = ws.restPos[i * 3 + 2];
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
                const double rr = rb + (ra - rb) * u;  // ring 0 at u = 1 (outside) when ring0Outside
                const double scale = (rim + (rv - rim) * std::max(0.05, (rr - rim) / (R - rim))) / rv;
                x = static_cast<float>(x * scale);
                y = static_cast<float>(y * scale);
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
    for (int k = 0; k < keys.size(); ++k)
        if (name == String(wheels[keys[k]])) {
            const String key = keys[k];
            wheel = key == "FL" ? 0 : (key == "FR" ? 1 : (key == "RL" ? 2 : 3));
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
    auto pickMaterial = [&](Ref<Material> m) -> Ref<Material> {
        if (m.is_valid()) {
            const String n = m->get_name();
            const Array keys = overrides.keys();
            for (int i = 0; i < keys.size(); ++i)
                if (n.findn(String(keys[i])) >= 0) return overrides[keys[i]];
        }
        return m;
    };
    std::vector<ModelPart> parts;
    collectParts(root, toBuild, wheels, hide, -1, parts, true);

    // Hide the procedural body (keep e.g. suspension / calipers).
    for (std::size_t si = 0; si < surfaces_.size() && si < visual_.skinned.size(); ++si) {
        bool k = false;
        for (int i = 0; i < keep.size(); ++i)
            if (String(visual_.skinned[si].material.c_str()) == String(keep[i])) k = true;
        surfaces_[si].instance->set_visible(k);
    }

    RenderingServer* rs = RenderingServer::get_singleton();
    struct WheelAcc {
        std::vector<std::pair<const ModelPart*, int>> surfs;
        std::vector<Vector3> pts;
    };
    std::vector<WheelAcc> wacc(wheels_.size());
    for (const ModelPart& part : parts) {
        Ref<Mesh> mesh = part.mi->get_mesh();
        for (int s = 0; s < mesh->get_surface_count(); ++s) {
            if (part.wheel >= 0 && static_cast<std::size_t>(part.wheel) < wheels_.size()) {
                wacc[static_cast<std::size_t>(part.wheel)].surfs.push_back({&part, s});
                const Array arr = mesh->surface_get_arrays(s);
                const PackedVector3Array v = arr[Mesh::ARRAY_VERTEX];
                for (int i = 0; i < v.size(); ++i) wacc[static_cast<std::size_t>(part.wheel)].pts.push_back(part.xf.xform(v[i]));
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
                ms.skin[static_cast<std::size_t>(i)] = sb::bindToNodes(restPositions_, layout_.bodyNodes, toS(p));
            }
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
            for (int k : {static_cast<int>(Mesh::ARRAY_TANGENT), static_cast<int>(Mesh::ARRAY_COLOR), static_cast<int>(Mesh::ARRAY_TEX_UV),
                          static_cast<int>(Mesh::ARRAY_TEX_UV2)})
                if (arr[k].get_type() != Variant::NIL) garr[k] = arr[k];
            garr[Mesh::ARRAY_INDEX] = idx;
            SurfaceGpu g;
            g.mesh.instantiate();
            g.mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, garr, Array(), Dictionary(), Mesh::ARRAY_FLAG_USE_DYNAMIC_UPDATE);
            Ref<Material> mat = part.mi->get_surface_override_material(s);
            if (mat.is_null()) mat = mesh->surface_get_material(s);
            mat = pickMaterial(mat);
            if (mat.is_valid()) g.mesh->surface_set_material(0, mat);
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
        Vector3 lo = acc.pts[0], hi = acc.pts[0];
        for (const Vector3& p : acc.pts) {
            lo = lo.min(p);
            hi = hi.max(p);
        }
        const Vector3 cm = (lo + hi) * 0.5;
        double C[3][3] = {{0, 0, 0}, {0, 0, 0}, {0, 0, 0}};
        for (const Vector3& p : acc.pts) {
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
            for (int i = 0; i < 3; ++i) e[i] = ne[i] / l;
        }
        Vector3 zm(static_cast<real_t>(e[0]), static_cast<real_t>(e[1]), static_cast<real_t>(e[2]));
        const double side = wg.right ? 1.0 : -1.0;  // outward along build +z for right wheels
        if (zm.z * side < 0) zm = -zm;
        Vector3 xm = toG(wg.restX);
        xm = (xm - zm * xm.dot(zm)).normalized();
        const Vector3 ym = zm.cross(xm);
        // Remove the procedural wheel meshes.
        for (WheelSurf& ws : wg.surfs) ws.instance->queue_free();
        wg.surfs.clear();
        for (const auto& ps : acc.surfs) {
            Ref<Mesh> mesh = ps.first->mi->get_mesh();
            const Array arr = mesh->surface_get_arrays(ps.second);
            const PackedVector3Array v = arr[Mesh::ARRAY_VERTEX];
            const PackedVector3Array n = arr[Mesh::ARRAY_NORMAL];
            PackedInt32Array idx = arr[Mesh::ARRAY_INDEX];
            if (idx.size() == 0) {
                idx.resize(v.size());
                for (int i = 0; i < v.size(); ++i) idx[i] = i;
            }
            const Basis nb = ps.first->xf.basis.inverse().transposed();
            PackedVector3Array lv, ln;
            lv.resize(v.size());
            ln.resize(v.size());
            for (int i = 0; i < v.size(); ++i) {
                const Vector3 d = ps.first->xf.xform(v[i]) - cm;
                lv[i] = Vector3(d.dot(xm), d.dot(ym), d.dot(zm));
                const Vector3 q = n.size() == v.size() ? nb.xform(n[i]).normalized() : Vector3(0, 0, 1);
                ln[i] = Vector3(q.dot(xm), q.dot(ym), q.dot(zm));
            }
            Array extra;
            extra.resize(Mesh::ARRAY_MAX);
            for (int k : {static_cast<int>(Mesh::ARRAY_COLOR), static_cast<int>(Mesh::ARRAY_TEX_UV), static_cast<int>(Mesh::ARRAY_TEX_UV2)})
                if (arr[k].get_type() != Variant::NIL) extra[k] = arr[k];
            Ref<Material> mat = ps.first->mi->get_surface_override_material(ps.second);
            if (mat.is_null()) mat = mesh->surface_get_material(ps.second);
            addWheelSurface(wg, lv, ln, extra, idx, pickMaterial(mat));
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
    c.throttle = phys_.throttle;
    c.brake = phys_.brake;
    c.steer = phys_.steer;
    c.handbrake = phys_.handbrake;
    c.clutch = phys_.clutch;
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
            pt.setGear(phys_.gear);
            phys_.gear = -99;
        }
    }
}

void SBVehicle::sync_from_world() {
    // Hand the latest controls to the physics thread (one-shot requests are consumed here).
    {
        const bool keepStarter = phys_.starter, keepReset = phys_.reset;
        const int keepGear = phys_.gear;
        const Transform3D keepXf = phys_.resetXform;
        phys_ = ctl_;
        if (!ctl_.starter) phys_.starter = keepStarter;
        if (!ctl_.reset) { phys_.reset = keepReset; phys_.resetXform = keepXf; }
        if (ctl_.gear == -99) phys_.gear = keepGear;
        ctl_.starter = false;
        ctl_.reset = false;
        ctl_.gear = -99;
    }
    const sb::SoftBody& body = world_->world().body(static_cast<std::size_t>(bodyIndex_));
    pos_ = body.positions();
    vel_ = body.velocities();
    tel_ = body.telemetry();
    if (body.hasSystems()) sys_ = body.systems().state();
    // Wheel slip / contact.
    const std::size_t nw = body.wheels().size();
    slip_.assign(nw, 0.0f);
    contact_.assign(nw, 0.0f);
    for (std::size_t i = 0; i < nw; ++i) {
        const sb::PressureWheel& w = body.wheels()[i];
        const sb::Vec3 c = w.center(body);
        const sb::Vec3 vh = (vel_[w.spec.hubLeft] + vel_[w.spec.hubRight]) * 0.5;
        const sb::Vec3 a = w.axis(body);
        const sb::Vec3 fwd = sb::normalize(sb::cross(sb::Vec3{0, 1, 0}, a) * -1.0);
        const double vRoll = w.angularVelocity * w.spec.radius;
        const double vLong = sb::dot(vh, fwd);
        const double vLat = sb::dot(vh, a);
        slip_[i] = static_cast<float>(std::sqrt((vRoll - vLong) * (vRoll - vLong) + vLat * vLat));
        double minR = 1e9;
        for (std::uint32_t t : w.treadNodes) {
            const sb::Vec3 rel = pos_[t] - c;
            const sb::Vec3 r = rel - a * sb::dot(rel, a);
            minR = std::min(minR, sb::length(r));
        }
        contact_[i] = static_cast<float>(std::clamp((w.spec.radius - minR) / 0.02, 0.0, 1.0));
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
            beamStrain_[i] = bm.broken ? -1.0f
                                       : static_cast<float>(std::abs(bm.restLength - bm.hydroOffset - bm.baseRestLength) /
                                                            std::max(1e-6, bm.baseRestLength));
        }
    }
    snapshotValid_ = true;
}

// ============================================================================ rendering

void SBVehicle::update_visual() {
    if (!snapshotValid_ || pos_.empty()) return;
    sb::computeNodeFrames(pos_, visual_, frames_);

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
        sb::deformSurface(pos_, frames_, s, tmpPos_, tmpNrm_);
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

    // Wheels: origin at the spindle centre, Z = outward axle, X = towards tread node 0.
    for (WheelGpu& w : wheels_) {
        const sb::Vec3 hl = pos_[w.hubL], hr = pos_[w.hubR];
        const sb::Vec3 c = (hl + hr) * 0.5;
        const sb::Vec3 axis = sb::normalize(hl - hr);
        const sb::Vec3 out = w.right ? axis * -1.0 : axis;
        sb::Vec3 rx = pos_[w.tread0] - c;
        rx = sb::normalize(rx - out * sb::dot(rx, out));
        const sb::Vec3 ry = sb::cross(out, rx);
        Basis bs;
        bs.set_column(0, toG(rx));
        bs.set_column(1, toG(ry));
        bs.set_column(2, toG(out));
        w.node->set_transform(Transform3D(bs, toG(c)));
        updateWheelMeshes(w, c, rx, ry, out);
    }

    for (std::size_t si = 0; si < importedGpu_.size(); ++si) {
        SurfaceGpu& g = importedGpu_[si];
        const sb::MeshSurface& s = importedSurf_[si];
        sb::deformSurfaceBlended(pos_, frames_, s, tmpPos_, tmpNrm_);
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
    d["width"] = def_.body.width;
    d["height"] = def_.body.height;
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
    return toG(sb::evalSkin(pos_, frames_, visual_.chaseTarget));
}

Vector3 SBVehicle::get_driver_eye() const {
    if (pos_.empty() || frames_.empty()) return get_position_ws();
    return toG(sb::evalSkin(pos_, frames_, visual_.driverEye));
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
