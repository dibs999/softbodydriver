# Native Chassis-Messung: Hochfrequenz und Geradeauslauf

Stand: 9. November 2026. Referenzstand `dc374de` mit neuen Messwerkzeugen;
Fahrzeugdefinitionen, Solver und Laufzeitphysik wurden für diese Messung nicht
verändert. Die Messung ergänzt die Ziele in
[VEHICLE_QUALITY_TARGET.md](VEHICLE_QUALITY_TARGET.md).

## Reproduktion

```sh
python3 tools/run_stability_bench.py --mode tow
python3 tools/run_stability_bench.py --skip-build --mode coast --output build-stability/coast
python3 tools/run_stability_bench.py --skip-build --mode powered --output build-stability/powered
```

Der erste Aufruf erstellt einen eigenen Release-Build ohne Godot-Erweiterung.
`--cmake`, `--build-dir`, `--output` und `--jobs` lassen sich anpassen. Bei einem
bestehenden Build wird beispielsweise `--build-dir build --skip-build` verwendet.
Der Wrapper unterstützt auch die `Release`-Unterverzeichnisse von
Mehrkonfigurations-Builds. Der native Aufruf lautet
`build-stability/apps/sbsim/stabilitybench --help`.

Jeder Modus prüft Kestrel Hatch und Concept GT bei 50, 100, 160 und 200 km/h.
Die Ausgabe enthält `report.json`, Rohdaten-CSV, Spektren-CSV und ein Manifest
mit Quell-/Binär-/Artefakt-SHA256, Git-Stand, CPU, Compiler und Betriebssystem.
Exitcode 0 bedeutet, dass die für den jeweiligen Modus ausgewerteten Kriterien
bestanden sind; 2 kennzeichnet mindestens einen nicht erreichten Zielzustand,
ein ungültiges Geschwindigkeitsfenster oder eine Grenzüberschreitung.
Exitcode 1 kennzeichnet einen Aufruf-/Werkzeugfehler. Eine ungültige Messung ist
im JSON getrennt von `hf_limits_pass` ausgewiesen.

## Messaufbau

- Eine horizontale Ebene mit Reibungsfaktor 1, unveränderte Gravitation,
  Aerodynamik, Reifen und Fahrzeugstruktur; keine Lenkeingabe.
- Drei Sekunden Einfedern. Im Schlepp- und Ausrollmodus wird anschließend die
  Translationsgeschwindigkeit gesetzt und jeder Reifenknoten erhält die passende
  Umfangsgeschwindigkeit `omega = v / radius`, wie im vorhandenen Highway-Test.
  Danach folgen zwei Sekunden Einschwingen und zehn Sekunden Aufzeichnung.
- Im **Schleppmodus (`tow`)** hält ein gleichmäßiger Geschwindigkeitszuschlag an
  allen Nodes ausschließlich die globale X-Komponente konstant. Relative
  Node-Geschwindigkeiten, Winkelbewegung sowie Y/Z-Geschwindigkeit werden dabei
  nicht korrigiert. Das ist ein idealisierter Prüfstand. Sobald das Fahrzeug
  seitlich abdriftet oder dreht, kann diese Regelung zusätzliche Energie zuführen;
  ein solcher Lauf belegt keinen realen Geradeauslauf bei der Sollgeschwindigkeit.
- Im **Ausrollmodus (`coast`)** gibt es nach der Initialisierung keine weiteren
  Geschwindigkeitskorrekturen. Tatsächlicher Geschwindigkeitsbereich und Sollwert
  werden getrennt ausgewiesen.
- Im **Antriebsmodus (`powered`)** beschleunigt das Fahrzeug aus dem Stand über
  seine normale Powertrain mit Vollgas und Automatik. Nach Erreichen von 99 %
  des Sollwerts regelt ein PI-Regler ausschließlich Gas/Bremse mit 50 Hz.
  Es folgen zehn Sekunden Regler-Einschwingen und zehn Sekunden Messung. Es
  werden zu keinem Zeitpunkt Node-Geschwindigkeiten gesetzt. Wird das Ziel in
  60 Sekunden nicht erreicht, lautet das Ergebnis `target_unattained_not_validated`;
  eine Hochfrequenzmessung bei diesem Zielwert wird dann nicht ausgegeben.
- Ein konstantes Geschwindigkeitsfenster gilt für diesen Messaufbau nur bei
  einer tatsächlich gemessenen Gesamtgeschwindigkeit innerhalb ±1 % als gültig.
  Das ist eine **Prüfstands-Gültigkeitsregel**, kein neuer Fahrzeug-Schadensgrenzwert.

