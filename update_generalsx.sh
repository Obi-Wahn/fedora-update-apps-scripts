#!/bin/bash

# Striktes Fehlermanagement
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# GeneralsX (https://github.com/fbraz3/GeneralsX) liefert für Linux keine RPM-
# Pakete, sondern Flatpak-Bundles. Deshalb kommt hier "flatpak" statt "dnf/rpm"
# zum Einsatz. Dieses Skript installiert bewusst nur die Zero-Hour-Variante
# (com.fbraz3.GeneralsXZH) - die Basisversion (Generals) wird nicht benötigt.

require_cmd curl "curl ist nicht installiert."
require_cmd python3 "python3 ist nicht installiert."
require_cmd flatpak "flatpak ist nicht installiert."

APP_ID="com.fbraz3.GeneralsXZH"
ASSET_NAME="Linux-GeneralsXZH.flatpak"
MARKER_FILE="$SCRIPT_DIR/.generalsxzh-installed-version"
TARGET_FILE="$SCRIPT_DIR/$ASSET_NAME"

echo "🔍 Suche nach der neuesten GeneralsX-Zero-Hour-Version..."

# Das veröffentlichte Flatpak-Bundle wird aktuell nur für x86_64 gebaut
ARCH="$(uname -m)"
if [ "$ARCH" != "x86_64" ]; then
    echo "❌ Fehler: Architektur $ARCH wird von GeneralsX (aktuell nur x86_64-Flatpaks) nicht unterstützt." >&2
    exit 1
fi

# Neueste Release-Infos abfragen: Tag sowie die Download-URL des Zero-Hour-Bundles
if ! RELEASE_INFO=$(python3 -c '
import urllib.request, json, sys
try:
    req = urllib.request.urlopen("https://api.github.com/repos/fbraz3/GeneralsX/releases/latest", timeout=15)
    data = json.loads(req.read().decode())
    tag = data.get("tag_name", "")
    zh_url = ""
    for asset in data.get("assets", []):
        if asset.get("name") == sys.argv[1]:
            zh_url = asset.get("browser_download_url", "")
            break
    if not tag or not zh_url:
        print("Erwartetes Asset nicht in der neuesten Release gefunden", file=sys.stderr)
        sys.exit(1)
    print(f"{tag}|{zh_url}")
except Exception as e:
    print(f"{type(e).__name__}: {e}", file=sys.stderr)
    sys.exit(1)
' "$ASSET_NAME"); then
    echo "❌ Fehler: Konnte die neueste GeneralsX-Release nicht abrufen (siehe Ursache oben)." >&2
    exit 1
fi

TAG=$(echo "$RELEASE_INFO" | cut -d'|' -f1)
URL=$(echo "$RELEASE_INFO" | cut -d'|' -f2)

# GeneralsX nutzt kein Semver (z.B. "GeneralsX-Beta-19"), daher nur ein loser
# Format-Check statt der strikten X.Y.Z-Validierung der übrigen Skripte
validate_identifier "$TAG" || exit 1

echo "🌐 Neuestes Release-Tag: $TAG"

INSTALLED_TAG=$(read_installed_marker "$MARKER_FILE")
echo "📦 Zuletzt installiertes Release: ${INSTALLED_TAG:-nicht installiert}"
echo "🌐 Neuestes verfügbares Release:  $TAG"

# Die Marker-Datei allein reicht nicht: sie merkt sich nur, was dieses Skript
# zuletzt selbst installiert hat, weiß aber nichts von einer manuellen
# Deinstallation durch den Nutzer. Deshalb zusätzlich bei flatpak nachfragen,
# ob die App im System-Scope tatsächlich noch installiert ist.
IS_INSTALLED=false
if flatpak info --system "$APP_ID" >/dev/null 2>&1; then
    IS_INSTALLED=true
fi

if [ "$INSTALLED_TAG" == "$TAG" ] && [ "$IS_INSTALLED" == "true" ]; then
    echo "✅ GeneralsX (Zero Hour) ist bereits aktuell."
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

if [ "$INSTALLED_TAG" == "$TAG" ] && [ "$IS_INSTALLED" == "false" ]; then
    echo "🔄 Release-Tag ist zwar aktuell, die App ist aber nicht (mehr) installiert. Installiere neu..."
else
    echo "🔄 Update verfügbar!"
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
echo "⚙️ Installiere GeneralsX (Zero Hour) ($APP_ID) via flatpak (System-Installation, fordert evtl. sudo an)..."
if ! sudo flatpak install --system --or-update -y "$TARGET_FILE"; then
    echo "❌ Fehler: flatpak install fehlgeschlagen." >&2
    exit 1
fi

write_installed_marker "$MARKER_FILE" "$TAG"

echo "------------------------------------------------"
echo "✅ Installation von GeneralsX (Zero Hour) ($TAG) erfolgreich abgeschlossen!"
echo "------------------------------------------------"
