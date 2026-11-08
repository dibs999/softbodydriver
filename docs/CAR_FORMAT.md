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
    "paintMetallic": 0.5
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
      "droopTravel": 0.10                // Ausfederweg bis zum Fangband
    },
    "rear": { "...": "wie front" }
  },

  "tires": { "radius": 0.317, "width": 0.225, "rimRadius": 0.216, "pressurePsi": 34,
             "friction": 1.15, "tireMass": 9.5, "rimMass": 9.0, "rays": 16 },

  "engine": {
    "name": "1.5 I4 Turbo", "layout": "FWD", "cylinders": 4,   // FWD | RWD | AWD
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
  "materialOverrides": { "Glass": "glass", "Paint 1": "paint" }  // Modell-Material -> Spiel-Material
}
```

Die Physik-Struktur entsteht weiterhin aus `body` und den übrigen Abschnitten. Passe deshalb Länge, Breite, Höhe, Radstand, Überhang, Spurweite und Reifenradius an das Modell an. Unterhalb von Rädern, Karosserie und Innenraum wird jeder Vertex an die 4 nächsten Karosserie-Nodes gebunden. Die Radachse der Modellräder wird per Hauptachsenanalyse bestimmt.

## Was der Generator daraus baut

- **Karosserie**: Ring-Stationen entlang der Fahrzeuglänge mit den Knoten Schweller-Träger, Schweller, Flanke, Gürtellinie und Dach bzw. Haube. Zwischen benachbarten Stationen liegen Längsträger und Schubdiagonalen. Die Fahrgastzelle ist steifer und fester, die Knautschzonen vorne und hinten sind weicher. Die Diagonalen über den Seitenfenstern verhalten sich wie Glas: schwach und spröde.
- **Fahrwerk**: Doppelquerlenker mit Radträger aus 5 starr verbundenen Nodes und Subframe-Punkten, die mit einem "Käfig" aus Beams in alle Raumrichtungen verankert sind. Die Feder ist vorgespannt, sodass das Auto auf Konstruktionshöhe steht. Dazu kommen Dämpfer mit Druck- und Zugstufe (`shock`), Anschlagpuffer (`support`), Fangband (`anisotropic`) und ein Stabilisator als 4-Node-Torsionsstab mit senkrechter Koppelstange.
- **Antrieb**: Das Reaktionsmoment des Antriebs wirkt auf Motorblock bzw. Differenzial, das Reaktionsmoment der Bremse auf den Radträger. Damit bleibt der Drehimpuls erhalten, Anfahren lässt das Heck einfedern und Bremsen die Front eintauchen.
- **Systeme**: Die Beam-Indizes von Kühler, Motorblock, Ölwanne, Tank, Motorlagern, Kardanwelle, Fahrwerk und Schadenszonen gehen an `CarSystems`.
- **Visual**: Querschnitte werden über Catmull-Rom-Kurven verfeinert, mit Radausschnitten, Front- und Heckabschluss, Materialzonen (Lack, Glas, Leuchten, Fugen, Griffe, Kunststoff) und Innenraum. Jeder Vertex ist an die 4 nächsten Nodes gebunden. Die Position setzt sich zusammen aus der starren Bewegung der Fahrgastzelle plus den interpolierten Verschiebungen der Nodes.

Mit `cartest <datei>` prüfst du ein neues Auto: Stabilität, Einfedern, 0-100, Bremsweg, Kurve, Crash und Kühlsystem.
