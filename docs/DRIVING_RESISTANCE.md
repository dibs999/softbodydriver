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
| Kestrel Hatch (110 kW, FWD) | 113,7 km/h | 141,7 km/h | 11,4 → 8,7 s |
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

## Offen

* **Rollwiderstand** liegt weiterhin 2–3× über realen Werten. Bei ~145 km/h zeigt sich
  ein Widerstandsmaximum aller Fahrzeuge, vermutlich eine stehende Welle im
  Laufflächenring (zu geringe Ringvorspannung bei gegebener Node-Masse).
  Eine Lösung braucht ein überarbeitetes Reifenmodell.
* **Kestrel Hatch** erreicht deshalb nur ~142 km/h (real ~205 km/h) und zieht unter
  Vollgas leicht zur Seite (asymmetrische Vorspuränderung unter Antriebsmoment, ~0,3°).
* **Concept GT** bricht oberhalb ~240 km/h ohne Lenkeingabe aus. Hinterer Abtrieb
  verschlechtert das; es handelt sich nicht um klassisches Übersteuern, sondern um ein
  lastabhängiges dynamisches Reifenverhalten.
* Spieler mit Tastatur/Gamepad und die Fahrhilfe korrigieren beides. Für die Abnahme
  „konstante 200 km/h“ gilt: Vortex GT, Kestrel Rally und Vortex Sprint erreichen sie
  im normalen Antrieb stabil; Kestrel und Basalt sind leistungsbegrenzt, Concept
  instabil oberhalb 240 km/h.
