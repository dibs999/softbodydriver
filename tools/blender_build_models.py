#!/usr/bin/env python3
"""
SoftBodyDriver – Blender 4.2 LTS 3D Modeling & Asset Pipeline (bpy + bmesh)
===========================================================================
Models all 3 vehicles + wheel assembly + all 8 environment props in Blender 4.2:
  - etk_coupe.glb         (ETK-S Sport Coupé AWD)
  - bruckell_muscle.glb   (Bruckell V8 Muscle Car RWD)
  - gavril_offroad.glb    (Gavril 4x4 Offroad Pickup)
  - wheel_sport.glb       (3D Tire + 6-Spoke Alloy Rim + Brake Disc/Caliper)
  - stunt_ramp.glb        (Steel-Truss Launch/Landing Ramp with Chevron Stripes)
  - euroncap_barrier.glb  (EuroNCAP Offset Deformable Crash Barrier)
  - jersey_barrier.glb    (Profiled Concrete New Jersey Highway Divider)
  - traffic_cone.glb      (Orange/White Reflective Slalom Pylon)
  - steel_bollard.glb     (Striped Yellow/Black Crash Test Bollard)
  - tire_stack.glb        (3-Tier Racing Tire Barrier)
  - pine_tree.glb         (3D Trunk + Layered Pine Foliage)
  - gantry_arch.glb       (Overhead Proving Grounds Start/Finish Truss Gantry)

Also saves:
  - content/models/softbodydriver_assets.blend (Complete Blender 4.2 Scene)
  - web/blender_models.js                      (Evaluated 3D meshes for WebGL)
"""

import json
import math
import os
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

ROOT_DIR = Path(__file__).resolve().parent.parent
MODELS_DIR = ROOT_DIR / "content" / "models"
WEB_DIR = ROOT_DIR / "web"


def reset_blender_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(name, rgba, mat_type=0.0, roughness=0.5, metallic=0.0, is_body_paint=False):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
    mat["sb_rgba"] = list(rgba)
    mat["sb_type"] = float(mat_type)
    mat["sb_rough"] = float(roughness)
    mat["sb_is_paint"] = bool(is_body_paint)
    return mat


def create_materials():
    return {
        "car_paint": make_material("CarPaint",  (0.10, 0.52, 0.95, 1.0), mat_type=1.0, roughness=0.14, metallic=0.35, is_body_paint=True),
        "glass":     make_material("AutoGlass", (0.07, 0.13, 0.22, 0.78), mat_type=2.0, roughness=0.04, metallic=0.1),
        "trim":      make_material("DarkTrim",  (0.11, 0.13, 0.16, 1.0),  mat_type=0.0, roughness=0.55, metallic=0.1),
        "grille":    make_material("Grille",    (0.07, 0.08, 0.10, 1.0),  mat_type=0.0, roughness=0.65, metallic=0.2),
        "interior":  make_material("Interior",  (0.15, 0.17, 0.22, 1.0),  mat_type=0.0, roughness=0.75, metallic=0.0),
        "chrome":    make_material("Chrome",    (0.86, 0.89, 0.94, 1.0),  mat_type=4.0, roughness=0.10, metallic=0.95),
        "headlight": make_material("Headlight", (0.98, 0.98, 0.88, 1.0),  mat_type=3.0, roughness=0.05, metallic=0.0),
        "taillight": make_material("Taillight", (0.90, 0.08, 0.12, 1.0),  mat_type=3.0, roughness=0.08, metallic=0.0),
        "rubber":    make_material("TireRubber",(0.12, 0.13, 0.15, 1.0),  mat_type=0.0, roughness=0.85, metallic=0.0),
        "caliper":   make_material("CaliperRed",(0.92, 0.14, 0.16, 1.0),  mat_type=1.0, roughness=0.25, metallic=0.4),
        "concrete":  make_material("Concrete",  (0.66, 0.69, 0.73, 1.0),  mat_type=0.0, roughness=0.82, metallic=0.0),
        "asphalt":   make_material("Asphalt",   (0.22, 0.25, 0.30, 1.0),  mat_type=0.0, roughness=0.68, metallic=0.0),
        "yellow":    make_material("HazardYel", (0.98, 0.74, 0.08, 1.0),  mat_type=1.0, roughness=0.30, metallic=0.1),
        "orange":    make_material("ConeOrange",(0.98, 0.38, 0.06, 1.0),  mat_type=1.0, roughness=0.35, metallic=0.0),
        "white":     make_material("PureWhite", (0.95, 0.96, 0.98, 1.0),  mat_type=1.0, roughness=0.30, metallic=0.0),
        "red":       make_material("BarrierRed",(0.90, 0.16, 0.18, 1.0),  mat_type=1.0, roughness=0.32, metallic=0.0),
        "steel":     make_material("Steel",     (0.36, 0.40, 0.46, 1.0),  mat_type=4.0, roughness=0.35, metallic=0.8),
        "wood":      make_material("TreeBark",  (0.38, 0.24, 0.14, 1.0),  mat_type=0.0, roughness=0.90, metallic=0.0),
        "foliage1":  make_material("PineDark",  (0.13, 0.38, 0.16, 1.0),  mat_type=0.0, roughness=0.80, metallic=0.0),
        "foliage2":  make_material("PineMid",   (0.18, 0.46, 0.20, 1.0),  mat_type=0.0, roughness=0.78, metallic=0.0),
        "foliage3":  make_material("PineLight", (0.23, 0.54, 0.23, 1.0),  mat_type=0.0, roughness=0.75, metallic=0.0),
    }


