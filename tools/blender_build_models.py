#!/usr/bin/env python3
"""
tools/blender_build_models.py
-----------------------------
High-Resolution Blender 4.2 LTS (bpy + bmesh) 3D modeling pipeline for SoftBodyDriver.
Builds smooth, high-poly 3D vehicles and environment assets with guaranteed outward normals:
  - Spline-interpolated automotive body shells (40x21 grid)
  - Circular sculpted 3D wheel arches (fender flares) + dark inner wheel-well liners
  - Beveled sub-parts with mathematically verified outward face normals
  - Projector headlights with LED DRL strips, 3D grille mesh, LED taillights,
    rear diffuser with strakes, and 20-segment round chrome exhaust pipes
  - Detailed 3D cabin interior (contoured bucket seats, steering wheel, dashboard, center console)
  - Smooth vertex normals on curved body panels + sharp EdgeSplit (28 deg) on creases
"""

import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector, Matrix, Euler


ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MODELS_DIR = os.path.join(ROOT_DIR, "content", "models")
WEB_JS_PATH = os.path.join(ROOT_DIR, "web", "blender_models.js")


def reset_blender_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def create_pbr_material(name, rgba, metallic=0.0, roughness=0.5, emission=0.0, mat_type=0.0, is_paint=False):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = rgba
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission
        if rgba[3] < 0.99 and "Alpha" in bsdf.inputs:
            bsdf.inputs["Alpha"].default_value = rgba[3]

    mat["sb_col"] = list(rgba)
    mat["sb_type"] = float(mat_type)
    mat["sb_rough"] = float(roughness)
    mat["sb_paint"] = bool(is_paint)
    return mat


def build_palette():
    return {
        "car_paint":   create_pbr_material("CarPaint",     (0.10, 0.52, 0.96, 1.0), metallic=0.80, roughness=0.14, mat_type=1.0, is_paint=True),
        "carbon_trim": create_pbr_material("CarbonTrim",   (0.09, 0.10, 0.13, 1.0), metallic=0.35, roughness=0.38, mat_type=1.0),
        "wheel_well":  create_pbr_material("WheelWell",    (0.04, 0.05, 0.06, 1.0), metallic=0.05, roughness=0.92, mat_type=0.0),
        "grille_dark": create_pbr_material("GrilleDark",   (0.06, 0.07, 0.09, 1.0), metallic=0.40, roughness=0.55, mat_type=1.0),
        "tinted_glass":create_pbr_material("TintedGlass",  (0.12, 0.18, 0.26, 0.58),metallic=0.92, roughness=0.05, mat_type=2.0),
        "chrome":      create_pbr_material("Chrome",       (0.90, 0.93, 0.97, 1.0), metallic=0.98, roughness=0.08, mat_type=4.0),
        "silver_metal":create_pbr_material("SilverMetal",  (0.72, 0.76, 0.82, 1.0), metallic=0.88, roughness=0.22, mat_type=4.0),
        "headlight":   create_pbr_material("HeadlightLED", (0.98, 0.99, 1.00, 1.0), metallic=0.10, roughness=0.08, emission=2.8, mat_type=3.0),
        "taillight":   create_pbr_material("TaillightLED", (0.96, 0.10, 0.14, 1.0), metallic=0.10, roughness=0.12, emission=2.4, mat_type=3.0),
        "amber_light": create_pbr_material("AmberLight",   (1.00, 0.58, 0.05, 1.0), metallic=0.10, roughness=0.15, emission=2.0, mat_type=3.0),
        "interior":    create_pbr_material("InteriorCab",  (0.13, 0.15, 0.19, 1.0), metallic=0.10, roughness=0.78, mat_type=0.0),
        "seat_sport":  create_pbr_material("SeatSport",    (0.18, 0.20, 0.25, 1.0), metallic=0.10, roughness=0.68, mat_type=0.0),
        "safety_org":  create_pbr_material("SafetyOrange", (0.98, 0.40, 0.06, 1.0), metallic=0.05, roughness=0.40, mat_type=1.0),
        "white_strip": create_pbr_material("ReflectWhite", (0.96, 0.97, 0.99, 1.0), metallic=0.10, roughness=0.25, emission=0.5, mat_type=1.0),
        "rubber_blk":  create_pbr_material("RubberBlack",  (0.10, 0.11, 0.13, 1.0), metallic=0.05, roughness=0.88, mat_type=0.0),
        "concrete":    create_pbr_material("Concrete",     (0.68, 0.71, 0.75, 1.0), metallic=0.00, roughness=0.86, mat_type=0.0),
        "concrete_dk": create_pbr_material("ConcreteDark", (0.50, 0.53, 0.58, 1.0), metallic=0.00, roughness=0.90, mat_type=0.0),
        "barrier_red": create_pbr_material("BarrierRed",   (0.88, 0.14, 0.16, 1.0), metallic=0.20, roughness=0.38, mat_type=1.0),
        "bollard_stl": create_pbr_material("BollardSteel", (0.20, 0.25, 0.32, 1.0), metallic=0.85, roughness=0.26, mat_type=4.0),
        "warn_yellow": create_pbr_material("WarnYellow",   (0.98, 0.78, 0.08, 1.0), metallic=0.15, roughness=0.28, emission=0.6, mat_type=3.0),
        "wood_trunk":  create_pbr_material("WoodTrunk",    (0.38, 0.23, 0.12, 1.0), metallic=0.00, roughness=0.92, mat_type=0.0),
        "pine_leaf1":  create_pbr_material("PineLeafDark", (0.11, 0.34, 0.15, 1.0), metallic=0.00, roughness=0.82, mat_type=0.0),
        "pine_leaf2":  create_pbr_material("PineLeafMid",  (0.16, 0.43, 0.20, 1.0), metallic=0.00, roughness=0.78, mat_type=0.0),
        "pine_leaf3":  create_pbr_material("PineLeafBright",(0.21, 0.50, 0.24, 1.0),metallic=0.00, roughness=0.75, mat_type=0.0),
    }


def ensure_material_slot(obj, mat):
    for idx, m in enumerate(obj.data.materials):
        if m == mat:
            return idx
    obj.data.materials.append(mat)
    return len(obj.data.materials) - 1


def Euler_from_deg(rx, ry, rz):
    return Euler((math.radians(rx), math.radians(ry), math.radians(rz)), 'XYZ')


