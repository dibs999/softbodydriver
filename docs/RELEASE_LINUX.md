# Linux-Paket bauen und prüfen

`tools/package_linux.sh` erzeugt ein eigenständig startbares Linux-x86_64-Entwicklungspaket. Voraussetzungen: Linux x86_64, C++20-Compiler, CMake ≥3.20, Python 3, Godot **4.5.1 stable**, curl, unzip, tar, ripgrep, sha512sum und objdump (binutils). Es werden keine Zugangsdaten benötigt. GitHub und die offiziellen GitHub-Downloadserver müssen erreichbar sein.

```bash
# Aus dem Repository; GODOT_BIN/CMAKE_BIN können absolute Programmpfade sein.
GODOT_BIN=godot CMAKE_BIN=cmake JOBS=3 bash tools/package_linux.sh
```

Im vorbereiteten Cloud-Arbeitsbereich:

```bash
export PATH=/workspace/.softbody-tools/venv/bin:/workspace/.softbody-tools/bin:$PATH
bash tools/package_linux.sh
```

Der erste Durchlauf lädt das vollständige offizielle Export-Template-Archiv (etwa 1,36 GB), prüft es gegen die offizielle SHA-512-Liste und extrahiert nur die Linux-Templates. Das ganze Archiv wird geprüft, bevor daraus Programme verwendet werden. Der Download und Editorzustand liegen unter `.cache/package-linux/` und werden bei weiteren Läufen wiederverwendet. Ein fehlgeschlagener Download verbleibt als `.part`; ein fehlgeschlagener Prüfsummenvergleich stoppt den Ablauf.

Die GDExtension wird als `template_debug` für den Editorimport und `template_release` für das fertige Spiel gebaut. Ein geeignetes vorhandenes `build/` wird für die Debug-Bibliothek inkrementell weiterverwendet; daher den Paketlauf nicht gleichzeitig mit einem anderen Build in diesem Verzeichnis starten. Der Release-Build liegt separat in `build-package-linux/`. Fehlt ein Debug-Build, wird `build-package-debug/` angelegt.

Jeder Lauf erhält ein neues `dist/linux-stage.XXXXXX/` und überschreibt keine früheren Pakete. Darin befinden sich:

* `SoftBodyDriver-linux-x64/`: Programm, native Bibliothek, Asset-Credits, Projekt-/Drittanbieter-Lizenzen und Startanleitung.
* `SoftBodyDriver-linux-x64.tar.gz` und SHA-256-Datei.
* Import-, Export- und Standalone-Prüfprotokolle.
* Im Paket `BUILD_MANIFEST.json` mit Commit, Kennzeichnung nicht eingecheckter Änderungen, Godot-/Buildsystem-Version, höchster benötigter GLIBC-Symbolversion der nativen Bibliothek und SHA-256 der Paketdateien.

Der Ablauf ist wiederholbar; er behauptet keine bitgenau identischen Binärdateien unterschiedlicher Compiler-/Systemversionen. Ein Paket aus einem geänderten Arbeitsverzeichnis ist ausdrücklich als solches gekennzeichnet. Für eine veröffentlichte Version einen geprüften Commit und protokollierte Toolchain verwenden.

## Standalone-Prüfung

`tools/package_smoke.py` kopiert ausschließlich das exportierte Paket in ein neues temporäres Verzeichnis und benutzt isolierte Benutzerprofile. Es startet das exportierte Programm zuerst im Hauptmenü und danach mit einem externen Prüfskript, das die **exportierte** Spielszene, Fahrzeugdefinition und native Physik lädt. Kestrel und Concept fahren jeweils drei Sekunden mit Gas; mindestens 10 km/h, endliche Positionen und die richtige Fahrzeugidentität sind Voraussetzung für den Erfolgsmarker. Die aktuelle Kestrel-Definition mit `detachableBumpers`/`detachableDoors`, die native Hauben-Schnittstelle und zwei Türmechanismen werden geprüft. Beide Fahrzeuge müssen zwei echte Spiegelflächen liefern, deren zentrale reflektierte Blickrichtung vom Fahrersitz nach hinten nahe zum Horizont zeigt. Anschließend wird die Rückkehr ins Menü geprüft. Es wird kein Godot-Editor gestartet. Fehlende Ressourcen, Script-/Enginefehler (auch bei Prozessstatus 0), Zeitüberschreitung oder ein fehlender Erfolgsmarker führen zum Fehlerstatus.

```bash
python3 tools/package_smoke.py /pfad/SoftBodyDriver-linux-x64 /tmp/package-check-logs
```

