# Fahrzeugformat `*.car.json`

Ein Auto wird nicht Node für Node beschrieben, sondern über seine **realen Eckdaten**. Der Generator (`core/src/car_build.cpp`, `car_visual.cpp`) baut daraus die Node-Beam-Struktur, das Fahrwerk, die Fahrzeugsysteme und das sichtbare Mesh. Alle Längen sind in Metern, Massen in Kilogramm. Schlüssel, die mit `_` beginnen, gelten als Kommentar. Unbekannte Schlüssel lösen einen Fehler aus, damit Tippfehler sofort auffallen.

Koordinaten im Generator: `x` zeigt nach vorne (hintere Stoßstange bei 0), `y` nach oben (Boden bei 0), `z` nach rechts.

```jsonc
{
  "id": "kestrel_hatch",                // Dateiname ohne .car.json
  "name": "Kestrel Hatch 1.5 TSX",
  "brand": "Kestrel",
  "description": "Kurzbeschreibung fürs Menü",

  "body": {
    "style": "hatchback",               // hatchback | sedan | coupe | suv
    "doors": 4,                          // 2 oder 4 (Türfugen, B-Säule, Rückbank)
    "length": 4.28, "width": 1.79, "height": 1.46,
    "wheelbase": 2.63, "frontOverhang": 0.89,
    "trackFront": 1.54, "trackRear": 1.51,
    "groundClearance": 0.14,
    "noseHeight": 0.72,                  // Oberkante Frontschürze
    "hoodHeight": 0.99,                  // Haube am Scheibenfuß
    "beltHeight": 1.01,                  // Fensterunterkante (Gürtellinie)
    "tailHeight": 1.02,                  // Oberkante Heck
    "hoodLength": 1.18,                  // Stoßstange vorn bis Scheibenfuß
    "windshieldRun": 0.78,               // horizontale Länge der Frontscheibe
    "roofLength": 1.72,                  // Dach (Frontscheibe oben bis Heckscheibe oben)
    "rearWindowRun": 0.45,               // horizontale Länge der Heckscheibe
    "roofWidthRatio": 0.78,              // Dachbreite / Fahrzeugbreite
    "cornerRadiusFront": 0.32,           // Rundung der Ecken in der Draufsicht
    "cornerRadiusRear": 0.24,
    "archClearance": 0.06,               // Radhaus-Radius = Reifenradius + dieser Wert
    "paint": [0.62, 0.05, 0.04],         // Lackfarbe (linear RGB)
    "paintMetallic": 0.5,
    "dragCoefficient": 0.32,             // optional: cw-Wert (Standard je Karosserieform)
    "frontalArea": 2.12                  // optional: Stirnfläche in m² (Standard 0,84·Breite·(Höhe−Bodenfreiheit))
  },

  "chassis": {
    "curbMass": 1290,                    // Leergewicht inkl. Flüssigkeiten
    "frontWeight": 0.61,                 // statischer Anteil auf der Vorderachse
    "bodyStiffness": 1.0,                // skaliert die Beam-Federraten der Karosserie
    "bodyStrength": 1.0                  // skaliert Verformungs- und Bruchgrenzen
  },

  "suspension": {                        // je Achse; Werte auf das Rad bezogen
    "front": {
      "wheelRate": 28000,                // N/m
      "bumpDamping": 2000,               // N·s/m Druckstufe
      "reboundDamping": 4000,            // N·s/m Zugstufe
      "antiRollRate": 9000,              // N/m Stabilisator (0 = keiner)
      "bumpTravel": 0.085,               // Einfederweg bis zum Anschlagpuffer
      "droopTravel": 0.10,               // Ausfederweg bis zum Fangband
      "toe": 0.0                         // optional: statische Spur je Rad in Grad, + = Vorspur (Standard vorn 0, hinten 0,25)
    },
    "rear": { "...": "wie front" }
  },

  "tires": { "radius": 0.317, "width": 0.225, "rimRadius": 0.216, "pressurePsi": 34,
             // optional "widthRear": 0.35 für Mischbereifung (breitere Hinterreifen, z. B. Mittelmotor)
             "friction": 1.15, "tireMass": 9.5, "rimMass": 9.0, "rays": 16 },

  "engine": {
    "name": "1.5 I4 Turbo", "layout": "FWD", "cylinders": 4,   // FWD | RWD | AWD
    "position": "front", // front (Standard) | mid: Motor vor Hinterachse, Tank vor Motor
    "torqueCurve": [[700, 120], [1600, 250], [3500, 250], [6000, 190], [6500, 0]],  // [U/min, Nm]
    "idleRpm": 780, "redlineRpm": 6200,
    "inertia": 0.15, "friction": 16, "engineBraking": 0.032,
    "mass": 140,                         // Motor + Getriebe (8 Nodes im Motorraum)
    "gears": [3.76, 2.27, 1.52, 1.13, 0.92, 0.81, 0.69], "reverse": -3.45, "finalDrive": 4.06,
    "automatic": true, "shiftUpRpm": 5600, "shiftDownRpm": 1800,
    "maxBrakeTorque": 2300, "frontBrakeBias": 0.68, "handbrakeTorque": 1600,
    "lsd": 4,                            // Sperrwirkung Nm pro rad/s Differenzdrehzahl
    "fuelCapacity": 50, "bsfc": 238,     // Tank (l), spezifischer Verbrauch (g/kWh)
    "radiatorUA": 1450                   // Kühlleistung W/K bei vollem Durchfluss und Fahrtwind
  }
}
```