def add_oriented_face(bm, verts, mat_idx, outward_hint, smooth=True):
    """Creates a face whose winding normal is guaranteed to align with outward_hint."""
    if len(verts) < 3:
        return None
    v0, v1, v2 = verts[0].co, verts[1].co, verts[2].co
    n = (v1 - v0).cross(v2 - v0)
    use_verts = list(reversed(verts)) if n.dot(outward_hint) < 0.0 else list(verts)
    try:
        f = bm.faces.new(use_verts)
        f.material_index = mat_idx
        f.smooth = smooth
        f.normal_update()
        if f.normal.dot(outward_hint) < 0.0:
            f.normal_flip()
        return f
    except ValueError:
        return None


def add_beveled_box(bm, cx, cy, cz, hx, hy, hz, mat_idx, bevel=0.012, rot_euler=None, smooth=False):
    """
    Creates a 3D box using bmesh.ops.create_cube['verts'] (never indexing bm.verts[-8:])
    with optional 1-segment bevel and guaranteed outward normals from box center.
    """
    ret = bmesh.ops.create_cube(bm, size=2.0)
    new_verts = ret["verts"]
    new_faces = list({f for v in new_verts for f in v.link_faces})

    rot_mat = rot_euler.to_matrix() if rot_euler else Matrix.Identity(3)
    center = Vector((cx, cy, cz))
    for v in new_verts:
        local = Vector((v.co.x * hx, v.co.y * hy, v.co.z * hz))
        v.co = center + (rot_mat @ local)

    all_faces = list(new_faces)
    if bevel > 1e-4:
        edges = list({e for f in new_faces for e in f.edges})
        bev = bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=1, profile=0.5, affect='EDGES')
        all_faces = list({f for f in (new_faces + bev.get("faces", [])) if f.is_valid})

    for f in all_faces:
        if not f.is_valid:
            continue
        f.material_index = mat_idx
        f.smooth = smooth
        f.normal_update()
        out_dir = f.calc_center_median() - center
        if f.normal.dot(out_dir) < 0.0:
            f.normal_flip()


def add_cylinder_x(bm, x0, x1, cy, cz, r0, r1, segs, mat_idx, cap_ends=True, smooth=True):
    ring0, ring1 = [], []
    for s in range(segs):
        a = (2.0 * math.pi * s) / segs
        ca, sa = math.cos(a), math.sin(a)
        ring0.append(bm.verts.new((x0, cy + r0 * ca, cz + r0 * sa)))
        ring1.append(bm.verts.new((x1, cy + r1 * ca, cz + r1 * sa)))
    for s in range(segs):
        sn = (s + 1) % segs
        a = (2.0 * math.pi * (s + 0.5)) / segs
        out_n = Vector((0.0, math.cos(a), math.sin(a)))
        add_oriented_face(bm, [ring0[s], ring1[s], ring1[sn], ring0[sn]], mat_idx, out_n, smooth=smooth)
    if cap_ends:
        if r0 > 0.002:
            c0 = bm.verts.new((x0, cy, cz))
            for s in range(segs):
                sn = (s + 1) % segs
                add_oriented_face(bm, [c0, ring0[sn], ring0[s]], mat_idx, Vector((-1, 0, 0)), smooth=False)
        if r1 > 0.002:
            c1 = bm.verts.new((x1, cy, cz))
            for s in range(segs):
                sn = (s + 1) % segs
                add_oriented_face(bm, [c1, ring1[s], ring1[sn]], mat_idx, Vector((1, 0, 0)), smooth=False)


def add_cylinder_y(bm, cx, cz, y0, y1, r0, r1, segs, mat_idx, cap_top=False, smooth=True):
    ring0, ring1 = [], []
    for s in range(segs):
        a = (2.0 * math.pi * s) / segs
        ca, sa = math.cos(a), math.sin(a)
        ring0.append(bm.verts.new((cx + r0 * ca, y0, cz + r0 * sa)))
        ring1.append(bm.verts.new((cx + r1 * ca, y1, cz + r1 * sa)))
    for s in range(segs):
        sn = (s + 1) % segs
        a = (2.0 * math.pi * (s + 0.5)) / segs
        out_n = Vector((math.cos(a), 0.15, math.sin(a)))
        add_oriented_face(bm, [ring0[s], ring0[sn], ring1[sn], ring1[s]], mat_idx, out_n, smooth=smooth)
    if cap_top and r1 > 0.003:
        top_c = bm.verts.new((cx, y1, cz))
        for s in range(segs):
            sn = (s + 1) % segs
            add_oriented_face(bm, [top_c, ring1[s], ring1[sn]], mat_idx, Vector((0, 1, 0)), smooth=False)


def catmull_rom_1d(p0, p1, p2, p3, t):
    t2 = t * t
    t3 = t2 * t
    return 0.5 * (
        (2.0 * p1) +
        (-p0 + p2) * t +
        (2.0*p0 - 5.0*p1 + 4.0*p2 - p3) * t2 +
        (-p0 + 3.0*p1 - 3.0*p2 + p3) * t3
    )


def sample_profile_spline(stations, x_query):
    n = len(stations)
    if x_query <= stations[0][0]:
        return stations[0][1:]
    if x_query >= stations[-1][0]:
        return stations[-1][1:]
    idx = 0
    for i in range(n - 1):
        if stations[i][0] <= x_query <= stations[i + 1][0]:
            idx = i
            break
    x0, x1 = stations[idx][0], stations[idx + 1][0]
    t = (x_query - x0) / max(1e-6, x1 - x0)
    st = t * t * (3.0 - 2.0 * t)
    s_prev = stations[max(0, idx - 1)]
    s_curr = stations[idx]
    s_next = stations[idx + 1]
    s_next2 = stations[min(n - 1, idx + 2)]
    out = []
    for k in range(1, 7):
        lin = s_curr[k] + (s_next[k] - s_curr[k]) * st
        cr = catmull_rom_1d(s_prev[k], s_curr[k], s_next[k], s_next2[k], t)
        out.append(0.65 * lin + 0.35 * cr)
    return out


def finalize_blender_object(name, bm, location=(0.0, 0.0, 0.0), edge_split_deg=28.0):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    # NOTE: Do NOT call recalc_face_normals here because add_oriented_face and add_beveled_box
    # already orient every single face strictly outward!
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    bpy.context.collection.objects.link(obj)

    mod = obj.modifiers.new(name="EdgeSplit", type="EDGE_SPLIT")
    mod.split_angle = math.radians(edge_split_deg)
    mod.use_edge_angle = True
    return obj


