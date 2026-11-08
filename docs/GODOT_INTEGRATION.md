# Godot 4 & C-ABI-Anbindung

Der Physik-Kern (`sbcore`) wird beim CMake-Build gleichzeitig als:

1. **statische C++20-Bibliothek** (`libsbcore.a` / `sbcore.lib`) und
2. **dynamische Bibliothek** (`libsbcore.so` auf Linux, `sbcore.dll` auf Windows, `libsbcore.dylib` auf macOS Universal)

gebaut und exportiert eine stabile C-Schnittstelle in [`core/include/sbcore/c_api.h`](../core/include/sbcore/c_api.h).

## Wichtigste Funktionen der C-ABI

| Funktion | Beschreibung |
|---|---|
| `sb_world_create(dt)` | Erstellt eine 2000-Hz-Welt (`dt = 1.0 / 2000.0`). |
| `sb_world_add_ground_plane(w, friction)` | Fügt eine Bodenebene ($y = 0$) hinzu. |
| `sb_world_spawn_drivable_car(w, x, y, z)` | Spawnt das fahrbare Auto (Chassis + 4 Pressure-Wheels + Federung + Hydro-Lenkung + 5-Gang-Antrieb). |
| `sb_world_load_sbeam(w, path, x, y, z)` | Lädt ein beliebiges `.sbeam.json`-Fahrzeug. |
| `sb_body_set_controls(w, idx, thr, brk, steer, hb, gear)` | Übergibt Gas, Bremse, Lenkung (`[-1, 1]`), Handbremse und Gang (`-99` = Automatik). |
| `sb_world_step(w, steps)` | Berechnet `steps` Physik-Schritte (z. B. `33` Schritte pro 60-FPS-Grafikframe). |
| `sb_body_get_telemetry(w, idx, &tel)` | Liest Geschwindigkeit (`km/h`), Drehzahl (`RPM`), Gang, Kupplung und verbeulte/gebrochene Beams aus. |
| `sb_body_get_positions_f32(w, idx, buf)` | Schreibt alle Node-Positionen als `float[3 * N]` direkt für ein `ImmediateMesh` / `ArrayMesh`. |
| `sb_body_get_beams_state(w, idx, pairs, strain)` | Schreibt alle Beam-Indexpaare und deren relative Dehnung (`< 0` = gerissen) für die Debug-/Flexbody-Darstellung. |

## Schnelltest über Python (`ctypes`)

```bash
python3 tools/test_c_api.py build
```
