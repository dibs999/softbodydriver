# Leistung und Grafikeinstellungen

Stand: 11. November 2026.

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
| Renderer | Standard (Forward+), Leistung (Mobile) | Gilt beim nächsten Start (`user://renderer.cfg` über `application/config/project_settings_override`). Mobile ist auf Onboard-Grafik (Intel HD/UHD) deutlich schneller und sieht tagsüber gleich aus; FSR entfällt (bilinear skaliert), nachts wirken weniger Lichter je Objekt, Autos unter Straßenlaternen sind dunkler |

Bäume, die die Einstellung *Bäume und Büsche* weglässt, verlieren auch ihre Stamm-Kollision. Es
bleiben also keine unsichtbaren Hindernisse zurück.

## Optimierungen

* **Fahrzeug-Meshes mit Detailstufe und auf mehreren Kernen (11. November 2026):**
  * Der eigentliche Bremser auf schwachen PCs war nicht die Grafik, sondern die CPU: Jedes Auto
    verformte jedes Bild alle seine Meshes neu (Meridian 140.000, Kestrel 90.000 Vertices), auch
    Verkehrsautos 200 m entfernt oder hinter der Kamera – 10–12 ms je Auto und Bild, mit Verkehr
    oder den Schauautos am Testgelände 40–50 ms (≈ 20 FPS hier, auf einem i5-Laptop ≈ 10 FPS,
    unabhängig von der Grafikstufe).
  * Jetzt wählt die Welt je Auto nach Kameraentfernung: bis 30 m jedes Bild, bis 70 m jedes 2.,
    bis 150 m jedes 4., darüber jedes 8. Bild; außerhalb des Sichtfelds mindestens jedes 4. Dazwischen
    werden die zuletzt verformten Meshes starr mit dem Auto mitbewegt (Lage aus den
    Achsreferenzknoten), die Räder weiter jedes Bild gesetzt. Frischer Schaden, Zurücksetzen und
    die Node-Beam-Ansicht verformen sofort. Gemessen: Mesh-Abstand zum Auto bei 100 m wie bei 5 m
    höchstens 1–3 cm (111 von 147 Bildern starr).
  * Ein stehendes Auto (geparkt, wartend, Menüvorschau) wird nicht neu verformt, solange sich kein
    Knoten bewegt.
  * Die Verformung der einzelnen Flächen läuft parallel auf dem Godot-WorkerThreadPool; Hochladen
    und Reißprüfung bleiben im Hauptthread. Meridian 10,8 → 5,0 ms, Kestrel 3,7 → 1,9 ms (4 Kerne).
  * Bildzeit ohne Rendering auf allen Karten 38–60 ms → 7,5–10 ms.
  * Unter ~10 FPS läuft die Physik nicht mehr in Echtzeit davon: Zwischen zwei Bildern simuliert
    sie höchstens 0,1 s, das Spiel wird dann langsamer statt dass Verkehrs-KI und Spielereingaben
    seltener als alle 0,1 s ankommen (vorher fuhren die KI-Autos bei ~1 FPS in die Leitplanke).
    Geprüft mit `--max-fps 5/6`: Wüsten-, Gelände-Verkehr und KI-Folgetest bestehen.

* **Physik auf mehreren Kernen (11. November 2026):**
  * Auf einem i5-Laptop zeigte F2 „Physik 52 % Echtzeit“: ein Kern schaffte die 2000 Hz für
    alle Autos nicht.
  * `World::step` rechnet Kräfte, Integration und Eigenkontakt
    jedes wachen Körpers jetzt auf einem kleinen Worker-Pool (bis zu drei Worker neben dem
    Physik-Thread, `SB_PHYSICS_THREADS=n` überschreibt). Kontakte zwischen Körpern und mit der Strecke bleiben
    seriell; daher ist das Ergebnis bitgleich zu einem Thread (Vier-Auto-Probe: gleicher
    Positions-Hash mit 1–4 Threads, 335 → 234 ms CPU je simulierter Sekunde auf 4 vCPUs; auf
    einer VM, deren Kerne Godot ohnehin auslastet, ist der Gewinn im Spiel kaum messbar).
  * Die Physik gibt die Weltsperre nach dem laufenden Schritt an einen wartenden Hauptthread
    ab, statt erst 16 Schritte (auf einem langsamen Laptop ~15 ms) fertigzurechnen.
  * Skripte lasen Tür-, Leuchten-, Scheiben-, Stoßfänger- und Klappenzustände und die
    Weltstatistik mehrmals je Bild, jedes Mal unter der Weltsperre: ~30 % der Stichproben im
    Hauptthread warteten auf der Autobahn auf einen Physikschritt. Die Zustände werden jetzt
    einmal je Bild beim Abgleich erneuert (nur die im letzten Bild gelesenen Arten), ändernde
    Aufrufe verwerfen sie, und `get_stats()` liest veröffentlichte Werte: 2 von 30 Stichproben.
  * Die Telemetrie zählte beschädigte Beams über `stats()`, das je Auto und Bild auch kinetische
    und elastische Energie über alle Knoten und Beams summierte – unter der Sperre; sie zählt
    jetzt nur noch.

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
