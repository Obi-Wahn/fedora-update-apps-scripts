#!/bin/bash

# Striktes Fehlermanagement
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# GeneralsX (https://github.com/fbraz3/GeneralsX) liefert für Linux keine RPM-
# Pakete, sondern Flatpak-Bundles. Deshalb kommt hier "flatpak" statt "dnf/rpm"
# zum Einsatz, und es gibt keine dnf-/rpm-Abfrage für die installierte Version -
# stattdessen wird das zuletzt installierte Release-Tag in einer einfachen
# Marker-Datei im Skriptverzeichnis gemerkt (siehe read_installed_marker()).

require_cmd curl "curl ist nicht installiert."
require_cmd python3 "python3 ist nicht installiert."
require_cmd flatpak "flatpak ist nicht installiert."

echo "🔍 Suche nach der neuesten GeneralsX-Version..."

# Die veröffentlichten Flatpak-Bundles werden aktuell nur für x86_64 gebaut
ARCH="$(uname -m)"
if [ "$ARCH" != "x86_64" ]; then
    echo "❌ Fehler: Architektur $ARCH wird von GeneralsX (aktuell nur x86_64-Flatpaks) nicht unterstützt." >&2
    exit 1
fi

# Neueste Release-Infos abfragen: Tag sowie die Download-URLs beider Varianten
# (Generals und Zero Hour) in einem einzigen API-Aufruf ermitteln
if ! RELEASE_INFO=$(python3 -c '
import urllib.request, json, sys
try:
    req = urllib.request.urlopen("https://api.github.com/repos/fbraz3/GeneralsX/releases/latest", timeout=15)
    data = json.loads(req.read().decode())
    tag = data.get("tag_name", "")
    assets = {a.get("name"): a.get("browser_download_url") for a in data.get("assets", [])}
    generals_url = assets.get("Linux-GeneralsX.flatpak", "")
    zh_url = assets.get("Linux-GeneralsXZH.flatpak", "")
    if not tag or not generals_url or not zh_url:
        print("Erwartete Assets nicht in der neuesten Release gefunden", file=sys.stderr)
        sys.exit(1)
    print(f"{tag}|{generals_url}|{zh_url}")
except Exception as e:
    print(f"{type(e).__name__}: {e}", file=sys.stderr)
    sys.exit(1)
'); then
    echo "❌ Fehler: Konnte die neueste GeneralsX-Release nicht abrufen (siehe Ursache oben)." >&2
    exit 1
fi

TAG=$(echo "$RELEASE_INFO" | cut -d'|' -f1)
GENERALS_URL=$(echo "$RELEASE_INFO" | cut -d'|' -f2)
ZH_URL=$(echo "$RELEASE_INFO" | cut -d'|' -f3)

# GeneralsX nutzt kein Semver (z.B. "GeneralsX-Beta-19"), daher nur ein loser
# Format-Check statt der strikten X.Y.Z-Validierung der übrigen Skripte
validate_identifier "$TAG" || exit 1

echo "🌐 Neuestes Release-Tag: $TAG"

DEST_DIR="$SCRIPT_DIR"

# Definiert: "Anzeigename|App-ID|Download-URL|Dateiname|Marker-Datei"
APPS=(
    "GeneralsX (Generals)|com.fbraz3.GeneralsX|$GENERALS_URL|Linux-GeneralsX.flatpak|.generalsx-installed-version"
    "GeneralsX (Zero Hour)|com.fbraz3.GeneralsXZH|$ZH_URL|Linux-GeneralsXZH.flatpak|.generalsxzh-installed-version"
)

for APP in "${APPS[@]}"; do
    echo "------------------------------------------------"
    IFS='|' read -r DISPLAY_NAME APP_ID URL ASSET_NAME MARKER_NAME <<< "$APP"
    MARKER_FILE="$DEST_DIR/$MARKER_NAME"
    TARGET_FILE="$DEST_DIR/$ASSET_NAME"

    INSTALLED_TAG=$(read_installed_marker "$MARKER_FILE")
    echo "📦 Zuletzt installiertes Release ($DISPLAY_NAME): ${INSTALLED_TAG:-nicht installiert}"
    echo "🌐 Neuestes verfügbares Release:                 $TAG"

    if [ "$INSTALLED_TAG" == "$TAG" ]; then
        echo "✅ $DISPLAY_NAME ist bereits aktuell."
        # Auch ohne anstehendes Update immer eine lokale Bundle-Kopie sicherstellen.
        # Anders als bei den RPM-Skripten steckt in ASSET_NAME keine Versionsnummer -
        # der Dateiname bleibt über Releases hinweg gleich, es gibt also nichts
        # "Altes" danach aufzuräumen.
        if [ ! -f "$TARGET_FILE" ]; then
            echo "📦 Keine lokale Flatpak-Sicherung gefunden, lade sie zusätzlich herunter: $TARGET_FILE"
            trap_download_cleanup "$TARGET_FILE"
            if ! download_file "$URL" "$TARGET_FILE"; then
                echo "⚠️ Warnung: Backup-Download für $DISPLAY_NAME fehlgeschlagen." >&2
            fi
            clear_download_trap
        fi
        continue
    fi

    echo "🔄 Update verfügbar! Lade Flatpak-Bundle herunter: $TARGET_FILE"
    trap_download_cleanup "$TARGET_FILE"
    if ! download_file "$URL" "$TARGET_FILE"; then
        clear_download_trap
        continue
    fi
    clear_download_trap

    # flatpak install prüft die Bundle-Integrität und installiert/aktualisiert in
    # einem Schritt; --user vermeidet sudo, --or-update erlaubt ein stilles Update
    # einer bereits vorhandenen Installation, -y unterdrückt Rückfragen.
    echo "⚙️ Installiere $DISPLAY_NAME ($APP_ID) via flatpak (Nutzer-Installation, kein sudo nötig)..."
    if ! flatpak install --user --or-update -y "$TARGET_FILE"; then
        echo "❌ Fehler: flatpak install für $DISPLAY_NAME fehlgeschlagen." >&2
        continue
    fi

    write_installed_marker "$MARKER_FILE" "$TAG"

    echo "✅ Installation von $DISPLAY_NAME ($TAG) erfolgreich abgeschlossen!"
done

echo "------------------------------------------------"
echo "🎉 Alle Vorgänge abgeschlossen."