## Optional: Detail-Modell (`visualModel`)

```jsonc
"credits": "Quelle und Lizenz des Modells",
"visualModel": {
  "path": "res://models/carconcept/CarConcept.glb",
  "forward": "+z",            // Modellachse, die nach vorne zeigt (+x, -x, +y, -y, +z, -z)
  "up": "+y",                 // Modellachse nach oben
  "fitLength": true,          // auf body.length skalieren (sonst "scale": 1.0)
  "driverEye": [0.0, 0.93, 0.48],  // optionaler Cockpit-Kamerapunkt in lokalen Modellkoordinaten
  "dashboard": [0.0, 0.77, 1.192], // Mitte der Anzeige in lokalen Modellkoordinaten
  "steeringWheel": { "pivot": [0.0, 0.654, 0.934], "axis": [0.0, 0.38, -0.925],
    "parts": ["InteriorSteeringWheel", "InteriorSteeringEmblem"] }, // Namenspräfixe beweglicher Teile
  "wheels": { "FL": "WheelFrontL", "FR": "WheelFrontR", "RL": "WheelRearL", "RR": "WheelRearR" },
  "hide": ["BrakePad", "Axles"],                  // Teile (Namens-Teilstrings), die entfallen
  "keepProcedural": ["chassis", "spring", "caliper"],  // eigene Teile, die sichtbar bleiben
  "aoOnUV2": true,  // nur für Modelle mit AO-Atlas auf der zweiten UV-Koordinate (glTF texCoord=1)
  "materialOverrides": { "Glass": "glass", "Paint 1": "paint" }  // Modell-Material -> Spiel-Material
}
```

Die Physik-Struktur entsteht weiterhin aus `body` und den übrigen Abschnitten. Passe deshalb Länge, Breite, Höhe, Radstand, Überhang, Spurweite und Reifenradius an das Modell an. Unterhalb von Rädern, Karosserie und Innenraum wird jeder Vertex an die 4 nächsten Karosserie-Nodes gebunden. Die Radachse der Modellräder wird per Hauptachsenanalyse bestimmt.

## Was der Generator daraus baut

- **Karosserie**: Ring-Stationen entlang der Fahrzeuglänge mit den Knoten Schweller-Träger, Schweller, Flanke, Gürtellinie und Dach bzw. Haube. Zwischen benachbarten Stationen liegen Längsträger und Schubdiagonalen. Die Fahrgastzelle ist steifer und fester, die Knautschzonen vorne und hinten sind weicher. Die Diagonalen über den Seitenfenstern verhalten sich wie Glas: schwach und spröde.
- **Fahrwerk**: Doppelquerlenker mit Radträger aus 6 starr verbundenen Nodes (Naben, Kugelgelenke, Spurstangenhebel, Bremssattelpunkt vor der Achse) und Achsträger-Punkten, die mit einem "Käfig" aus Beams in alle Raumrichtungen verankert sind. Querlenkerlager beider Seiten und Spurstangenlager bilden einen gemeinsamen starren Achsträger; der obere Federteller ist über einen Federbeindom bis zu Längsträger und Schweller abgestützt. Die Feder ist vorgespannt, sodass das Auto auf Konstruktionshöhe steht. Dazu kommen Dämpfer mit Druck- und Zugstufe (`shock`), Anschlagpuffer (`support`), Fangband (`anisotropic`) und ein Stabilisator als 4-Node-Torsionsstab mit senkrechter Koppelstange.
- **Reifen und Luft**: Laufflächen-Nodes haben einen nachgiebigen Bodenkontakt (Gummi speichert den Einlaufstoß). Der Luftdruck wirkt als Membran auf jedes Laufflächensegment, mit passender Gürtelspannung in der Radebene; das hebt die Wellengeschwindigkeit des Laufflächenrings über die Höchstgeschwindigkeit. Die Bremse hält das Rad relativ zum Radträger. Der Druckwiderstand der Kollisionshaut wird auf `dragCoefficient · frontalArea` kalibriert. Messwerte: [DRIVING_RESISTANCE.md](DRIVING_RESISTANCE.md).
- **Antrieb**: Das Reaktionsmoment des Antriebs wirkt auf Motorblock bzw. Differenzial, das Reaktionsmoment der Bremse auf den Radträger. Damit bleibt der Drehimpuls erhalten, Anfahren lässt das Heck einfedern und Bremsen die Front eintauchen.
- **Systeme**: Die Beam-Indizes von Kühler, Motorblock, Ölwanne, Tank, Motorlagern, Kardanwelle, Fahrwerk und Schadenszonen gehen an `CarSystems`.
- **Visual**: Querschnitte werden über Catmull-Rom-Kurven verfeinert, mit Radausschnitten, Front- und Heckabschluss, Materialzonen (Lack, Glas, Leuchten, Fugen, Griffe, Kunststoff) und Innenraum. Jeder Vertex ist an die 4 nächsten Nodes gebunden. Die Position setzt sich zusammen aus der starren Bewegung der Fahrgastzelle plus den interpolierten Verschiebungen der Nodes.

