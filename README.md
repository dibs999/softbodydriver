# SoftBodyDriver

Soft-Body-Fahrzeugphysik nach dem Node-Beam-Prinzip (inspiriert von *Rigs of Rods* und *BeamNG.drive*): Fahrzeuge sind keine starren Körper, sondern Gitter aus Massepunkten (**Nodes**) und Feder-Dämpfern (**Beams**), die mit **2000 Hz** berechnet werden, sich plastisch verbeulen und samt Bruchgruppen (`breakGroup`) abreißen können. Auch die Räder (**Pressure Wheels**), die Radaufhängung und die Lenkung (`hydro`-Spurstangen) bestehen vollständig aus Nodes und Beams.

## Projektstruktur

| Pfad | Inhalt |
|---|---|
| `core/` | **`sbcore`** – engine-unabhängige C++20-Physikbibliothek (Nodes, Beams, Plastizität, Bruch, Pressure-Wheels, 5-Gang-Antriebsstrang, ColTri-Kollisionsdreiecke, Heightfield-Terrain, `.sbeam.json`-Loader, C-ABI, Replay-Recorder). |
| `core/tests/` | Unit-Tests (doctest): 27 Test-Suites (freier Fall, Feder-Schwingung, Plastizität, Bruchgruppen, Pressure-Wheels, Getriebe/Schaltung, Hydro-Lenkung, Auto-gegen-Auto ColTri-Crash, Aerodynamik, Heightfield, C-ABI). |
| `web/index.html` | **Live spielbares 3D-Spiel im Browser (2000 Hz Echtzeit)** – Flexbody-Karosserie + Röntgen-Node-Beam-Ansicht (`B`), Live-Steuerung (`WASD`/Pfeiltasten, `Space`, `R`, `C`, `Tab`), 5 Szenarien, 3 Fahrzeug-Presets, KI-Gegner, Tuning-Menü, Schadens-Silhouette-HUD & WebAudio-Motorsound. |
| `apps/sbsim/` | Kommandozeilen-Simulator zum Ausführen, Benchmarken und Aufzeichnen von Szenen. |
| `tools/make_viewer.py` | Packt aufgezeichnete C++-Simulationen in einen interaktiven 3D-Replay-Viewer (`.html`). |
| `tools/test_c_api.py` | Testet die dynamische Bibliothek (`libsbcore.so` / `sbcore.dll` / `libsbcore.dylib`) über die C-ABI. |
| `game/` | Godot-4-Projektgerüst mit vorkonfigurierten Eingaben (WASD / Pfeiltasten, Leertaste, R). |
| `content/vehicles/` | Beispiel-Objekte & Fahrzeuge im `.sbeam.json`-Format (`drivable_car.sbeam.json`, `test_car.sbeam.json`, `test_box.sbeam.json`). |
| `docs/` | [SBEAM_FORMAT.md](docs/SBEAM_FORMAT.md) und [GODOT_INTEGRATION.md](docs/GODOT_INTEGRATION.md). |
| `.github/workflows/ci.yml` | Baut und testet automatisch für **Windows (x64)**, **macOS (Universal: Apple Silicon + Intel)** und **Linux**. |

## Sofort live spielen (Windows, macOS, Linux)

Öffne einfach `web/index.html` direkt in einem modernen Browser (Chrome, Edge, Safari, Firefox) – ohne Installation:
- **`WASD` / Pfeiltasten:** Gas, Bremse/Rückwärts, Lenken
- **`Leertaste`:** Handbremse (Drift)
- **`R` / `Shift+R`:** Szene zurücksetzen / Fahrzeug vor Ort reparieren
- **`B`:** Röntgen-Modus (Node-Beam-Skelett live unter der 3D-Karosserie einblenden)
- **`C`:** Kamera wechseln (Verfolger, Cockpit, Freier Orbit, Action-Seite)
- **`Tab`:** Zwischen Spieler-Fahrzeug und KI-Fahrzeug umschalten

## C++20-Kern selbst bauen (Windows, macOS, Linux)

Voraussetzungen: CMake ≥ 3.20, C++20-Compiler (MSVC, Clang oder GCC), optional Python 3 für den HTML-Viewer.

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release --parallel
ctest --test-dir build -C Release --output-on-failure
```

## C++-Szenen ausführen & im 3D-Replay-Viewer ansehen

```bash
# Alle eingebauten Szenen auflisten / benchmarken:
./build/apps/sbsim/sbsim --list
./build/apps/sbsim/sbsim --bench

# Mehrere Crash- & Fahrszenen simulieren und als 3D-Replay speichern:
./build/apps/sbsim/sbsim --scene head_on_crash --record head_on.json
./build/apps/sbsim/sbsim --scene t_bone_crash  --record t_bone.json
./build/apps/sbsim/sbsim --scene hill_climb    --record hill_climb.json
python3 tools/make_viewer.py -o softbody_replay.html head_on.json t_bone.json hill_climb.json
```

## Roadmap

- [x] **Phase 0 & 1:** C++20-Physik-Kern (2000 Hz), Beam-Typen (`normal`, `support`, `anisotropic`, `hydro`), plastische Verformung + Bruchgruppen, Ebenen- & Box-Kollision mit Reibung, `.sbeam.json`-Format, 3D-Replay-Viewer, Windows/macOS/Linux-CI.
- [x] **Phase 2:** **Pressure Wheels** (Node-Beam-Reifen mit Innendruck & Reifenplatzer), Einzelradaufhängung (Querlenker + Federbeine + Bump-Stops), **Hydro-Spurstangen-Lenkung**, **Antriebsstrang** (Motorkennlinie, Leerlaufregler, Drehzahlbegrenzer, Kupplung, 5-Gang-Automatik/Manuell, Sperrdifferential, Bremskraftverteilung), C-ABI (`sbcore.dll` / `.dylib` / `.so`) & Godot-4-Projektgerüst.
- [x] **Phase 3:** Kollisions-Dreiecke (`ColTri`), Auto-gegen-Auto-Crash (`head_on_crash`, `t_bone_crash`), Aerodynamik (Luftwiderstand & Abtrieb pro Dreieck), Terrain-Heightfield (`hill_climb`).
- [x] **Phase 4 & 5:** Live spielbares 3D-Spiel (`web/index.html`) mit **3D-Flexbody-Karosserie** + umschaltbarem **Node-Beam-Röntgenblick (`B`)**, **Echtzeit-Steuerung (`WASD`, Handbremse, Zeitlupe, Reset `R`, 4 Kameras `C`)**, **3 Fahrzeug-Presets + Live-Tuning-Menü**, **KI-Gegnern**, **BeamNG-Schadens-Silhouette-App**, **G-Kräfte-Sensor** und **WebAudio-Synthesizer**.