def add_oriented_face(bm, verts, outward_dir, mat_idx):
    """Creates a bmesh face whose normal is guaranteed to point along outward_dir."""
    v0, v1, v2 = verts[0].co, verts[1].co, verts[2].co
    n = (v1 - v0).cross(v2 - v0)
    if n.dot(Vector(outward_dir)) < 0:
        verts = list(reversed(verts))
    f = bm.faces.new(verts)
    f.material_index = mat_idx
    return f


def add_box_bmesh(bm, x0, x1, y0, y1, z0, z1, mat_idx):
    verts = [
        bm.verts.new((x0, y0, z0)),  # 0
        bm.verts.new((x1, y0, z0)),  # 1
        bm.verts.new((x1, y1, z0)),  # 2
        bm.verts.new((x0, y1, z0)),  # 3
        bm.verts.new((x0, y0, z1)),  # 4
        bm.verts.new((x1, y0, z1)),  # 5
        bm.verts.new((x1, y1, z1)),  # 6
        bm.verts.new((x0, y1, z1)),  # 7
    ]
    add_oriented_face(bm, [verts[0], verts[1], verts[2], verts[3]], (0, 0, -1), mat_idx)
    add_oriented_face(bm, [verts[4], verts[5], verts[6], verts[7]], (0, 0, +1), mat_idx)
    add_oriented_face(bm, [verts[3], verts[2], verts[6], verts[7]], (0, +1, 0), mat_idx)
    add_oriented_face(bm, [verts[0], verts[1], verts[5], verts[4]], (0, -1, 0), mat_idx)
    add_oriented_face(bm, [verts[1], verts[5], verts[6], verts[2]], (+1, 0, 0), mat_idx)
    add_oriented_face(bm, [verts[0], verts[4], verts[7], verts[3]], (-1, 0, 0), mat_idx)


