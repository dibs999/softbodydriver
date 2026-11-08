# SoftBodyDriver

Soft-Body-Fahrzeugphysik nach dem Node-Beam-Prinzip (inspiriert von *Rigs of Rods* und *BeamNG.drive*): Fahrzeuge sind keine starren Körper, sondern Gitter aus Massepunkten (**Nodes**) und Feder-Dämpfern (**Beams**), die mit **2000 Hz** berechnet werden, sich plastisch verbeulen und samt Bruchgruppen (`breakGroup`) abreißen können. Auch die Räder (**Pressure Wheels**), die Radaufhängung und die Lenkung (`hydro`-Spurstangen) bestehen vollständig aus Nodes und Beams.

## Projektstruktur

| Pfad | Inhalt |
|---|---|
| `core/` | **`sbcore`** – engine-unabhängige C++20-Physikbibliothek (Nodes, Beams, Plastizität, Bruch, Pressure-Wheels, 5-Gang-Antriebsstrang, `.sbeam.json`-Loader, C-ABI, Replay-Recorder). |
| `core/tests/` | Unit-Tests (doctest): freier Fall, Feder-Schwingung, Plastizität, Bruchgruppen, Pressure-Wheels, Getriebe/Schaltung, Hydro-Lenkung, C-ABI, Crash-Zonen. |
| `apps/sbsim/` | Kommandozeilen-Simulator zum Ausführen, Benchmarken und Aufzeichnen von Szenen. |
| `tools/make_viewer.py` | Packt aufgezeichnete Simulationen in einen interaktiven 3D-Replay-Viewer (`.html` mit Drehzahlmesser, Gang- und Pedalanzeige). |
| `tools/test_c_api.py` | Testet die dynamische Bibliothek (`libsbcore.so` / `sbcore.dll` / `libsbcore.dylib`) über die C-ABI. |
| `game/` | Godot-4-Projektgerüst mit vorkonfigurierten Eingaben (WASD / Pfeiltasten, Leertaste, R). |
| `content/vehicles/` | Beispiel-Objekte & Fahrzeuge im `.sbeam.json`-Format (`drivable_car.sbeam.json`, `test_car.sbeam.json`, `test_box.sbeam.json`). |
| `docs/` | [SBEAM_FORMAT.md](docs/SBEAM_FORMAT.md) und [GODOT_INTEGRATION.md](docs/GODOT_INTEGRATION.md). |
| `.github/workflows/ci.yml` | Baut und testet automatisch für **Windows (x64)**, **macOS (Universal: Apple Silicon + Intel)** und **Linux**. |

## Selbst bauen (Windows, macOS, Linux)

Voraussetzungen: CMake ≥ 3.20, C++20-Compiler (MSVC, Clang oder GCC), optional Python 3 für den HTML-Viewer.

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release --parallel
ctest --test-dir build -C Release --output-on-failure
```

## Szenen ausführen & im 3D-Viewer ansehen

```bash
# Alle eingebauten Szenen auflisten / benchmarken:
./build/apps/sbsim/sbsim --list
./build/apps/sbsim/sbsim --bench

# Vollgas-Sprint + Vollbremsung simulieren und als 3D-Replay speichern:
./build/apps/sbsim/sbsim --scene accel_brake --record sprint.json
python3 tools/make_viewer.py -o sprint.html sprint.json
# Dann sprint.html einfach im Browser öffnen!
```

## Roadmap

- [x] **Phase 0 & 1:** C++20-Physik-Kern (2000 Hz), Beam-Typen (`normal`, `support`, `anisotropic`, `hydro`), plastische Verformung + Bruchgruppen, Ebenen- & Box-Kollision mit Reibung, `.sbeam.json`-Format, 3D-Replay-Viewer, Windows/macOS/Linux-CI.
- [x] **Phase 2:** **Pressure Wheels** (Node-Beam-Reifen mit Innendruck & Reifenplatzer), Einzelradaufhängung (Querlenker + Federbeine + Bump-Stops), **Hydro-Spurstangen-Lenkung**, **Antriebsstrang** (Motorkennlinie, Leerlaufregler, Drehzahlbegrenzer, Kupplung, 5-Gang-Automatik/Manuell, Sperrdifferential, Bremskraftverteilung), C-ABI (`sbcore.dll` / `.dylib` / `.so`) & Godot-4-Projektgerüst.
- [ ] **Phase 3:** Kollisions-Dreiecke (`coltris`), Auto-gegen-Auto-Crash, Eigenkollision, Terrain-Heightfield.
- [ ] **Phase 4:** Flexbodies (sichtbares 3D-Blech verformt sich mit den Nodes), Sound, Partikel.
- [ ] **Phase 5:** Komplette Fahrzeuge, Maps, Menüs, fertige Downloads für Windows und Mac.