# ==============================================================================
# 3. High-Resolution Sculpted Vehicle Builder in Blender 4.2 (~5,000 Tris/Car)
# ==============================================================================
def build_highres_vehicle_mesh(name, stations, pal, style="coupe", world_loc=(0, 0, 0)):
    bm = bmesh.new()
    temp_mesh = bpy.data.meshes.new(name + "_Tmp")
    temp_obj = bpy.data.objects.new(name + "_TmpObj", temp_mesh)

    m_paint  = ensure_material_slot(temp_obj, pal["car_paint"])
    m_carbon = ensure_material_slot(temp_obj, pal["carbon_trim"])
    m_well   = ensure_material_slot(temp_obj, pal["wheel_well"])
    m_grille = ensure_material_slot(temp_obj, pal["grille_dark"])
    m_glass  = ensure_material_slot(temp_obj, pal["tinted_glass"])
    m_chrome = ensure_material_slot(temp_obj, pal["chrome"])
    m_silver = ensure_material_slot(temp_obj, pal["silver_metal"])
    m_head   = ensure_material_slot(temp_obj, pal["headlight"])
    m_tail   = ensure_material_slot(temp_obj, pal["taillight"])
    m_amber  = ensure_material_slot(temp_obj, pal["amber_light"])
    m_int    = ensure_material_slot(temp_obj, pal["interior"])
    m_seat   = ensure_material_slot(temp_obj, pal["seat_sport"])

    x_min, x_max = stations[0][0], stations[-1][0]
    nx = 44
    xs = [x_min + (x_max - x_min) * (i / (nx - 1)) for i in range(nx)]

    arch_centers = [(0.70, 0.34, 0.42), (3.15, 0.34, 0.42)]
    if style == "offroad":
        arch_centers = [(0.70, 0.37, 0.46), (3.15, 0.37, 0.46)]

    half_steps = 10
    total_ring = 2 * half_steps + 1

    grid_verts = []
    for i, x in enumerate(xs):
        yF, yW, yB, yT, wH, wT = sample_profile_spline(stations, x)

        arch_lift = 0.0
        flare_out = 0.0
        for acx, acy, arad in arch_centers:
            dx = abs(x - acx)
            if dx < arad * 1.18:
                u = dx / arad
                if u < 1.0:
                    circ = math.sqrt(max(0.0, 1.0 - u * u))
                    arch_y = acy + (arad * 0.86) * circ
                    arch_lift = max(arch_lift, max(0.0, arch_y - yF))
                flare_bell = math.exp(-((dx / (arad * 0.82)) ** 2))
                flare_out = max(flare_out, (0.065 if style != "offroad" else 0.085) * flare_bell)

        yF_eff = yF + arch_lift

        hood_dome = 0.0
        if 2.55 < x < 3.85:
            hood_dome = 0.028 * math.sin(((x - 2.55) / 1.30) * math.pi)
        roof_crown = 0.032 if (1.05 < x < 2.65) else 0.016

        row = [None] * total_ring
        for hs in range(-half_steps, half_steps + 1):
            sign = -1.0 if hs < 0 else (1.0 if hs > 0 else 0.0)
            a = abs(hs)

            if a <= 4:
                t = a / 4.0
                z_abs = wT * (t ** 0.92)
                crown = roof_crown * (1.0 - t * t)
                dome = hood_dome * max(0.0, 1.0 - (t * 1.8) ** 2)
                bed_drop = 0.0
                if style == "offroad" and 0.06 < x < 1.18 and a <= 3:
                    bed_drop = -0.26
                y = yT + crown + dome + bed_drop
            elif a <= 6:
                t = (a - 4) / 2.0
                z_abs = wT + (wH * 0.96 - wT) * t + flare_out * 0.25 * t
                y = yT + (yB - yT) * t
            else:
                t = (a - 6) / 4.0
                side_curve = math.sin(t * math.pi) * 0.045
                door_scallop = -0.022 * math.sin(t * math.pi) if (1.25 < x < 2.55 and 0.2 < t < 0.8) else 0.0
                arch_lip_flare = flare_out * math.sin(t * math.pi * 0.85)
                z_abs = wH * (0.96 + 0.04 * math.sin(t * math.pi * 0.6)) + side_curve + door_scallop + arch_lip_flare
                y = yB + (yF_eff - yB) * (t ** 1.05)

            v = bm.verts.new((x, y, sign * z_abs))
            row[hs + half_steps] = v
        grid_verts.append(row)

    for i in range(nx - 1):
        xm = 0.5 * (xs[i] + xs[i + 1])
        r0 = grid_verts[i]
        r1 = grid_verts[i + 1]

        for hs in range(-half_steps, half_steps):
            c0 = hs + half_steps
            c1 = c0 + 1
            v00, v10, v11, v01 = r0[c0], r1[c0], r1[c1], r0[c1]

            hs_mid = hs + 0.5
            a_mid = abs(hs_mid)
            z_sign = -1.0 if hs_mid < 0 else 1.0

            mat = m_paint
            smooth_face = True

            is_windshield = (2.12 < xm < 2.72) and (a_mid < 3.6)
            is_rear_win = (0.62 < xm < 1.26) and (a_mid < 3.5) and (style != "offroad" or xm > 1.05)
            is_side_win = (0.92 < xm < 2.58) and (4.0 <= a_mid <= 6.0)
            is_b_pillar = (1.62 < xm < 1.76) and (4.0 <= a_mid <= 6.0)
            is_a_pillar = (2.12 < xm < 2.72) and (3.5 <= a_mid < 4.1)

            if (is_windshield or is_rear_win or is_side_win) and not is_b_pillar:
                mat = m_glass
            elif is_b_pillar or is_a_pillar:
                mat = m_carbon
            elif style == "offroad" and (0.06 < xm < 1.18) and (a_mid < 3.6):
                mat = m_carbon
                smooth_face = False
            elif a_mid > 9.0 and 0.95 < xm < 2.85:
                mat = m_carbon

            if a_mid <= 4.0:
                out_hint = Vector((0.0, 1.0, 0.25 * z_sign))
            else:
                out_hint = Vector((0.0, 0.18, z_sign))

            add_oriented_face(bm, [v00, v10, v11, v01], mat, out_hint, smooth=smooth_face)

        # Underbody chassis floor closure
        v_left0, v_left1 = r0[0], r1[0]
        v_right0, v_right1 = r0[-1], r1[-1]
        in_arch = any(abs(xm - acx) < arad * 1.05 for acx, _, arad in arch_centers)
        add_oriented_face(
            bm,
            [v_left0, v_right0, v_right1, v_left1],
            m_well if in_arch else m_carbon,
            Vector((0.0, -1.0, 0.0)),
            smooth=False
        )

    # Recessed Dark 3D Wheel-Well Housings (Radhausschalen)
    for acx, acy, arad in arch_centers:
        for z_sign in (-1.0, 1.0):
            z_outer = z_sign * (0.86 if style != "offroad" else 0.90)
            z_inner = z_sign * 0.50
            arch_segs = 18
            ring_out, ring_in = [], []
            for s in range(arch_segs + 1):
                ang = math.pi * (s / arch_segs)
                ax = acx + arad * 0.94 * math.cos(ang)
                ay = acy - 0.04 + arad * 0.88 * math.sin(ang)
                ring_out.append(bm.verts.new((ax, ay, z_outer)))
                ring_in.append(bm.verts.new((ax, ay, z_inner)))
            for s in range(arch_segs):
                add_oriented_face(
                    bm,
                    [ring_out[s], ring_out[s + 1], ring_in[s + 1], ring_in[s]],
                    m_well,
                    Vector((0.0, -0.5, z_sign)),
                    smooth=True
                )
            c_in = bm.verts.new((acx, acy - 0.02, z_inner))
            for s in range(arch_segs):
                add_oriented_face(
                    bm,
                    [c_in, ring_in[s], ring_in[s + 1]],
                    m_well,
                    Vector((0.0, 0.0, z_sign)),
                    smooth=False
                )

    # Close Front & Rear End Caps of the Body Shell
    r_rear = grid_verts[0]
    for hs in range(half_steps):
        add_oriented_face(
            bm,
            [r_rear[half_steps - hs - 1], r_rear[half_steps - hs], r_rear[half_steps + hs + 1], r_rear[half_steps + hs]],
            m_carbon,
            Vector((-1.0, 0.0, 0.0)),
            smooth=False
        )
    r_front = grid_verts[-1]
    for hs in range(half_steps):
        add_oriented_face(
            bm,
            [r_front[half_steps - hs - 1], r_front[half_steps - hs], r_front[half_steps + hs + 1], r_front[half_steps + hs]],
            m_grille,
            Vector((1.0, 0.0, 0.0)),
            smooth=False
        )

    # Detailed Front Fascia: Projector Headlights, LED DRL Strips, 3D Grille & Lower Intake
    xf = x_max
    add_beveled_box(bm, xf + 0.010, 0.56, 0.0, 0.018, 0.085, 0.44, m_chrome, bevel=0.006)
    add_beveled_box(bm, xf + 0.016, 0.56, 0.0, 0.015, 0.072, 0.41, m_grille, bevel=0.004)
    for g_bar in (-0.035, 0.0, 0.035):
        add_beveled_box(bm, xf + 0.024, 0.56 + g_bar, 0.0, 0.008, 0.006, 0.39, m_silver, bevel=0.002)
    add_beveled_box(bm, xf + 0.012, 0.36, 0.0, 0.020, 0.055, 0.50, m_grille, bevel=0.004)

    for z_sign in (-1.0, 1.0):
        add_beveled_box(bm, xf - 0.01, 0.60, z_sign * 0.62, 0.035, 0.058, 0.17, m_carbon, bevel=0.006)
        add_cylinder_x(bm, xf - 0.01, xf + 0.032, 0.60, z_sign * 0.56, 0.034, 0.030, 16, m_head)
        add_cylinder_x(bm, xf - 0.01, xf + 0.030, 0.60, z_sign * 0.66, 0.030, 0.026, 16, m_head)
        add_beveled_box(bm, xf + 0.024, 0.648, z_sign * 0.61, 0.012, 0.008, 0.15, m_head, bevel=0.002)
        add_beveled_box(bm, xf - 0.01,  0.595, z_sign * 0.77, 0.025, 0.035, 0.025, m_amber, bevel=0.003)
        add_beveled_box(bm, xf + 0.005, 0.37, z_sign * 0.65, 0.024, 0.038, 0.11, m_carbon, bevel=0.004)
        add_cylinder_x(bm, xf + 0.005, xf + 0.030, 0.37, z_sign * 0.65, 0.022, 0.020, 14, m_head)

    # Detailed Rear Fascia: LED Lightbar Taillights, Diffuser Strakes & Round Exhausts
    xr = x_min
    for z_sign in (-1.0, 1.0):
        add_beveled_box(bm, xr - 0.012, 0.72, z_sign * 0.60, 0.025, 0.052, 0.22, m_tail, bevel=0.006)
        add_beveled_box(bm, xr - 0.022, 0.735, z_sign * 0.55, 0.018, 0.014, 0.12, m_head, bevel=0.002)
        add_beveled_box(bm, xr - 0.022, 0.695, z_sign * 0.66, 0.018, 0.012, 0.10, m_amber, bevel=0.002)
    if style == "coupe":
        add_beveled_box(bm, xr - 0.015, 0.745, 0.0, 0.018, 0.014, 0.42, m_tail, bevel=0.003)

    add_beveled_box(bm, xr + 0.03, 0.35, 0.0, 0.05, 0.048, 0.68, m_carbon, bevel=0.006)
    for z_fin in (-0.36, -0.14, 0.14, 0.36):
        add_beveled_box(bm, xr - 0.01, 0.34, z_fin, 0.055, 0.052, 0.012, m_carbon, bevel=0.002)

    for z_sign in (-1.0, 1.0):
        ex_offsets = [0.50, 0.61] if style == "coupe" else [0.54]
        for z_off in ex_offsets:
            add_cylinder_x(bm, xr - 0.10, xr + 0.10, 0.32, z_sign * z_off, 0.040, 0.042, 20, m_chrome)
            add_cylinder_x(bm, xr - 0.105, xr - 0.08, 0.32, z_sign * z_off, 0.031, 0.031, 16, m_well)

    # Exterior Details: Sculpted Wing Mirrors, Door Handles & Shark-Fin Antenna
    for z_sign in (-1.0, 1.0):
        add_beveled_box(bm, 2.34, 0.89, z_sign * 0.84, 0.035, 0.022, 0.055, m_carbon, bevel=0.004)
        add_beveled_box(bm, 2.30, 0.92, z_sign * 0.92, 0.068, 0.044, 0.075, m_paint, bevel=0.010, smooth=True)
        add_beveled_box(bm, 2.24, 0.92, z_sign * 0.92, 0.012, 0.034, 0.062, m_chrome, bevel=0.002)
        add_beveled_box(bm, 1.62, 0.79, z_sign * 0.89, 0.085, 0.018, 0.022, m_paint, bevel=0.004, smooth=True)
        add_beveled_box(bm, 1.62, 0.79, z_sign * 0.88, 0.092, 0.024, 0.012, m_carbon, bevel=0.002)

    if style == "coupe":
        add_beveled_box(bm, 1.28, 1.32, 0.0, 0.085, 0.048, 0.022, m_carbon, bevel=0.005, smooth=True)

    # Detailed 3D Interior: Two Sport Bucket Seats, Dashboard, Gauge Pod, Steering Wheel & Console
    add_beveled_box(bm, 1.85, 0.44, 0.0, 0.58, 0.08, 0.14, m_int, bevel=0.012)
    add_beveled_box(bm, 2.02, 0.58, 0.0, 0.025, 0.08, 0.025, m_silver, bevel=0.004)
    add_beveled_box(bm, 2.38, 0.76, 0.0, 0.20, 0.11, 0.68, m_int, bevel=0.015, smooth=True)
    add_beveled_box(bm, 2.32, 0.87, -0.36, 0.10, 0.055, 0.15, m_carbon, bevel=0.010, smooth=True)
    add_cylinder_x(bm, 2.12, 2.32, 0.81, -0.36, 0.032, 0.038, 12, m_int)
    add_cylinder_x(bm, 2.09, 2.13, 0.82, -0.36, 0.145, 0.145, 20, m_carbon)

    for z_seat in (-0.36, 0.36):
        add_beveled_box(bm, 1.78, 0.50, z_seat, 0.24, 0.06, 0.21, m_seat, bevel=0.014, smooth=True)
        add_beveled_box(bm, 1.78, 0.54, z_seat - 0.17, 0.22, 0.045, 0.045, m_int, bevel=0.010, smooth=True)
        add_beveled_box(bm, 1.78, 0.54, z_seat + 0.17, 0.22, 0.045, 0.045, m_int, bevel=0.010, smooth=True)
        tilt = Euler_from_deg(0, 0, 14)
        add_beveled_box(bm, 1.56, 0.76, z_seat, 0.065, 0.26, 0.20, m_seat, bevel=0.014, rot_euler=tilt, smooth=True)
        add_beveled_box(bm, 1.50, 1.05, z_seat, 0.052, 0.095, 0.12, m_int, bevel=0.012, rot_euler=tilt, smooth=True)

    # Preset-Specific Signature Aero & Offroad Parts
    if style == "coupe":
        add_beveled_box(bm, xf + 0.07, 0.285, 0.0, 0.12, 0.016, 0.86, m_carbon, bevel=0.004)
        for z_sign in (-1.0, 1.0):
            add_beveled_box(bm, xf + 0.09, 0.34, z_sign * 0.85, 0.09, 0.065, 0.014, m_carbon, bevel=0.003)
            add_beveled_box(bm, xf + 0.03, 0.39, z_sign * 0.79, 0.07, 0.010, 0.07, m_carbon, bevel=0.002)
        add_beveled_box(bm, 0.16, 0.94, -0.44, 0.065, 0.12, 0.020, m_carbon, bevel=0.004)
        add_beveled_box(bm, 0.16, 0.94,  0.44, 0.065, 0.12, 0.020, m_carbon, bevel=0.004)
        wing_tilt = Euler_from_deg(0, 0, -8)
        add_beveled_box(bm, 0.14, 1.06,  0.0,  0.14,  0.022, 0.84, m_paint, bevel=0.006, rot_euler=wing_tilt, smooth=True)
        add_beveled_box(bm, 0.05, 1.08,  0.0,  0.035, 0.014, 0.83, m_carbon, bevel=0.003, rot_euler=wing_tilt)
        add_beveled_box(bm, 0.14, 1.06, -0.84, 0.17,  0.095, 0.016, m_carbon, bevel=0.004)
        add_beveled_box(bm, 0.14, 1.06,  0.84, 0.17,  0.095, 0.016, m_carbon, bevel=0.004)

    elif style == "muscle":
        add_beveled_box(bm, 3.08, 0.88, 0.0, 0.34, 0.045, 0.26, m_carbon, bevel=0.008)
        add_beveled_box(bm, 3.10, 0.95, 0.0, 0.28, 0.055, 0.21, m_chrome, bevel=0.012, smooth=True)
        add_beveled_box(bm, 3.38, 0.955, 0.0, 0.02, 0.038, 0.18, m_grille, bevel=0.003)
        for z_bf in (-0.11, 0.0, 0.11):
            add_cylinder_x(bm, 3.36, 3.41, 0.955, z_bf, 0.032, 0.032, 16, m_tail)
        add_beveled_box(bm, xf + 0.045, 0.38, 0.0, 0.048, 0.055, 0.90, m_chrome, bevel=0.012, smooth=True)
        add_beveled_box(bm, xr - 0.040, 0.40, 0.0, 0.048, 0.055, 0.90, m_chrome, bevel=0.012, smooth=True)
        for lv in range(5):
            lx = 0.72 + lv * 0.12
            ly = 0.92 + lv * 0.068
            add_beveled_box(bm, lx, ly, 0.0, 0.045, 0.008, 0.56, m_carbon, bevel=0.002)
        add_beveled_box(bm, 0.06, 0.90, 0.0, 0.075, 0.058, 0.82, m_carbon, bevel=0.010, smooth=True)

    elif style == "offroad":
        add_beveled_box(bm, xf + 0.09, 0.44,  0.0,  0.055, 0.065, 0.84, m_carbon, bevel=0.010)
        add_beveled_box(bm, xf + 0.06, 0.34,  0.0,  0.065, 0.045, 0.52, m_silver, bevel=0.008)
        add_beveled_box(bm, xf + 0.11, 0.62, -0.42, 0.035, 0.24,  0.035, m_carbon, bevel=0.006)
        add_beveled_box(bm, xf + 0.11, 0.62,  0.42, 0.035, 0.24,  0.035, m_carbon, bevel=0.006)
        add_beveled_box(bm, xf + 0.11, 0.82,  0.0,  0.032, 0.032, 0.48, m_carbon, bevel=0.006)
        add_beveled_box(bm, 2.36, 1.48, 0.0, 0.065, 0.045, 0.64, m_carbon, bevel=0.008)
        for z_led in (-0.50, -0.30, -0.10, 0.10, 0.30, 0.50):
            add_cylinder_x(bm, 2.34, 2.44, 1.48, z_led, 0.032, 0.032, 14, m_head)
        add_beveled_box(bm, 1.12, 1.18, -0.60, 0.042, 0.26, 0.042, m_carbon, bevel=0.008)
        add_beveled_box(bm, 1.12, 1.18,  0.60, 0.042, 0.26, 0.042, m_carbon, bevel=0.008)
        add_beveled_box(bm, 1.12, 1.41,  0.0,  0.042, 0.042, 0.64, m_carbon, bevel=0.008)
        for z_sign in (-1.0, 1.0):
            add_beveled_box(bm, 0.72, 1.14, z_sign * 0.60, 0.42, 0.036, 0.036, m_carbon, bevel=0.006, rot_euler=Euler_from_deg(0, 0, -28))
            add_beveled_box(bm, 1.92, 0.30, z_sign * 0.92, 0.85, 0.028, 0.055, m_carbon, bevel=0.005)

    obj = finalize_blender_object(name, bm, location=world_loc, edge_split_deg=28.0)
    for m in temp_obj.data.materials:
        obj.data.materials.append(m)
    bpy.data.objects.remove(temp_obj)
    bpy.data.meshes.remove(temp_mesh)
    return obj