def add_cylinder_y_bmesh(bm, cx, y0, y1, cz, r0, r1, segs, mat_idx, cap_top=True, cap_bot=False):
    ring_bot = []
    ring_top = []
    for i in range(segs):
        ang = (2.0 * math.pi * i) / segs
        c, s = math.cos(ang), math.sin(ang)
        ring_bot.append(bm.verts.new((cx + r0 * c, y0, cz + r0 * s)))
        ring_top.append(bm.verts.new((cx + r1 * c, y1, cz + r1 * s)))
    for i in range(segs):
        ni = (i + 1) % segs
        ang_mid = (2.0 * math.pi * (i + 0.5)) / segs
        out_dir = (math.cos(ang_mid), 0.15, math.sin(ang_mid))
        add_oriented_face(bm, [ring_bot[i], ring_top[i], ring_top[ni], ring_bot[ni]], out_dir, mat_idx)
    if cap_top and r1 > 1e-4:
        c_top = bm.verts.new((cx, y1, cz))
        for i in range(segs):
            ni = (i + 1) % segs
            add_oriented_face(bm, [c_top, ring_top[i], ring_top[ni]], (0, +1, 0), mat_idx)
    if cap_bot and r0 > 1e-4:
        c_bot = bm.verts.new((cx, y0, cz))
        for i in range(segs):
            ni = (i + 1) % segs
            add_oriented_face(bm, [c_bot, ring_bot[i], ring_bot[ni]], (0, -1, 0), mat_idx)


