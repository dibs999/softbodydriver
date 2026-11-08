# SoftBodyDriver

Soft-Body-Fahrzeugphysik nach dem Node-Beam-Prinzip (inspiriert von *Rigs of Rods* und *BeamNG.drive*): Fahrzeuge sind keine starren Körper, sondern Gitter aus Massepunkten (**Nodes**) und Feder-Dämpfern (**Beams**), die mit **2000 Hz** berechnet werden, sich plastisch verbeulen und samt Bruchgruppen (`breakGroup`) abreißen können.

## Projektstruktur

| Pfad | Inhalt |
|---|---|
| `core/` | **`sbcore`** – engine-unabhängige C++20-Physikbibliothek (Nodes, Beams, Plastizität, Bruch, Welt-Kollision, `.sbeam.json`-Loader, Replay-Recorder). |
| `core/tests/` | Unit-Tests (doctest): freier Fall, Feder-Schwingung, Dämpfung, Plastizität, Bruchgruppen, Reibung, Determinismus, Crash-Zonen. |
| `apps/sbsim/` | Kommandozeilen-Simulator zum Ausführen, Benchmarken und Aufzeichnen von Szenen. |
| `tools/make_viewer.py` | Packt aufgezeichnete Simulationen in einen interaktiven 3D-Replay-Viewer (`.html`, läuft direkt im Browser). |
| `content/vehicles/` | Beispiel-Objekte im `.sbeam.json`-Format (`test_box.sbeam.json`, `test_car.sbeam.json`). |
| `docs/SBEAM_FORMAT.md` | Beschreibung des `.sbeam.json`-Dateiformats. |
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

# Einen 50-km/h-Wand-Crash simulieren und als 3D-Replay speichern:
./build/apps/sbsim/sbsim --scene wall_crash --record crash.json
python3 tools/make_viewer.py -o crash.html crash.json
# Dann crash.html einfach im Browser öffnen!

# Eigene .sbeam.json-Datei laden und aus 3 m Höhe fallen lassen:
./build/apps/sbsim/sbsim --file content/vehicles/test_box.sbeam.json --drop 3
```

## Roadmap

- [x] **Phase 0 & 1:** C++20-Physik-Kern (2000 Hz), Beam-Typen (`normal`, `support`, `anisotropic`, `hydro`), plastische Verformung + Bruchgruppen, Ebenen- & Box-Kollision mit Reibung, `.sbeam.json`-Format, 4 Demo-Szenen, 3D-Replay-Viewer, Windows/macOS/Linux-CI.
- [ ] **Phase 2:** Räder (Pressure Wheels), Lenkung, Motor/Getriebe/Differential, Godot-4-Anbindung (`GDExtension`) – erstes live steuerbares Auto.
- [ ] **Phase 3:** Kollisions-Dreiecke (`coltris`), Auto-gegen-Auto-Crash, Terrain-Heightfield.
- [ ] **Phase 4:** Flexbodies (sichtbares 3D-Blech verformt sich mit den Nodes), Sound, Partikel.
- [ ] **Phase 5:** Komplette Fahrzeuge, Maps, Menüs, fertige Downloads für Windows und Mac.
