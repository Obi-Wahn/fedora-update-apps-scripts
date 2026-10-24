#!/bin/bash

# Striktes Fehlermanagement
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Processing 4 (https://github.com/processing/processing4) liefert für Linux keine
# RPM-Pakete, sondern u.a. ein Flatpak-Bundle für x86_64 ("x64") und aarch64. Die
# Release-Tags haben die Form "processing-<Revision>-<Version>" (z.B.
# "processing-1434-4.5.6"), die Asset-Namen enthalten die Version
# (z.B. "processing-4.5.6-linux-x64.flatpak"). Bezogen werden nur stabile Releases
# über /releases/latest, das Release Candidates (GitHub-Prereleases) ausschließt.
# Die App-ID des GitHub-Bundles ist org.processing.pde; das Flathub-Paket
# (org.processing.processingide) ist davon unabhängig.

require_cmd curl "curl ist nicht installiert."
require_cmd python3 "python3 ist nicht installiert."
require_cmd flatpak "flatpak ist nicht installiert."

APP_ID="org.processing.pde"
MARKER_FILE="$SCRIPT_DIR/.processing-installed-version"

echo "🔍 Suche nach der neuesten stabilen Processing-Version..."

DL_ARCH=$(detect_arch "x64" "aarch64") || exit 1

# Lokale Kopie mit festem Dateinamen (ohne Version), damit sie bei einem Update
# ersetzt wird und keine alten Bundles liegen bleiben (siehe flatpak_update_app)
TARGET_FILE="$SCRIPT_DIR/processing-linux-${DL_ARCH}.flatpak"

if ! RELEASE_INFO=$(python3 -c '
import urllib.request, json, sys
try:
    req = urllib.request.urlopen("https://api.github.com/repos/processing/processing4/releases/latest", timeout=15)
    data = json.loads(req.read().decode())
    tag = data.get("tag_name", "")
    url = ""
    for asset in data.get("assets", []):
        if asset.get("name", "").endswith(sys.argv[1]):
            url = asset.get("browser_download_url", "")
            break
    if not tag or not url:
        print("Kein passendes Flatpak-Bundle in der neuesten Release gefunden", file=sys.stderr)
        sys.exit(1)
    print(f"{tag}|{url}")
except Exception as e:
    print(f"{type(e).__name__}: {e}", file=sys.stderr)
    sys.exit(1)
' "-linux-${DL_ARCH}.flatpak"); then
    echo "❌ Fehler: Konnte die neueste stabile Processing-Release nicht abrufen (siehe Ursache oben)." >&2
    exit 1
fi

TAG=$(echo "$RELEASE_INFO" | cut -d'|' -f1)
URL=$(echo "$RELEASE_INFO" | cut -d'|' -f2)

# Version aus "processing-<Revision>-<Version>" herauslösen
if [[ ! "$TAG" =~ ^processing-[0-9]+-(.+)$ ]]; then
    echo "❌ Fehler: Das Release-Tag '$TAG' hat ein unerwartetes Format." >&2
    exit 1
fi
VERSION="${BASH_REMATCH[1]}"

validate_version "$VERSION" || exit 1

flatpak_update_app "Processing" "$APP_ID" "$TARGET_FILE" "$MARKER_FILE" "$VERSION" "$URL" || exit 1