def build_all_vehicles(pal):
    coupe_stations = [
        (0.00, 0.36, 0.56, 0.80, 0.84, 0.85, 0.72),
        (0.28, 0.32, 0.55, 0.82, 0.88, 0.89, 0.75),
        (0.68, 0.30, 0.55, 0.84, 0.94, 0.91, 0.74),
        (1.22, 0.28, 0.54, 0.85, 1.27, 0.89, 0.64),
        (1.85, 0.28, 0.54, 0.85, 1.30, 0.89, 0.63),
        (2.18, 0.28, 0.55, 0.84, 1.24, 0.90, 0.66),
        (2.68, 0.29, 0.55, 0.81, 0.84, 0.91, 0.77),
        (3.22, 0.30, 0.53, 0.76, 0.79, 0.90, 0.76),
        (3.85, 0.31, 0.50, 0.68, 0.71, 0.86, 0.72),
        (4.18, 0.33, 0.46, 0.60, 0.62, 0.79, 0.66),
    ]
    coupe = build_highres_vehicle_mesh("ETK_Sport_Coupe", coupe_stations, pal, style="coupe", world_loc=(0, 0, 0))

    muscle_stations = [
        (0.00, 0.36, 0.58, 0.84, 0.86, 0.89, 0.78),
        (0.35, 0.31, 0.58, 0.86, 0.90, 0.93, 0.80),
        (0.75, 0.29, 0.58, 0.87, 0.95, 0.94, 0.78),
        (1.18, 0.28, 0.56, 0.86, 1.25, 0.91, 0.66),
        (1.82, 0.28, 0.56, 0.86, 1.26, 0.91, 0.66),
        (2.12, 0.28, 0.56, 0.85, 1.22, 0.91, 0.68),
        (2.48, 0.29, 0.56, 0.84, 0.86, 0.92, 0.80),
        (3.25, 0.30, 0.55, 0.82, 0.84, 0.92, 0.80),
        (3.92, 0.32, 0.52, 0.76, 0.79, 0.89, 0.77),
        (4.20, 0.34, 0.48, 0.69, 0.72, 0.84, 0.74),
    ]
    muscle = build_highres_vehicle_mesh("Bruckell_V8_Muscle", muscle_stations, pal, style="muscle", world_loc=(0, 0, 4.0))

    offroad_stations = [
        (0.00, 0.44, 0.66, 0.96, 0.98, 0.91, 0.84),
        (0.55, 0.42, 0.66, 0.96, 0.98, 0.93, 0.85),
        (1.18, 0.40, 0.66, 0.96, 0.99, 0.93, 0.85),
        (1.24, 0.40, 0.68, 0.98, 1.44, 0.93, 0.74),
        (2.05, 0.40, 0.68, 0.98, 1.45, 0.93, 0.74),
        (2.32, 0.40, 0.68, 0.97, 1.42, 0.93, 0.76),
        (2.68, 0.41, 0.66, 0.94, 0.97, 0.93, 0.83),
        (3.35, 0.42, 0.64, 0.91, 0.94, 0.92, 0.82),
        (3.95, 0.44, 0.60, 0.86, 0.89, 0.89, 0.79),
        (4.18, 0.46, 0.56, 0.80, 0.82, 0.85, 0.76),
    ]
    offroad = build_highres_vehicle_mesh("Gavril_Offroad_4x4", offroad_stations, pal, style="offroad", world_loc=(0, 0, 8.0))

    return {
        "coupe": coupe,
        "muscle": muscle,
        "offroad": offroad,
    }


