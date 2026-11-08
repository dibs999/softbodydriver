# SoftBodyDriver

Soft-Body-Fahrzeugsimulation als **native Desktop-App für Windows, macOS und Linux**. Autos sind keine starren Körper, sondern Strukturen aus Massepunkten (**Nodes**) und Feder-Dämpfern (**Beams**). Berechnet wird mit **2000 Hz** in C++. Karosserie, Fahrwerk, Reifen, Motor und Kühler bestehen aus dieser Struktur, verformen sich bleibend und können brechen. Der Schaden wirkt sich auf die Technik aus: Ein eingedrückter Kühler verliert Kühlmittel, der Motor überhitzt und frisst sich fest.

## Architektur

```
┌────────────────────────────── game/ (Godot 4.5, GDScript) ─────────────────────────────┐
│  Hauptmenü · Karten · Kameras · HUD · Sound · KI-Verkehr · Eingabe (Tastatur/Gamepad)   │
└───────────────▲─────────────────────────────────────────────────────────┬──────────────┘
                │ Telemetrie, verformte Meshes                             │ Steuerung
┌───────────────┴──────────── gdextension/ (C++, GDExtension) ────────────▼──────────────┐
│  SBWorld: Physik-Thread (2000 Hz, Echtzeit-Takt)  ·  SBVehicle: Flexbody-Skinning,      │
│  Räder, Node-Beam-Röntgenansicht, Steuerung → Physik, Telemetrie → Spiel                 │
└───────────────▲────────────────────────────────────────────────────────────────────────┘
┌───────────────┴──────────── core/ (sbcore, C++20, engine-unabhängig) ──────────────────┐
│  Nodes/Beams (normal, support, anisotropic, hydro, shock), Torsionsstäbe, Plastizität,  │
│  Bruch, Pressure Wheels, Antriebsstrang, Traktionskontrolle/ABS, Kollisionen, Terrain,  │
│  Fahrzeug-Generator (*.car.json → Struktur + Render-Mesh), CarSystems (Kühlung, Öl,     │
│  Motorschaden, Kraftstoff, Bremstemperatur, Schadenszonen)                               │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

**Warum nicht mehr im Browser?** Die Physik läuft jetzt nativ in C++ auf einem eigenen Thread statt in JavaScript. Dadurch reicht die Leistung für detailliertere Autos und mehrere Fahrzeuge gleichzeitig: 3 Autos brauchen etwa 15 % eines CPU-Kerns. Godot übernimmt Rendering, Eingabe, Audio und den Export als `.exe` (Windows) und `.app` (macOS, Universal).

## Fahrzeuge

Jedes Auto ist eine Datendatei in `game/cars/*.car.json` mit realen Werten:

- Abmessungen und Karosserieform: Länge, Breite, Höhe, Radstand, Überhänge, Spurweiten, Haubenlänge, Neigung von Front- und Heckscheibe, Dachlänge
- Masse und Gewichtsverteilung
- Fahrwerk: Radrate, Druck- und Zugstufe, Stabilisator, Federwege
- Reifen
- Motor: Drehmomentkurve, Getriebe, Achsübersetzung, Antriebsart
- Kühler, Tank

Aus einer Datei erzeugt der Generator:

- **Karosserie-Struktur** mit Knautschzonen vorne und hinten und steifer Fahrgastzelle
- **Doppelquerlenker-Fahrwerk** an allen vier Rädern mit steifem Radträger, Schraubenfeder, Stoßdämpfer (getrennte Druck- und Zugstufe), Anschlagpuffer, Fangband, Spurstange (vorne gelenkt) und Stabilisator als Torsionsstab
- **Motorblock** (8 schwere Nodes) auf brechbaren Motorlagern, **Kühler** hinter der Stoßstange, **Ölwanne** unter dem Motor, **Tank** unter der Rückbank, **Kardanwelle** (bei Heck- und Allradantrieb)
- **Pressure-Wheels**: Reifen aus Nodes mit Innendruck, die platzen können
- **Render-Mesh**: Lack, Glas, Scheinwerfer, Rückleuchten, Grill, Spiegel, Türfugen und -griffe, Innenraum mit Sitzen, Armaturenbrett und Lenkrad. Dazu sichtbare Querlenker, Schraubenfedern, Dämpfer, Bremssättel, Motor und Wellen. Das Mesh ist an die Nodes gebunden (Flexbody), deshalb erscheint jede Delle der Physik auch am sichtbaren Auto.

| Datei | Fahrzeug | Antrieb | Leistung | Masse |
|---|---|---|---|---|
| `kestrel_hatch` | Kompakt-Fließheck (C-Segment) | FWD | 1,5 l Turbo, 110 kW | 1290 kg |
| `aurora_sedan` | Mittelklasse-Limousine | RWD | 2,0 l Turbo, 190 kW | 1590 kg |
| `vortex_gt` | V8-Sportcoupé | RWD, Sperre | 5,0 l V8, 335 kW | 1720 kg |
| `basalt_suv` | Mittelgroßer SUV | AWD | 3,5 l V6, 220 kW | 2050 kg |

Marken und Modelle sind frei erfunden, Maße und Fahrleistungen entsprechen echten Autos der jeweiligen Klasse. Neue Autos legst du an, indem du eine `.car.json` kopierst und anpasst. Das Spiel findet sie automatisch. Das Format ist in [docs/CAR_FORMAT.md](docs/CAR_FORMAT.md) beschrieben.

### Schadensmodell (aus der Physik abgeleitet, nicht geskriptet)

| Bauteil | Ursache | Folge |
|---|---|---|
| Kühler | Verformung oder Bruch der Kühler-Beams | Kühlmittelleck → weniger Kühlleistung → Überhitzung → Leistungsverlust → Zylinderkopfdichtung → Motor fest |
| Ölwanne | Aufsetzen, Bordstein | Ölverlust → kein Öldruck → Lagerverschleiß → Motor fest |
| Motorblock | Verformung bei schwerem Frontcrash | Leistungsverlust und mehr Reibung, bei Totalschaden fest |
| Motorlager / Kardanwelle | Bruch | Kraftfluss unterbrochen |
| Tank | Beschädigung | Kraftstoffleck |
| Bremsen | Scheibentemperatur | Fading ab ca. 450 °C |
| Reifen | Bruch von Reifen-Beams | Platten |
| Fahrwerk | Verformung von Lenkern und Radträger | Schiefe Räder, Spur und Sturz verstellt |

Weitere Systeme: Thermostat, elektrischer Lüfter, Fahrtwind am Kühler, Öltemperatur, Kraftstoffverbrauch nach spezifischem Verbrauch (BSFC), Abwürgen, Anlasser, Traktionskontrolle mit Motor- und Bremseingriff, ABS.

## Spielen

### Fertige Builds

Die CI erzeugt bei jedem Push ins Repository ladbare Builds als Artefakte:

- `SoftBodyDriver-windows-x64`
- `SoftBodyDriver-macos-universal` (Apple Silicon und Intel)
- `SoftBodyDriver-linux-x64`

Der macOS-Build ist nicht signiert. Öffne ihn beim ersten Start per Rechtsklick → *Öffnen*.

### Aus dem Quellcode (Windows / macOS / Linux)

Du brauchst CMake ≥ 3.20, einen C++20-Compiler (MSVC 2022, Xcode/Clang oder GCC), Python 3 (für den godot-cpp-Generator) und [Godot 4.5](https://godotengine.org/download).

```bash
# 1. GDExtension bauen (lädt godot-cpp automatisch); landet in game/bin/
cmake -S . -B build-gd -DCMAKE_BUILD_TYPE=Release -DSB_BUILD_GDEXTENSION=ON -DSB_BUILD_TESTS=OFF -DSB_BUILD_APPS=OFF
cmake --build build-gd --config Release --parallel

# 2. Spiel starten (oder game/project.godot im Godot-Editor öffnen und F5 drücken)
godot --path game
```

Für exportierte Release-Builds zusätzlich `-DGODOTCPP_TARGET=template_release` bauen und dann im Editor *Projekt → Exportieren* wählen. Die Presets für Windows, macOS und Linux liegen bereits in `game/export_presets.cfg`.

### Steuerung

| Taste | Funktion |
|---|---|
| `W` / `S` | Gas / Bremse (im Stand halten = Rückwärtsgang) |
| `A` / `D` | Lenken |
| `Leertaste` | Handbremse |
| `Q` / `E`, `M` | Gang runter / hoch, Automatik oder Manuell (`Shift` = Kupplung) |
| `I` | Motor starten / abstellen |
| `T` / `Z` | Traktionskontrolle / ABS ein/aus |
| `C`, `V` | Kamera wechseln (Verfolger, Orbit, Cockpit, Motorhaube, Streckenrand), Rückblick |
| Rechte Maustaste, Mausrad | Umsehen, Zoom |
| `R` / `Rücktaste` | Zurücksetzen / an Ort und Stelle reparieren |
| `B` | Node-Beam-Röntgenansicht (verformte Beams gelb bis rot) |
| `J`, `P` | Zeitlupe (×0,5 / ×0,25 / ×0,1), Physik pausieren |
| `Tab` | Fahrzeug wechseln |
| `F6` | Hindernis-Auto vor dir abstellen |
| `F1`, `Esc` | Hilfe, Pausenmenü |
| Gamepad | RT/LT Gas/Bremse, linker Stick lenken, A Handbremse, LB/RB schalten, Y Kamera, B Reset |

### Karten

- **Testgelände**: Asphaltfläche mit Oval (KI-Verkehr), Sprungrampen, Bodenwellen, Schlaglochpiste, Leitplanken, Crash-Wand, Mast für Seitenaufprall, Slalom und Hügel
- **Hügelland**: prozedurales Terrain mit kurviger Landstraße über Kuppen und durch Senken, dazu Wald

## Entwicklung

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
ctest --test-dir build --output-on-failure                       # Unit-Tests (Physik, Fahrwerk, Kühlung, Crash, ...)
./build/apps/sbsim/cartest game/cars/aurora_sedan.car.json       # Prüfstand: Einfedern, 0-100, Bremsen, Kurve, Crash + Kühlsystem
./build/apps/sbsim/sbsim --list                                  # klassische Physik-Testszenen + Replay-Viewer (tools/make_viewer.py)
godot --headless --path game -s res://tests/smoke_test.gd        # GDExtension-Smoke-Test
```

Beispielausgabe des Prüfstands:

```
== Aurora 330t Sedan (aurora_sedan)
   nodes 367, beams 1887, coltris 332, torsionbars 2, mass 1590 kg (+tyres), stability 0.87
   settle: floor 0.157 m (design 0.195, delta -0.038), 24.1x real time
   accel: 0-100 km/h 7.2 s
   brake: 100 -> 0 km/h: 35.9 m
   corner: steer +0.35 @ 49 km/h -> yaw 26 deg/s, lateral 0.63 g
   crash (50 km/h): front 33%, radiator 43%
     +10s coolant 94 C, level 73%   ...   +60s coolant 145 C, level 0%, 'ENGINE SEIZED'
```

| Pfad | Inhalt |
|---|---|
| `core/` | Physik-Kern `sbcore` mit Fahrzeug-Generator und CarSystems |
| `core/tests/` | doctest-Unit-Tests |
| `gdextension/` | Godot-Anbindung (`SBWorld`, `SBVehicle`) |
| `game/` | Godot-Projekt: Szenen, Skripte, Autos (`cars/`), Export-Presets, Headless-Tests (`tests/`) |
| `apps/sbsim/` | `sbsim` (Szenen, Benchmarks, Replays) und `cartest` (Fahrzeug-Prüfstand) |
| `content/vehicles/` | Beispiel-Strukturen im Low-Level-Format `.sbeam.json` |
| `docs/` | [CAR_FORMAT.md](docs/CAR_FORMAT.md), [SBEAM_FORMAT.md](docs/SBEAM_FORMAT.md), [GODOT_INTEGRATION.md](docs/GODOT_INTEGRATION.md) |

## Roadmap

- [x] C++20-Physik-Kern mit 2000 Hz, Plastizität, Bruch, Pressure-Wheels, Antriebsstrang, Kollisionen, Terrain
- [x] Datengetriebener Generator für realistische Autos mit Doppelquerlenker-Fahrwerk, Stabilisatoren und Stoßdämpfern mit Zug- und Druckstufe
- [x] Fahrzeugsysteme: Kühlung, Öl, Motorschaden, Kraftstoff, Bremsen, Traktionskontrolle und ABS
- [x] Native Desktop-App (Godot 4.5 + GDExtension) für Windows, macOS und Linux, inklusive CI-Export
- [ ] Abnehmbare Teile (Türen, Motorhaube, Stoßstangen als eigene Bruchgruppen) und splitterndes Glas
- [ ] Kollision mit Bäumen und Requisiten (Broadphase für viele statische Objekte), bewegliche Requisiten (Pylonen, Fässer)
- [ ] Reifenmodell mit Lastabhängigkeit und Schräglaufkurve, Oberflächen (Schotter, Gras, Nässe)
- [ ] Detailliertere Karosserie-Meshes (optional aus Blender) über dasselbe Flexbody-Skinning
- [ ] Multithreading über mehrere Fahrzeuge