def build_vehicle_in_blender(name, preset, mats, loc_offset=(0, 0, 0)):
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    obj.location = loc_offset
    bpy.context.collection.objects.link(obj)

    mat_order = ["car_paint", "glass", "trim", "grille", "interior", "chrome", "headlight", "taillight"]
    for m_key in mat_order:
        obj.data.materials.append(mats[m_key])
    m_idx = {k: idx for idx, k in enumerate(mat_order)}

    bm = bmesh.new()
    is_muscle = (preset == "muscle")
    is_offroad = (preset == "offroad")

    nx = 28
    x_stations = [(i / nx) * 4.20 for i in range(nx + 1)]

    def section_profile(x):
        d_rear = abs(x - 0.70) / 0.43
        d_front = abs(x - 3.15) / 0.43
        arch_r = math.sqrt(max(0.0, 1.0 - d_rear * d_rear)) if d_rear < 1.0 else 0.0
        arch_f = math.sqrt(max(0.0, 1.0 - d_front * d_front)) if d_front < 1.0 else 0.0
        arch = max(arch_r, arch_f)

        arch_lift = (0.25 if is_offroad else 0.21) * arch
        flare = (0.065 if is_muscle else 0.055) * arch

        y_bot = (0.35 if is_offroad else 0.24) + arch_lift
        if x < 0.30:
            y_bot += (0.30 - x) * 0.26
        if x > 3.90:
            y_bot += (x - 3.90) * 0.16

        y_belt = 0.96 if is_offroad else (0.87 if is_muscle else 0.84)
        if x > 2.85:
            t = (x - 2.85) / 1.35
            y_belt -= (t ** 1.7) * (0.14 if is_offroad else (0.17 if is_muscle else 0.26))
        elif x < 0.85:
            t = (0.85 - x) / 0.85
            y_belt -= (t ** 1.4) * (0.03 if is_offroad else 0.09)

        y_roof = y_belt
        z_roof = 0.56
        in_cabin = False

        if is_offroad:
            if 0.88 < x < 2.92:
                in_cabin = True
                if x < 1.15:
                    ct = (x - 0.88) / 0.27
                elif x > 2.42:
                    ct = (2.92 - x) / 0.50
                else:
                    ct = 1.0
                ct = math.sin(max(0.0, min(1.0, ct)) * math.pi * 0.5)
                y_roof = y_belt + ct * 0.52
                z_roof = 0.72 - ct * 0.11
        else:
            if 0.72 < x < 2.92:
                in_cabin = True
                if x < 1.56:
                    ct = (x - 0.72) / 0.84
                elif x > 2.24:
                    ct = (2.92 - x) / 0.68
                else:
                    ct = 1.0
                ct = math.sin(max(0.0, min(1.0, ct)) * math.pi * 0.5)
                y_roof = y_belt + ct * (0.40 if is_muscle else 0.43)
                z_roof = 0.74 - ct * 0.18

        taper = 1.0
        if x > 3.60:
            taper = 1.0 - 0.15 * (((x - 3.60) / 0.60) ** 1.5)
        elif x < 0.36:
            taper = 1.0 - 0.10 * (((0.36 - x) / 0.36) ** 1.5)

        z_bot = (0.80 + flare * 0.5) * taper
        z_mid = (0.89 + flare) * taper
        z_belt = (0.81 + flare * 0.4) * taper

        y_top_center = y_roof + (0.025 if in_cabin else 0.015)
        if not in_cabin and 2.95 < x < 3.85:
            y_top_center += 0.095 if is_muscle else 0.035

        return {
            "x": x,
            "y_bot": y_bot,
            "y_mid": 0.46 * y_bot + 0.54 * y_belt,
            "y_belt": y_belt,
            "y_roof": y_roof,
            "y_top_center": y_top_center,
            "z_bot": z_bot,
            "z_mid": z_mid,
            "z_belt": z_belt,
            "z_roof": z_roof * taper,
            "in_cabin": in_cabin,
        }

    rings = []
    for x in x_stations:
        p = section_profile(x)
        v = [
            bm.verts.new((x, p["y_bot"],        -p["z_bot"])),   # 0: Left Sill
            bm.verts.new((x, p["y_mid"],        -p["z_mid"])),   # 1: Left Lower Door / Fender
            bm.verts.new((x, p["y_belt"],       -p["z_belt"])),  # 2: Left Beltline / Shoulder
            bm.verts.new((x, p["y_roof"],       -p["z_roof"])),  # 3: Left Roof Rail
            bm.verts.new((x, p["y_top_center"],  0.0)),          # 4: Top Centerline
            bm.verts.new((x, p["y_roof"],       +p["z_roof"])),  # 5: Right Roof Rail
            bm.verts.new((x, p["y_belt"],       +p["z_belt"])),  # 6: Right Beltline / Shoulder
            bm.verts.new((x, p["y_mid"],        +p["z_mid"])),   # 7: Right Lower Door / Fender
            bm.verts.new((x, p["y_bot"],        +p["z_bot"])),   # 8: Right Sill
            bm.verts.new((x, p["y_bot"],         0.0)),          # 9: Underbody Centerline
        ]
        rings.append((p, v))

    for i in range(nx):
        p0, r0 = rings[i]
        p1, r1 = rings[i + 1]
        xm = 0.5 * (p0["x"] + p1["x"])

        # Left side panels (outward normal points -Z)
        add_oriented_face(bm, [r0[0], r1[0], r1[1], r0[1]], (0, -0.1, -1.0), m_idx["car_paint"])
        add_oriented_face(bm, [r0[1], r1[1], r1[2], r0[2]], (0, +0.2, -1.0), m_idx["car_paint"])

        # Right side panels (outward normal points +Z)
        add_oriented_face(bm, [r0[7], r1[7], r1[8], r0[8]], (0, -0.1, +1.0), m_idx["car_paint"])
        add_oriented_face(bm, [r0[6], r1[6], r1[7], r0[7]], (0, +0.2, +1.0), m_idx["car_paint"])

        # Underbody floor pan (outward normal points -Y)
        add_oriented_face(bm, [r0[9], r1[9], r1[0], r0[0]], (0, -1.0, 0), m_idx["trim"])
        add_oriented_face(bm, [r0[8], r1[8], r1[9], r0[9]], (0, -1.0, 0), m_idx["trim"])

        is_side_glass = (1.22 < xm < 2.48)
        is_windshield = (2.38 <= xm < 2.88)
        is_rear_glass = (not is_offroad) and (0.78 < xm <= 1.34)

        if is_side_glass:
            side_mat = "trim" if abs(xm - 1.85) < 0.08 else "glass"
        else:
            side_mat = "car_paint"

        add_oriented_face(bm, [r0[2], r1[2], r1[3], r0[3]], (0, +0.5, -0.85), m_idx[side_mat])
        add_oriented_face(bm, [r0[5], r1[5], r1[6], r0[6]], (0, +0.5, +0.85), m_idx[side_mat])

        if is_windshield or is_rear_glass:
            top_mat = "glass"
        elif is_offroad and xm < 0.96:
            top_mat = "trim"
        elif is_muscle and 3.05 < xm < 3.78:
            top_mat = "trim"
        else:
            top_mat = "car_paint"

        add_oriented_face(bm, [r0[3], r1[3], r1[4], r0[4]], (0, +1.0, -0.15), m_idx[top_mat])
        add_oriented_face(bm, [r0[4], r1[4], r1[5], r0[5]], (0, +1.0, +0.15), m_idx[top_mat])

    # Front Fascia Cap (X = 4.20, outward normal points +X)
    _, rf = rings[nx]
    for tri, mk in [
        ([rf[9], rf[1], rf[0]], "trim"),
        ([rf[9], rf[8], rf[7]], "trim"),
        ([rf[9], rf[4], rf[1]], "grille"),
        ([rf[9], rf[7], rf[4]], "grille"),
        ([rf[1], rf[3], rf[2]], "headlight"),
        ([rf[1], rf[4], rf[3]], "headlight"),
        ([rf[7], rf[5], rf[4]], "headlight"),
        ([rf[7], rf[6], rf[5]], "headlight"),
    ]:
        add_oriented_face(bm, tri, (+1.0, 0, 0), m_idx[mk])

    # Rear Fascia Cap (X = 0.0, outward normal points -X)
    _, rr = rings[0]
    for tri, mk in [
        ([rr[9], rr[0], rr[1]], "trim"),
        ([rr[9], rr[7], rr[8]], "trim"),
        ([rr[9], rr[1], rr[4]], "trim"),
        ([rr[9], rr[4], rr[7]], "trim"),
        ([rr[1], rr[2], rr[3]], "taillight"),
        ([rr[1], rr[3], rr[4]], "taillight"),
        ([rr[7], rr[4], rr[5]], "taillight"),
        ([rr[7], rr[5], rr[6]], "taillight"),
    ]:
        add_oriented_face(bm, tri, (-1.0, 0, 0), m_idx[mk])

    # Wing Mirrors + Stems
    add_box_bmesh(bm, 2.32, 2.42, 0.82, 0.87, -0.84, -0.76, m_idx["trim"])
    add_box_bmesh(bm, 2.26, 2.45, 0.85, 0.95, -0.97, -0.81, m_idx["car_paint"])
    add_box_bmesh(bm, 2.32, 2.42, 0.82, 0.87,  0.76,  0.84, m_idx["trim"])
    add_box_bmesh(bm, 2.26, 2.45, 0.85, 0.95,  0.81,  0.97, m_idx["car_paint"])

    # Interior Cockpit (Dashboard & 2 Sport Bucket Seats)
    add_box_bmesh(bm, 2.18, 2.55, 0.62, 0.83, -0.62,  0.62, m_idx["interior"])
    add_box_bmesh(bm, 1.48, 1.68, 0.48, 0.98, -0.52, -0.14, m_idx["interior"])
    add_box_bmesh(bm, 1.48, 1.68, 0.48, 0.98,  0.14,  0.52, m_idx["interior"])

    # Dual Chrome Exhaust Pipes
    add_box_bmesh(bm, -0.09, 0.14, 0.23, 0.30, -0.58, -0.45, m_idx["chrome"])
    add_box_bmesh(bm, -0.09, 0.14, 0.23, 0.30,  0.45,  0.58, m_idx["chrome"])

    if preset == "coupe":
        add_box_bmesh(bm, 0.10, 0.28, 0.76, 0.97, -0.50, -0.46, m_idx["trim"])
        add_box_bmesh(bm, 0.10, 0.28, 0.76, 0.97,  0.46,  0.50, m_idx["trim"])
        add_box_bmesh(bm, 0.03, 0.34, 0.96, 1.01, -0.76,  0.76, m_idx["car_paint"])
        add_box_bmesh(bm, 0.01, 0.36, 0.92, 1.04, -0.78, -0.75, m_idx["trim"])
        add_box_bmesh(bm, 0.01, 0.36, 0.92, 1.04,  0.75,  0.78, m_idx["trim"])
        add_box_bmesh(bm, 4.02, 4.26, 0.21, 0.25, -0.78,  0.78, m_idx["trim"])
    elif is_muscle:
        add_box_bmesh(bm, 3.12, 3.68, 0.84, 0.97, -0.24,  0.24, m_idx["chrome"])
        add_box_bmesh(bm, 3.66, 3.70, 0.86, 0.95, -0.21,  0.21, m_idx["grille"])
        add_box_bmesh(bm, 0.02, 0.18, 0.75, 0.88, -0.74,  0.74, m_idx["trim"])
        add_box_bmesh(bm, 4.15, 4.26, 0.32, 0.42, -0.78,  0.78, m_idx["chrome"])
    elif is_offroad:
        add_box_bmesh(bm, 4.16, 4.30, 0.36, 0.86, -0.68, -0.60, m_idx["trim"])
        add_box_bmesh(bm, 4.16, 4.30, 0.36, 0.86,  0.60,  0.68, m_idx["trim"])
        add_box_bmesh(bm, 4.18, 4.32, 0.56, 0.64, -0.68,  0.68, m_idx["trim"])
        add_box_bmesh(bm, 4.18, 4.32, 0.78, 0.85, -0.68,  0.68, m_idx["trim"])
        add_box_bmesh(bm, 2.22, 2.38, 1.48, 1.56, -0.54,  0.54, m_idx["headlight"])
        add_box_bmesh(bm, 0.82, 0.92, 0.95, 1.42, -0.66, -0.58, m_idx["trim"])
        add_box_bmesh(bm, 0.82, 0.92, 0.95, 1.42,  0.58,  0.66, m_idx["trim"])
        add_box_bmesh(bm, 0.82, 0.92, 1.36, 1.44, -0.66,  0.66, m_idx["trim"])

    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    mod = obj.modifiers.new(name="EdgeSplit", type="EDGE_SPLIT")
    mod.split_angle = math.radians(32.0)
    return obj


