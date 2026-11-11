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
  Feder-Dämpfer-Bodenkontakt (`NodeParams::contactStiffness`, 4,5·10⁵ N/m bei 16 Rays, skaliert mit 16/Rays,
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

## Dritte Iteration: Pendeln des Concept GT an der Höchstgeschwindigkeit

Der Concept GT fuhr bei Vollgas ohne Lenkeingabe nicht geradeaus. Ab ~320 km/h ging er in einen
selbsterhaltenden Kreis mit ~0,5 g über, mit bis zu 36° Gierwinkel auf gerader Fläche.
Messreihe (Werkzeug: Vollgas- bzw. Tempomatlauf mit Lenkimpuls, 0,1-s-Protokoll):

* **Ohne Luftwiderstand** blieb er bei 320 km/h exakt geradeaus. Ein Lenkimpuls klang bei
  200/280 km/h ab, bei 320 km/h nur noch schleppend. Die Stabilitätsreserve fiel also mit der
  Geschwindigkeit; die Aerodynamik lieferte lediglich den Anstoß.
* **Ausgeschlossen:**
  * Asymmetrie der Haut-Triangulierung: Knotenlasten bis 258 N links/rechts verschieden, eine
    spiegelsymmetrische Triangulierung änderte aber nichts.
  * Aero-Giermoment (46 Nm bei 3° Schräganströmung) und Aero-Balance.
  * Sperrdifferenzial, Nachlauf (3,4° → 7°) und Hilfsrahmenlager (Faktor 3 steifer).
* **Ursache:**
  * Die Vorderreifen schlupften schon bei 310 km/h 5–7-mal stärker als die angetriebenen
    Hinterreifen, mit steil steigender Tendenz. Bei ~320 km/h brach ihre Haftung ein.
  * Die schmalen Vorderreifen (0,27 m) trugen dieselbe Reifenmasse (13 kg) wie die breiten
    Hinterreifen (0,35 m). Bei gleicher Laufflächenmasse, aber nur 77 % Membranspannung lag die
    Wellengeschwindigkeit des Laufflächenrings ~12 % niedriger, und die stehende Welle setzte vorn
    knapp oberhalb von 300 km/h ein.
* **Änderung:** `TireDef::massFor(front)`. `tireMass` gilt für den breiteren Reifen; der schmalere
  Reifen ist im Verhältnis der Breiten leichter (Concept vorn 10,0 kg). Masse, Schwerpunkt und
  ungefederte Masse verwenden die achsweise Masse.
* **Ergebnis:**
  * Concept GT bei Vollgas 338,5 km/h, über 80 s 2,4° Gesamtgierwinkel.
  * Ein Lenkimpuls bei 337 km/h klingt in ~3 s ab.
  * Andere Fahrzeuge unverändert (Kestrel 197, Vortex 277, Aurora 234 km/h; alle unter 1,2° Gierwinkel).
  * Prüfung: `staggered tyres keep grip at top speed…` in `core/tests/test_car.cpp`.

## Vierte Iteration: Reifendämpfung

Zerlegung des Ausrollwiderstands beim Kestrel (100 km/h):

| Anteil | Wert |
|---|---:|
| Insgesamt | 557 N |
| Luftwiderstand | 279 N, entspricht dem kalibrierten Cd·A |
| Rollwiderstand | 278 N, ein Rollwiderstandsbeiwert von 0,022 statt real ~0,010 |

Den größten Teil liefert die viskose Dämpfung der Flanken- und Gürtel-Beams. Halbiert
(Flanke 40 → 20, Gürtel 45 → 22,5 N·s/m) sinkt der Rollwiderstand auf 213 N und der
Ausrollwiderstand auf **498 N**. Das Spurflattern im Grenzbereich, an dem frühere Versuche
scheiterten, tritt nicht auf:

* alle Kernprüfungen bestehen, darunter Spurwechsel, Grenzkurve, Bremsen, Höchstgeschwindigkeit und
  Karosseriesteifigkeit;
* alle Prüfstände `cartest --quick` bestehen;
* die Höchstgeschwindigkeiten bleiben unverändert, alle Fahrzeuge fahren geradeaus.

Die Prüfgrenze für den Ausrollwiderstand ist auf 560 N verschärft.

## Fünfte Iteration: geschwindigkeitsabhängige Dämpfung (verworfen)

**Idee:** Gummi verliert je Lastwechsel ungefähr gleich viel Energie, ein viskoser Dämpfer umso mehr,
je schneller er arbeitet. Getestet wurde deshalb eine Reifendämpfung, die oberhalb von 36 km/h mit
1/v abnimmt, mit Untergrenze 35 % bzw. 60 %. Sie wurde im gedrosselten 100-Hz-Block von
`PressureWheel::step` gesetzt.

| Messung | Bisher | 35 % | 60 % |
|---|---:|---:|---:|
| Kestrel Ausrollwiderstand 100 km/h | 498 N | 432 N | 451 N |
| Kestrel Vollgas-Spitze / Gierabweichung (90 s) | 199 km/h / 2,8° | 197 km/h / 5,4° | 198 km/h / 3,1° |
| Vortex GT | 280 km/h / 2,8° | 278 km/h / 6,3° | 278 km/h / **42°** |
| Concept GT | 336 km/h / 1,7° | 336 km/h / 1,1° | 335 km/h / 1,3° |

**Ergebnis:**

* Bei 100 km/h sinkt der Rollwiderstand auf ~150 N.
* Bei hohem Tempo gewinnt die Änderung nichts. Die Höchstgeschwindigkeiten sinken sogar leicht,
  weil ungedämpfte Laufflächenschwingungen selbst Energie verbrauchen.
* Der Geradeauslauf wird schlechter, beim Vortex mit 60 % instabil.
* Kernprüfungen und `cartest --quick` bestanden zwar, die Änderung wurde trotzdem zurückgenommen.

## Sechste Iteration: 20 Laufflächen-Nodes und Hysterese-Moment

Stand: 11. November 2026.

**Befund.** Eine feinere Ausrollmessung (mittlere Geschwindigkeit über 0,5-s-Fenster, 3 s Messdauer)
zeigte, dass der Rollwiderstand stark von der Geschwindigkeit abhing (Kestrel ohne Luftwiderstand):

| km/h | 20 | 40 | 60 | 80 | 100 | 120 | 150 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 16 Nodes, bisher | 41 N | 92 N | 189 N | 298 N | 203 N | 489 N | 589 N |
| entspricht c_rr | 0,003 | 0,007 | 0,015 | 0,024 | 0,016 | 0,039 | 0,047 |

**Ursache.** Bei 16 Nodes auf 0,317 m Radius ist die Lauffläche ein Vieleck mit 12 cm Kantenlänge und
6 mm Durchhang zwischen den Nodes. Jeder einlaufende Node ist ein kleiner Stoß. Die Verluste steigen
mit v² und regen bei bestimmten Geschwindigkeiten Resonanzen an. Die 100-km/h-Messung, nach der
bisher kalibriert wurde, lag zufällig in einem Tal.

**Änderungen.**

* **20 Laufflächen-Nodes für alle Autos** (`tires.rays`, Standard jetzt 20). Bei 24 Nodes ist der
  Verlust noch flacher, aber der Vortex GT gerät mit konstanter `treadSpring` über 270 km/h in eine
  stehende Welle. Wird sie auf gleiches EA skaliert, schwingt er unter Volllast mit ±1,5° Gierwinkel.
  20 Nodes nutzt der Concept GT schon geprüft. Kosten: +30 % Physik-Rechenzeit je Auto (Kestrel 5,4 → 7,1 % eines
  CPU-Kerns in Echtzeit, eigener Physik-Thread).
* **Hysterese-Moment** `PressureWheelSpec::rollingHysteresis` (0,004). Ein Moment c·Last·R wirkt gegen
  das Abrollen. Viskose Beam-Dämpfung verliert Energie proportional zur Frequenz; echter Gummi verliert
  je Umdrehung ungefähr gleich viel.
  * Das Moment folgt dem um 20 ms geglätteten Raddrehen relativ zum Radträger.
  * Es blendet zwischen 0,05 und 0,3 m/s ein.
  * Seine Reaktion wirkt wie eine leichte Bremse auf den Radträger (Drehimpulserhaltung).
  * Ohne Reaktion schob es geparkte Autos; ohne Glättung rüttelte das Zittern des stehenden Rings an
    der Karosserie (gestützte Haube sackte ab, Türen verfehlten das Schloss).
  * 0,005 brachte den Concept-Spurwechseltest knapp ins Hinterachs-Flattern; daher 0,004.
* **Positionshaltende Haftreibung nur noch bei gehaltener Bremse oder über 0,5 m/s.** Sie hielt bisher
  jeden Laufflächenkontakt fest. Ein ungebremst geparktes Auto schaukelte dadurch dauerhaft ±3 cm mit
  ~0,8 Hz vor und zurück (schon auf `main`); eine geöffnete Haube pendelte ±5° mit. Jetzt steht es
  still (0,03 mm Restbewegung). Am Hang hält die Bremse unverändert.
* **Längenbegrenzung für Beams** (`BeamParams::longBound`/`boundSpring`, wie BeamNGs „long bound").
  Leitkegel dehnen sich höchstens 15 %. Vorher konnte ein zwischen Lauffläche und Straße
  eingeklemmter Kegel-Node mit dem Reifen herumlaufen. Der Kegel zog sich dabei auf 1,5 m um das Rad
  und bremste das Auto um bis zu 13 km/h. Das hing von der Node-Zahl ab: Mit 16 Nodes hatten die
  Prüflagen nur zufällig gepasst, mit 18, 20 und 22 Nodes hakte jeweils eine andere Lage. Jetzt
  liegen alle 18 Lagen bei ≤ 2,7 km/h.

**Ergebnis** (Rollwiderstand ohne Luft, c_rr):

| Auto | 30 km/h | 60 km/h | 80 km/h | 100 km/h | 130 km/h | Ausroll gesamt 100 km/h |
|---|---:|---:|---:|---:|---:|---:|
| Kestrel | 0,007 | 0,013 | 0,015 | 0,012 | 0,019 | 419 N |
| Aurora | 0,007 | 0,012 | 0,012 | 0,011 | 0,014 | 425 N |
| Basalt | 0,007 | 0,011 | 0,012 | 0,012 | 0,010 | 679 N |
| Concept | 0,006 | 0,009 | 0,012 | 0,013 | 0,012 | 447 N |
| Fastback | 0,008 | 0,014 | 0,021 | 0,013 | 0,014 | 508 N |
| Vortex | 0,007 | 0,010 | 0,012 | 0,011 | 0,012 | 454 N |

Höchstgeschwindigkeiten (Vollgas, 80 s, ohne Lenkeingabe):

| Auto | vorher | jetzt | reales Vorbild |
|---|---:|---:|---:|
| Kestrel | 199 km/h | 208 km/h | ~216 km/h |
| Aurora | 234 km/h | 246 km/h | ~250 km/h, abgeregelt |
| Vortex | 282 km/h | 283 km/h | |
| Concept | 338 km/h | 337 km/h | |

Kein Fahrzeug bricht aus. Alle zwölf `cartest --quick` zeigen OK, mit unveränderten Brems- und
Kurvenwerten (±0,1 s / ±0,01 g).

Prüfungen in `core/tests/test_car.cpp`:

* `rolling resistance stays like a real tyre…` (c_rr 0,005–0,02 bei 30/60/100/130 km/h)
* `an unbraked parked car comes to rest…`

## Offen

* Einzelne Resonanzbuckel: Fastback bei 80 km/h (c_rr 0,021), Kestrel bei 130 km/h (0,019).
  * Beim Fastback ist der Buckel schmal: 75 km/h 0,014, 80 km/h 0,021, 85 km/h 0,016, 90 km/h 0,012.
  * Kein Radflattern (Achsresonanz): Die senkrechte Nabenbewegung wird von der
    Node-Durchlauffrequenz (20 × Raddrehzahl, 180–235 Hz) bestimmt. Bei 80 km/h zeigt sie kein
    Maximum (0,022 m/s gegenüber 0,044 bei 70 km/h).
  * Wahrscheinlich eine Eigenform des Laufflächenrings. Dafür ist eine Modalanalyse des Reifens
    nötig.
* Spieler mit Tastatur/Gamepad und die Fahrhilfe korrigieren kleinere Abweichungen.