def build_traffic_cone(pal, world_loc=(6, 0, 0)):
    bm = bmesh.new()
    tmp_m = bpy.data.meshes.new("ConeTmp")
    tmp_o = bpy.data.objects.new("ConeTmp", tmp_m)
    m_blk = ensure_material_slot(tmp_o, pal["rubber_blk"])
    m_org = ensure_material_slot(tmp_o, pal["safety_org"])
    m_wht = ensure_material_slot(tmp_o, pal["white_strip"])

    add_beveled_box(bm, 0.0, 0.035, 0.0, 0.30, 0.035, 0.30, m_blk, bevel=0.010)
    bands = [
        (0.07, 0.26, 0.22, 0.165, m_org),
        (0.26, 0.44, 0.165, 0.115, m_wht),
        (0.44, 0.58, 0.115, 0.078, m_org),
        (0.58, 0.72, 0.078, 0.046, m_wht),
        (0.72, 0.88, 0.046, 0.022, m_org),
    ]
    for y0, y1, r0, r1, mat in bands:
        add_cylinder_y(bm, 0.0, 0.0, y0, y1, r0, r1, 24, mat, cap_top=(y1 > 0.85), smooth=True)

    obj = finalize_blender_object("Traffic_Cone", bm, location=world_loc, edge_split_deg=35.0)
    for m in tmp_o.data.materials: obj.data.materials.append(m)
    bpy.data.objects.remove(tmp_o); bpy.data.meshes.remove(tmp_m)
    return obj


