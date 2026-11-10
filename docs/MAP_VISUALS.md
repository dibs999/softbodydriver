# Kartenoptik: Himmel, Böden, Straßen und Vegetation

Stand: 9. November 2026. Diese Iteration geht die in den Kartenrendern (Forward+, Werkzeug
`tests/map_shots.gd`) sichtbaren Schwächen an: grauer Nebelhimmel, einfarbige Flächen mit sichtbarer
Kachelung und Bäume aus Kugeln und Kegeln.

## Himmel

* `shaders/sky.gdshader` mit `scripts/game_sky.gd` (`GameSky`): Farbverlauf, Mie-Halo um die Sonne,
  Sonnenscheibe und eine FBM-Wolkenschicht. Im Cubemap-Pass für das Umgebungslicht entfällt die
  Wolkenschicht.
* Das Wetter (`world_weather.gd`) steuert Bewölkung (klar/bewölkt/Regen), Wolkenhelligkeit nach
  Tageszeit und die Farben am Horizont.
* `fog_sky_affect = 0,12`: Der Nebel färbt den Himmel nur noch leicht ein.

## Boden- und Belagsflächen

`materials/surfaces/ground.gdshader` ersetzt die bisherigen `StandardMaterial3D` aller Gras-, Asphalt-,
Pflaster-, Schotter- und Geländeflächen (`common.gd: surface_material`, `terrain_material`):

* triplanare Projektion in Weltkoordinaten (keine UVs oder Tangenten nötig), Normalmap über
  UDN-Blending;
* Anti-Kachelung: zweite Abtastung mit anderem Maßstab und gedrehter Projektion, überblendet mit
  niederfrequentem Rauschen;
* großflächige Variation je Belag (`GROUND_LOOK`): Helligkeitsflecken sowie trockene oder
  ausgebleichte Partien;
* Nässe über den globalen Shader-Parameter `road_wetness` (`project.godot`, `[shader_globals]`):
  versiegelte Flächen werden dunkler und glänzend, Gras und Sand nur schwach.

Das Gras-Foto zeigt spätsommerliches Gras. Gelände bekommt deshalb standardmäßig eine grünere Tönung;
das Testgelände nutzt dieselbe Tönung wie Stadt und Autobahn. Die Wüste verwendet das Schotter-Foto
mit warmen Vertexfarben. Das bisher genutzte Foto „Coast Sand“ war nasser, dunkler Küstensand.

## Straßen

`road.gdshader`:

* Tonvariation in Weltkoordinaten (Chargen, Ausbleichung);
* polierte Radspuren je Fahrstreifen;
* Flickstellen;
* abgefahrene Markierungen;
* Nässe aus `road_wetness`.

Feldwege der Wüste sind dunkler und verdichtet (`dirt_tint`, Stil `desert`).

## Vegetation

`scripts/maps/vegetation.gd` erzeugt beim Laden je Art drei Varianten mit festem Seed:

| Art | Aufbau |
|---|---|
| `broadleaf`, `poplar` | Stamm, Hauptäste zu 4–6 Kronenlappen, ~110–150 Blattkarten |
| `conifer` | durchgehender Stamm, Astquirle aus hängenden Zweigkarten, Kegelform |
| `bush`, `dry_shrub` | Zweige und 40 Karten, grün bzw. trocken (Wüste) |

* Die Blatt-, Nadel- und Trockenzweig-Texturen werden prozedural gemalt. Transparente Texel tragen die
  Blattfarbe, damit die Mipmaps nicht dunkel ausfransen.
* `materials/foliage.gdshader`: Alpha-Test (wirkt auch im Schattenpass), kronenförmige Normalen ohne
  Seitenumkehr, Lichtdurchlässigkeit (`BACKLIGHT`), Farbvariation je Baum (einige mit Herbstton) und
  leichter Wind.
* `V.plant(parent, art, Bodenpunkte, seed, min, max)` verteilt Größe, Drehung und eine leichte
  Schräglage und bündelt die Instanzen räumlich in MultiMeshes. Kollisionsboxen der Stämme legt weiterhin
  die jeweilige Karte an.

Alle Karten verwenden die neuen Pflanzen:

* Testgelände (Laub- und Nadelbäume);
* Autobahn;
* Hügelland (Nadelbäume auf den Höhen, Hecken als Büsche);
* Offroad (Wald, Waldkorridor und Büsche);
* Stadt (Park, Markt und Straßenbäume);
* Wüste (Trockensträucher).

Die Vorschau `tests/vegetation_shots.gd` rendert alle Arten nebeneinander.

**Bodenbewuchs:**

* `V.grass` setzt Grasbüschel aus je drei gekreuzten Halmkarten. Sie sind zu den Wurzeln hin dunkler
  und bewegen sich nur an den Spitzen im Wind.
* Die Büschel werden in 48-m-Blöcken gebündelt und nur bis 85 m gezeichnet.
* `V.roadside_grass` streut sie in Bändern entlang einer Straße und dünnt sie zum Feld hin aus. Die Höhe
  folgt dem Gelände; belegte Flächen werden ausgelassen.
* Im Einsatz auf Hügelland, Offroad-Wegen und den Autobahnböschungen.

## Stadtfassaden

`materials/facade.gdshader` ersetzt die gemalten Fassadentexturen:

* Fensterachsen und Geschosse werden je Gebäude aus der Instanzskalierung abgeleitet (symmetrische
  Ränder, Attika, dunklerer Sockel).
