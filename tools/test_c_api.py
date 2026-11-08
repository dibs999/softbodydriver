#!/usr/bin/env python3
"""Smoke test for the C ABI (libsbcore.so / sbcore.dll / libsbcore.dylib).

Verifies that external languages / engines can create a 2000 Hz world, spawn the
drivable car, feed throttle/brake/steering controls, read live telemetry and
fetch the float32 vertex/beam buffers for rendering.
"""

import ctypes
import sys
from pathlib import Path


class TelemetryC(ctypes.Structure):
    _fields_ = [
        ("speed_kmh", ctypes.c_double),
        ("engine_rpm", ctypes.c_double),
        ("gear", ctypes.c_int32),
        ("clutch", ctypes.c_double),
        ("throttle", ctypes.c_double),
        ("brake", ctypes.c_double),
        ("steer", ctypes.c_double),
        ("deformed_beams", ctypes.c_uint32),
        ("broken_beams", ctypes.c_uint32),
    ]


def find_lib(build_dir: Path) -> Path:
    candidates = [
        build_dir / "core" / "libsbcore.so",
        build_dir / "core" / "libsbcore.dylib",
        build_dir / "core" / "sbcore.dll",
        build_dir / "core" / "Release" / "sbcore.dll",
    ]
    for c in candidates:
        if c.exists():
            return c
    raise FileNotFoundError(f"could not find shared sbcore library in {build_dir}")


def main() -> int:
    build_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("build")
    lib = ctypes.CDLL(str(find_lib(build_dir)))

    lib.sb_world_create.argtypes = [ctypes.c_double]
    lib.sb_world_create.restype = ctypes.c_void_p
    lib.sb_world_destroy.argtypes = [ctypes.c_void_p]
    lib.sb_world_add_ground_plane.argtypes = [ctypes.c_void_p, ctypes.c_double]
    lib.sb_world_spawn_drivable_car.argtypes = [ctypes.c_void_p, ctypes.c_double, ctypes.c_double, ctypes.c_double]
    lib.sb_world_spawn_drivable_car.restype = ctypes.c_int32
    lib.sb_body_set_controls.argtypes = [
        ctypes.c_void_p, ctypes.c_int32,
        ctypes.c_double, ctypes.c_double, ctypes.c_double, ctypes.c_double, ctypes.c_int32,
    ]
    lib.sb_body_get_telemetry.argtypes = [ctypes.c_void_p, ctypes.c_int32, ctypes.POINTER(TelemetryC)]
    lib.sb_world_step.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    lib.sb_body_node_count.argtypes = [ctypes.c_void_p, ctypes.c_int32]
    lib.sb_body_node_count.restype = ctypes.c_uint32
    lib.sb_body_triangle_count.argtypes = [ctypes.c_void_p, ctypes.c_int32]
    lib.sb_body_triangle_count.restype = ctypes.c_uint32
    lib.sb_body_get_positions_f32.argtypes = [ctypes.c_void_p, ctypes.c_int32, ctypes.POINTER(ctypes.c_float)]
    lib.sb_body_get_triangles_state.argtypes = [
        ctypes.c_void_p, ctypes.c_int32, ctypes.POINTER(ctypes.c_uint32), ctypes.POINTER(ctypes.c_uint8)
    ]

    w = lib.sb_world_create(1.0 / 2000.0)
    lib.sb_world_add_ground_plane(w, 1.0)
    car = lib.sb_world_spawn_drivable_car(w, 0.0, 0.01, 0.0)
    assert car == 0

    lib.sb_body_set_controls(w, car, 1.0, 0.0, 0.0, 0.0, -99)
    lib.sb_world_step(w, 2000)  # 1.0 s at 2000 Hz

    tel = TelemetryC()
    lib.sb_body_get_telemetry(w, car, ctypes.byref(tel))
    n_nodes = lib.sb_body_node_count(w, car)
    n_tris = lib.sb_body_triangle_count(w, car)
    pos = (ctypes.c_float * (n_nodes * 3))()
    lib.sb_body_get_positions_f32(w, car, pos)
    tris = (ctypes.c_uint32 * (n_tris * 3))()
    tri_broken = (ctypes.c_uint8 * n_tris)()
    lib.sb_body_get_triangles_state(w, car, tris, tri_broken)

    lib.sb_world_destroy(w)
    print(f"C ABI OK: nodes={n_nodes}, tris={n_tris}, speed={tel.speed_kmh:.1f} km/h, rpm={tel.engine_rpm:.0f}, gear={tel.gear}")
    assert n_tris > 100, f"expected surface ColTris on car, got {n_tris}"
    assert tel.speed_kmh > 10.0, f"expected car to accelerate, got {tel.speed_kmh} km/h"
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
