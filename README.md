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

### Fahrgefühl, Aktivitäten und Darstellung

- Reifenlast und Schlupf werden an den tatsächlichen Bodenkontakten gemessen. Ein
  frei drehendes Rad in der Luft erzeugt keinen Reifenrauch. Normales schnelles
  Rollen wird nicht mit einem Burnout verwechselt.
- Asphalt, Pflaster, Schotter, Sand und Gras beeinflussen Grip, Rollgeräusch und
  Partikel gemeinsam. Drifts hinterlassen ausblendende Bremsspuren; Schotter wirft
  kleine Steinchen auf. Rauch und Staub folgen Fahrtwind und einer leichten Brise.
- Der Kestrel dient als Referenzwagen: zweifarbiger Innenraum, Lüftungsdüsen,
  Türdetails und zusätzliches Live-Display für Kühlmittel, Kraftstoff und Verbrauch.
  Die Minikarte rückt im Cockpit nach oben, damit die Instrumente frei bleiben.
- `F3` wählt freie Fahrt, Zeitfahren oder eine 60-Sekunden-Drift-Challenge; in der
  Stadt gibt es zusätzlich Lieferfahrten. `F4` stellt das Auto am Start auf bzw.
  bricht den Lauf ab. Checkpoints und Ziele erscheinen in Welt und Minikarte.
  Bestleistungen werden je Karte, Auto und Modus lokal gespeichert. Zurücksetzen,
  Reparatur und Fahrzeugwechsel beenden einen laufenden Versuch. Pausen stoppen
  die Uhr; Zeitlupe verwendet die tatsächliche Simulationszeit.
- Die Stadt enthält befahrbare Werkstatthöfe, eine Altstadtgasse und eine Hochstraße
  mit Unterführung, zusätzlich zu Parkdeck, Markt und Frachtterminal. Auf dem
  Testgelände gibt es eine markierte 100-m-Bremsbahn und eine milde Bodenwellenreihe.
- `F2` zeigt Fahrzeugzustand, mittlere/P95-Bildzeit, Zeichenaufrufe und Physiktempo.
  Kleine Kartenobjekte werden räumlich gruppiert und in großer Entfernung ausgeblendet;
  ihre Kollisionen bleiben aktiv. Partikel und Bremsspuren haben feste Speicherbudgets.
- Jeder Motorsound verwendet jetzt eine zusammenhängende Fahrzeugaufnahme mit
  getrennten Last-/Ruhebereichen. Der Vierzylinder besitzt echte Ausrollsegmente.
  Die V6-Aufnahme deckt hohe Drehzahlen nicht direkt ab; diese werden transponiert.
  Beim V8 ersetzt ein leiserer Aufnahmeabschnitt eine dedizierte Schubaufnahme.
  Quellen und Lizenzen stehen im Hauptmenü und in [ASSET_CREDITS.md](game/ASSET_CREDITS.md).

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
| `concept_gt` | Concept-GT mit **importiertem Detail-Modell** (glTF, CC-BY 4.0) | RWD | 4,0 l V8 Biturbo, 456 kW | 1580 kg |
| `kestrel_hatch` | Kompakt-Fließheck (C-Segment) | FWD | 1,5 l Turbo, 110 kW | 1290 kg |
| `aurora_sedan` | Mittelklasse-Limousine | RWD | 2,0 l Turbo, 190 kW | 1590 kg |
| `vortex_gt` | V8-Sportcoupé | RWD, Sperre | 5,0 l V8, 335 kW | 1720 kg |
| `basalt_suv` | Mittelgroßer SUV | AWD | 3,5 l V6, 220 kW | 2050 kg |

Marken und Modelle sind frei erfunden, Maße und Fahrleistungen entsprechen echten Autos der jeweiligen Klasse.

### Echte 3D-Automodelle importieren (Flexbody)

Jede Fahrzeugdatei kann über `visualModel` auf ein **glTF/GLB-Modell** verweisen. Das Spiel richtet das Modell automatisch aus (Achsen, Länge, Bodenhöhe) und bindet jeden Vertex an die nächsten Nodes der Physik-Struktur, wie die Flexbodies in BeamNG. Dellen, abgerissene Frontpartien und platte Reifen erscheinen dadurch am Detail-Modell. Die Räder des Modells werden als drehende Räder übernommen, auch wenn sie im Modell eingelenkt gespeichert sind. Beispiel: `game/cars/concept_gt.car.json` mit dem frei lizenzierten Modell [„Car Concept“ (Khronos, CC-BY 4.0)](game/models/carconcept/LICENSE.md).

