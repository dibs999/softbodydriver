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

Die reproduzierbaren Chassis-Messungen und ihre Grenzen stehen in
[CHASSIS_STABILITY_MEASUREMENTS.md](docs/CHASSIS_STABILITY_MEASUREMENTS.md),
Fahrwiderstand, Höchstgeschwindigkeiten und Fahrwerkssteifigkeit in
[DRIVING_RESISTANCE.md](docs/DRIVING_RESISTANCE.md).
Der Prüfstand unterscheidet hochfrequente Schwingungen, langsames Ausbrechen
und ungültige Geschwindigkeitsfenster. Eine kleine RMS-Zahl allein bestätigt
keine stabile Hochgeschwindigkeitsfahrt.

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
- Zeitfahren, Lieferfahrten, Rennen und Crashtest vergeben **Medaillen**: Gold im Tempo der
  KI-Zielgeschwindigkeiten der Karte, Silber bis 20 %, Bronze bis 50 % langsamer; im Rennen
  Gold und Silber für Platz 1 und 2, im Crashtest nach Sternen (5/4/3). Die beste Medaille je
  Karte und Aktivität bleibt gespeichert, das Hauptmenü zählt sie.
- `F3` wählt freie Fahrt, Zeitfahren oder eine 60-Sekunden-Drift-Challenge; in der
  Stadt gibt es zusätzlich Lieferfahrten. Im **Rennen** stehen zwei KI-Gegner eine
  Reihe vor dem Spieler, warten den Countdown ab, fahren dieselbe Runde (mit Überholen)
  und verlassen die Karte nach dem Ziel; das HUD zeigt die Position, das Ergebnis den
  Platz. Verkehr am Start wird vorher weggesetzt. Auf dem Testgelände gibt es den
  **Crashtest**: Anlauf auf der Crashbahn, Aufprall auf die Betonwand mit mindestens
  50 km/h; der Bericht nennt Aufprallgeschwindigkeit, Spitzenverzögerung, Front- und
  Fahrgastzellenschaden, Motor- und Kühlerzustand und vergibt 1–5 Sterne (beste
  Wertung wird gespeichert). `F4` stellt das Auto am Start auf bzw.
  bricht den Lauf ab. Checkpoints und Ziele erscheinen in Welt und Minikarte.
  Bestleistungen werden je Karte, Auto und Modus lokal gespeichert. Zurücksetzen,
  Reparatur und Fahrzeugwechsel beenden einen laufenden Versuch. Pausen stoppen
  die Uhr; Zeitlupe verwendet die tatsächliche Simulationszeit.
- Zeitfahren zeigt Entfernung und nächste Kurve an. Nach der Ziellinie bleiben
  Rundenzeit, Vergleich zur bisherigen Bestzeit und Speicherstatus sichtbar;
  `F4` startet einen neuen Versuch. Der erste Abschluss erscheint nach einem
  Neustart auch im Hauptmenü. Bei einem Schreibfehler bleibt das Ergebnis für
  diese Sitzung sichtbar und wird ausdrücklich als nicht gespeichert bezeichnet.
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
| `kestrel_hatch` | Kompakt-Fließheck (C-Segment) | FWD | 1,5 l Turbo, 119 kW | 1290 kg |
| `aurora_sedan` | Mittelklasse-Limousine | RWD | 2,0 l Turbo, 196 kW | 1590 kg |
| `vortex_gt` | V8-Sportcoupé | RWD, Sperre | 5,0 l V8, 323 kW | 1720 kg |
| `basalt_suv` | Mittelgroßer SUV | AWD | 3,5 l V6, 210 kW | 2050 kg |

Marken und Modelle sind frei erfunden, Maße und Fahrleistungen entsprechen echten Autos der jeweiligen Klasse.

### Echte 3D-Automodelle importieren (Flexbody)