Mit `cartest <datei>` prüfst du ein neues Auto: Stabilität, Einfedern, 0-100, Bremsweg, Kurve, Crash und Kühlsystem.

`aoOnUV2` stellt bei importierten Materialien den zweiten UV-Kanal für Ambient Occlusion wieder her, wenn der Godot-Import diese glTF-Angabe nicht übernimmt. Standard ist `false`. Die Materialkopien des Fahrzeugs werden angepasst; das gemeinsam geladene Originalmaterial bleibt unverändert.

### Abtrennbare Stoßfänger (Referenzfahrzeug)

`body.detachableBumpers: true` aktiviert getrennte vordere und hintere untere Stoßfänger-Verkleidungen. Aktuell ist diese Option im Kestrel Hatch aktiviert; bei anderen Fahrzeugen bleibt der Standard `false`. Die Verkleidungen bestehen aus jeweils acht Physik-Nodes mit zwölf Befestigungs-Beams an der Karosserie. Die Breakgroups heißen `bumper_front_mounts` und `bumper_rear_mounts`. Beim Versagen einer Befestigung löst die jeweilige Gruppe aus; der Stoßfänger bleibt eine eigene Struktur statt als gestreckte Karosseriehaut zurückzubleiben.

Die vordere Baugruppe wiegt 12 kg, die hintere 10 kg. Diese Masse wird vom Karosseriebudget abgezogen, sodass Gesamtmasse und vorgegebene Achslastverteilung erhalten bleiben. Verkleidung, unterer Lufteinlass und innere Rückkantungen sind ausschließlich an ihren eigenen Käfig gebunden. Querträger und Befestigungskonsolen bleiben am Fahrzeug sichtbar. Die Reparatur stellt Positionen, Verbindungen und Kollisionszustand wieder her.

Die Option beschreibt die **untere Verkleidung**, nicht komplette Kotflügel, Türen oder Leuchten. Importierte Karosseriemodelle müssen ihre Bauteile gesondert zuordnen; diese Option erzeugt keine automatische Segmentierung eines GLB-Modells. Der Concept GT verwendet weiterhin sein importiertes Modell ohne zusätzliche Stoßfänger-Verkleidung.

Die Motorhaube besitzt zwei zusätzliche Hubstützen (Hydro-Kanal 1). Die ausgefahrene Soll-Länge wird aus einer Öffnung um 65° gegenüber der geschlossenen Haubenlage berechnet; Federkraft und Dämpfung halten die Haube gegen die Schwerkraft. Die Stützen verwenden dieselbe `bonnet_hinge`-Breakgroup wie die Scharniere und halten ein abgerissenes Bauteil deshalb nicht unsichtbar am Fahrzeug fest. Das Spiel fährt den Kanal beim manuellen Öffnen allmählich aus und setzt ihn beim Reparieren zurück. Dies ist eine Inspektionsfunktion am stehenden prozeduralen Fahrzeug, keine automatische Animation importierter Modelle.

`body.detachableDoors: true` aktiviert zwei eigenständige vordere Türen beim
prozeduralen Fahrzeug. Aktuell nutzt der Kestrel Hatch diese Option. Jede Tür
besitzt acht Eck-Nodes und zwei vertikale Scharnierpunkte mit zusammen 30 kg;
die Masse gehört zum bestehenden Leergewichtsbudget. `door_left_hinges` und
`door_right_hinges` enthalten auch den jeweiligen Öffnungsantrieb, damit nach
einem Scharnierbruch kein unsichtbarer Antrieb die Tür festhält. Die separaten
Latch-Gruppen heißen `door_left_latch` und `door_right_latch`.

Die Hydro-Kanäle 2 und 3 werden vom Türmechanismus verwaltet. Anwendungen rufen
`SoftBody::setDoorOpen(side, open)` auf, statt diese Kanäle direkt zu ändern.
Manuelles Entriegeln deaktiviert die Latch-Beams reversibel (`disabled`), ohne
sie als Unfallschaden zu zählen. Schließen verriegelt erst bei intakten
Befestigungen, weniger als 15 mm Abweichung der Latch-Längen und weniger als
0,15 m/s relativer Geschwindigkeit. Ein beschädigtes Scharnier oder Schloss
wird dadurch nicht repariert. `repair()` stellt Geometrie, Verriegelung und
Antriebszustand gemeinsam zurück. Diese Option segmentiert keine importierten
Fahrzeugmodelle automatisch.