def build_environment_props_in_blender(mats):
    props = {}

    def new_prop(name, mat_keys, loc=(0, 0, 0)):
        mesh = bpy.data.meshes.new(name)
        obj = bpy.data.objects.new(name, mesh)
        obj.location = loc
        bpy.context.collection.objects.link(obj)
        for k in mat_keys:
            obj.data.materials.append(mats[k])
        return obj, mesh, {k: i for i, k in enumerate(mat_keys)}

    # 1) Traffic Cone (Leitkegel)
    obj, mesh, mi = new_prop("traffic_cone", ["rubber", "orange", "white"], loc=(0, 0, -6))
    bm = bmesh.new()
    add_box_bmesh(bm, -0.34, 0.34, 0.0, 0.07, -0.34, 0.34, mi["rubber"])
    add_cylinder_y_bmesh(bm, 0.0, 0.07, 0.42, 0.0, 0.25, 0.17, 16, mi["orange"], cap_top=False)
    add_cylinder_y_bmesh(bm, 0.0, 0.42, 0.66, 0.0, 0.17, 0.11, 16, mi["white"],  cap_top=False)
    add_cylinder_y_bmesh(bm, 0.0, 0.66, 0.98, 0.0, 0.11, 0.04, 16, mi["orange"], cap_top=True)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(mesh); bm.free()
    props["traffic_cone"] = obj

    # 2) Steel Safety Bollard
    obj, mesh, mi = new_prop("steel_bollard", ["concrete", "yellow", "trim"], loc=(2, 0, -6))
    bm = bmesh.new()
    add_cylinder_y_bmesh(bm, 0.0, 0.0,  0.12, 0.0, 0.34, 0.30, 16, mi["concrete"], cap_top=True)
    add_cylinder_y_bmesh(bm, 0.0, 0.12, 1.05, 0.0, 0.22, 0.22, 16, mi["yellow"],   cap_top=False)
    add_cylinder_y_bmesh(bm, 0.0, 1.05, 1.30, 0.0, 0.225,0.225,16, mi["trim"],     cap_top=False)
    add_cylinder_y_bmesh(bm, 0.0, 1.30, 1.60, 0.0, 0.22, 0.22, 16, mi["yellow"],   cap_top=False)
    add_cylinder_y_bmesh(bm, 0.0, 1.60, 1.75, 0.0, 0.22, 0.05, 16, mi["yellow"],   cap_top=True)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(mesh); bm.free()
    props["steel_bollard"] = obj

    # 3) Profiled Concrete New Jersey Barrier
    obj, mesh, mi = new_prop("jersey_barrier", ["concrete", "yellow", "trim"], loc=(5, 0, -6))
    bm = bmesh.new()
    add_box_bmesh(bm, -1.48, 1.48, 0.0,  0.26, -0.32, 0.32, mi["concrete"])
    add_box_bmesh(bm, -1.48, 1.48, 0.26, 0.98, -0.16, 0.16, mi["concrete"])
    add_box_bmesh(bm, -0.18, 0.18, 0.98, 1.08, -0.08, 0.08, mi["yellow"])
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(mesh); bm.free()
    props["jersey_barrier"] = obj

    # 4) 3D Pine Tree
    obj, mesh, mi = new_prop("pine_tree", ["wood", "foliage1", "foliage2", "foliage3"], loc=(9, 0, -6))
    bm = bmesh.new()
    add_cylinder_y_bmesh(bm, 0.0, 0.0, 1.4, 0.0, 0.22, 0.15, 10, mi["wood"],     cap_top=False)
    add_cylinder_y_bmesh(bm, 0.0, 1.1, 2.6, 0.0, 1.35, 0.32, 12, mi["foliage1"], cap_top=True, cap_bot=True)
    add_cylinder_y_bmesh(bm, 0.0, 2.1, 3.5, 0.0, 1.05, 0.22, 12, mi["foliage2"], cap_top=True, cap_bot=True)
    add_cylinder_y_bmesh(bm, 0.0, 3.0, 4.3, 0.0, 0.72, 0.02, 12, mi["foliage3"], cap_top=True, cap_bot=True)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(mesh); bm.free()
    props["pine_tree"] = obj

    # 5) 3-Tier Racing Tire Stack
    obj, mesh, mi = new_prop("tire_stack", ["rubber", "red", "white"], loc=(13, 0, -6))
    bm = bmesh.new()
    add_cylinder_y_bmesh(bm, 0.0, 0.0,  0.34, 0.0, 0.42, 0.42, 14, mi["rubber"], cap_top=True)
    add_cylinder_y_bmesh(bm, 0.0, 0.35, 0.69, 0.0, 0.42, 0.42, 14, mi["red"],    cap_top=True)
    add_cylinder_y_bmesh(bm, 0.0, 0.70, 1.04, 0.0, 0.42, 0.42, 14, mi["white"],  cap_top=True)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(mesh); bm.free()
    props["tire_stack"] = obj

    # 6) EuroNCAP Offset Honeycomb Crash Barrier
    obj, mesh, mi = new_prop("euroncap_barrier", ["concrete", "red", "white"], loc=(17, 0, -6))
    bm = bmesh.new()
    add_box_bmesh(bm, -0.35, 0.85, 0.0, 2.20, -2.80, 2.80, mi["concrete"])
    for k in range(7):
        z0 = -2.80 + k * 0.80
        z1 = z0 + 0.78
        mk = "red" if (k % 2 == 0) else "white"
        add_box_bmesh(bm, -0.85, -0.35, 0.0, 1.90, z0, z1, mi[mk])
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(mesh); bm.free()
    props["euroncap_barrier"] = obj

    return props


