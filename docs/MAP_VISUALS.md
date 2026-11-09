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

## Offen

* Stadtfassaden sind weiterhin texturierte Quader ohne Tiefe (Fenster, Gesimse).
* Felsen und Klippen der Wüste haben nur Vertexfarben.
* Grasbüschel und Bodenbewuchs in Fahrbahnnähe fehlen noch.
