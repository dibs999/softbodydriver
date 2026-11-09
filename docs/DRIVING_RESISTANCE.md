# Fahrwiderstand, Höchstgeschwindigkeit und Fahrwerkssteifigkeit

Stand: 9. November 2026. Diese Iteration behebt die in
[CHASSIS_STABILITY_MEASUREMENTS.md](CHASSIS_STABILITY_MEASUREMENTS.md) offen gebliebene
Leistungs-/Verlustkalibrierung: Kestrel und Concept erreichten im Vollgasversuch
nur 113,70 bzw. 174,66 km/h.

## Ursachen

Eine Zerlegung des Ausrollwiderstands (Kestrel, 100 km/h, ohne Antrieb) ergab
**1.910 N** statt der für einen Kompaktwagen üblichen ~400 N:

| Anteil | gemessen | real (Größenordnung) | Ursache |
|---|---|---|---|
| Luftwiderstand | ~700 N | ~250 N | Druckwiderstand je Kollisionsdreieck wirkt wie ein Kasten aus ebenen Platten |
| Rollwiderstand | ~1.210 N | ~130–160 N | starre Bodenkontakte vernichten bei jedem einlaufenden Laufflächen-Node dessen Vertikalimpuls; zusätzlich viskose Reifendämpfung |

Beim Hochbeschleunigen kamen drei Fahrwerksfehler hinzu, die bei den bisherigen
niedrigen Geschwindigkeiten verdeckt blieben:

1. **Radträger nicht räumlich steif.** Nabe innen/außen und beide Kugelgelenke lagen
   in einer Querebene. Die Achse konnte um die Hochachse schwenken (gehalten nur vom
   Spurstangenhebel-Beam): eine ~25-Hz-Eigenform, die Autos bei hoher Geschwindigkeit
   und im Grenzbereich drehen ließ.
2. **Federbeindom an weicher Knautschzone.** Der obere Federteller hing nur an den
   nächstgelegenen Kotflügel-Nodes. Die Karosserie sank um den Dom ~5 cm ein
   (Concept), zog die Lenkgeometrie mit und erzeugte statisch bis zu 1,8° Vorspur-
   *aus*stellung je Vorderrad.
3. **Bremse gegen Absolutdrehung.** Eine gehaltene Bremse stoppte die absolute
   Raddrehung statt der Drehung relativ zum Radträger und kämpfte so gegen jedes
   Nicken der Karosserie; ein geparkter Concept schaukelte mit ~4 kJ.

## Änderungen

* **Aerodynamik kalibriert:** Der Generator misst die Kollisionshaut frontal bei
  Einheitsgeschwindigkeit (identische Formel wie `World::accumulateAerodynamicForces`)
  und skaliert sie auf `Cd·A`. Neue optionale Felder `body.dragCoefficient` und
  `body.frontalArea` (Standard nach Karosserieform bzw. `0,84·Breite·(Höhe−Bodenfreiheit)`).
* **Nachgiebiger Laufflächenkontakt:** Laufflächen-Nodes verwenden einen steifen
  Feder-Dämpfer-Bodenkontakt (`NodeParams::contactStiffness`, 4,5·10⁵ N/m bei 16 Rays,
  harter Anschlag ab 2 cm). Der Einlaufstoß wird gespeichert und am Auslauf wieder
  abgegeben. Weichere Kontakte sparen mehr, lassen die Lauffläche aber im Grenzbereich
  rattern (Hinterachs-Spurflattern); deshalb dieser Kompromiss.
* **Bremssattelpunkt am Radträger** vor der Achse: Der Radträger ist ein starrer
  3D-Körper (6 Nodes). Die Masse stammt aus dem Nabenbudget; die ungefederte Masse bleibt gleich.
* **Federbeindom** mit vier Beams bis Längsträger/Schweller.
* **Starrer Achsträger** je Achse: Querlenkerlager beider Seiten und Lenkgetriebe-
  bzw. Spurstangenlager bilden einen gemeinsamen Rahmen.
* **Bremse wirkt relativ zum Radträger.**
* **Hinterachse mit 0,25° statischer Vorspur** (`suspension.*.toe`, Standard vorn 0°).

Verworfen (gemessen, aber instabil): Reduktion der Reifendämpfung nach Rollgeschwindigkeit
(hysteretische Dämpfung), Gürtelkraft gegen Fliehkraft, Karkassendämpfung, Abtrieb an der
Hinterachse. Alle senkten den Widerstand, ließen aber die Lauffläche bei Tempo gleiten
bzw. die Autos ausbrechen.

## Messwerte

Vollgas mit Automatik auf ebener Fläche, keine Lenkeingabe, 60 s, Spitzenwert
(Werkzeuge: `cartest`, Kernprüfungen; Rohwerte aus der Prüfsitzung):

| Fahrzeug | vorher | nachher | 0–100 km/h vorher → nachher |
|---|---:|---:|---|
| Kestrel Hatch (119 kW, FWD) | 113,7 km/h | 141,7 km/h | 11,4 → 8,7 s |
| Aurora Sedan | 134,1 | 170,7 | 7,2 → 6,4 s |
| Vortex GT | 147,6 | 252,6 | 5,6 → 5,3 s |
| Vortex Sprint | 132,2 | 205,9 | 7,4 → 6,6 s |
| Kestrel Rally | 141,2 | 232,8 | 5,7 → 5,1 s |
| Basalt SUV | 125,2 | 150,0 | 9,5 → 8,0 s |
| Concept GT | 174,6 | ~240 (bricht danach aus) | 4,4 → 3,9 s |