Jede Fahrzeugdatei kann über `visualModel` auf ein **glTF/GLB-Modell** verweisen. Das Spiel richtet das Modell automatisch aus (Achsen, Länge, Bodenhöhe) und bindet jeden Vertex an die nächsten Nodes der Physik-Struktur, wie die Flexbodies in BeamNG. Dellen, abgerissene Frontpartien und platte Reifen erscheinen dadurch am Detail-Modell. Die Räder des Modells werden als drehende Räder übernommen, auch wenn sie im Modell eingelenkt gespeichert sind. Beispiel: `game/cars/concept_gt.car.json` mit dem frei lizenzierten Modell [„Car Concept“ (Khronos, CC-BY 4.0)](game/models/carconcept/LICENSE.md).

So kommt ein eigenes Auto ins Spiel:

1. `.glb` nach `game/models/<name>/` legen.
2. Eine vorhandene `.car.json` kopieren und Maße, Radstand, Spur und Reifenradius an das Modell anpassen.
3. `visualModel` eintragen: Pfad, Vorwärts- und Hochachse, Namen der vier Rad-Nodes, auszublendende Teile. Details in [docs/CAR_FORMAT.md](docs/CAR_FORMAT.md).

> **Modelle realer Autos:** Der Import unterstützt auch solche Modelle. Für die Weiterverteilung müssen die konkreten Assetrechte und mögliche Marken-/Designrechte geprüft werden; eine Lizenz des Demo-Codes genügt dafür nicht. Die bisher geprüften Kandidaten und ihre belegte Lizenzlage stehen in [VEHICLE_QUALITY_TARGET.md](docs/VEHICLE_QUALITY_TARGET.md). Aktuell wird kein zusätzliches Markenfahrzeug mitgeliefert. Neue Autos entstehen durch eine passende `.car.json` und werden automatisch gefunden; das Format steht in [docs/CAR_FORMAT.md](docs/CAR_FORMAT.md).

### Schadensmodell (aus der Physik abgeleitet, nicht geskriptet)

| Bauteil | Ursache | Folge |
|---|---|---|
| Kühler | Verformung oder Bruch der Kühler-Beams | Kühlmittelleck → weniger Kühlleistung → Überhitzung → Leistungsverlust → Zylinderkopfdichtung → Motor fest |
| Ölwanne | Aufsetzen, Bordstein | Ölverlust → kein Öldruck → Lagerverschleiß → Motor fest |
| Motorblock | Verformung bei schwerem Frontcrash | Leistungsverlust und mehr Reibung, bei Totalschaden fest |
| Motorlager / Kardanwelle | Bruch | Kraftfluss unterbrochen |
| Kupplung | Anhaltender Schlupf erzeugt Reibungswärme | Ab 180 °C sinkt das übertragbare Drehmoment, über 230 °C entsteht dauerhafter Verschleiß; vollständig verschlissen kein Vortrieb |
| Getriebe | Wiederholte Schaltvorgänge unter Last ohne Auskuppeln, extreme Rückschaltungen oder Richtungswechsel | Schleifgeräusch, längere Schaltunterbrechung, Leistungsverlust bis zum Ausfall; ein Gang, dessen Drehzahl weit über dem roten Bereich läge (z. B. bei 150 km/h in den 1.), kostet auf einen Schlag einen großen Teil des Getriebes; Automatik schützt vor destruktiven Gangwechseln |
| Felgen und Reifen (Bordstein, Schlagloch) | Ein Bordstein- oder Schlaglochrand drückt einen einzelnen Laufflächenpunkt mit mehr als dem ~4,5-fachen der Radlast gegen die Felge | Felge verbogen (Wulst undicht, Reifen verliert langsam Luft, Diagnose „Felge verbogen“), bei sehr hartem Schlag Durchschlag mit schnellem Luftverlust; ein platter Reifen zieht das Auto zur Seite |
| Spurstangen | Seitlicher Schlag aufs Rad | Spurstangen geben ab ~45 kN nach, Querlenker erst bei echten Unfällen: verstellte Spur, das Auto zieht |
| Fahrzeugbrand | Öl auf heißem Motor (gerissene Ölwanne, Pleuel durch den Block), frisch zerdrückter laufender Motor nach einem Unfall (selten, ~9 %), leckender Tank nach schwerem Heckaufprall | Flammen und schwarzer Rauch aus Motorraum oder Tank, flackerndes Licht, Knistern; der Brand wächst über ~30 s, die Elektrik brennt durch (Motor aus, Anlasser tot), er verbrennt Kraftstoff und Öl und erlischt, wenn nichts mehr da ist; nur eine Reparatur behebt ihn |
| Motor (Überdrehzahl) | Die Räder treiben den Motor über die rote Linie, meist durch zu tiefes Zurückschalten | Ab ~1,1 × Drehzahlgrenze Ventilflattern und Verschleiß, ab ~1,35 × verbogene Ventile (Leistungsverlust, unrunder Lauf), ab ~1,6 × reißt ein Pleuel: Knall, Ölverlust, Motor fest; die Kupplung nimmt beim schlagartigen Einkuppeln zusätzlich Schaden |
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

