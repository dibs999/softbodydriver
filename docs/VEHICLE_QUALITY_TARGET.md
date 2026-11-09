# Ziel: ein überzeugendes, vollständig spielbares Referenzfahrzeug

Stand: 8. November 2026. Erst ein Fahrzeug bis zur nachstehenden Abnahme bringen, danach dieselbe Qualität auf die Flotte übertragen. Ein neues HUD, mehr Polygone oder zusätzliche Kästen im Motorraum allein erfüllen dieses Ziel nicht.

## Bildreferenzen, die tatsächlich geprüft wurden

* [Offizielles BeamNGpy-Bild: West Coast USA mit Schadensdiagnose](https://github.com/BeamNG/BeamNGpy/blob/0c7009e2da87019bed5278f7f9e07f242b89469b/media/damage_west_coast_usa.png). Das Bild wurde visuell geprüft. Der Fenstertitel nennt **BeamNG.drive 0.24.0.2**: historische Referenz, kein Beleg für das aktuelle HUD. Sichtbar sind ein runder Drehzahlmesser unten rechts, Geschwindigkeit und Gang zentral darin, Temperatur-/Kraftstoffanzeigen, Licht-/Parkbrems-/ABS-Symbole, Blinker-Pfeile und ein separater Motorstartknopf. Das Auto zeigt stimmige Proportionen, gefasste Scheiben, echte Lampenflächen, Heckwischer, Kennzeichenmulde, Auspuff und gegliederte Stoßfänger. Der Straßenraum besitzt Materialvariation, Zäune, Pfosten und Hintergrundstaffelung.
* [Khronos CarConcept: Originaldarstellung](https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/CarConcept/screenshot/screenshot_Large.jpg). Ebenfalls visuell geprüft: glatte Karosserieflächen, klar getrennte Lack-/Glas-/Gummioberflächen, Reifenprofil, Innenraum und sichtbare Fugen. Dies ist eine Material-/Geometriereferenz, kein Beleg dafür, dass unsere Godot-Darstellung bereits gleichwertig ist.
* [CarConcept-Herstellungsdokumentation](https://github.com/KhronosGroup/glTF-Sample-Assets/blob/main/Models/CarConcept/README.md): geordnete Bauteilhierarchien und Tür-Pivots, UV-Aufbereitung, AO mit geöffneten Türen, Reifen-Normalmap. Die Dokumentation sagt auch ausdrücklich, dass kleine und unsichtbare mechanische Teile entfernt wurden. Deshalb ersetzt das vorhandene Modell keinen vollständigen Motorraum oder Unterboden.

Die offizielle Dokumentationsdomain war zuvor durch den Cloud-Proxy gesperrt; es wurde keine zwischenzeitliche Freigabe gemeldet. Die zugänglichen offiziellen GitHub-Bilder liefern jetzt eine konkrete historische Bildreferenz. Aktuelle BeamNG-Menüs und aktuelle Modellqualität bleiben separat zu überprüfen.

## Modellwahl und belegte Download-/Lizenzlage

| Kandidat | Belegte Herkunft und Download | Lizenznachweis / Eignung |
|---|---|---|
| **CarConcept (bereits enthalten)** | [Khronos-Modellverzeichnis](https://github.com/KhronosGroup/glTF-Sample-Assets/tree/main/Models/CarConcept), [GLB](https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/CarConcept/glTF-Binary/CarConcept.glb) | [Explizite Metadaten](https://github.com/KhronosGroup/glTF-Sample-Assets/blob/main/Models/CarConcept/metadata.json): Modell und Texturen CC BY 4.0, Eric Chadwick / Darmstadt Graphics Group GmbH. Khronos-Logos separat ausgenommen. Gute sofort verfügbare Grundlage, aber fiktives Konzeptfahrzeug und kein fertiges Schadensmodell. |
| **Ferrari 458 Italia von vicent091036** | [three.js-Demo mit Urheber-/Quellenlink](https://github.com/mrdoob/three.js/blob/dev/examples/webgl_materials_car.html), [bereitgestelltes GLB](https://raw.githubusercontent.com/mrdoob/three.js/dev/examples/models/gltf/ferrari.glb), [Originalquelle](https://sketchfab.com/models/57bf6cc56931426e87494f554df1dab6) | Demo und GLB erreichbar; GLB-Metadaten nennen keinen Modell-Lizenztext. Originalquelle durch Proxy 403 nicht lesbar. **Lizenz somit nicht verifiziert, keine Übernahme ins Produkt empfohlen.** Das Modell wurde ausschließlich außerhalb des Repositorys zur Metadatenprüfung geladen. Eine Softwarelizenz des Demo-Repositories ist kein hinreichender Nachweis der Assetrechte. |

**Konkrete Empfehlung:** Das vorhandene CarConcept als unmittelbaren visuellen Vergleichsmaßstab verwenden und dessen Import-/Materialqualität zuerst korrekt herstellen. Parallel einen sauber gegliederten eigenen Kestrel als langfristiges Referenzfahrzeug ausarbeiten. Für ein echtes Markenfahrzeug erst einen spezifischen Kandidaten mit lesbarer Lizenz und passender Teilehierarchie wählen; aktuell wurde kein zusätzlicher realer Markenwagen als zur Weiterverteilung geklärt nachgewiesen.

Modell-/Texturrechte und Rechte an Marken/Logos sind getrennte Fragen. Eine CC-Lizenz für ein Mesh belegt nicht automatisch eine Herstellerlizenz; vorhandene Credits bleiben erhalten, Änderungen werden vermerkt. Hieraus folgt kein pauschales Verbot realer Autos, sondern ein konkreter noch offener Prüfschritt beim gewählten Asset.

## Abnahme: Referenzwagen

Diese Werte sind **Projektziele**, keine Behauptungen über BeamNGs interne Vorgaben oder bereits bestandene Prüfungen.

### Geometrie und Material

* Eine konsistente Meter-Skalierung; Radstand, Spur, Durchmesser und Außenmaße stimmen innerhalb **1 %** mit der Fahrzeugdefinition überein. Raddrehpunkte liegen innerhalb **5 mm** der sichtbaren Radmitten.
* Karosserie, Haube, Heckklappe, Türen, Glas, Stoßfänger, Leuchten, Felgen, Reifen, Bremsen, Innenraum, Motor-/Getriebegruppe und Unterboden sind benannte Baugruppen. Keine sichtbaren Löcher beim Öffnen oder nach Beschädigung.
* Lack, Klarlackwirkung, Glas, Kunststoff, Gummi, Metall und Textilien unterscheiden sich erkennbar in Rauheit, Reflexion und Normaldetails. Keine flächigen weißen Platzhalter oder verlorenen Texturen nach Import.
* Fugen, Dichtungen, Lampeninnenteile und Innenflächen halten einer Aufnahme aus **0,5–1 m** stand. UVs zeigen bei einem Prüfraster keine auffälligen Sprünge; normale Ansicht zeigt keine schwarzen Normalen-/Tangentenfehler.
* Referenzbilder in **1920×1080**: vorn/hinten seitlich, beide Profile, Front/Heck, Cockpit, Motorraum offen, Unterboden und Nacht mit Licht. Gleiche Kamera, Belichtung und Position für Vorher/Nachher; zusätzlich bewegtes Video, damit Reflexionsflimmern erkennbar wird.

### Mechanik und Schaden

* Radlenkung, Raddrehung, Federweg und Lenkrad sind sichtbar gekoppelt; Bremsen verbleiben korrekt am Radträger. Unter der geöffneten Haube befinden sich Motor, Ansaugung, Kühlung, Leitungen und plausibel angeordnete Nebenaggregate.
* Tür und Haube lassen sich geschlossen, geöffnet, beschädigt und abgetrennt prüfen. Scharnier und Schloss sind getrennte mechanische Funktionen. Ein abgetrenntes Teil bewegt sich unabhängig, besitzt Kollision und verschwindet nicht einfach.
* Reproduzierbare Frontal-/Schräg-/Seitencrashs bei **30 und 60 km/h**, anschließend Reparatur. Keine NaNs, Explosionsimpulse oder endlos gedehnten Dreiecke. Schäden müssen mit Fahrzeugzustand und sichtbarer Struktur übereinstimmen.
* Geradeausfahrt auf ebener Strecke bei **50/100/160 km/h**, Bremsung und Bodenwellen separat aufzeichnen. Als vorläufige Messgrenze auf glatter Fahrbahn: nach dem Einschwingen unter **5 mm RMS** hochfrequenter vertikaler Chassisbewegung und unter **0,15° RMS** hochfrequenter Roll-/Nickbewegung (Messband über 10 Hz). Diese Grenzen anhand aufgezeichneter Messdaten kalibrieren, keine Filterung zur bloßen Kaschierung.
* Bei **30/60/120 Render-FPS** bleibt die Bewegung kontinuierlich; gleicher Fahrtest darf keine FPS-abhängige Instabilität erzeugen. Physikwerte, Renderpose und Kamera getrennt protokollieren.
* Zusätzlich getrennte Kernprüfungen bei **100 und 200 km/h** auf ebener Strecke: nach Einfedern auf Geschwindigkeit bringen, mindestens zehn Sekunden ohne Lenkeingriff protokollieren. Soll: alle Werte endlich, keine neu gebrochenen Beams, kein unbegründeter Reifenschaden; maximale Roll-/Nickwinkel, vertikale Geschwindigkeit und Radlastschwankung im Bericht ausweisen. Ein Test, der nur erkennt, dass das Auto noch existiert, genügt nicht.
* Die tatsächliche Spielsteuerung separat prüfen: Referenzwagen durch Gasgeben über 100 km/h bringen, volle linke/rechte Tastatureingabe, Loslassen, anschließend Bremsen. Lenkwinkel muss geschwindigkeitsabhängig begrenzt und links/rechts sowie vorwärts/rückwärts symmetrisch sein; Loslassen führt zur Geradeausanforderung zurück. Der vorhandene `game/tests/steering_assist_test.gd` prüft Teile dieses Pfads. Eine bestandene Eingabeprüfung allein belegt weder stabile Kernphysik noch gutes subjektives Fahrgefühl.

### Bedienung, Umwelt und Performance

* Licht-/Fernlicht-, Blinker-/Warnblinker-, Motor- und Getriebezustände sind am Auto und HUD konsistent. Cockpit, Außenkamera, Pause, Zeitlupe, Fahrzeugwechsel und Reparatur jeweils testen.
* Nachtfahrt bleibt lesbar, Scheinwerfer treffen die Fahrbahn; kein Licht leuchtet aus einem abgetrennten Bauteil weiter. Regen berücksichtigt Pause/Zeitlupe und verursacht keine Niederschläge im geschlossenen Innenraum.
* Tankstelle besitzt verständliche Anfahrt und Interaktion; Stillstand, Motor aus, begrenzte Füllmenge und vollständiger Tank sind abgedeckt. Serviceobjekte stehen nicht in Fahrspuren oder unter dem Boden.
* Performanceziel auf **vorab protokollierter Referenzhardware**: 1080p, ein Referenzwagen, Referenzkarte, 60 Sekunden Fahrt, **P95-Bildzeit ≤16,7 ms** und Physik mindestens **1× Echtzeit**. GPU/CPU, Renderer, Qualitätsstufe und Fahrzeuganzahl gehören zum Ergebnis. Cloud-Software-Rendering ist kein Ersatz für diesen GPU-Benchmark.

## Fertig bedeutet nachgewiesen

Für jede Zeile im Abnahmeprotokoll stehen **bestanden**, **fehlgeschlagen** oder **noch nicht geprüft**, dazu Bild/Video oder Messdatei. Ein Headless-Test kann Funktionsverhalten belegen, aber keine hochwertige Modellierung. Erst wenn das Referenzfahrzeug die visuelle und mechanische Abnahme erfüllt, folgen weitere Autos und der Ausbau aller Karten.