def build_steel_bollard(pal, world_loc=(8, 0, 0)):
    bm = bmesh.new()
    tmp_m = bpy.data.meshes.new("BollardTmp")
    tmp_o = bpy.data.objects.new("BollardTmp", tmp_m)
    m_blk = ensure_material_slot(tmp_o, pal["rubber_blk"])
    m_stl = ensure_material_slot(tmp_o, pal["bollard_stl"])
    m_yel = ensure_material_slot(tmp_o, pal["warn_yellow"])

    add_cylinder_y(bm, 0.0, 0.0, 0.00, 0.06, 0.32, 0.28, 28, m_blk, cap_top=True, smooth=True)
    bands = [
        (0.06, 1.05, 0.22, 0.22, m_stl),
        (1.05, 1.24, 0.224, 0.224, m_yel),
        (1.24, 1.40, 0.22, 0.22, m_stl),
        (1.40, 1.56, 0.224, 0.224, m_yel),
        (1.56, 1.72, 0.22, 0.18, m_stl),
        (1.72, 1.80, 0.18, 0.06, m_stl),
    ]
    for y0, y1, r0, r1, mat in bands:
        add_cylinder_y(bm, 0.0, 0.0, y0, y1, r0, r1, 28, mat, cap_top=(y1 > 1.78), smooth=True)

    obj = finalize_blender_object("Steel_Bollard", bm, location=world_loc, edge_split_deg=35.0)
    for m in tmp_o.data.materials: obj.data.materials.append(m)
    bpy.data.objects.remove(tmp_o); bpy.data.meshes.remove(tmp_m)
    return obj


