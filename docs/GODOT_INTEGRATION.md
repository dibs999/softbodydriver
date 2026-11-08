# Godot-4.5-Anbindung (GDExtension)

`gdextension/` bindet den Physik-Kern als native Bibliothek in Godot ein:

- `libsoftbodydriver.windows.*.dll`
- `libsoftbodydriver.macos.*.universal.dylib`
- `libsoftbodydriver.linux.*.so`

`game/softbodydriver.gdextension` lädt sie automatisch.

## Threading

- `SBWorld` startet in `_ready()` einen **Physik-Thread**. Er hält die Simulationszeit synchron zur Wanduhr, multipliziert mit `time_scale`, und rechnet in Blöcken von 16 Schritten zu je 0,5 ms. Fällt die Simulation zurück, holt sie höchstens 100 ms nach. Danach läuft das Spiel langsamer, statt sich festzufahren.
- Einmal pro Frame (`_process`) übernimmt der Haupt-Thread unter einer kurzen Sperre die Steuerung aller Fahrzeuge und kopiert den Physikzustand: Positionen, Telemetrie, Systeme. Ohne Sperre werden danach die Meshes verformt und hochgeladen (`ArrayMesh.surface_update_vertex_region`).

## `SBWorld` (Node3D)

| Methode / Property | |
|---|---|
| `add_ground_plane(friction)` | Bodenebene y = 0 |
| `add_box(center, half_extents, euler_xyz, friction)` | Gedrehter Quader (Rampe, Wand, Leitplanke). Euler-Reihenfolge wie `Basis.from_euler(e, EULER_ORDER_XYZ)` |
| `add_heightfield(origin_x, origin_z, cell, nx, nz, heights, friction)` | Terrain, `heights[ix * nz + iz]` |
| `spawn_car(path, xform) -> SBVehicle` | Lädt `res://cars/*.car.json`. Ursprung ist der Bodenpunkt zwischen den Achsen, die lokale +X-Achse zeigt nach vorne |
| `remove_vehicle(v)`, `get_vehicles()` | |
| `time_scale`, `paused`, `air_density`, `material_library` | `material_library`: Name → Material (`paint`, `glass`, `chrome`, `trim`, `tire`, `rim`, `headlight`, `taillight`, …). Fehlt ein Eintrag, wird ein Standardmaterial verwendet |
| `get_stats()` | Simulationszeit, Echtzeitfaktor, Schritte/s, Anzahl Nodes und Beams |
| `step_blocking(s)`, `sync_visuals()` | Für Headless-Tests |

## `SBVehicle` (Node3D, wird von `spawn_car` erzeugt)

| Methode | |
|---|---|
| `set_input(throttle, brake, steer, handbrake)` | `steer` +1 = links |
| `set_gear(g)`, `shift_up()`, `shift_down()`, `set_automatic(b)`, `set_clutch(c)` | `g`: -1 R, 0 N, 1..n. Kupplung `< 0` = automatisch |
| `start_engine()`, `set_ignition(b)`, `set_tcs(b)`, `set_abs(b)` | |
| `reset_to(xform)`, `repair_in_place()` | Repariert Struktur und Systeme |
| `set_debug_view(b)`, `set_body_visible(b)` | Node-Beam-Röntgenansicht |
| `get_telemetry() -> Dictionary` | `speed_kmh`, `rpm`, `gear`, `coolant_temp`, `coolant_level`, `oil_temp`, `oil_pressure`, `fuel_l`, `running`, `seized`, `status`, `radiator_damage`, `engine_damage`, `zones[6]`, `wheel_burst[4]`, `brake_temps[4]`, `suspension_damage[4]`, `tcs_active`, `abs_active`, … |
| `get_info() -> Dictionary` | Name, Motor, Leistung, Drehzahlbereich, Masse, … |
| `get_position_ws()`, `get_forward()`, `get_right()`, `get_up()`, `get_velocity()`, `get_chase_target()`, `get_driver_eye()` | Für Kameras und KI |
| `get_wheel_slip()`, `get_wheel_load()`, `take_impact()` | Für Audio (Reifenquietschen, Crash) und Kamerawackeln |

## Bauen

```bash
cmake -S . -B build-gd -DCMAKE_BUILD_TYPE=Release -DSB_BUILD_GDEXTENSION=ON -DSB_BUILD_TESTS=OFF -DSB_BUILD_APPS=OFF \
      [-DGODOTCPP_TARGET=template_release] [-DSB_GODOTCPP_DIR=/pfad/zu/godot-cpp]
cmake --build build-gd --config Release --parallel
```

Unter macOS entsteht automatisch eine Universal-Bibliothek (arm64 + x86_64).

Die C-ABI (`core/include/sbcore/c_api.h`, `tools/test_c_api.py`) bleibt für andere Engines und Tools erhalten.