* Fenster sind 20 cm zurückgesetzt. Die Laibung wird per Parallaxe sichtbar und mit eigener Normalen
  beleuchtet.
* Hinter dem Glas liegen per Interior Mapping Räume mit 4 m Tiefe: Rückwand mit Möbelzone, Boden,
  Decke und Seitenwände. Dazu kommen Jalousien auf zufälliger Höhe.
* Nachts leuchten einzelne Räume (globaler Parameter `city_night` aus dem Tageszeitmodell).
* Drei Stile: Putz/Stein mit Geschossbändern, Klinker mit Mauerverband, Bürohaus mit beschichtetem,
  spiegelndem Glas.
* Alle Kanten werden über ableitungsbasierte Abdeckungsmasken geglättet. Instanzkonstanten sind
  `flat`-Varyings: Interpolierte Werte erzeugten im Hash Pixelrauschen.

Vorschau: `tests/facade_shots.gd -- <png> <stil> [debug]`.

## Offen

* Felsen und Klippen der Wüste haben nur Vertexfarben.
* Testgelände, Stadtpark und Wüste haben noch keinen Bodenbewuchs.

## Hügelland: Straßenausstattung, Wald und Felder

* **Schutzplanken:** W-Profil auf Pfosten an der Außenseite der schärfsten Kurven und an Böschungen, mit Kollision in Stoßfängerhöhe.
* **Kurvenwarnung:** rot-weiße Leittafeln in den Kurven, Warnschilder rund 60 m davor.
* **Stromleitung:** Holzmasten mit Querträger und Isolatoren, dazu durchhängende Leitungen.
* **Höfe:** Weidezaun, Heuballen, Felsbrocken. Felder in Streifen aus Weizen und umgepflügter Erde hinter den Höfen.
* **Waldkorridore:** dichter Nadel- und Laubwald mit Unterholz auf einzelnen Abschnitten.
* **Wälder:** geschlossene Waldstücke an den Hängen und auf den Höhenzügen rund ums Tal (10-m-Raster), frei um Höfe, Aussichtspunkt und Start; dunkler Waldboden darunter. Alle Baumstämme in Reichweite der Straße kollidieren (vorher waren die verstreuten Bäume nur Optik).
* **Hänge:** An steilen Hängen und Böschungen kommt auf allen Karten Erde und Gestein durch (Bodenshader).

Bausteine in `scripts/maps/roadside.gd`; Ansichten bestimmter Stellen mit `AT=<Wegpunkte> tests/map_shots.gd`.

## Weitere Karten

| Karte | Neu |
|---|---|
| Wüste | Raststätte „Coyote Flats“ (Tankstellendach mit Zapfsäulen, Diner mit Mastschild, Motelzeile, Wasserturm) auf der flachsten freien Stelle neben der Rallyeschleife; Saguaros mit Rippen; dichtes Gestrüpp und Felsen in Sichtweite der Piste; Telegrafenleitung; Kurventafeln; Boden aus Wüstenlack, rotem Boden und hellen Trockenrinnen. Tafelberge und Steilhänge mit Sandsteinschichtung und Erosionsstreifen (Bodenshader `has_strata`); Piste mit Schotterwällen in der Mitte und am Rand, Steinen, Waschbrettwellen, Schlaglöchern (bei Regen mit Wasser) und ausgefranstem Rand. |
| Autobahn | Sanfte, teils bewaldete Hügel am Horizont (nur Optik, jenseits der Felder); Flickenteppich aus Weizen, Raps, Mais, Wiese und Acker mit Hecken; Dorf mit Kirchturm; Wildschutzzaun; Kilometertafeln (500 m); Notrufsäulen (2 km); Lärmschutzwand; W-Profil-Leitplanken auf Pfosten. |
| Offroad | Feldwege mit geschlängelten Spuren, Staub- und Feuchtflecken, Kieseln, ausgefransten Rändern und Pfützen (mehr bei Nässe); Gebüsch, Stämme, Stümpfe und verwitterte Felsen am Rand. Geschlossener Wald (Raster ~10 m mit Lichtungen) in den Waldzonen und auf den Höhenzügen rund ums Tal, dunkler Waldboden darunter; Start: ~2,9 Mio. Primitive statt 1,9 Mio. |
| Stadt | Häuser mit Sockel, Geschossbändern, Gesims und Brüstung oder Satteldach; Dachaufbauten (Treppenhaus, Klimageräte, Wassertank, Antennen); Hinterhofgassen mit Toren und Müllcontainern; Reihenhausblock mit Giebelwänden, gerahmten Fenstern, Haustüren, Schornsteinen, Hecken, Wegen, Zäunen, Schuppen und Gartenbäumen. Geparkte Autos an den Nebenstraßen: gebackene Low-Poly-Fassungen der glTF-Modelle, ~20.000 Dreiecke mit Detailstufen, `tests/bake_parked_cars.gd`. Dazu Bänke, Mülleimer, Fahrradständer, Poller und Gullydeckel. |
| Felsen (alle Karten) | `scripts/maps/rocks.gd`: unregelmäßige Felsformen mit Bruchflächen und flacher Basis, Gesteinsshader mit Schichtung, Körnung, Rissen und hellen Oberseiten (rot in der Wüste, grau sonst). |
| Asphalt (alle Karten) | Rissnetze, einzelne Bitumen-Vergussfugen, Randrisse mit Splitt, Ölflecken. |