So kommt ein eigenes Auto ins Spiel:

1. `.glb` nach `game/models/<name>/` legen.
2. Eine vorhandene `.car.json` kopieren und Maße, Radstand, Spur und Reifenradius an das Modell anpassen.
3. `visualModel` eintragen: Pfad, Vorwärts- und Hochachse, Namen der vier Rad-Nodes, auszublendende Teile. Details in [docs/CAR_FORMAT.md](docs/CAR_FORMAT.md).

> **Echte Marken (Mercedes, BMW, …):** Freie Modelle solcher Autos gibt es zum Beispiel auf Sketchfab, meist unter CC-BY oder mit „Editorial Use“. Das Urheberrecht am 3D-Modell ist aber nur ein Teil. Name, Logo und Design gehören den Herstellern, und ein veröffentlichtes Spiel braucht dafür deren Lizenz. Deshalb nutzt auch BeamNG erfundene Marken. Für **private Nutzung** kannst du solche Modelle über den Import-Weg oben einbinden, ins Repository oder in Releases sollten sie nicht. Neue Autos legst du an, indem du eine `.car.json` kopierst und anpasst. Das Spiel findet sie automatisch. Das Format ist in [docs/CAR_FORMAT.md](docs/CAR_FORMAT.md) beschrieben.

### Schadensmodell (aus der Physik abgeleitet, nicht geskriptet)

| Bauteil | Ursache | Folge |
|---|---|---|
| Kühler | Verformung oder Bruch der Kühler-Beams | Kühlmittelleck → weniger Kühlleistung → Überhitzung → Leistungsverlust → Zylinderkopfdichtung → Motor fest |
| Ölwanne | Aufsetzen, Bordstein | Ölverlust → kein Öldruck → Lagerverschleiß → Motor fest |
| Motorblock | Verformung bei schwerem Frontcrash | Leistungsverlust und mehr Reibung, bei Totalschaden fest |
| Motorlager / Kardanwelle | Bruch | Kraftfluss unterbrochen |
| Kupplung | Anhaltender Schlupf erzeugt Reibungswärme | Ab 180 °C sinkt das übertragbare Drehmoment, über 230 °C entsteht dauerhafter Verschleiß; vollständig verschlissen kein Vortrieb |
| Getriebe | Wiederholte Schaltvorgänge unter Last ohne Auskuppeln, extreme Rückschaltungen oder Richtungswechsel | Schleifgeräusch, längere Schaltunterbrechung, Leistungsverlust bis zum Ausfall; Automatik schützt vor destruktiven Gangwechseln |
| Tank | Beschädigung | Kraftstoffleck |
| Bremsen | Scheibentemperatur | Fading ab ca. 450 °C |
| Reifen | Rutschen erzeugt Wärme und Abrieb, Hitze erhöht den Luftdruck. Verbeulte Felge oder Flanke führt zu schleichendem Luftverlust | Weniger Grip bei kalten, überhitzten oder abgefahrenen Reifen. Platzen bei abgefahrener Lauffläche (Verschleiß 100 %) oder über 175 °C. Ein platter Reifen sackt sichtbar zusammen |
| Fahrwerk | Verformung von Lenkern und Radträger | Schiefe Räder, Spur und Sturz verstellt |

Weitere Systeme: Thermostat, elektrischer Lüfter, Fahrtwind am Kühler, Öltemperatur, Kraftstoffverbrauch nach spezifischem Verbrauch (BSFC), Abwürgen, Anlasser, Traktionskontrolle mit Motor- und Bremseingriff, ABS.

Reifenrauch folgt dem tatsächlichen Radschlupf, auf der Wüstenkarte entsteht Staub.
Ein heißer, beschädigter Kühler dampft; Motor- und Kupplungsschäden erzeugen Rauch.
Platte Reifen haben eine verbreiterte, abgeflachte Aufstandsfläche und ein geschwindigkeitsabhängiges Schlaggeräusch.
Die Partikelzahl ist begrenzt und im Grafikprofil „Leistung“ halbiert.
Motorgeräusche verwenden aufbereitete echte Aufnahmen mit laufenden Drehzahlübergängen und der simulierten Schaltunterbrechung.
Die Quellen stehen in [game/ASSET_CREDITS.md](game/ASSET_CREDITS.md).

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
| `F1`, `F2`, `Esc` | Hilfe, Fahrzeugdiagnose, Pausenmenü |
| `F3`, `F4` | Aktivität wählen, am Start aufstellen / Lauf abbrechen |
| `N`, `K` | Minikarte ein/aus, Übersichtskarte |
| Gamepad | RT/LT Gas/Bremse, linker Stick lenken, A Handbremse, LB/RB schalten, Y Kamera, B Reset |