Abgetastet wird jeder Physikschritt mit 2.000 Hz, also 20.000 Werte je Messfenster.
Die Chassishöhe und vertikale Geschwindigkeit sind das Mittel der vier
Sicherheitszellen-Bodenreferenzen. Roll und Nick werden aus deren räumlicher
Basis bestimmt. Pro Schritt werden außerdem Gierwinkel, seitliche Bewegung,
Geschwindigkeit und vier Radlasten erfasst. Endliche Node-Positionen und
-Geschwindigkeiten werden während der Aufzeichnung geprüft; Beam-Schäden und
Reifenzustand stehen im Bericht.

Die rohe Radlast stammt aus der Summe der vertikalen Reifenkontaktimpulse geteilt
durch den Physik-Zeitschritt. Daneben steht der bereits im Fahrzeugmodell
vorhandene Lastschätzer mit 25-ms-Zeitkonstante. Bei polygonalen Druckreifen kann
die rohe Impulslast stark von Schritt zu Schritt schwanken. Beide Reihen bleiben
sichtbar; der geglättete Schätzer ersetzt die Rohmessung nicht.

## Spektrale Auswertung

Die Rohdaten bleiben unverändert. Für das Spektrum wird je Reihe eine lineare
Ausgleichsgerade entfernt und ein symmetrisches Hann-Fenster angewendet. Ein
Radix-2-FFT mit 32.768 Punkten enthält die 20.000 Messwerte und Nullauffüllung.
Der Frequenzabstand der FFT-Bins beträgt 0,061035 Hz; die tatsächliche
Fensterauflösung bleibt 0,1 Hz. Nullauffüllung erzeugt keine zusätzlichen
Messinformationen.

Einseitige Bin-Leistung ist `|FFT[k]|² / (Nfft * sum(window²))`, für alle Bins
außer DC und Nyquist mit Faktor 2. Die Quadratwurzel der summierten Leistung
für **10 < f ≤ 1.000 Hz** ergibt den angegebenen Hochfrequenz-RMS. Die
Hann-Fensterung verbreitert den Übergang nahe 10 Hz; es handelt sich um eine
zeitlich begrenzte Spektralschätzung. Die Energie-Normierung gilt für stationäre
Schwingungen, während starke Transienten zusätzlich anhand der vollständigen
Rohdaten zu beurteilen sind.

`stabilitybench --self-test` prüft einen bekannten 30-Hz-Sinus, die Unterdrückung
eines 3-Hz-Sinus, einen linearen Trend, deren Mischung und die korrekte
Nyquist-Normierung. Diese Kalibrierung ist als
`stability_spectral_calibration` in CTest registriert. Der vollständige
Fahrversuch ist bewusst kein pauschales CI-Erfolgsgate.

## Bewertung

Die projektseitigen Grenzwerte sind 5 mm vertikaler RMS sowie jeweils 0,15°
Roll-/Nick-RMS über 10 Hz. Sie prüfen diesen Teil der Chassisbewegung. Ein
niederfrequentes Ausbrechen, dauerhaft schief stehendes Fahrzeug, Lenkfehler,
Kamerazittern oder zitternde einzelne Karosserieteile kann trotz kleiner Werte
bestehen. Deshalb enthalten die Berichte zusätzlich ungefilterte Min/Max-Werte,
Gier-/Seitwärtsbewegung, Radlastschwankung und Geschwindigkeitsgültigkeit.

Die Ergebnisse validieren weder Renderer/Kamera bei 30/60/120 FPS noch einen
GPU-Performancewert. Sie sind auch keine Zertifizierung von Reifen, Fahrgefühl
oder vollständiger Fahrzeugphysik.

## Aufgezeichnete Ergebnisse

Die folgenden Tabellen und JSON-Berichte gehören zur Messung vom 9. November
2026. Große Rohdaten und das vollständige Manifest liegen im erzeugten
`build/stability-{tow,coast,powered}/` und im lokalen Evidenzarchiv
`build/chassis-stability-evidence.tar.gz`. Die mitgelieferten kompakten Berichte
unter `docs/measurements/` enthalten die Messwerte und verweisen auf die
reproduzierbaren Rohdateinamen.

### Schleppprüfstand: Hochfrequenz-RMS

| Fahrzeug | Soll km/h | Vertikal mm | Roll ° | Nick ° | Geschwindigkeitsfenster |
|---|---:|---:|---:|---:|---|
| kestrel_hatch | 50 | 0.00385 | 0.000464 | 0.000361 | gültig |
| kestrel_hatch | 100 | 0.00747 | 0.001839 | 0.000607 | gültig |
| kestrel_hatch | 160 | 0.05161 | 0.019377 | 0.004108 | gültig |
| kestrel_hatch | 200 | 0.03454 | 0.006065 | 0.002066 | gültig |
| concept_gt | 50 | 0.01031 | 0.000089 | 0.000654 | gültig |
| concept_gt | 100 | 0.00222 | 0.000500 | 0.000146 | gültig |
| concept_gt | 160 | 0.01438 | 0.001821 | 0.000964 | gültig |
| concept_gt | 200 | 0.04097 | 0.008976 | 0.002874 | **ungültig: seitliches Ausbrechen** |

