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
| `get_effect_anchors()` | `wheels`, `radius`, `engine`, `exhaust`, dazu `contacts` und `normals` aus den tatsächlichen Reifenkontakten. Kontaktpunkte nur bei positiver Radlast verwenden |
| `set_surface_grip(PackedFloat32Array)` | Vier Untergrundfaktoren, auf 0,35–1,2 begrenzt; wie Eingaben erst bei `pre_step` auf den Physik-Thread übernommen |
| `puncture_tire(index, leak_psi_per_second)` | Fadenübergreifender einmaliger Druckverlust-Auftrag, Rad 0–3, Rate 0,1–100 PSI/s; keine direkte Änderung am Physik-Thread |

Die Antriebstelemetrie enthält außerdem `clutch_temp` (°C), `clutch_wear` und
`gearbox_damage` (0–1), `clutch_slip_rpm`, `shift_remaining` (s) und `gear_grind` (0–1).
Schaltbefehle durchlaufen `Powertrain::step`, damit manuelle und automatische
Schaltunterbrechungen in Physik, Diagnose und Audio übereinstimmen. Reparieren
stellt auch Kupplung, Getriebe, Drehzahl und laufende Schalt-Timer zurück.

`get_wheel_load()` ist ein geglätteter, auf 0–1 normierter Kontaktwert; die interne
`PressureWheel::load` wird aus normalen Kontaktimpulsen in Newton berechnet.
`get_wheel_slip()` misst die tangentiale Restgeschwindigkeit des belasteten Gummis
nach dem Kontaktlöser. Das vermeidet den falschen Schlupf einer verformbaren Karkasse,
der aus `Radwinkelgeschwindigkeit × Nennradius` entstehen würde.

`road_surface.gd` teilt Grip, Audio und Partikeln dieselbe räumliche Klassifikation
zu. Die Erkennung läuft auch für Fahrzeuge außerhalb der Partikel-Sichtweite.
`road_marks.gd` verwendet einen Ringpuffer mit 1024 Instanzen und Simulationszeit.
`driving_activity.gd` verwendet ebenfalls `sim_time`; die UI ist keine Rennuhr.

## Bergung und Werkstatt

`SBVehicle.relocate_to(transform) -> bool` versetzt das vorhandene deformierte
Fahrzeug als Ganzes. Ursprung und Achsen entsprechen `reset_to`: der Ursprung
liegt am Boden, die lokale X-Achse zeigt vorwärts. Nur endliche starre
Transformationen ohne Skalierung oder Spiegelung sind erlaubt. Positionen werden
gedreht/verschoben, Geschwindigkeiten und alte Kontakte gelöscht. Verformte und
gebrochene Beams, Reifenzustand, technische Schäden und Kraftstoff bleiben erhalten.
Ein vorher angeforderter Sandbox-Reset wird verworfen, damit er die Bergung nicht
nachträglich in eine kostenlose Reparatur verwandelt.

`SBVehicle.service_repair() -> bool` richtet das Fahrzeug am aktuellen Ort auf und
repariert Struktur, Reifen und technische Systeme. Der tatsächliche Tankinhalt
bleibt erhalten, die Zündung bleibt aus und ausstehende Start-/Reset-Aufträge
werden verworfen. Beide Methoden arbeiten synchron unter dem Welt-Mutex und
aktualisieren danach den Darstellungs-/Telemetrie-Snapshot. Sie verbuchen keine
Kosten; diese Aufgabe hat die Spiel-/Werkstattlogik. `reset_to` bleibt der
vollständige Sandbox-Reset einschließlich Startzustand der Systeme.

`SBVehicle.release_bonnet() -> bool` öffnet am stehenden prozeduralen Fahrzeug die
Haube über brechbare, gedämpfte Hubstützen. Hydro-Kanal 1 fährt über 1,25 Sekunden
aus; Steuerkanal 0 bleibt der Lenkung vorbehalten. Reparatur setzt die Stützen
zurück. Während der Fahrt über 2 km/h, bei bereits gelöstem Verschluss und bei
importierten Modellen ohne passende Haubensegmentierung liefert die Methode
`false`. `get_info().bonnet_supported` kennzeichnet die visuelle Unterstützung.

`SBVehicle.set_door_open(index, open) -> bool` und `toggle_door(index) -> bool`
bedienen die physischen Vordertüren des Kestrel (0 Fahrer, 1 Beifahrer). Sie
arbeiten unter dem Welt-Mutex, erlauben die Bedienung nur bis 2 km/h und lehnen
beschädigte Halter ab. Manuelles Entriegeln deaktiviert Schloss-Beams, ohne sie
zu brechen; Schließen rastet erst bei ausgerichteter, ruhender Tür ein. Reparatur
setzt Türanforderung, Hub und Schlösser zurück. `get_door_states() -> Array`
liefert `index`, `requested_open`, `travel`, `latched`, `attached`, `missing`,
`damaged`, `angle_degrees` und `open`; Fahrzeuge ohne diese Mechanik liefern `[]`.

`get_mirror_surfaces() -> Array` liefert die sichtbaren optischen Flächen als
`mesh`, `side`, `center`, `normal`, `up`, `half_extents`. Position und Ebene werden
aus den tatsächlich verformten Vertices berechnet, nicht aus der Fahrzeug-AABB.
`vehicle_mirrors.gd` verwendet diese Weltkoordinaten für planare Reflexionen im
Cockpit. Die separaten Viewports teilen die Spielwelt; ihre Kameras schließen
Spiegelflächen auf Render-Layer 20 aus, damit keine rekursiven Spiegelbilder
entstehen. Außerhalb des Cockpits werden die ursprünglichen Materialien und
Render-Layer wiederhergestellt.

## Bauen

```bash
cmake -S . -B build-gd -DCMAKE_BUILD_TYPE=Release -DSB_BUILD_GDEXTENSION=ON -DSB_BUILD_TESTS=OFF -DSB_BUILD_APPS=OFF \
      [-DGODOTCPP_TARGET=template_release] [-DSB_GODOTCPP_DIR=/pfad/zu/godot-cpp]
cmake --build build-gd --config Release --parallel
```

Unter macOS entsteht automatisch eine Universal-Bibliothek (arm64 + x86_64).

Die C-ABI (`core/include/sbcore/c_api.h`, `tools/test_c_api.py`) bleibt für andere Engines und Tools erhalten.