### Linux-Entwicklungspaket

Ein eigenständig startbares Linux-Entwicklungspaket erzeugt `bash tools/package_linux.sh`
(Godot 4.5.1, CMake und C++20 vorausgesetzt). Der Ablauf prüft offizielle Export-Templates,
baut die native Release-Bibliothek, übernimmt Asset-Credits und testet das exportierte
Spiel ohne Editor. Paketdatei und Protokolle stehen anschließend in `dist/linux-stage.*/`.
Details und verbleibende Release-Abnahmen: [Linux-Paketierung](docs/RELEASE_LINUX.md).

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
| `F9` | Freie Kamera ein/aus: Fahrtasten bewegen, `Q`/`E` runter/hoch, `Umschalt` schneller, rechte Maustaste umsehen; das Auto steht solange still |
| Rechte Maustaste, Mausrad | Umsehen auch im Cockpit, Zoom in Außenkameras |
| `R` / `Rücktaste` | Zurücksetzen / an Ort und Stelle reparieren |
| `B` | Node-Beam-Röntgenansicht (verformte Beams gelb bis rot) |
| `J`, `P` | Zeitlupe (×0,5 / ×0,25 / ×0,1), Physik pausieren |
| `F5` | Wiederholung der letzten 20 Sekunden (läuft in Schleife, jede Kamera inklusive freier Kamera; `F5` beendet) |
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

## Ausbau: Fahrzeugbedienung und Umgebung

Die aktuelle Iteration ergänzt einen detaillierteren prozeduralen Motorraum,
Projektoroptiken und Reifenprofil, eine Instrumentenanzeige mit Drehzahlbogen sowie
bedienbare Fahrzeugausrüstung:

| Taste | Funktion |
|---|---|
| `L` | Aus → Abblendlicht → Fernlicht (bis dahin schaltet der Lichtsensor das Abblendlicht bei Dämmerung, Nacht und starkem Regen selbst) |
| `,` / `.` | Blinker links/rechts |
| `H` | Warnblinker |
| `Enter` (Gamepad: linker Stick drücken) | Hupe |
| `O` | Motorhaube im Stand öffnen, erneut drücken schließt sie; auch im Pausenmenü |
| `Shift`+`O` | Heckklappe (Kombi, SUV, Kestrel) bzw. Kofferraumdeckel (Limousine, Fastback) öffnen/schließen; auch im Pausenmenü |
| `U` / `Shift`+`U` | Kestrel: Fahrer-/Beifahrertür im Stand öffnen oder schließen; auch im Pausenmenü |
| `F` halten | Am markierten Serviceplatz tanken; anhalten und Motor mit `I` abstellen |
| `G` halten | Am Serviceplatz vier Simulationssekunden reparieren; Tankinhalt bleibt erhalten |
| `F7` | Klar, bedeckt, Regen |
| `F8` | Mittag, Abend, Nacht, Morgen |
| `Shift` + `F8` | Automatischen Tagesablauf ein/aus |

Regen baut Nässe allmählich auf; sie reduziert die Reifenhaftung für Spieler und
Verkehr und trocknet bei klarem Wetter wieder ab. Der Serviceplatz befindet sich
am Startpunkt der Karte. Tanken füllt den simulierten Tank und repariert keine
Schäden. Licht und Blinker bleiben je Fahrzeug gespeichert.

Gefiltertes Stereo-Regenrauschen und Tropfenimpulse folgen Wetter, Hauptlautstärke,
Pause und Zeitlupe. Im geschlossenen Cockpit klingt Regen gedämpft, unter
Service-Dächern leiser. Eine offene oder fehlende Vordertür hebt die vereinfachte
Innenraum-Abschirmung auf; eine exakte Abdichtung jeder verformten Fuge fehlt noch.