Alle acht Spektren liegen unter den vorläufigen HF-Grenzen. Beim Concept mit
Sollwert 200 km/h erreicht die ungefilterte Rollbewegung jedoch **8,83°**,
die vertikale Chassisgeschwindigkeit **0,74 m/s** und die Gesamtgeschwindigkeit
**222,12 km/h**. Der Gierwinkel durchläuft eine Drehung. Der globale X-Regler
ist in diesem Zustand keine gültige 200-km/h-Geradeausprüfung und kann Energie
in die seitliche Bewegung eintragen. Ein bestandener 200-km/h-Fahrtest wird
daraus ausdrücklich nicht abgeleitet.

### Normaler Antrieb: Zielerreichung und tatsächlicher Messbereich

| Fahrzeug | Soll km/h | Gemessener Bereich / erreichter Höchstwert | Bewertung |
|---|---:|---|---|
| kestrel_hatch | 50 | 49.94–49.99 km/h | HF-Grenzen bestanden, gültiges Fenster |
| kestrel_hatch | 100 | 98.85–99.83 km/h | HF-Grenzen bestanden; Reglerfenster ungültig |
| kestrel_hatch | 160 | 113.70 km/h Maximum in 60 s | Ziel nicht erreicht; HF bei Sollwert nicht geprüft |
| kestrel_hatch | 200 | 113.70 km/h Maximum in 60 s | Ziel nicht erreicht; HF bei Sollwert nicht geprüft |
| concept_gt | 50 | 50.02–50.18 km/h | HF-Grenzen bestanden, gültiges Fenster |
| concept_gt | 100 | 99.88–99.99 km/h | HF-Grenzen bestanden, gültiges Fenster |
| concept_gt | 160 | 158.77–159.85 km/h | HF-Grenzen bestanden, gültiges Fenster |
| concept_gt | 200 | 174.66 km/h Maximum in 60 s | Ziel nicht erreicht; HF bei Sollwert nicht geprüft |

Beim Kestrel-100-Lauf verletzt der Geschwindigkeitsregler die ±1-%-Vorgabe
leicht. Dieser Lauf bleibt als Messung bei seinem angegebenen tatsächlichen
Geschwindigkeitsbereich erhalten; daraus wird kein Hochfrequenzversagen des
Fahrzeugs abgeleitet. Die anderen erreichbaren Antriebspunkte halten das
Messfenster nach dem Einschwingen ein. Bei allen aufgezeichneten Läufen bleiben
Positionen/Geschwindigkeiten endlich; es entstehen keine gebrochenen oder
plastisch verformten Beams. Alle vollständig gemessenen Zehn-Sekunden-Fenster
enden ohne Reifenplatzer.

Im zusätzlichen Concept-Ausrollversuch mit anfänglich 200 km/h liegt der
Messbereich nach dem Einschwingen bei **166,36 bis 87,22 km/h**, mit weniger als
**0,93° Gierwinkel**. Er bestätigt einen unauffälligen Ausrollvorgang in diesem
Bereich, liefert jedoch keine Aussage über zehn Sekunden konstante 200 km/h.

**Offene Ursache und nächste Prüfung:** Die normale Powertrain erreicht in
diesem Modell die höheren Sollgeschwindigkeiten nicht. Der Concept endet im
60-Sekunden-Vollgasversuch bei rund 174,66 km/h im dritten Gang. Die genaue
Aufteilung der Verluste zwischen Aerodynamik, Reifen, Antriebsstrang und
Übersetzung wurde hier nicht bestimmt. Ebenso ist nicht geklärt, wie viel des
synthetischen 200-km/h-Ausbrechens vom X-Regler und wie viel von der
Fahrzeugdynamik ausgeht. Eine Kalibrierung dieser Verlust-/Antriebsmodelle und
eine anschließend tatsächlich erreichte 200-km/h-Fahrt bleiben erforderlich.
In diesem Arbeitsschritt wurden weder zusätzliche Dämpfung noch stärkere
Motoren eingesetzt, um einen Messpunkt künstlich bestehen zu lassen.

Messdateien: [Schleppprüfstand](measurements/chassis-stability-tow.json),
[Ausrollen](measurements/chassis-stability-coast.json),
[normaler Antrieb](measurements/chassis-stability-powered.json),
[kompakte CSV-Tabelle](measurements/chassis-stability-summary.csv) und
[Provenienz mit Hashes](measurements/chassis-stability-provenance.json).
