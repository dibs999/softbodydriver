# Abnahmestand – 10. November 2026

Die laufende Referenz ist Kestrel Hatch auf dem Testgelände. Die Zielkriterien in
[PRODUCT_TARGET.md](PRODUCT_TARGET.md) bleiben verbindlich; dieser Stand belegt
konkrete Teilergebnisse und erklärt das Gesamtprodukt noch nicht für fertig.

| Bereich | Nachgewiesene Änderung | Noch offen |
|---|---|---|
| Fahrzeugdarstellung | Abgerundetes Cockpit, Instrumente mit realer Telemetrie, sichtbarer Motorraum unter gestützter Haube; Tages-/Nachtbilder in 1920×1080 geprüft; echte Cockpit-Außenspiegel mit korrigierter Kestrel-Blickrichtung; Innenraum mit konturierten Sitzen, Rückbank, Gurten, Teppich, Dachhimmel, Pedalen; Unterboden mit Abgasanlage, Hitzeschild, Trägern und Radhausschalen (auch für importierte Modelle) | Handmodellierte Detailqualität, vollständige Referenzbildserie |
| Teile und Schaden | Kestrel-Stoßfänger vorn/hinten besitzen eigene Käfige/Masse, brechbare Halter und unabhängige Darstellung; Haube stößt gegen eigene Dach-/Motorflächen; Kestrel-Vordertüren öffnen/schließen mit getrennten Schlössern und Scharnieren und können abreißen; Scheinwerfer und Rückleuchten gehen je Ecke mit der Verformung der Karosserie kaputt und bleiben bis zur Reparatur dunkel (`lamp_damage_test`); Stoßfänger hängen an vier Clipgruppen (6 kN) und reißen eckweise ab, die Gegenseite bleibt bei Aufprallen dran; Türen mit getrennten Scharnieren (12 kN) und Schlössern (10 kN): beim Seitenaufprall bleibt die abgewandte Tür zu (`a side impact leaves the far door shut…`); viertürige Karosserien haben eigene Hintertüren (vom hinteren Radlauf bis vor die B-Säule, Scharniere an der B-Säule, Schlösser, Öffnung auf 62°, Türverkleidung, Scheibe und Rahmen wandern mit; Pausenmenü „Hintertüren öffnen / schließen“), auch bei den importierten Meridian-Limousinen, dem Estate und dem Trailhead entlang der Scharnier- und Fugenlinien des Modells (`frontDoorHingeX`, `bPillarX`, `rearDoorHingeX`, `rearDoorRearX`); Heckklappe (Estate, Trailhead mit Reserverad) bzw. Kofferraumdeckel (Limousinen, Fastback) als eigenes Bauteil an den Modellscharnieren mit Scharnier-/Schlossbruchgruppen und Gasdruckfedern auf Kanal 6, öffnet im Stand auf ~80° bzw. ~70° (`tailgate and boot lid release…`, `tailgate_test`, `Shift`+`O`); importierte Modelle werden an ihren Rädern auf die Achsen ausgerichtet (der Trailhead saß 18 cm vor seinen Rädern); Scheiben reißen spinnennetzartig vom Aufprallpunkt aus, Seiten- und Heckscheiben platzen heraus; Splitter von Leuchten, Clips und Türen | Heckklappe der prozeduralen Kestrel-Karosserie (Segmentierung des Heckmeshes) und kompatible Segmentierung des importierten Concept; Schließen von Haube/Heckklappe ohne Reparatur; allgemeiner Kantenkontakt; Auto-gegen-Auto-Kontakt: nach einem Auffahrunfall mit ~17 km/h Differenz verhakten sich zwei Karosserien, fuhren ~150 s als Einheit und wurden dann auf fast 100 km/h geschleudert (Eindringtiefe/Trennung der Kollisionsdreiecke untersuchen) |
| Fahrphysik | Alle sieben nativen Prüfstände bestehen Einfedern, Beschleunigen, Bremsen und Kurvenfahrt. Fahrwiderstand kalibriert (Kestrel 100 km/h: 1.910 → 498 N), Reifenmembran ohne Stehwellen-Resonanz, starrer Radträger, Federbeindom, Achsträger, Mischbereifung Concept (achsweise Reifenmasse, kein Pendeln mehr): Vollgas-Spitzen 197–338 km/h, alle Fahrzeuge geradeaus bis zur Höchstgeschwindigkeit ([Messung](DRIVING_RESISTANCE.md)) | Rollwiderstand noch ~60 % über real (Ausrollwiderstand gesamt ~15 % über real); Renderfrequenz-Vergleich und Langzeitfahrt mit mehreren beschädigten Fahrzeugen; Bremsen halten am steilen Hang nicht statisch: bei 15 % kriecht ein voll gebremstes Auto mit ~1,3 km/h, weil die Reibung nur auf Geschwindigkeitsebene nach dem Positionsschritt wirkt (eine positionsgenaue Haftreibung wurde erprobt; sie hält, regt aber im Stand ein Längsschaukeln von ±4 cm über die Reifenkarkasse an und wurde verworfen; auch nur für das gebremst stehende Auto angewandt schaukelt es um ~5 cm und kriecht noch 0,3 m in 4 s – nötig wäre ein gedämpftes Haftmodell mit Ankerpunkten je Profilknoten) |
| Testgelände | Freie Bremsgerade als Start, Wegweiser, Servicezufahrt, Nachtlampen, kollidierende Dächer, bepflanzte Innenflächen, Geländebermen und Randbegrenzung; rot-weiße Curbs in beiden Ovalkurven, kollidierende Reifenstapel hinter der Auslaufzone, Tribüne mit Dach und Fahnen an der Nordgeraden | – |
| Streckenabnahme (alle Karten) | `track_acceptance_test`: Die KI fährt das Spielerauto über die gesamte Strecke jeder Karte. Alle sechs Karten bestehen: vollständige Runde, höchstens 9,4 m Abweichung, kein Stillstand, kein Unfall, kein Schaden. Werte: Testgelände 1,2 km / 69 km/h, Autobahn 8,4 km / 105 km/h, Stadt 2,8 km / 33 km/h, Hügelland 2,6 km / 59 km/h, Offroad 3,2 km / 28 km/h (Trailhead 4x4), Wüste 3,8 km / 63 km/h (Kestrel Rally). Gefundene und behobene Fehler: Bäume auf der Autobahn (sichtbar erst, seit Bäume kollidieren), Aussichtszaun quer über dem Offroad-Rundkurs, Knick durch später eingefräste Seitenwege, Wüsten-Rallyeschleife mit Steigungen bis 28 % an der Tafelbergkante (jetzt höchstens 10 %), Ölwanne, die schon durch normale Feldwegstöße undicht wurde | Manuelle Referenzfahrt mit realem Gamepad |
| Spielablauf | Einführung → gemessene Bremsung → Bergung → Reparatur → Tanken → gespeicherten Abschluss neu laden; Aktivitäten und Wetter auch über Pausenmenü bedienbar; Rennen gegen zwei KI-Gegner mit Startaufstellung, Countdown, Positionsanzeige und Platzierung (`race_test`); Abstimmung von Reifendruck je Achse und Bremsbalance im Pausenmenü (`tuning_test`); Auto Hold der Automatik (`auto_hold_test`); Hupe | Eine komplette manuelle Referenzsitzung einschließlich beendeter Zeitfahrrunde und realem Gamepad |
| Karten | Dörfer und Höfe aus detaillierten Landhäusern (Lindenau im Hügelland, Dorf an der Autobahn, Bauernhöfe mit Scheunen), nachts mit beleuchteten Fenstern und Straßenlaternen; Raststätte in der Wüste; Stadt mit Sockeln, Gesimsen, Satteldächern, Dachaufbauten, Hinterhofgassen und detailliertem Reihenhausblock; Wüste mit Sandsteinschichtung und Pisten mit Schotterwällen, Waschbrett und Schlaglöchern; geschlossene Wälder in Offroad und Hügelland; Hügel am Autobahn-Horizont; Felsen mit Bruchflächen und Gesteinsshader; alle Bäume in Fahrweite kollidieren ([MAP_VISUALS](MAP_VISUALS.md)) | Handmodellierte Gebäude und Landmarken, Straßennetze statt einzelner Rundkurse |
| Wetter | Innenraum-/Dachvolumen halten sichtbaren Regen fern; Tageszeit, Pause, Zeitlupe und Nässe geprüft; Abblend-/Fernlicht visuell geprüft; Stereo-Regen mit Innenraum-/Dachdämpfung und tatsächlicher AudioServer-Aufnahme geprüft; lichtbrechende Regentropfen auf der Frontscheibe, die mit der Beregnung wachsen; Tandem-Scheibenwischer (Automatik/Aus/Dauer, Taste X oder Pausenmenü), die die überstrichene Fläche analytisch freiwischen und am Zyklusende parken (`wipers_test`, Fahrerblick-Render `rain_shots.gd`) | Verformungsgenaue Regenabdichtung, Fahrtwind-Tropfenlauf, subjektive Hörabnahme der neuen Regenakustik |
| Fortschritt | Versionierte Profile mit Sicherung/Wiederherstellung, Bremsrekorden, Einführungszielen und letzter Auswahl; Einstellungen bleiben erhalten | Weiterer Spielverlauf über Einführung und vorhandene Aktivitäten hinaus |
| Linux-Paket | Wiederholbarer Export mit Debug-/Release-Bibliothek, offiziellen geprüften Templates, Credits und isolierter Standalone-Prüfung | GPU-Benchmark, 30-minütige kombinierte Fahrsitzung, ältere Distributionen und andere Betriebssysteme |

