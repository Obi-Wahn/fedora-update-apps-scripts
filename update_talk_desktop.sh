#!/bin/bash

# Striktes Fehlermanagement
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Nextcloud Talk Desktop (https://github.com/nextcloud/talk-desktop) liefert für
# Linux keine RPM-Pakete, sondern ein Flatpak-Bundle. Die eigentlichen Releases
# werden nicht im Quell-Repo, sondern in nextcloud-releases/talk-desktop
# veröffentlicht (siehe README des Projekts). Dieses Skript bezieht bewusst nur
# stabile Releases über /releases/latest, das Vorabversionen (Tags mit
# "-beta"-Suffix, z.B. v2.3.1-beta) als GitHub-Prerelease ausschließt.

require_cmd curl "curl ist nicht installiert."
require_cmd python3 "python3 ist nicht installiert."
require_cmd flatpak "flatpak ist nicht installiert."

APP_ID="com.nextcloud.talk"
ASSET_NAME="Nextcloud.Talk-linux-x64.flatpak"
MARKER_FILE="$SCRIPT_DIR/.talk-desktop-installed-version"
TARGET_FILE="$SCRIPT_DIR/$ASSET_NAME"

echo "🔍 Suche nach der neuesten stabilen Nextcloud-Talk-Desktop-Version..."

# Das veröffentlichte Flatpak-Bundle wird aktuell nur für x86_64 gebaut
ARCH="$(uname -m)"
if [ "$ARCH" != "x86_64" ]; then
    echo "❌ Fehler: Architektur $ARCH wird von Nextcloud Talk Desktop (aktuell nur x86_64-Flatpaks) nicht unterstützt." >&2
    exit 1
fi

# Neueste STABILE Release-Infos abfragen (releases/latest schließt Prereleases
# wie die "-beta"-Tags automatisch aus)
if ! RELEASE_INFO=$(python3 -c '
import urllib.request, json, sys
try:
    req = urllib.request.urlopen("https://api.github.com/repos/nextcloud-releases/talk-desktop/releases/latest", timeout=15)
    data = json.loads(req.read().decode())
    tag = data.get("tag_name", "").lstrip("v")
    url = ""
    for asset in data.get("assets", []):
        if asset.get("name") == sys.argv[1]:
            url = asset.get("browser_download_url", "")
            break
    if not tag or not url:
        print("Erwartetes Asset nicht in der neuesten Release gefunden", file=sys.stderr)
        sys.exit(1)
    print(f"{tag}|{url}")
except Exception as e:
    print(f"{type(e).__name__}: {e}", file=sys.stderr)
    sys.exit(1)
' "$ASSET_NAME"); then
    echo "❌ Fehler: Konnte die neueste stabile Nextcloud-Talk-Desktop-Release nicht abrufen (siehe Ursache oben)." >&2
    exit 1
fi

VERSION=$(echo "$RELEASE_INFO" | cut -d'|' -f1)
URL=$(echo "$RELEASE_INFO" | cut -d'|' -f2)

validate_version "$VERSION" || exit 1

echo "🌐 Neueste stabile Version: $VERSION"

INSTALLED_VERSION=$(read_installed_marker "$MARKER_FILE")
echo "📦 Zuletzt installierte Version: ${INSTALLED_VERSION:-nicht installiert}"

# Die Marker-Datei allein reicht nicht: sie merkt sich nur, was dieses Skript
# zuletzt selbst installiert hat, weiß aber nichts von einer manuellen
# Deinstallation durch den Nutzer. Deshalb zusätzlich bei flatpak nachfragen,
# ob die App im System-Scope tatsächlich noch installiert ist.
IS_INSTALLED=false
if flatpak info --system "$APP_ID" >/dev/null 2>&1; then
    IS_INSTALLED=true
fi

if [ "$INSTALLED_VERSION" == "$VERSION" ] && [ "$IS_INSTALLED" == "true" ]; then
    echo "✅ Nextcloud Talk Desktop ist bereits aktuell ($INSTALLED_VERSION)."
    # Auch ohne anstehendes Update immer eine lokale Bundle-Kopie sicherstellen.
    # Der Dateiname enthält keine Versionsnummer und bleibt über Releases hinweg
    # gleich, es gibt also nichts "Altes" danach aufzuräumen.
    if [ ! -f "$TARGET_FILE" ]; then
        echo "📦 Keine lokale Flatpak-Sicherung gefunden, lade sie zusätzlich herunter: $TARGET_FILE"
        trap_download_cleanup "$TARGET_FILE"
        if ! download_file "$URL" "$TARGET_FILE"; then
            echo "⚠️ Warnung: Backup-Download fehlgeschlagen." >&2
        fi
        clear_download_trap
    fi
    exit 0
fi

if [ "$INSTALLED_VERSION" == "$VERSION" ] && [ "$IS_INSTALLED" == "false" ]; then
    echo "🔄 Version ist zwar aktuell, die App ist aber nicht (mehr) installiert. Installiere neu..."
else
    echo "🔄 Update verfügbar! (lokal: ${INSTALLED_VERSION:-nicht installiert})"
fi

echo "⬇️ Lade Flatpak-Bundle herunter: $TARGET_FILE"
trap_download_cleanup "$TARGET_FILE"
if ! download_file "$URL" "$TARGET_FILE"; then
    clear_download_trap
    exit 1
fi
clear_download_trap

# flatpak install prüft die Bundle-Integrität und installiert/aktualisiert in
# einem Schritt; --system installiert für alle Nutzer des Rechners (erfordert
# sudo), --or-update erlaubt ein stilles Update einer bereits vorhandenen
# Installation, -y unterdrückt Rückfragen.
echo "⚙️ Installiere Nextcloud Talk Desktop ($APP_ID) via flatpak (System-Installation, fordert evtl. sudo an)..."
if ! sudo flatpak install --system --or-update -y "$TARGET_FILE"; then
    echo "❌ Fehler: flatpak install fehlgeschlagen." >&2
    exit 1
fi

write_installed_marker "$MARKER_FILE" "$VERSION"

echo "------------------------------------------------"
echo "✅ Installation von Nextcloud Talk Desktop ($VERSION) erfolgreich abgeschlossen!"
echo "------------------------------------------------"