def build_jersey_barrier(pal, world_loc=(10, 0, 0)):
    bm = bmesh.new()
    tmp_m = bpy.data.meshes.new("JerseyTmp")
    tmp_o = bpy.data.objects.new("JerseyTmp", tmp_m)
    m_con = ensure_material_slot(tmp_o, pal["concrete"])
    m_cdk = ensure_material_slot(tmp_o, pal["concrete_dk"])
    m_yel = ensure_material_slot(tmp_o, pal["warn_yellow"])

    profile = [
        (0.00, -0.34), (0.00,  0.34),
        (0.18,  0.34), (0.42,  0.19),
        (1.05,  0.13), (1.05, -0.13),
        (0.42, -0.19), (0.18, -0.34),
    ]
    hx = 1.48
    front_v = [bm.verts.new((-hx, y, z)) for y, z in profile]
    back_v  = [bm.verts.new(( hx, y, z)) for y, z in profile]
    n = len(profile)
    for i in range(n):
        inext = (i + 1) % n
        mat = m_cdk if i == 0 else m_con
        ym = 0.5 * (profile[i][0] + profile[inext][0])
        zm = 0.5 * (profile[i][1] + profile[inext][1])
        out_n = Vector((0.0, 1.0 if ym > 0.9 else (-1.0 if ym < 0.05 else 0.2), 1.0 if zm >= 0 else -1.0))
        add_oriented_face(bm, [front_v[i], back_v[i], back_v[inext], front_v[inext]], mat, out_n, smooth=False)

    for s_end, v_ring in ((-1.0, front_v), (1.0, back_v)):
        add_oriented_face(bm, [v_ring[0], v_ring[1], v_ring[2], v_ring[7]], m_cdk, Vector((s_end, 0, 0)), smooth=False)
        add_oriented_face(bm, [v_ring[7], v_ring[2], v_ring[3], v_ring[6]], m_cdk, Vector((s_end, 0, 0)), smooth=False)
        add_oriented_face(bm, [v_ring[6], v_ring[3], v_ring[4], v_ring[5]], m_cdk, Vector((s_end, 0, 0)), smooth=False)

    add_beveled_box(bm, 0.0, 0.88, 0.0, 0.45, 0.045, 0.155, m_yel, bevel=0.006)

    obj = finalize_blender_object("Jersey_Barrier", bm, location=world_loc, edge_split_deg=28.0)
    for m in tmp_o.data.materials: obj.data.materials.append(m)
    bpy.data.objects.remove(tmp_o); bpy.data.meshes.remove(tmp_m)
    return obj


def build_pine_tree(pal, world_loc=(12, 0, 0)):
    bm = bmesh.new()
    tmp_m = bpy.data.meshes.new("TreeTmp")
    tmp_o = bpy.data.objects.new("TreeTmp", tmp_m)
    m_trk = ensure_material_slot(tmp_o, pal["wood_trunk"])
    m_lf1 = ensure_material_slot(tmp_o, pal["pine_leaf1"])
    m_lf2 = ensure_material_slot(tmp_o, pal["pine_leaf2"])
    m_lf3 = ensure_material_slot(tmp_o, pal["pine_leaf3"])

    add_cylinder_y(bm, 0.0, 0.0, 0.0, 1.45, 0.28, 0.18, 16, m_trk, smooth=True)
    tiers = [
        (1.05, 3.00, 1.85, 0.22, m_lf1),
        (2.25, 4.15, 1.48, 0.18, m_lf2),
        (3.35, 5.10, 1.10, 0.12, m_lf1),
        (4.30, 5.85, 0.72, 0.02, m_lf3),
    ]
    for y0, y1, r0, r1, mat in tiers:
        add_cylinder_y(bm, 0.0, 0.0, y0, y1, r0, r1, 18, mat, cap_top=True, smooth=True)

    obj = finalize_blender_object("Pine_Tree", bm, location=world_loc, edge_split_deg=38.0)
    for m in tmp_o.data.materials: obj.data.materials.append(m)
    bpy.data.objects.remove(tmp_o); bpy.data.meshes.remove(tmp_m)
    return obj


def build_tire_stack(pal, world_loc=(15, 0, 0)):
    bm = bmesh.new()
    tmp_m = bpy.data.meshes.new("TireStackTmp")
    tmp_o = bpy.data.objects.new("TireStackTmp", tmp_m)
    m_blk = ensure_material_slot(tmp_o, pal["rubber_blk"])
    m_red = ensure_material_slot(tmp_o, pal["barrier_red"])
    m_wht = ensure_material_slot(tmp_o, pal["white_strip"])

    for idx, mat in enumerate([m_red, m_wht, m_blk]):
        y0 = idx * 0.38
        y1 = y0 + 0.36
        add_cylinder_y(bm, 0.0, 0.0, y0, y0 + 0.06, 0.40, 0.46, 24, mat, smooth=True)
        add_cylinder_y(bm, 0.0, 0.0, y0 + 0.06, y1 - 0.06, 0.46, 0.46, 24, mat, smooth=True)
        add_cylinder_y(bm, 0.0, 0.0, y1 - 0.06, y1, 0.46, 0.40, 24, mat, cap_top=True, smooth=True)
        add_cylinder_y(bm, 0.0, 0.0, y1 - 0.01, y1 + 0.005, 0.25, 0.02, 20, m_blk, cap_top=True, smooth=False)

    obj = finalize_blender_object("Tire_Stack", bm, location=world_loc, edge_split_deg=35.0)
    for m in tmp_o.data.materials: obj.data.materials.append(m)
    bpy.data.objects.remove(tmp_o); bpy.data.meshes.remove(tmp_m)
    return obj