## Funktionale Prüfungen

* Native Kernprüfung: **80 Testfälle, 85.724 Assertions bestanden**. Darin echte
  Aufprallversuche, Haubenstabilität, Kontaktimpulse und Reparaturzustände.
* Alle sieben `cartest … --quick`-Prüfstände: `RESULT: OK`.
* Erweiterter Headless-Belastungstest: **30 Minuten 1,75 Sekunden simuliert**
  in **5 Minuten 5,753 Sekunden Laufzeit**. **51 vollständige Zyklen** mit echter
  Beschleunigung über 70 km/h, Bremsung, Öffnen und erneutem Verriegeln beider
  Vordertüren, Aufprall an der Crashwand, Bergung mit erhaltenem Schaden,
  Service-Reparatur und Kraftstoffabgabe. Wetter, Tageszeit, Licht und Kameras
  wechselten wiederholt. Physikwerte, Tankgrenzen, Fahrzeugzugehörigkeit und
  Szenen-Node-Anzahl blieben gültig; keine Fehler oder Warnungen.
  Audioverarbeitung und GPU-Darstellung gehören nicht zu diesem Test.
  Wiederholung: `session_soak_test.gd`.
* Türbedienung: **20 Prüfungen**; Cockpitinstrumente einschließlich Türwarnung:
  **15 Prüfungen**; Tür-/Regen-/Akustikintegration: **8 Prüfungen** bestanden.
  Die normale Türbewegung erhält vorhandene Schäden und Tankinhalt.
