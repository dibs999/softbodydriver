# Leistung und Grafikeinstellungen

Stand: 9. November 2026.

## Grafikeinstellungen

Statt vier fester Stufen gibt es jetzt einzelne Optionen (Hauptmenü → Einstellungen → Grafik,
Pausenmenü → Einstellungen). Die Voreinstellungen *Sehr niedrig*, *Niedrig*, *Mittel*, *Hoch* und
*Ultra* setzen nur alle Optionen auf einmal. Jede einzelne Änderung schaltet auf
*Benutzerdefiniert*. Alle Werte werden in `user://graphics.cfg` gespeichert.

| Option | Werte | Wirkung |
|---|---|---|
| 3D-Auflösung | 50–100 % | Renderauflösung der 3D-Szene, die Oberfläche bleibt scharf |
| Hochskalierung | Bilinear, FSR 1, FSR 2 | Verfahren zum Hochskalieren |
| Kantenglättung | Aus, FXAA, TAA, MSAA 2×/4× | |
| Schatten | Aus, Niedrig, Mittel, Hoch | Atlasgröße 1024–4096, Reichweite 60/120/220 m, 2 oder 4 Kaskaden |
| SSAO, Leuchteffekte | An/Aus | |
| Sichtweite | 600–4000 m | Kamera-Fernebene, Grenze für entfernte Bäume |
| Bäume und Büsche | Wenig, Mittel, Voll | Anteil der gepflanzten Vegetation (gilt beim Laden) |
| Gras | Aus, Nah (45 m), Normal (85 m), Weit (130 m) | Zeichenweite der Grasbüschel (gilt beim Laden) |
| Fassaden | Einfach, Detailliert | Räume hinter den Fenstern (Interior Mapping) oder getöntes Glas |
| Spiegel | Aus, Niedrig, Hoch | Auflösung und Bildrate der Spiegel |
| Partikel und Regen | Reduziert, Voll | Partikelbudget |
| Bildrate begrenzen, VSync | | |

Bäume, die die Einstellung *Bäume und Büsche* weglässt, verlieren auch ihre Stamm-Kollision. Es
bleiben also keine unsichtbaren Hindernisse zurück.

## Optimierungen

* **Bäume mit Detailstufen:**
  * Jede Baumart hat neben dem Nahmodell ein Fernmodell mit ~22 % der Blattkarten
    (größere Karten, einfacher Stamm).
  * Das Nahmodell gilt bis 130 m, das Fernmodell bis 80 % der Sichtweite; dahinter wird nichts
    gezeichnet.
  * Fernbäume werfen keine Schatten.
  * Gemessen auf Hügelland bei *Niedrig*: 1,80 → 1,13 Mio. Dreiecke, 713 → 555 Zeichenaufrufe.
* **Sehr niedrig:** 0,45 Mio. Dreiecke und 313 Zeichenaufrufe auf derselben Strecke (vorher stets
  ~1,8 Mio.).
* **Physik mit mehreren Fahrzeugen:**
  * `Beam` trug die vollständigen Autorenparameter mitsamt einem `std::string`, ~300 Byte je Beam
    und ~700 KB je Auto. Mit mehreren Autos passte das nicht mehr in den Cache.
  * Die Parameter liegen jetzt getrennt in `SoftBody::beamParams()`.
  * Vier Autos kosten statt 447 nur noch 285 ms CPU je simulierter Sekunde (ein Auto: 59 ms).

## Messwerkzeuge

* `tests/perf_probe.gd [-- <karte>]`: Zeichenaufrufe, Objekte, Dreiecke und Prozesszeit je Karte.
  Mit `PRESET=<0..4>` gilt eine bestimmte Voreinstellung.
* `tests/perf_breakdown.gd -- <karte>`: schaltet einzelne Systeme ab und misst die Hauptthread-Zeit.

Die Messungen entstanden mit Software-Rendering (lavapipe). Dreiecke und Zeichenaufrufe sind
übertragbar, absolute Bildraten nicht.

## Offen

* Abnahme auf echter Einsteiger-Hardware (integrierte Grafik).
* Physik der KI-Fahrzeuge in größerer Entfernung mit reduzierter Rate.
