# Produktziel: eine vollständige, überzeugende Fahrsimulation

Das Ziel ist ein zusammenhängendes Spiel: ein glaubwürdiges Auto auf einer ausgearbeiteten Karte, mit nachvollziehbarer Bedienung, nutzbarem Schaden, Reparatur/Tanken, Fahraktivitäten und gespeichertem Fortschritt. Neue Einzeloptionen erfüllen dieses Ziel erst, wenn sie gemeinsam spielbar und überprüft sind.

Die erste Abnahme konzentriert sich auf **ein Referenzfahrzeug und ein Testgelände mit Servicebereich**. Das vorhandene CarConcept liefert kurzfristig eine importierte visuelle Vergleichsbasis; die langfristige Referenzfahrzeugwahl und deren Kriterien stehen in [VEHICLE_QUALITY_TARGET.md](VEHICLE_QUALITY_TARGET.md). Alle anderen Autos und Karten folgen erst nach dieser Abnahme. BeamNG-Funktionsquellen stehen in [BEAMNG_REFERENCE.md](BEAMNG_REFERENCE.md).

## Gegenwärtige Lücke

Vorhanden sind eine native Node-Beam-Simulation, datengetriebene Fahrzeuge, mehrere prozedurale Karten, Schaden an technischen Systemen, ein HUD sowie einzelne Aktivitäten und gespeicherte Bestleistungen. Das ist eine technische Grundlage. Es ist noch kein Nachweis durchgehend hochwertiger Modelle, stabilen Fahrverhaltens, physikalisch abtrennbarer Karosserieteile, fertiger Innenräume, ausgearbeiteter Karten oder eines vollständigen Spielverlaufs.

Die laufende Erweiterung von Motorraumdetails, Licht, Tanken und Wetter ist eine erste Iteration. Jedes neue Element braucht die nachstehenden Integrationsprüfungen. Das Dokument setzt das Ziel; es bescheinigt keinen Fertigstellungsstand.

## Priorisierte Meilensteine

| Priorität | Ergebnis | Abnahme |
|---|---|---|
| 1 | **Referenzauto sieht aus und fährt wie ein fertiges Fahrzeug.** Importmaßstab, Materialien, Reifen, Cockpit, Motorraum und Unterboden sind konsistent; Lenkung und Hochgeschwindigkeitsfahrt stabil. | Screenshotserie, Fahrvideo und Messfahrten gemäß Fahrzeugziel; keine übersehene Importgeometrie, kein verdecktes Zittern. |
| 2 | **Schaden ist sichtbar und spielerisch relevant.** Haube/Tür/Stoßfänger können öffnen beziehungsweise abreißen; darunter liegen ausgearbeitete Teile. Defekte beeinträchtigen konkrete Funktionen. | Frontal-/Seitencrash, Weiterfahrt, vollständige Reparatur, erneute Fahrt. Lose Teile bleiben physikalisch nachvollziehbar. Keine bloße Delle als Ersatz für Bauteiltrennung. |
| 3 | **Eine Karte trägt die komplette Spielschleife.** Teststrecke mit verschiedenen Straßenbelägen, glaubwürdigen Rändern und Höhenübergängen, Beschilderung, Servicehof, Tankstelle, Nachtbeleuchtung. | Jede befahrbare Stelle stimmt visuell mit Kollision überein; Service ist erreichbar und liegt außerhalb der Strecke. Beleuchtung und Navigation führen dorthin. |
| 4 | **Eine zusammenhängende Fahrsitzung funktioniert.** Einstieg → Auto wählen → kurze Einführung → freie Fahrt → Zeitfahren/Bremsprüfung → Schaden → Service → Ergebnis. | Neue Person erreicht alle Schritte aus dem Hauptmenü ohne Entwicklerkonsole; Ziele, Bedienelemente, Erfolg/Abbruch und Rückkehr sind klar. |
| 5 | **Fortschritt und Einstellungen bleiben erhalten.** Fahrzeug-/Kartenwahl, Steuerungs-/Grafikeinstellungen, Bestleistungen und abgeschlossene Einführungsziele sind versioniert gespeichert. | Anwendung schließen und neu starten; Fortschritt laden; ungültige/ältere Speicherdatei sicher behandeln; Neustart-/Zurücksetzen-Option nachvollziehbar. Bestehende Bestzeiten allein sind noch keine vollständige Fortschrittsstruktur. |
| 6 | **Wetter, Audio und Nacht ergeben ein Gesamtbild.** Regen, Nassgrip, Sicht, Reifen-/Motor-/Umweltklang und Lichter passen zusammen. | Dieselbe Strecke bei trocken/nass und Tag/Nacht; Pause/Zeitlupe, Innen-/Außenkamera und Grafikprofile prüfen. Regen fällt nicht durch ein geschlossenes Dach; Nassgrip verändert Bremsweg nachvollziehbar. |
| 7 | **Auslieferbare Qualität.** Bedienung, Performance, Fehlerbehandlung und Paketstart sind belastbar; anschließend weitere Autos/Karten auf denselben Standard bringen. | Sauberer Linux-Spielstart ohne Editor, 30 Minuten kombinierte Fahrsitzung ohne Absturz, protokollierte GPU-Bildzeiten und Echtzeitphysik, verständliche Steuerungsübersicht. Weitere Plattformen separat nachweisen. |

## Konkrete Referenzsitzung

1. Hauptmenü öffnen, Referenzauto und Testgelände auswählen. Laden zeigt Fortschritt und liefert eine spielbare Kamera.
2. Eine kurze Einführung erklärt Starten, Fahren, Bremsen, Schalten, Kamera und Licht. Sie lässt sich überspringen und später wiederholen.
3. Freie Fahrt führt zu einer markierten Bremsprüfung. Ergebnis zeigt Ausgangstempo, Bremsweg und gültig/ungültig; Bestleistung wird gespeichert.
4. Der Spieler fährt einen Crashversuch, erkennt den Schaden außen und in der Diagnose und erreicht den Service oder nutzt eine erklärte Bergungsfunktion.
5. Reparatur stellt Geometrie, lose Teile und Systeme konsistent wieder her. Tanken verändert nur den Tankinhalt und hat sichtbaren Fortschritt.
6. Spieler startet ein kurzes Zeitfahren, beendet oder bricht es nachvollziehbar ab und kehrt ins Menü zurück.
7. Nach Neustart sind Einstellungen und Ergebnis vorhanden; ein weiterer Lauf funktioniert unverändert.

Die Sitzung wird sowohl per Tastatur als auch mit Gamepad geprüft. Ein fehlendes Eingabegerät wird als ungetestet dokumentiert, nicht als bestanden.

## Arbeitsweise und Abschluss

Jede Iteration liefert eine spielbare Änderung, eine passende Funktionsprüfung und Bild-/Videonachweise für sichtbare Verbesserungen. Probleme aus dieser Prüfung haben Vorrang vor weiteren Funktionslisten. Kein Meilenstein gilt als abgeschlossen, solange sein Kernziel nur geplant, simuliert oder ausschließlich im Headless-Modus geprüft wurde.

Ein einfaches Abnahmeprotokoll verwendet je Meilenstein: **Status**, **konkrete Änderung**, **Nachweis**, **offene Fehler**, **nächster Schritt**. Es gibt keine pauschale Behauptung „vollwertiges Spiel“ vor Bestehen der kompletten Referenzsitzung und der technischen Qualitätsziele.