def build_euroncap_barrier(pal, world_loc=(18, 0, 0)):
    bm = bmesh.new()
    tmp_m = bpy.data.meshes.new("BarrierTmp")
    tmp_o = bpy.data.objects.new("BarrierTmp", tmp_m)
    m_con = ensure_material_slot(tmp_o, pal["concrete_dk"])
    m_red = ensure_material_slot(tmp_o, pal["barrier_red"])
    m_wht = ensure_material_slot(tmp_o, pal["white_strip"])
    m_yel = ensure_material_slot(tmp_o, pal["warn_yellow"])

    add_beveled_box(bm, 0.15, 1.10, 0.0, 0.68, 1.10, 2.80, m_con, bevel=0.025)
    for s in range(6):
        sz = -2.25 + s * 0.90
        mat = m_red if (s % 2 == 0) else m_wht
        add_beveled_box(bm, -0.62, 0.95, sz, 0.22, 0.95, 0.44, mat, bevel=0.015)
    add_beveled_box(bm, -0.72, 2.05, 0.0, 0.08, 0.12, 2.75, m_yel, bevel=0.008)

    obj = finalize_blender_object("EuroNCAP_Barrier", bm, location=world_loc, edge_split_deg=28.0)
    for m in tmp_o.data.materials: obj.data.materials.append(m)
    bpy.data.objects.remove(tmp_o); bpy.data.meshes.remove(tmp_m)
    return obj


def extract_evaluated_mesh_for_webgl(obj):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    eval_obj = obj.evaluated_get(depsgraph)
    mesh = eval_obj.to_mesh()
    mesh.calc_loop_triangles()

    verts = []
    for v in mesh.vertices:
        verts.append([
            round(float(v.co.x), 4),
            round(float(v.co.y), 4),
            round(float(v.co.z), 4),
            round(float(v.normal.x), 4),
            round(float(v.normal.y), 4),
            round(float(v.normal.z), 4),
        ])

    tris = []
    for lt in mesh.loop_triangles:
        mat = mesh.materials[lt.material_index] if lt.material_index < len(mesh.materials) else None
        col = list(mat.get("sb_col", [0.8, 0.8, 0.8, 1.0])) if mat else [0.8, 0.8, 0.8, 1.0]
        mtype = float(mat.get("sb_type", 0.0)) if mat else 0.0
        mrough = float(mat.get("sb_rough", 0.5)) if mat else 0.5
        mpaint = bool(mat.get("sb_paint", False)) if mat else False

        ia, ib, ic = int(lt.vertices[0]), int(lt.vertices[1]), int(lt.vertices[2])
        fn = lt.normal
        tris.append({
            "a": ia,
            "b": ib,
            "c": ic,
            "n": [round(float(fn.x), 3), round(float(fn.y), 3), round(float(fn.z), 3)],
            "col": [round(float(c), 3) for c in col],
            "type": round(mtype, 2),
            "rough": round(mrough, 2),
            "paint": 1 if mpaint else 0,
        })

    eval_obj.to_mesh_clear()
    return {"verts": verts, "tris": tris}


def export_single_glb(obj, filepath):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    saved_loc = obj.location.copy()
    obj.location = (0.0, 0.0, 0.0)
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        use_selection=True,
        export_format="GLB",
        export_apply=True,
        export_yup=True,
    )
    obj.location = saved_loc


def main():
    os.makedirs(MODELS_DIR, exist_ok=True)
    reset_blender_scene()
    pal = build_palette()

    vehicles = build_all_vehicles(pal)
    props = {
        "traffic_cone":     build_traffic_cone(pal),
        "steel_bollard":    build_steel_bollard(pal),
        "jersey_barrier":   build_jersey_barrier(pal),
        "pine_tree":        build_pine_tree(pal),
        "tire_stack":       build_tire_stack(pal),
        "euroncap_barrier": build_euroncap_barrier(pal),
    }

    blend_path = os.path.join(MODELS_DIR, "softbodydriver_assets.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    if os.path.exists(blend_path + "1"):
        os.remove(blend_path + "1")
    print(f"[Blender 4.2] Saved master scene: {blend_path}")

    all_glb_path = os.path.join(MODELS_DIR, "softbodydriver_assets.glb")
    bpy.ops.export_scene.gltf(filepath=all_glb_path, export_format="GLB", export_apply=True, export_yup=True)

    for key, obj in vehicles.items():
        fname = {"coupe": "etk_coupe.glb", "muscle": "bruckell_muscle.glb", "offroad": "gavril_offroad.glb"}[key]
        export_single_glb(obj, os.path.join(MODELS_DIR, fname))

    for key, obj in props.items():
        export_single_glb(obj, os.path.join(MODELS_DIR, f"{key}.glb"))

    bundle = {
        "generator": f"Blender {bpy.app.version_string}",
        "vehicles": {k: extract_evaluated_mesh_for_webgl(obj) for k, obj in vehicles.items()},
        "props":    {k: extract_evaluated_mesh_for_webgl(obj) for k, obj in props.items()},
    }

    with open(WEB_JS_PATH, "w", encoding="utf-8") as f:
        f.write("// Auto-generated by tools/blender_build_models.py using Blender " + bpy.app.version_string + "\n")
        f.write("window.BLENDER_MODELS = ")
        json.dump(bundle, f, separators=(",", ":"))
        f.write(";\n")

    print(f"[Blender 4.2] Wrote WebGL mesh bundle: {WEB_JS_PATH}")
    for k, v in bundle["vehicles"].items():
        print(f"  Vehicle '{k}': {len(v['verts'])} verts, {len(v['tris'])} tris")
    for k, p in bundle["props"].items():
        print(f"  Prop    '{k}': {len(p['verts'])} verts, {len(p['tris'])} tris")


if __name__ == "__main__":
    main()
    sys.stdout.flush()
    os._exit(0)