Die Motorhaube besitzt eigene Massepunkte, brechbare Halterungen und gedämpfte
Hubstützen. `O` entriegelt ihr Schloss und öffnet sie langsam; erneutes `O` senkt sie
auf den Stützen ab, bis das Schloss sie fängt, zuzieht und wieder einrastet. Ein im
Unfall abgerissenes Schloss oder Scharnier bleibt bis zur Reparatur kaputt. Lose Hauben kollidieren mit ausgewählten Flächen der eigenen Karosserie
und dem Motor. Beim Kestrel Hatch können außerdem die unteren Stoßfänger vorn und
hinten als eigene Bauteile abreißen. Das importierte Concept-Modell besitzt noch
keine separat bewegliche Haube. Grenzen der Kontaktauflösung und verbleibende
Schadensbaugruppen stehen in [PHYSICS_ACCEPTANCE.md](docs/PHYSICS_ACCEPTANCE.md).

Pylonen und Ölfässer sind eigene kleine Soft-Bodies: Leitkegel (4,5 kg, biegsames PVC,
federn zurück) auf dem Slalom und Handling-Parcours des Testgeländes, als Baustellen auf
dem Autobahn-Seitenstreifen, vor Lindenau im Hügelland und in einer gesperrten
Stadtspur, 200-Liter-Stahlfässer (20 kg, verbeulen) als Fasswand am Testgelände, an
den Baustellen und an der Raststätte Coyote Flats in der Wüste, und rot-weiße,
wassergefüllte Absperrungen (300 kg, lassen sich wegschieben und eindrücken) an den
Baustellen von Autobahn und Stadt. Im Gelände liegen gefällte Baumstämme (3 m,
380 kg) am Holzlager, am Waldweg und quer über dem 4x4-Pfad: Sie lassen sich schieben,
rollen und überklettern. In der Stadt stehen 240-Liter-Mülltonnen (15 kg, verbeulen) am
Abholtag paarweise an der Bordsteinkante und in den Hinterhöfen neben den Containern.
Ruhende Requisiten schlafen und kosten keine Rechenzeit, bis sich etwas Bewegtes nähert.
Autos stoßen die Requisiten um, schleifen
Pylonen unter dem Stoßfänger mit oder schleudern Fässer weg; das Pausenmenü stellt
alle wieder auf („Pylonen und Fässer zurückstellen“).

Alle Fahrzeuge tragen vorn und hinten deutsche Kennzeichen (520 × 110 mm, blaues EU-Feld, je Fahrzeug eigene Nummer), die am Karosserie-Skinning hängen und sich mit einem eingedrückten Stoßfänger mitbewegen.

Meridian Estate und Trailhead 4x4 haben eine Heckklappe, Meridian-Limousinen und
der Fastback einen Kofferraumdeckel: ein eigenes Bauteil mit brechbaren Scharnieren
und Schloss, das an den Scharnierpunkten des Modells aufschwingt und von zwei
gedämpften Gasdruckfedern offen gehalten wird (Heckklappe etwa 80°, Deckel etwa 70°)
und sich wie die Haube wieder schließen lässt. Bei einem Heckaufprall springt das
Schloss auf; Reparieren stellt es wieder her. Beim Kestrel bilden Heckscheibe,
Heckblech, Rückleuchten, Wischer und Spoiler die Heckklappe. Die importierten
Viertürer öffnen außerdem alle vier Türen um die Scharnierlinien des Modells.

Beim Kestrel haben beide Vordertüren eigene Massepunkte, brechbare Scharniere,
reversible Schlösser, Innenverkleidung und mitbewegte Scheiben/Spiegel. Normales
Öffnen erzeugt keinen Unfallschaden; verbogene oder abgerissene Halter lassen sich
mit „Schließen“ nicht reparieren. Die übrigen Fahrzeuge besitzen diese Türmechanik
noch nicht. Im Cockpit verwenden sichtbare Außenspiegel echte planare Ansichten
der Spielwelt. Rechte Maustaste beziehungsweise rechter Gamepad-Stick ermöglichen
den Blick auf beide Seiten. Unsichtbare Spiegel benötigen keine eigene Aufnahme.

