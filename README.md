# Fedora Update Apps Scripts

[![Shell Script Checks](https://github.com/Obi-Wahn/fedora-update-apps-scripts/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/Obi-Wahn/fedora-update-apps-scripts/actions/workflows/shellcheck.yml)

Eine Sammlung von Bash-Skripten, die Anwendungen unter Fedora Linux aktuell halten, deren Updates nicht (zeitnah) über die offiziellen Paketquellen (`dnf`) verfügbar sind. Jedes Skript prüft die neueste verfügbare Version (meist über die GitHub-API oder die offizielle Release-Seite), vergleicht sie mit der lokal installierten Version und installiert bei Bedarf automatisch das passende Paket (`.rpm` via `dnf`, bei GeneralsX und Nextcloud Talk Desktop ein `.flatpak`-Bundle via `flatpak`).

## Enthaltene Updater

| Skript | Aktualisiert |
| --- | --- |
| `update_fastfetch.sh` | [Fastfetch](https://github.com/fastfetch-cli/fastfetch) über die GitHub-Releases |
| `update_docker_desktop.sh` | [Docker Desktop](https://www.docker.com/products/docker-desktop/) über die offiziellen Release Notes |
| `update_linwood-apps.sh` | [Linwood Butterfly](https://github.com/LinwoodDev/butterfly) & [Linwood Flow](https://github.com/LinwoodDev/Flow) über die GitHub-Releases |
| `update_moonfin.sh` | [Moonfin](https://github.com/Moonfin-Client/Moonfin-Core) über die GitHub-Releases |
| `update_OpenLogi.sh` | [OpenLogi](https://github.com/AprilNEA/OpenLogi) über die GitHub-Releases |
| `update_generalsx.sh` | [GeneralsX](https://github.com/fbraz3/GeneralsX) (nur Zero Hour) über die GitHub-Releases — **Sonderfall:** nutzt `flatpak` statt `dnf`/`rpm`, siehe Hinweis unten |
| `update_talk_desktop.sh` | [Nextcloud Talk Desktop](https://github.com/nextcloud/talk-desktop) (nur stabile Releases) über die GitHub-Releases von [nextcloud-releases/talk-desktop](https://github.com/nextcloud-releases/talk-desktop) — **Sonderfall:** nutzt `flatpak` statt `dnf`/`rpm`, siehe Hinweis unten |

Alle Skripte liegen direkt im Wurzelverzeichnis und binden [`common.sh`](./common.sh) ein, das gemeinsam genutzte Funktionen bereitstellt (siehe unten). `common.sh` ist keine eigenständige Updater; sie wird nur per `source` eingebunden und muss nicht ausführbar sein oder manuell gestartet werden.

Für Moonfin liegt zusätzlich eine Einrichtungsanleitung bei: [`Anleitung_Moonfin_auf_Fedora_44_einrichten.md`](./Anleitung_Moonfin_auf_Fedora_44_einrichten.md).

### Sonderfall: Flatpak-basierte Updater (GeneralsX, Nextcloud Talk Desktop)

GeneralsX und Nextcloud Talk Desktop veröffentlichen für Linux keine `.rpm`-Pakete, sondern `.flatpak`-Bundle-Dateien (aktuell nur für x86_64). `update_generalsx.sh` und `update_talk_desktop.sh` weichen deshalb vom gemeinsamen RPM-Muster ab. Beide ermitteln nur noch Version und Download-URL (per `find_github_latest_asset()`) und überlassen den restlichen Ablauf der gemeinsamen Funktion `flatpak_update_app()` in `common.sh`:

* Installation/Update läuft über `sudo flatpak install --system --or-update`, nicht über `dnf`. Die Installation ist damit system-weit für alle Nutzer des Rechners verfügbar (und benötigt entsprechend `sudo`, genau wie die `dnf install`-Schritte der anderen Skripte).
* Da die Bundle-Dateinamen keine Versionsnummer enthalten, merkt sich jedes Skript die zuletzt installierte Version zusätzlich in einer einfachen Marker-Datei (`.generalsxzh-installed-version` bzw. `.talk-desktop-installed-version`). Die Marker-Datei allein reicht aber nicht aus, um eine manuelle Deinstallation zu erkennen — deshalb fragt jedes Skript vor jedem Lauf zusätzlich per `flatpak_is_installed()` (`sudo flatpak info --system`) nach, ob die App tatsächlich noch installiert ist, und installiert bei Bedarf neu, selbst wenn der Marker bereits die aktuelle Version zeigt. Die Abfrage läuft bewusst schon mit `sudo`, da `flatpak info --system` ohne erhöhte Rechte auf manchen Systemen fälschlich "nicht gefunden" meldet.
* `flatpak_install_bundle()` fängt außerdem den Fall ab, dass `flatpak install` eine bereits exakt installierte Version als Fehler statt als No-Op behandelt (z.B. wenn zwar die App, aber noch keine Marker-Datei vorhanden ist) — das wird als Erfolg gewertet statt als Fehlschlag gemeldet.
* GeneralsX nutzt kein Semver-Schema (z.B. `GeneralsX-Beta-19`), daher greift dort `validate_identifier()` (loser Format-Check) statt der strikten `validate_version()`. Nextcloud Talk Desktop nutzt normales Semver (`vX.Y.Z`, teils mit `-beta`-Suffix) und damit die strikte Validierung.
* `update_talk_desktop.sh` bezieht ausschließlich stabile Releases: Die Abfrage läuft gegen `/releases/latest`, was Vorabversionen mit `-beta`-Suffix als GitHub-Prerelease automatisch ausschließt.

## Gemeinsame Funktionsweise

Alle Skripte folgen demselben Muster; die wiederkehrenden Bausteine (Download, Prüfung, Versionsvergleich, Cleanup) liegen zentral in [`common.sh`](./common.sh), damit Verbesserungen an einer Stelle allen Skripten zugutekommen:

* **Architekturerkennung:** Ermittelt per `uname -m` automatisch, ob x86_64 oder aarch64 vorliegt, und wählt das passende `.rpm`-Paket.
* **Versionsabgleich mit Downgrade-Schutz:** Vergleicht die installierte Version (per `rpm -q` bzw. dem jeweiligen `--version`-Aufruf) mit der neuesten verfügbaren Version per `sort -V`. Ist die installierte Version bereits aktuell oder neuer, bricht das Skript ohne Download ab – ein versehentliches Downgrade wird so vermieden.
* **Robuste API-/Web-Abfrage:** Nutzt Python (`urllib`/`json`) für zuverlässiges JSON-Parsing der GitHub-API (inkl. Timeout und Fehlerursache auf stderr) bzw. `curl` mit Timeouts (`--connect-timeout`, `--max-time`) und Retry-Logik (`--retry`) für Downloads und Webseiten-Abfragen.
* **Validierung:** Prüft die extrahierte Versionsnummer per Regex, bevor sie in Dateinamen oder URLs verwendet wird.
* **Integritätsprüfung:** Verifiziert jedes heruntergeladene Paket vor der Installation mit `rpm -qip` auf eine gültige RPM-Struktur.
* **Interrupt-sicheres Aufräumen:** Ein `trap` entfernt eine unvollständig heruntergeladene Datei, falls der Download per Strg+C abgebrochen wird.
* **User-Space First:** Bei den RPM-Skripten laufen Download und Prüfung ohne Root-Rechte; `sudo` wird nur für den finalen `dnf install`-Schritt angefordert. Die Flatpak-Skripte brauchen `sudo` bereits für die Installationsprüfung (siehe Sonderfall oben).
* **Striktes Fehlermanagement:** Jedes Skript nutzt `set -euo pipefail` und bricht bei Fehlern sauber mit einer verständlichen Meldung ab.
* **Dateiverwaltung mit lokaler Sicherung:** RPM-Pakete werden in das jeweilige Skriptverzeichnis heruntergeladen (per `.gitignore` von Git ausgeschlossen). Für die aktuell installierte Version wird dort immer eine lokale Kopie vorgehalten – ist sie nicht vorhanden (z.B. nach einem frischen Klon), wird sie auch ohne anstehendes Update automatisch nachgeladen. Ältere Pakete desselben Programms werden dabei automatisch entfernt.

## `update_all.sh` – alle Updates auf einmal

`update_all.sh` führt alle `update_*.sh`-Skripte im selben Verzeichnis nacheinander aus:

```bash
chmod +x update_all.sh
./update_all.sh
```

Dabei wird einmalig `sudo`-Zugriff angefordert und im Hintergrund wachgehalten, sodass die einzelnen Skripte nicht mehrfach nach dem Passwort fragen. Vor jeder Ausführung prüft `update_all.sh`, ob das jeweilige Skript dem aktuellen Nutzer gehört und ausführbar ist; andernfalls wird es übersprungen. Am Ende gibt es eine Zusammenfassung fehlgeschlagener Updates aus und beendet sich mit einem entsprechenden Exit-Code.

## Einzelne Skripte ausführen

Jedes Skript lässt sich auch unabhängig von `update_all.sh` starten:

```bash
chmod +x update_fastfetch.sh
./update_fastfetch.sh
```

## Systemvoraussetzungen

* **Betriebssystem:** Fedora Linux (oder kompatible RHEL-Derivate)
* **Architektur:** x86_64 oder aarch64
* **Abhängigkeiten:** `bash`, `curl`, `dnf`, `rpm`, `python3`, `coreutils` (u.a. `sort -V` für den Downgrade-Schutz) (je nach Skript zusätzlich `awk`, `grep`, `sed`; `update_generalsx.sh` und `update_talk_desktop.sh` benötigen statt `dnf`/`rpm` zusätzlich `flatpak`, aktuell nur für x86_64 verfügbar)

## Hinweis zur Entwicklung (KI-Transparenz)

Der Quellcode dieser Skripte sowie Teile dieser Dokumentation wurden in Zusammenarbeit mit generativen KI-Modellen (Large Language Models) iterativ entwickelt, auf Robustheit geprüft und optimiert.

## Lizenz

Dieses Projekt ist Open Source und steht unter der [MIT-Lizenz](./LICENSE). Es kann frei verwendet, modifiziert und weitergegeben werden.