* Spiegelintegration: **42 Prüfungen** für optische Flächen, Blickrichtung,
  Projektionsgrenzen, Fahrzeugwechsel und stabile Abbildung zwischen Aufnahmen
  sowie mitbewegte Spiegelflächen beim tatsächlichen Türöffnen bestanden.
  Kestrel-Spiegelglas und Gehäuse sind am Modell zum rückwärtigen
  Horizont ausgerichtet; Concept verwendet seine vorhandene Spiegelgeometrie.
* Regenakustik: **14 Prüfungen** einschließlich tatsächlicher Master-Bus-Aufnahme
  bestanden. Die Aufnahme ist bei aktivem Regen hörbar ausgesteuert und bei
  Hauptlautstärke null exakt stumm. Eine subjektive Hörabnahme ist separat offen.
* Godot-Prüfungen umfassen Fahrsteuerung, Aktivitäten, importiertes Modell,
  Fahrerassistenz, Gamepad-Ereignisse, Cockpit, Service, Wetter, Kartenzugang,
  Einführung und gespeicherte Profile. Befehle stehen in der README.
* Zeitfahren: Zwei native Prüfrunden bestehen jeweils **12 Prüfungen** inklusive
  Pause, gültigem Abschluss, Profil-/Rekord-Neuladen sowie Reparatur-/Versetzungs-
  abbruch. Beide fahren die unveränderte Ovalstrecke über **26 Kontrollpunkte**
  in **102,75 Sekunden**, über **1.162 m**, ausschließlich über native Lenk-/Gas-/
  Bremseingaben eines Prüfautopiloten. Die zweite Runde verwendet einen nicht
  schreibbaren Rekordpfad und meldet den Fehler korrekt. Das ist keine manuelle
  Fahrabnahme mit einem neuen Spieler.
* Gemessene Kestrel-Bremsung über den tatsächlichen Untergrund-/Reifengriffpfad:
  trocken **16,89 m aus 60,194 km/h**, nass **19,45 m aus 60,000 km/h**;
  beide Läufe ohne gebrochene Beams. Das ist ein Regressionsvergleich, keine
  Messung an einem realen Fahrzeug.

