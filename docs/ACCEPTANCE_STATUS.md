# Abnahmestand – 10. November 2026

Die laufende Referenz ist Kestrel Hatch auf dem Testgelände. Die Zielkriterien in
[PRODUCT_TARGET.md](PRODUCT_TARGET.md) bleiben verbindlich; dieser Stand belegt
konkrete Teilergebnisse und erklärt das Gesamtprodukt noch nicht für fertig.

| Bereich | Nachgewiesene Änderung | Noch offen |
|---|---|---|
| Fahrzeugdarstellung | Kennzeichen vorn und hinten an allen Fahrzeugen (an der Karosserie mitbewegt, `plates_test`); Abgerundetes Cockpit, Instrumente mit realer Telemetrie, sichtbarer Motorraum unter gestützter Haube; Tages-/Nachtbilder in 1920×1080 geprüft; echte Cockpit-Außenspiegel mit korrigierter Kestrel-Blickrichtung; Innenraum mit konturierten Sitzen, Rückbank, Gurten, Teppich, Dachhimmel, Pedalen; Unterboden mit Abgasanlage, Hitzeschild, Trägern und Radhausschalen (auch für importierte Modelle) | Handmodellierte Detailqualität, vollständige Referenzbildserie |
| Teile und Schaden | Kestrel-Stoßfänger vorn/hinten besitzen eigene Käfige/Masse, brechbare Halter und unabhängige Darstellung; Haube stößt gegen eigene Dach-/Motorflächen; Kestrel-Vordertüren öffnen/schließen mit getrennten Schlössern und Scharnieren und können abreißen; Scheinwerfer und Rückleuchten gehen je Ecke mit der Verformung der Karosserie kaputt und bleiben bis zur Reparatur dunkel (`lamp_damage_test`); Stoßfänger hängen an vier Clipgruppen (6 kN) und reißen eckweise ab, die Gegenseite bleibt bei Aufprallen dran; Türen mit getrennten Scharnieren (12 kN) und Schlössern (10 kN): beim Seitenaufprall bleibt die abgewandte Tür zu (`a side impact leaves the far door shut…`); viertürige Karosserien haben eigene Hintertüren (vom hinteren Radlauf bis vor die B-Säule, Scharniere an der B-Säule, Schlösser, Öffnung auf 62°, Türverkleidung, Scheibe und Rahmen wandern mit; Pausenmenü „Hintertüren öffnen / schließen“), auch bei den importierten Meridian-Limousinen, dem Estate und dem Trailhead entlang der Scharnier- und Fugenlinien des Modells (`frontDoorHingeX`, `bPillarX`, `rearDoorHingeX`, `rearDoorRearX`); Heckklappe (Estate, Trailhead mit Reserverad) bzw. Kofferraumdeckel (Limousinen, Fastback) als eigenes Bauteil an den Modellscharnieren mit Scharnier-/Schlossbruchgruppen und Gasdruckfedern auf Kanal 6, öffnet im Stand auf ~80° bzw. ~70° (`tailgate and boot lid release…`, `tailgate_test`, `Shift`+`O`); Haube und Heckklappe haben wie die Türen ein reversibles Schloss: erneutes `O`/`Shift`+`O` senkt sie ab, das Schloss fängt die Klappe auch zugeschlagen und zieht sie zu (`bonnet and tailgate open on their struts, close again and relatch…`); ein Heckaufprall mit 50 km/h lässt das Heckklappenschloss aufspringen, die Klappe bleibt als Teil an den Scharnieren; importierte Modelle werden an ihren Rädern auf die Achsen ausgerichtet (der Trailhead saß 18 cm vor seinen Rädern); Auto-gegen-Auto: nach einem Auffahrunfall lösen sich die Karosserien wieder – früher verhakte sich ein Knoten in einer Falte der anderen Haut (gegenläufige Flächen, nach innen zeigende Splitterdreiecke am Heck), beide fuhren als Einheit und wurden dann weggeschleudert; jetzt löst jeder Knoten nur noch seinen besten Kontakt auf, und die Hautdreiecke zeigen auch an Bug und Heck nach außen (`a rear-ended car drives away…`, 24 Auffahrszenarien geprüft); Scheiben reißen spinnennetzartig vom Aufprallpunkt aus, Seiten- und Heckscheiben platzen heraus; Splitter von Leuchten, Clips und Türen; Bordsteinschläge: ein Laufflächenpunkt über dem 4,5-fachen der statischen Radlast verbiegt die Felge (Leck), sehr harte Schläge schlitzen den Reifen; seitlich mit 30 km/h gegen einen 12-cm-Bordstein ist der Reifen platt, mit 12 km/h passiert nichts (`sliding a wheel into a kerb…`); Spurstangen geben ab 45 kN nach | Kompatible Segmentierung des importierten Concept (Haube, Türen, Heck); allgemeiner Kantenkontakt; Auffahrunfall, bei dem ein hohes SUV auf das Heck eines Kombis aufsteigt und dort liegen bleibt (physikalisch plausibel, aber unrealistisch weit); mit gehaltener Betriebsbremse und Handbremse zugleich blieb eine Hintertür nach dem Schließen 2–4° vor dem Schloss stehen (verspannte Karosserie an der Fuge); Auto Hold gibt deshalb bei gezogener Handbremse die Betriebsbremse frei, die Ursache an der Türfuge ist offen |
| Fahrphysik | Alle sieben nativen Prüfstände bestehen Einfedern, Beschleunigen, Bremsen und Kurvenfahrt. Fahrwiderstand kalibriert (Kestrel 100 km/h: 1.910 → 498 N), Reifenmembran ohne Stehwellen-Resonanz, starrer Radträger, Federbeindom, Achsträger, Mischbereifung Concept (achsweise Reifenmasse, kein Pendeln mehr): Vollgas-Spitzen 197–338 km/h, alle Fahrzeuge geradeaus bis zur Höchstgeschwindigkeit ([Messung](DRIVING_RESISTANCE.md)); Überdrehzahl schadet dem Motor: „Geldschaltung" mit 150 km/h in den 1. Gang zerstört ihn (Pleuel), kostet ~55 % Getriebe und Kupplungsbelag, vernünftiges Zurückschalten bleibt folgenlos (`a money shift into 1st…`); Motorschäden wie bei BeamNG: Pleuellager (Klopfen bis Pleuelriss), Kolbenringe (Ölverbrennung), Ölmangel bei wenig Öl in Kurven, Fahrzeugbrand (`oil on a hot engine…`, `fire_test`); Bremsen halten statisch am Hang: voll gebremst bei 30 %, nur mit Handbremse bei 20 % keine Bewegung und kein Schaukeln (Haltebremse als gedämpfte Winkelfeder bis zum Klemmmoment, Haftreibung auch auf Positionsebene; vorher kroch ein gebremstes Auto bei 15 % mit 1,5 km/h, `brakes hold a car on a steep hill…`) | Rollwiderstand noch ~60 % über real (Ausrollwiderstand gesamt ~15 % über real); Renderfrequenz-Vergleich und Langzeitfahrt mit mehreren beschädigten Fahrzeugen |
| Testgelände | Freie Bremsgerade als Start, Wegweiser, Servicezufahrt, Nachtlampen, kollidierende Dächer, bepflanzte Innenflächen, Geländebermen und Randbegrenzung; rot-weiße Curbs in beiden Ovalkurven, kollidierende Reifenstapel hinter der Auslaufzone, Tribüne mit Dach und Fahnen an der Nordgeraden | – |
| Streckenabnahme (alle Karten) | `track_acceptance_test`: Die KI fährt das Spielerauto über die gesamte Strecke jeder Karte. Alle sechs Karten bestehen: vollständige Runde, höchstens 9,4 m Abweichung, kein Stillstand, kein Unfall, kein Schaden. Werte: Testgelände 1,2 km / 69 km/h, Autobahn 8,4 km / 105 km/h, Stadt 2,8 km / 33 km/h, Hügelland 2,6 km / 59 km/h, Offroad 3,2 km / 28 km/h (Trailhead 4x4), Wüste 3,8 km / 63 km/h (Kestrel Rally). Gefundene und behobene Fehler: Bäume auf der Autobahn (sichtbar erst, seit Bäume kollidieren), Aussichtszaun quer über dem Offroad-Rundkurs, Knick durch später eingefräste Seitenwege, Wüsten-Rallyeschleife mit Steigungen bis 28 % an der Tafelbergkante (jetzt höchstens 10 %), Ölwanne, die schon durch normale Feldwegstöße undicht wurde | Manuelle Referenzfahrt mit realem Gamepad |
| Spielablauf | Einführung → gemessene Bremsung → Bergung → Reparatur → Tanken → gespeicherten Abschluss neu laden; Aktivitäten und Wetter auch über Pausenmenü bedienbar; Rennen gegen zwei KI-Gegner mit Startaufstellung, Countdown, Positionsanzeige und Platzierung (`race_test`); Abstimmung von Reifendruck je Achse und Bremsbalance im Pausenmenü (`tuning_test`); Auto Hold der Automatik (`auto_hold_test`); Hupe; Crashtest auf dem Testgelände: Aufprall, Verzögerung, Front- und Zellenschaden, Sterne (`crash_test_activity_test`: Kestrel mit 62 km/h → 41 g, 4 Sterne) | Eine komplette manuelle Referenzsitzung einschließlich beendeter Zeitfahrrunde und realem Gamepad |
| Requisiten | Leitkegel, Stahlfässer, Wasserbarrieren, Mülltonnen (240 l, 15 kg) und gefällte Baumstämme (3 m, 380 kg) als Soft-Bodies (`props stand still…`, `a felled log is shoved or climbed…`, `prop_test`): stehen ruhig, ein Auto mit 40 km/h stößt Kegel und Fässer 20–25 m weit und verliert dabei < 2 km/h, auch bei seitlich versetztem Treffer (vorher blieb ein Kegel hängen: Löcher in der Bughaut an den Ecken und an der Haubenfuge ließen Knoten in den Motorraum, und ein über den Stoßfänger gespannter Kegel hob mit dem Fuß unter dem Vorderrad die Front an, bis zu −19 km/h; jetzt ist die Bughaut geschlossen und der hohle Kegel lässt sich flach drücken, dehnt sich aber nicht); ein Stamm wird geschoben, gerollt oder überklettert und ist nie schneller als das Auto (pro Körper begrenzte Kontakttiefe statt der allgemeinen 0,14 m, die dünne, steife Körper unter der Lauffläche einklemmte und wegschleuderte); Rücksetzen im Pausenmenü; Baustellen auf Autobahn, Hügelland und in der Stadt, Fässer in der Wüste, Stämme am Holzlager, am Waldweg und quer über dem 4x4-Pfad im Gelände; Streckenabnahme aller Karten mit Requisiten ohne Treffer; ruhende Requisiten schlafen (keine Integration, bis ein bewegter Körper ihre Hüllbox erreicht; `resting props fall asleep…`), so kosten die ~110 Requisiten der Stadt nichts; Reifen haben eine Kontaktfläche für fremde Körper; ein Reifen rollt über niedrige schwere Gegenstände (7-cm-Gummiblock, 25 kg: −0,7 km/h, statt ihn 15 m vor sich herzuschieben und von 38 auf 8 km/h abzubremsen: die im Latsch wenige Millimeter in die Fahrbahn gedrückten Profilknoten lagen unter der Unterseite des Gegenstands und hoben ihn an, bis er sich unter dem Rad aufstellte; nach unten weisende Flächen flacher Requisiten fangen keine fremden Knoten mehr, `a tyre rolls over a low heavy object…`) | Leitbaken: zwei Fassungen (25-kg-Gummifuß, 1-m-Tafel, auch mit herausziehbarem Stiel) gerieten bei Treffern in der Radspur unter ein Vorderrad, das dann stehen blieb und die Bake mitschleifte (−15 bis −24 km/h); zurückgestellt; ebenso selten ein Kegel unter einem Hinterrad (1 von 30 Trefferlagen); Äste |
| Karten | Wüste mit Tafelbergen (Schuttfuß, fast senkrechte Deckgesteinswand, flaches Plateau) statt gestreifter Kegel, die Rallyeschleife unverändert; Autobahn mit deutschem Querschnitt (Randstreifen am Mittelstreifen, drei 3,75-m-Fahrstreifen, 30-cm-Breitstrich, Standstreifen; Leitlinien 6 m / 12 m), Landstraßen mit weißer Leitlinie; Nachts unterschiedlich hell und warm/neutral/kühl beleuchtete Fenster (etwa jedes vierte Zimmer), Fahrradbügel statt schwebender Ringe; Lichtsensor schaltet das Abblendlicht aller Fahrzeuge (`auto_lights_test`); Dörfer und Höfe aus detaillierten Landhäusern (Lindenau im Hügelland, Dorf an der Autobahn, Bauernhöfe mit Scheunen), nachts mit beleuchteten Fenstern und Straßenlaternen; Raststätte in der Wüste; Stadt mit Sockeln, Gesimsen, Satteldächern, Dachaufbauten, Hinterhofgassen und detailliertem Reihenhausblock; Wüste mit Sandsteinschichtung und Pisten mit Schotterwällen, Waschbrett und Schlaglöchern; geschlossene Wälder in Offroad und Hügelland; Hügel am Autobahn-Horizont; Felsen mit Bruchflächen und Gesteinsshader; alle Bäume in Fahrweite kollidieren ([MAP_VISUALS](MAP_VISUALS.md)) | Handmodellierte Gebäude und Landmarken, Straßennetze statt einzelner Rundkurse |
| Wetter | Innenraum-/Dachvolumen halten sichtbaren Regen fern; Tageszeit, Pause, Zeitlupe und Nässe geprüft; Abblend-/Fernlicht visuell geprüft; Stereo-Regen mit Innenraum-/Dachdämpfung und tatsächlicher AudioServer-Aufnahme geprüft; lichtbrechende Regentropfen auf der Frontscheibe, die mit der Beregnung wachsen; Tandem-Scheibenwischer (Automatik/Aus/Dauer, Taste X oder Pausenmenü), die die überstrichene Fläche analytisch freiwischen und am Zyklusende parken (`wipers_test`, Fahrerblick-Render `rain_shots.gd`) | Verformungsgenaue Regenabdichtung, Fahrtwind-Tropfenlauf, subjektive Hörabnahme der neuen Regenakustik |
| Fortschritt | Versionierte Profile mit Sicherung/Wiederherstellung, Bremsrekorden, Einführungszielen und letzter Auswahl; Einstellungen bleiben erhalten; Medaillen (Bronze/Silber/Gold) für Zeitfahren, Lieferfahrt, Rennen und Crashtest, je Karte und Aktivität gespeichert, Zählung im Hauptmenü (`medals_test`) | Weiterer Spielverlauf (Freischaltungen, Karriere); Medaillen für die Drift-Challenge (keine feste Punkteskala) |
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