Das belegt Paketvollständigkeit und einen kurzen funktionalen Start. Es belegt **keine** GPU-Bildqualität, Gamepad-Bedienung, vollständige Tutorial-/Service-/Aktivitätsrunde oder 30-minütige Stabilität. Diese Abnahmen bleiben gemäß [PRODUCT_TARGET.md](PRODUCT_TARGET.md) separat erforderlich.

## Verbleibende Veröffentlichungskriterien

* Eine vollständige Referenzsitzung samt Speichern/Neustart auf einem sauberen Benutzerprofil durchführen; nicht allein auf Unit-Tests verlassen.
* Eine mindestens 30-minütige gerenderte Spielsitzung aufzeichnen und Fehler prüfen. Der automatisierte Headless-Dauerlauf mit 51 Fahr-/Tür-/Crash-/Servicezyklen ist bereits bestanden; er ersetzt keine Bild- und Eingabegeräteabnahme (Details in [ACCEPTANCE_STATUS.md](ACCEPTANCE_STATUS.md)).
* Auf dokumentierter GPU-Hardware testen; die native Bibliothek verwendet den Compiler und die Systembibliotheken des Build-Rechners. Kompatibilität mit älteren Linux-Distributionen ist ohne passenden Build-Basisstand nicht zugesichert.
* Modell-/Markenrechte und Credit-Vollständigkeit vor öffentlicher Auslieferung des konkreten Pakets prüfen. Der Ablauf übernimmt die vorhandenen Asset-Credits unverändert; das ist keine zusätzliche Lizenzierung neuer Assets.
* Windows/macOS-Exporte, Signierung, Installer und Updates sind eigenständige Aufgaben. Dieser Ablauf validiert nur Linux x86_64.

## Nachgewiesener Paketlauf am 9. November 2026

Der vollständige Paketablauf wurde nach der Erweiterung um den Zeitfahrabschluss mit Ergebnisanzeige, Bestzeit und gespeichertem Fortschritt erneut ausgeführt. Kestrel-Vordertüren und echte Cockpit-Außenspiegel mit korrigierter physikalischer Blickrichtung sind ebenfalls enthalten. Das aktuelle Ergebnis liegt unter `dist/linux-stage.jEwZyc/SoftBodyDriver-linux-x64.tar.gz` (44.179.587 Bytes, etwa 42,1 MiB). SHA-256: `0e32fc28b2dd0104efa458ef253d1fca32763b2d3e8d7df02e194d89bb89f579`.

* Offizielles Godot-Template-Archiv vollständig gegen SHA-512 geprüft; aktuelle native Release-Bibliothek aus dem eingefrorenen Laufzeit-Quellstand gebaut.
* Import/Export, Standalone-Menü, Kestrel und Concept sowie Rückkehr ins Menü bestanden. Exportierte Türmechanismen, Spiegelflächen und deren Blickrichtung sind geprüft. Diese Standardprotokolle enthalten keine `ERROR`- oder `WARNING`-Einträge.
* Anschließend das **fertige Archiv** separat entpackt, alle zehn Dateihashes im Manifest verifiziert und dieselbe Standalone-Prüfung aus dem entpackten Paket erneut bestanden.
* Zusätzlich das vorhandene `time_trial_flow_test.gd` gegen das **exportierte Programm** mit isoliertem Profil ausgeführt: eine vollständige Runde über 26 Kontrollpunkte in 102,75 Sekunden; alle zwölf Prüfungen bestanden, einschließlich Abschlussereignis, Bestzeit-/Profil-Neuladen, Wiederholung und Abbruch bei Fahrzeugversetzung. Keine Script-/Enginefehler. Dieses ergänzende Testskript meldet beim Prozessende eine `ObjectDB instances leaked`-Aufräumwarnung; das Protokoll bleibt unter `archive-check/standalone-time-trial.log` erhalten.
* Die native Bibliothek benötigt auf diesem Buildstand GLIBC-Symbole bis **2.38**. Ältere Systeme brauchen einen Build auf einer passenden Basis; sie wurden nicht geprüft.

Das Paket enthält einen geänderten, noch nicht eingecheckten Arbeitsstand und ist als Entwicklungsbuild gekennzeichnet. Die 42 Spiegelintegrationsprüfungen, Bildprüfung und der 30-minütige simulierte Dauerlauf sind in [ACCEPTANCE_STATUS.md](ACCEPTANCE_STATUS.md) separat dokumentiert. Eine bestandene 200-km/h-Stabilitätsabnahme wird nicht behauptet; insbesondere ist der Concept-Zielgeschwindigkeitsfall weiterhin ungeklärt. Die dokumentierten GPU-, Eingabegeräte- und Plattformabnahmen bleiben offen; dieser Paketnachweis ersetzt sie nicht.