Mit Automatik hält **Auto Hold** das Auto nach dem Anhalten mit der Bremse (und beim Start) fest,
bis Gas gegeben wird, statt es in der Fahrstufe davonkriechen zu lassen (`auto_hold_test`).
Bremsen halten wie echte Bremssättel auch statisch: Ein voll gebremstes Auto steht an 30 %
Steigung, die Handbremse allein hält an 20 %, ohne zu rutschen oder zu schaukeln.
Das Pausenmenü bietet Aktivitäten, Wetter und Tageszeit auch ohne Funktionstasten.
Unter **Fahrzeug → Abstimmung** lassen sich der Reifendruck je Achse (18–50 psi) und der
Bremskraftanteil vorn (50–80 %) einstellen; „Abstimmung auf Werkswerte“ setzt beides zurück.
Weniger Druck macht die Reifen weicher, mehr Bremskraft vorn lässt die Vorderräder früher
blockieren (`tuning_test`).
Auf dem Gamepad schaltet D-Pad oben das Licht, unten den Getriebemodus, links hält
die Betankung und rechts die Reparatur; X betätigt die Kupplung. Anzeigen passen
sich dem zuletzt verwendeten Eingabegerät an. Im Cockpit zeigen die Instrumente
Kraftstoff, Kühlmittel, Blinker, Licht und technische Warnungen an.

Referenzquellen, Qualitätsziele und noch offene Ausbauschritte stehen in
[BEAMNG_REFERENCE.md](docs/BEAMNG_REFERENCE.md). Die Modelle bleiben eigenständige,
prozedurale Fahrzeuge; diese Iteration ist noch kein vollständiger Ersatz für
handmodellierte Fahrzeuge und ausgearbeitete Karten.

## Qualitätsziel und Concept-GT-Fahrverhalten

Ziel ist eine vollständige Referenz-Spielschleife: ein ausgearbeitetes Fahrzeug
auf einer ausgearbeiteten Karte, mit Fahren, Schaden, Service, Aktivitäten und
verlässlich gespeicherten Einstellungen und Ergebnissen. Die verbindlichen
Abnahmekriterien stehen in [PRODUCT_TARGET.md](docs/PRODUCT_TARGET.md) und
[VEHICLE_QUALITY_TARGET.md](docs/VEHICLE_QUALITY_TARGET.md).

Der Concept GT verwendet jetzt eine tatsächliche Mittelmotor-Anordnung. Seine
hintere Spurführung wurde für hohe Seitenkräfte überarbeitet. Die aktivierte
Lenkhilfe begrenzt den angeforderten Lenkwinkel anhand von Tempo und Radstand;
sie verändert keine Reifenkräfte und kann für direkte Steuerung deaktiviert
werden. Die Option ist im Haupt- und Pausenmenü verfügbar. TCS, ABS, Getriebemodus,
Lenkhilfe und KI-Verkehr bleiben nach einem Neustart gespeichert.

## Erste Fahrt und Service

Im Hauptmenü startet **Fahreinführung** eine optionale Runde auf dem Testgelände:
Motor prüfen, 20 Meter fahren, über 50 km/h beschleunigen und bis zum Stillstand
bremsen. Die Anzeige nennt Bremsweg und Ausgangstempo und führt anschließend zum
Serviceplatz. Dort beendet tatsächliches Tanken die Einführung. In der Pause lässt
sich die Einführung ausblenden oder wiederholen.

**Zum Service bergen** im Pausenmenü transportiert das vorhandene Fahrzeug;
Verformungen, defekte Teile und Kraftstoff bleiben erhalten. `G` repariert nach
vier Simulationssekunden bei Stillstand und ausgeschaltetem Motor. Loslassen,
Bewegung, Verlassen des Platzes, Pause oder Fahrzeugwechsel brechen die Arbeit ab.
`F` zeigt die tatsächlich eingefüllte Menge an. Die bisherigen Sofort-Reset- und
Reparaturtasten bleiben für freie Versuche verfügbar; sie machen eine laufende
Bremsmessung ungültig.