### Karten

- **Wald & Weide · Offroad**: etwa 1,5 × 1,5 km Gelände ohne Asphalt. 3,2-km-Feldwegrunde, schmaler Waldpfad, Höhenroute und optionaler Geröllpfad mit kleinen Felsstufen. Bauernhof, Holzlager, Aussichtspunkt und Weiden mit Heuballen. Minikarte und Zeitfahren sind integriert; auf dieser Karte gibt es keinen Straßenverkehr. Empfohlen: Basalt-SUV oder Kestrel Rallye. Die Grasnarbe und Fahrspuren sind festes Terrain, kein dynamisch verformbarer Schlamm.
- **Testgelände**: Asphaltfläche mit Oval (KI-Verkehr), Sprungrampen, Bodenwellen, Schlaglochpiste, Leitplanken, Crash-Wand, Mast für Seitenaufprall, Slalom und Hügel
- **Autobahn**: 8,5 km Ring mit 2×3 Spuren, Beton-Mittelleitplanke, Schutzplanken, Brücken, Schilderbrücken, Beleuchtung und Gegenverkehr
- **Stadt**: Straßenraster mit Bordsteinkanten, Hochhäusern, Wohnviertel, Markt, Werkstatthöfen, Altstadtgasse, Hochstraße, Parkdeck und Frachtterminal
- **Wüste**: 1 km² Dünen und Tafelberge, Schotterpiste mit Sprüngen, Felsbrocken und Kakteen
- **Hügelland**: prozedurales Terrain mit kurviger Landstraße über Kuppen und durch Senken, dazu Wald

Statische Hindernisse laufen über eine Broadphase. Deshalb bremsen auch Karten mit über 600 Kollisionsobjekten (Leitplanken, Gebäude) die 2000-Hz-Physik nicht aus.

### HUD

Kompakte Fahrdatenkarte mit Tempo, Drehzahl, Gang, Tank und Temperatur. Im Cockpit
übernehmen die Instrumente diese Aufgabe. Warnungen geben konkrete Handlungshinweise;
die ausführliche Diagnose für Motor, Kupplung, Getriebe und Reifen ist über `F2`
ausblendbar. Hilfe: `F1`, Minikarte: `N`, Kartenübersicht: `K`.

## Entwicklung

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
ctest --test-dir build --output-on-failure                       # Unit-Tests (Physik, Fahrwerk, Kühlung, Crash, ...)
./build/apps/sbsim/cartest game/cars/aurora_sedan.car.json       # Prüfstand: Einfedern, 0-100, Bremsen, Kurve, Crash + Kühlsystem
./build/apps/sbsim/sbsim --list                                  # klassische Physik-Testszenen + Replay-Viewer (tools/make_viewer.py)
godot --headless --path game -s res://tests/smoke_test.gd        # GDExtension-Smoke-Test
godot --headless --path game -s res://tests/drivetrain_test.gd   # Antrieb, Schaden und Reparatur
godot --headless --path game -s res://tests/activities_test.gd   # Checkpoints, Untergrund und Laufregeln
godot --headless --path game -s res://tests/offroad_test.gd      # Offroad-Karte, Grip, Anstiege und Streckenanschlüsse
godot --headless --path game -s res://tests/actions_test.gd      # Gameplay-Eingaben und Kamerawechsel
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
- [ ] Bewegliche Requisiten (Pylonen, Fässer), Kollision mit Bäumen auf allen Karten
- [ ] Reifenmodell mit Lastabhängigkeit und Schräglaufkurve, Oberflächen (Schotter, Gras, Nässe)
- [x] Import detaillierter glTF-Automodelle als Flexbody
- [x] Reifenverschleiß, -temperatur, Luftdruck, Plattfuß und Platzen
- [x] Karten Autobahn, Stadt und Wüste, Kombiinstrument im HUD
- [ ] Multithreading über mehrere Fahrzeuge