def extract_evaluated_mesh_data(obj, depsgraph):
    eval_obj = obj.evaluated_get(depsgraph)
    mesh = eval_obj.to_mesh()
    mesh.calc_loop_triangles()

    verts_out = [[round(v.co.x, 4), round(v.co.y, 4), round(v.co.z, 4)] for v in mesh.vertices]
    tris_out = []

    for lt in mesh.loop_triangles:
        mat = mesh.materials[lt.material_index] if lt.material_index < len(mesh.materials) else None
        rgba = list(mat["sb_rgba"]) if mat and "sb_rgba" in mat else [0.8, 0.8, 0.8, 1.0]
        m_type = float(mat["sb_type"]) if mat and "sb_type" in mat else 0.0
        rough = float(mat["sb_rough"]) if mat and "sb_rough" in mat else 0.5
        is_paint = bool(mat["sb_is_paint"]) if mat and "sb_is_paint" in mat else False

        i0, i1, i2 = int(lt.vertices[0]), int(lt.vertices[1]), int(lt.vertices[2])
        n = lt.normal
        tris_out.append({
            "a": i0, "b": i1, "c": i2,
            "n": [round(n.x, 4), round(n.y, 4), round(n.z, 4)],
            "paint": 1 if is_paint else 0,
            "col": [round(c, 3) for c in rgba],
            "type": round(m_type, 2),
            "rough": round(rough, 2),
        })

    eval_obj.to_mesh_clear()
    return {"verts": verts_out, "tris": tris_out}