Einführungsmeilensteine, Bremsrekorde mit Ausgangstempo und letzte Fahrzeug-/Kartenwahl
liegen im versionierten `user://player_progress.json`. Der Hauptbildschirm zeigt
Fortschritt und den Bremsrekord des gewählten Autos. Ungültige/neue Profilversionen
werden nicht still überschrieben; validierte Sicherungen können wiederhergestellt
werden. Bestzeiten der vorhandenen Aktivitäten bleiben separat gespeichert.

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
godot --headless --path game -s res://tests/equipment_test.gd    # Beleuchtung, Blinker und Tanken
godot --headless --path game -s res://tests/weather_test.gd      # Tageszeit, Regen und Nasshaftung
godot --headless --path game -s res://tests/weather_audio_test.gd # Regenklang, Dämpfung und AudioServer-Aufnahme
godot --headless --path game -s res://tests/weather_door_test.gd # Offene Tür, Regenabschirmung und Akustik
godot --headless --path game -s res://tests/door_controls_test.gd # Öffnen, Schließen, Scharniere und Reparatur
godot --headless --path game -s res://tests/mirror_test.gd       # Optische Flächen, Projektion und Kamerawechsel
godot --headless --path game -s res://tests/bonnet_test.gd       # Entriegelung und Reparatur der Haube
godot --headless --path game -s res://tests/steering_assist_test.gd # Fahrsteuerung einschließlich Bremsung
godot --headless --path game -s res://tests/imported_vehicle_test.gd # Modellimport, Räder, Normalen/Tangenten
godot --headless --path game -s res://tests/rubble_vehicles_test.gd # Fünf importierte Detailmodelle: Räder, Lack, Fahrbarkeit
godot --headless --path game -s res://tests/settings_test.gd     # Gespeicherte Fahreinstellungen
godot --headless --path game -s res://tests/first_drive_flow_test.gd # Einführung bis Service und Profil-Neuladen
godot --headless --path game -s res://tests/native_service_test.gd # Beschädigtes Fahrzeug bergen/reparieren
godot --headless --path game -s res://tests/service_test.gd      # Reparatur, Abbruchfälle, tatsächliche Tankmenge
godot --headless --path game -s res://tests/player_progress_test.gd # Speicherung und beschädigte Profile
godot --headless --path game -s res://tests/driving_lesson_test.gd # Bremsmessung und ungültige Versuche
godot --headless --path game -s res://tests/gamepad_controls_test.gd # Gamepad bis Service und Licht
godot --headless --path game -s res://tests/driver_input_test.gd # Rückwärtsfahrt und manueller/automatischer Antrieb
godot --headless --path game -s res://tests/cockpit_instruments_test.gd # Echte Zustände im Cockpit
godot --headless --path game -s res://tests/session_controls_test.gd # Pausenmenü, Wetter, Aktivitäten und Bergung
godot --headless --path game -s res://tests/time_trial_flow_test.gd # Echte vollständige Runde, Ergebnis und Profil-Neuladen
godot --headless --path game -s res://tests/time_trial_flow_test.gd -- --record-save-failure # Echte Runde bei nicht schreibbarer Rekorddatei
godot --headless --path game -s res://tests/proving_ground_test.gd # Anfahrt, Service, Gelände und Kollisionen
godot --headless --path game -s res://tests/wet_braking_test.gd # Gemessene Trocken-/Nassbremsung
godot --headless --path game -s res://tests/session_soak_test.gd # 30 simulierte Minuten wiederholter Fahr-/Crash-/Serviceabläufe
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
- [x] Bewegliche Requisiten (Pylonen, Fässer, Wasserbarrieren, Baumstämme)
- [ ] Kollision mit Bäumen auf allen Karten
- [ ] Reifenmodell mit Lastabhängigkeit und Schräglaufkurve, Oberflächen (Schotter, Gras, Nässe)
- [x] Import detaillierter glTF-Automodelle als Flexbody
- [x] Reifenverschleiß, -temperatur, Luftdruck, Plattfuß und Platzen
- [x] Karten Autobahn, Stadt und Wüste, Kombiinstrument im HUD
- [ ] Multithreading über mehrere Fahrzeuge