## Bildprüfung und Grenzen

Die aktuelle Cloud-Prüfung verwendet Godot 4.5.1 mit Software-OpenGL/llvmpipe.
Geprüft wurden Fahransicht, Cockpit, Service, Nachtlicht, Regen unter Dächern und
geöffnete Haube. Die neue Türserie zeigt eine tatsächlich um 68,36° geöffnete
Tür, erneutes Verriegeln bei 0,01°, Abtrennung nach einem Fahrzeug-Seitenaufprall
und Reparatur. Scheibe, Innenverkleidung und Spiegel bleiben am Türkäfig; die
Öffnung ist frei von zurückbleibender Außenhaut. Beide Fahrzeuge zeigen im
Cockpit echte Spiegelbilder bewegter und umgefärbter Weltobjekte. Der Kestrel
zeigt nach Korrektur der Glasneigung die Straße und Böschung hinter dem Auto;
beim Concept nimmt die eigene Karosserie noch einen großen Teil des Spiegels ein.
Die neue Zeitfahrserie zeigt die tatsächlich gefahrene Runde mit Zielführung,
Ergebnisanzeige und nach Profil-Neuladen sichtbarem Abschluss im Hauptmenü.
Cockpitaufnahmen in 1920×1080 und 960×600 prüfen die Abstände zwischen Ergebnis,
Serviceanzeige und Minikarte. Die Aufnahmen pausieren echte Simulationszustände;
Kontrollpunkte und Ziellinie wurden im Prüflauf tatsächlich durchfahren.
Ein mit tatsächlichen Gas-/Bremseingaben erstelltes Video fährt
von 0 auf 75,8 km/h und wieder bis zum Stillstand, ohne neue gebrochene Beams.
Seine wenigen Software-Renderbilder belegen
keine gleichmäßige Darstellung mit 60 FPS. Bildschirmfotos und Video liegen im
Arbeitsbereich unter `/workspace/.softbody-tools/visual/reference/`.

Gamepad-Prüfungen speisen echte Godot-Gamepad-Ereignisse ein, verwenden aber kein
physisches Eingabegerät. Headless-Testskripte melden teilweise weiterhin
ObjectDB-Aufräumwarnungen beim Prozessende; Script-/Enginefehler gelten als Fehler.
Der Paketprüfer erfordert einen erfolgreichen Standalone-Start beider Referenz-
fahrzeuge und eine Rückkehr ins Hauptmenü ohne Script-/Enginefehler.

Die Tür-/Spiegelbilder liegen unter
`/workspace/.softbody-tools/visual/doors-mirrors/`, die Regenaufnahmen unter
`/workspace/.softbody-tools/audio/`. Bei geöffneter oder fehlender Vordertür wird
aktuell der gesamte vereinfachte Innenraum-Regenausschluss aufgehoben. Das ist
keine verformungsgenaue Simulation von eindringendem Wasser an der Türöffnung.

## Neue Messreihe zum Chassis

Der [reproduzierbare Chassis-Prüfstand](CHASSIS_STABILITY_MEASUREMENTS.md)
zeichnet Kestrel und Concept bei Sollwerten von 50/100/160/200 km/h mit 2.000 Hz
auf. Schleppprüfstand, freies Ausrollen und normaler Antrieb werden getrennt
ausgewertet. Die Hochfrequenzgrenzen werden in den aufgezeichneten Fenstern
eingehalten. Der synthetische Concept-Schlepplauf bei 200 km/h ist wegen
Ausbrechens und überschrittenem Geschwindigkeitsband ungültig. Im normalen
Vollgasversuch erreichten Kestrel und Concept in 60 Sekunden zunächst nur etwa 113,70 bzw.
174,66 km/h (nach der Kalibrierung in [DRIVING_RESISTANCE.md](DRIVING_RESISTANCE.md):
~142 bzw. ~240 km/h). Das belegt eine noch offene Leistungs-/Verlustkalibrierung; es
bescheinigt weder stabile konstante 200 km/h noch eine bestandene Renderprüfung.

Die neue Zeitfahr-Bildserie liegt unter
`/workspace/.softbody-tools/visual/time-trial/`. Der aktualisierte Linux-Build
wurde auch nach separatem Entpacken mit einer vollständigen nativen Runde
und anschließendem Profil-/Rekord-Neuladen geprüft; Paketnachweise stehen in
[RELEASE_LINUX.md](RELEASE_LINUX.md).