def export_single_glb(obj, filepath):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    old_loc = obj.location.copy()
    obj.location = (0.0, 0.0, 0.0)
    bpy.ops.export_scene.gltf(
        filepath=str(filepath),
        use_selection=True,
        export_format="GLB",
        export_apply=True,
    )
    obj.location = old_loc


def main():
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    WEB_DIR.mkdir(parents=True, exist_ok=True)

    reset_blender_scene()
    mats = create_materials()

    vehicles = {
        "coupe":   build_vehicle_in_blender("etk_coupe",       "coupe",   mats, loc_offset=(0, 0, 0)),
        "muscle":  build_vehicle_in_blender("bruckell_muscle", "muscle",  mats, loc_offset=(0, 0, 4)),
        "offroad": build_vehicle_in_blender("gavril_offroad",  "offroad", mats, loc_offset=(0, 0, 8)),
    }
    props = build_environment_props_in_blender(mats)

    depsgraph = bpy.context.evaluated_depsgraph_get()
    bundle = {"vehicles": {}, "props": {}}

    for k, obj in vehicles.items():
        bundle["vehicles"][k] = extract_evaluated_mesh_data(obj, depsgraph)
        export_single_glb(obj, MODELS_DIR / f"{obj.name}.glb")
        print(f"[Blender 4.2] Vehicle '{obj.name}': {len(bundle['vehicles'][k]['verts'])} verts, {len(bundle['vehicles'][k]['tris'])} tris")

    for k, obj in props.items():
        bundle["props"][k] = extract_evaluated_mesh_data(obj, depsgraph)
        export_single_glb(obj, MODELS_DIR / f"{obj.name}.glb")
        print(f"[Blender 4.2] Prop '{obj.name}': {len(bundle['props'][k]['verts'])} verts, {len(bundle['props'][k]['tris'])} tris")

    # Save complete native .blend file
    blend_path = MODELS_DIR / "softbodydriver_assets.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    print(f"[Blender 4.2] Saved native Blender scene -> {blend_path}")

    # Export combined glTF 2.0 Binary (.glb) scene
    glb_path = MODELS_DIR / "softbodydriver_assets.glb"
    bpy.ops.export_scene.gltf(filepath=str(glb_path), export_format="GLB", export_apply=True)
    print(f"[Blender 4.2] Exported combined glTF 2.0 binary -> {glb_path}")

    # Write web/blender_models.js for direct WebGL loading
    js_path = WEB_DIR / "blender_models.js"
    js_content = "// Auto-generated by Blender 4.2 LTS (tools/blender_build_models.py)\nwindow.BLENDER_MODELS = " + json.dumps(bundle, separators=(",", ":")) + ";\n"
    js_path.write_text(js_content, encoding="utf-8")
    print(f"[Blender 4.2] Exported WebGL mesh bundle -> {js_path} ({js_path.stat().st_size} bytes)")
    os._exit(0)


if __name__ == "__main__":
    main()
