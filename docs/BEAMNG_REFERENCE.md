# Referenz und schrittweise Produktüberarbeitung

Recherche vom 8. November 2026. BeamNG dient als Funktions- und Qualitätsreferenz; SoftBodyDriver behält eigene Fahrzeuge, Karten und Gestaltung. Diese Notiz trennt belegte Referenzen von vorgeschlagenen Produktentscheidungen. Sie ist keine Behauptung, dass die unten genannten Ausbauziele bereits implementiert sind.

## Tatsächlich geprüfte öffentliche Quellen

Die folgenden Dateien wurden aus offiziellen BeamNG-GitHub-Repositories gelesen:

* [BeamNGpy: Fahrzeugbeleuchtung](https://github.com/BeamNG/BeamNGpy/blob/0c7009e2da87019bed5278f7f9e07f242b89469b/src/beamngpy/api/vehicle/root.py): `set_lights` behandelt linken/rechten Blinker und Warnblinker separat; Scheinwerfer akzeptieren drei Zustände (0, 1, 2). Das belegt die API-Funktionen, jedoch keine konkreten Standardtasten oder HUD-Symbole.
* [BeamNGpy: Umwelt](https://github.com/BeamNG/BeamNGpy/blob/0c7009e2da87019bed5278f7f9e07f242b89469b/src/beamngpy/api/beamng/environment.py): Uhrzeit, Tageslänge und getrennte Tag-/Nachtgeschwindigkeiten sind steuerbar. Wetter-Presets verändern mehrere Einstellungen wie Uhrzeit, Wind und Bewölkung gemeinsam und erlauben Übergangszeiten. Die Dokumentation verweist ausdrücklich auf BeamNG.tech; daraus folgt keine Zusicherung eines identischen Regenmenüs in jeder BeamNG.drive-Version.
* [BeamNGpy: struktureller Schaden](https://github.com/BeamNG/BeamNGpy/blob/0c7009e2da87019bed5278f7f9e07f242b89469b/src/beamngpy/sensors/damage.py): Der Damage-Sensor liefert strukturelle Schadensinformationen und verarbeitet bauteilbezogene Schadensdaten. Das ist keine Spezifikation des internen Lösers.
* [BeamNG: Blender JBeam Editor](https://github.com/BeamNG/Blender-JBeam-Editor/blob/240af8826dfd006a9c630805b734f096bcfc3182/README.md): Import ganzer Fahrzeuge oder einzelner Teile, Bearbeitung von Nodes sowie Beams, Dreiecken und Quads, anschließend Export. Das zeigt, warum hochwertige sichtbare Geometrie und bearbeitbare physikalische Struktur gemeinsam benötigt werden. Das Plugin ist für JBeam gedacht; SoftBodyDrivers eigenes Format braucht einen eigenen Export-/Importweg.

Der Zugriff auf `documentation.beamng.com` wurde für die Bereiche Benutzeroberfläche, Fahrzeugsteuerung, JBeam und World Editor versucht, aber vom Cloud-Proxy mit HTTP 403 abgelehnt. Deshalb wurden aktuelle BeamNG-HUD-Layouts, UI-Apps, Screenshots und Tastenbelegungen **nicht visuell verifiziert**. Die folgende HUD-Richtung ist ein eigener Vorschlag, keine behauptete pixelgenaue Rekonstruktion. In der anschließenden Recherche wurde ein offizielles historisches BeamNG.drive-0.24.0.2-Bild mit sichtbarem HUD gefunden und visuell geprüft; Quelle und konkrete Beobachtungen stehen in [VEHICLE_QUALITY_TARGET.md](VEHICLE_QUALITY_TARGET.md). Das belegt weiterhin kein aktuelles HUD-Layout.

## Ausgangslage im Repository

Die Begutachtung vor dieser Überarbeitungsrunde zeigt bereits C++-Node-Beam-Physik, Pressure-Wheels, plastische Verformung und Bruch, Antriebsstrang, Kühl-/Öl-/Kraftstoffsysteme sowie einen Godot-Flexbody. Manuelles Schalten und Kupplungsschäden existieren bereits. Das Problem ist daher nicht das vollständige Fehlen von Simulation.

* `core/src/car_visual.cpp`: weitgehend prozedurale Geometrie; mehr Material- und Bauteildetails allein ersetzen noch kein sorgfältig modelliertes Referenzfahrzeug.
* `gdextension/src/sb_vehicle.cpp`: Physik-Snapshots werden in deformierte Renderflächen umgesetzt. Zittern muss zwischen instabiler Physik, zeitlich ungleichmäßigen Snapshots und Kamera-/Renderbewegung unterschieden werden.
* `game/scripts/hud.gd`: kompakte Fahrdatenkarte, Statuswarnungen, Diagnose und Hilfe vorhanden. Ergänzungen benötigen klare Zustandsanzeigen und konsistente Tastenerklärungen.
* `game/scripts/maps/` und `map_builder.gd`: prozedurale Karten. Mehr Einzelobjekte ohne Fahrbahn-, Höhen-, Kollisions- und Performanceprüfung ergeben noch keine hochwertige Spielwelt.

## Reihenfolge und Abnahmekriterien

1. **Ein Referenzfahrzeug fertig ausarbeiten.** Kestrel außen, Cockpit, Motorraum und Unterboden in denselben Maßstab bringen. Getrennte Haube/Türen/Glas, plausible Materialrauheit, sichtbare Dichtungen und Befestigungen. Abnahme: Nahaufnahmen aus mehreren Winkeln bei Tag/Nacht, Innenkamera und beschädigter Zustand. Danach erst die übrige Flotte anpassen.
2. **Fahrstabilität messen.** Geradeauslauf, Bremsung, Kurven und Bodenwellen bei mehreren Geschwindigkeiten reproduzierbar testen. Rad-/Karosserieschwingung und Render-Snapshot-Timing getrennt messen. Keine pauschale Glättung, die physikalische Instabilität lediglich versteckt.
3. **Bauteile statt einer einzigen Hülle.** Haube mit Scharnieren und Schloss, Türen mit Innenflächen, abreißbare Stoßfänger und Kotflügel benötigen eigene Bindungen, Kollisionsverhalten und Bruchregeln. Abnahme: Teil kann öffnen, sich verformen, lösen und liegen bleiben; darunter ist fertige Geometrie; Reparatur stellt konsistent alles wieder her. Eine animierte Haube allein erfüllt dieses Ziel nicht.
4. **Bedienung und HUD vervollständigen.** Geschwindigkeit, Drehzahl und Gang gut lesbar gruppieren; Blinker, Warnblinker, Licht und Motorzustand direkt sichtbar. Mechanische Diagnose bleibt separat. Nachtlesbarkeit, kleine Fenster, Cockpitansicht und Tastaturkonflikte prüfen. Tankstelle als räumliche Interaktion mit Stillstand/Motorzustand und nachvollziehbarem Fortschritt.
5. **Eine Karte zur Referenzkarte machen.** Fahrbahnübergänge, Bankette, Entwässerung, Beschilderung, Leitplankenenden, Vegetationsgruppen und Tankstellenhof bewusst gestalten. Fahrbare Kollisionen müssen der sichtbaren Geometrie entsprechen. Erst danach weitere Karten ausbauen.
6. **Wetter und Tageszeit verknüpfen.** Sonne/Himmel, Umgebungslicht, Straßenlaternen und Scheinwerfer gemeinsam prüfen. Regen braucht mehr als Partikel: Sichtweite, Oberflächenwirkung, Audio und später belastbar getesteten Nassgrip. Ein reiner Regen-Effekt darf nicht als vollständige Wettersimulation beschrieben werden.
7. **Spielschleifen und Qualität absichern.** Einstellungen, Eingabegeräte, Speichern/Laden, Tutorials, Aktivitäten, Audio, Performance-Budgets und reproduzierbare Crash-Szenarien. Abnahme umfasst spielbare Desktop-Tests; Headless-Tests belegen keine Bildqualität.

## Grenzen dieser Iteration

Ein vollständig ausgearbeitetes kommerzielles Fahrzeugspiel entsteht über mehrere überprüfbare Iterationen. Neue Funktionen und bestandene Tests belegen nur ihren jeweiligen Umfang. Fotorealistische Modelle, alle Karten, physikalisch abtrennbare Karosserieteile und ein vollständiger Spielmodus dürfen erst nach eigener Umsetzung und Abnahme als fertig gelten. Für die nächste visuelle Referenzrunde ist Zugriff auf die offizielle BeamNG-Dokumentation oder bereitgestelltes Bildmaterial erforderlich.
