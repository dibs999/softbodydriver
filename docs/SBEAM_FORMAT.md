# Das `.sbeam.json`-Format (Version 1)

`.sbeam.json` definiert Fahrzeuge und verformbare Objekte als **Nodes** (Massepunkte) und **Beams** (Feder-Dämpfer-Verbindungen). Es ist gültiges JSON, erlaubt aber zusätzlich `//`- und `/* ... */`-Kommentare.

Koordinatensystem (wie in Godot): **+Y ist oben**, **+X ist vorne**, Einheiten sind SI (**Meter, Kilogramm, Sekunden, Newton**).

```jsonc
{
  "format": "sbeam",
  "version": 1,
  "name": "mein_objekt",

  "nodes": [
    // Setzt Standardwerte für alle nachfolgenden Nodes:
    {"set": {"mass": 10.0, "friction": 0.85}},

    // [id, x, y, z]  oder  [id, x, y, z, {Überschreibung für diesen Node}]
    ["n0", 0.0, 0.0, 0.0],
    ["n1", 1.0, 0.0, 0.0, {"fixed": true}]
  ],

  "beams": [
    {"set": {
      "type": "normal",
      "spring": 500000,   // N/m  (Steifigkeit)
      "damp": 150,        // N*s/m (Dämpfung)
      "deform": 15000,    // N (ab hier bleibende Delle; "inf" = nie)
      "strength": 45000   // N (ab hier Riss/Bruch; "inf" = unzerbrechlich)
    }},
    ["n0", "n1"]
  ]
}
```

## Node-Eigenschaften

| Eigenschaft | Standard | Bedeutung |
|---|---|---|
| `mass` | `1.0` | Masse in kg (`> 0`). |
| `friction` | `1.0` | Reibungskoeffizient (wird mit dem der Oberfläche multipliziert). |
| `fixed` | `false` | Wenn `true`, ist der Punkt fest im Raum verankert (z. B. Brückenlager). |
| `collision` | `true` | Wenn `false`, ignoriert der Punkt die Welt-Kollision. |

## Beam-Eigenschaften

| Eigenschaft | Standard | Bedeutung |
|---|---|---|
| `type` | `"normal"` | `"normal"`, `"support"` (nur Druck), `"anisotropic"` (Zug ≠ Druck), `"hydro"` (steuerbare Länge, z. B. Lenkung). |
| `spring` | `1e6` | Federsteifigkeit in N/m. |
| `damp` | `100` | Dämpfung in N·s/m. |
| `deform` | `"inf"` | Kraft in N, ab der sich die Ruhelänge dauerhaft verschiebt. |
| `strength` | `"inf"` | Kraft in N, ab der der Beam reißt. |
| `deformLimit` | `"inf"` | Maximale Stauchung der Ruhelänge als Anteil (z. B. `0.5` = bis auf 50 % verkürzbar). |
| `deformLimitExpansion` | `"inf"` | Maximale Dehnung der Ruhelänge als Anteil. |
| `hardening` | `0.0` | Kaltverfestigung: um welchen Faktor `deform` beim Verbiegen ansteigt. |
| `precompression` | `1.0` | Faktor auf die Ruhelänge beim Spawnen (z. B. vorgespannte Fahrwerksfeder). |
| `springExpansion`, `dampExpansion` | `-1` | Nur für `"anisotropic"`: Werte bei Zug (`< 0` = wie `spring`/`damp`). |
Mit `{"reset": true, "set": {...}}` werden alle Standardwerte vor dem Setzen wieder auf ihre Grundwerte zurückgesetzt.

## Kollisions- und Aerodynamik-Dreiecke (`triangles`)

```jsonc
  "triangles": [
    {"set": {"friction": 0.5, "dragCoef": 1.0, "breakable": true, "breakGroup": "hood_latch"}},
    // [idA, idB, idC] mit Außen-Normale (pos[b] - pos[a]) x (pos[c] - pos[a])
    ["n0", "n1", "n2"]
  ]
```

| Eigenschaft | Standard | Bedeutung |
|---|---|---|
| `friction` | `0.5` | Reibungskoeffizient für Fahrzeug-gegen-Fahrzeug-Kontakte (`Node vs ColTri`). |
| `dragCoef` | `1.0` | Aerodynamischer Druckwiderstands-/Abtriebs-Beiwert $C_d$. |
| `breakable` | `true` | Wenn `true`, löst sich das Dreieck automatisch auf, sobald einer seiner drei Kanten-Beams reißt. |
| `breakGroup` | `""` | Optionale Bruchgruppe: reißt die Gruppe, deaktiviert sich auch das `ColTri`. |