Ausrollwiderstand bei 100 km/h inklusive Luft: Kestrel **1.910 → 908 N**, übrige
Fahrzeuge 750–1.310 N. Statischer Vorspurfehler vorn nach dem Einfedern: Concept
−1,82° → −0,15°, Kestrel −0,63° → −0,35°. Bodensenkung der Fahrgastzelle
beim Einfedern: Concept 6,6 → 1,4 cm.

## Abgesicherte Prüfungen

`core/tests/test_car.cpp`:
* Kollisionshaut erzeugt den vorgegebenen Luftwiderstand (±5 %).
* Ausrollwiderstand des Kestrel bei 100 km/h zwischen 250 und 1.150 N.
* Vortex GT fährt mit Vollgas ohne Lenkeingabe über 210 km/h bei unter 4° Gierwinkel.
* Einfedern ohne Karosseriesenkung > 3,5 cm, ohne Vorspurfehler > 0,6° und ohne
  Brems-Schaukeln (kinetische Energie im Stand < 100 J).
* Die Concept-Spurprüfung bei 200 km/h lenkt jetzt einen echten Spurwechsel
  (~0,5 g). Die frühere Eingabe verlangte kinematisch ~1,2 g und blieb nur unter der
  Haftgrenze, weil der übermäßige Widerstand das Auto in 4 s von 200 auf 145 km/h bremste.

## Zweite Iteration: Reifenmembran und Mischbereifung

Die Zerlegung zeigte, dass fast der gesamte verbleibende Verlust in der Dämpfung der
Reifen-Beams entsteht und bei ~145 km/h ein Maximum hat. Die Ursache war weder die
Polygonform (24/32 Rays ändern wenig) noch die Dämpfung selbst, sondern eine **stehende
Welle im Laufflächenring**: Ohne Fülldruck-Spannung lag seine Wellengeschwindigkeit bei
etwa 40 m/s. Reale Reifen erreichen ihre kritische Geschwindigkeit erst bei 250–300 km/h,
vor allem weil der Luftdruck die Lauffläche wie eine Trommelhaut spannt.

* **Membranmodell** (`PressureWheelSpec::membranePressure`): Druck `p · Breite` wirkt
  normal auf jedes Laufflächensegment, der Gürtel trägt die passende Ringspannung
  `T = p · Breite · R` – nur in der Radebene, weil eine axiale Komponente die Lauffläche zur
  seitlich gespannten Saite macht und das Rückstellmoment umkehrt (Vorderräder lenkten in
  die Kurve hinein). Auf dem runden Ring heben sich beide Kräfte exakt auf. Der Faktor 2
  ersetzt die nur teilweise abgebildete Biegesteifigkeit des Gürtels.
* **Mischbereifung** (`tires.widthRear`): Der hecklastige Concept GT (56 % hinten) war bei
  gleich breiten Reifen über ~150 km/h instabil (Querbeschleunigung wuchs bei konstanter
  Lenkung weiter). Mit 0,27 m vorne / 0,35 m hinten (wie reale Mittelmotorfahrzeuge)
  stellt sich ein stationärer Kurvenzustand ein. Physik, prozedurales Rad und Import-
  skalierung verwenden die achsweise Breite.

| Fahrzeug | Spitze 1. Iteration | Spitze jetzt | 0–100 km/h | Ausrollwiderstand 100 km/h |
|---|---:|---:|---|---:|
| Kestrel Hatch (119 kW) | 141,7 km/h | **197,0** | 8,2 s | 557 N |
| Aurora Sedan | 170,7 | **233,6** | 6,3 s | 566 N |
| Vortex GT | 252,6 | **280,7** | 5,1 s | 544 N |
| Vortex Sprint | 205,9 | **229,3** | 6,4 s | 476 N |
| Kestrel Rally | 232,8 | **245,3** | 4,9 s | 502 N |
| Basalt SUV | 150,0 | **213,0** | 7,5 s | 767 N |
| Concept GT | ~240, dann Ausbruch | **324,6** (bis 322 km/h unter 0,3° Gierwinkel) | 3,9 s | 479 N |

Alle Fahrzeuge fahren ohne Lenkeingabe bis 200 km/h mit unter 1,5° Gierwinkel geradeaus
(der Kestrel zog vorher seitlich weg). Der Rollwiderstand ohne Luft bei 145 km/h sinkt
beim Kestrel von 1.838 auf ~500 N. Zusätzliche Prüfungen: kein Resonanzmaximum bei
145 km/h, Ausrollwiderstand unter 750 N, stationäre Kurvenfahrt des Concept GT.

## Offen

* Ausrollwiderstand liegt noch ~30–40 % über typischen Realwerten.
* Concept GT pendelt an seiner Höchstgeschwindigkeit (~324 km/h) auf.
* Spieler mit Tastatur/Gamepad und die Fahrhilfe korrigieren kleinere Abweichungen.
