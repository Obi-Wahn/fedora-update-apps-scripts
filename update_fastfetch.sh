#!/bin/bash

# Striktes Fehlermanagement aktivieren
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 1. Prüfen, ob die benötigten Werkzeuge vorhanden sind
require_cmd curl "curl ist nicht installiert."
require_cmd dnf "dnf ist nicht installiert. Dieses Skript erfordert Fedora/RHEL."
require_cmd rpm "rpm ist nicht installiert."
require_cmd python3 "python3 ist nicht installiert."

echo "🔍 Ermittle aktuellste Versionsnummer für Fastfetch..."

# 2. Architektur dynamisch ermitteln
DL_ARCH=$(detect_arch "amd64" "aarch64") || exit 1

# 3. Zuverlässige JSON-Abfrage
if ! VERSION=$(python3 -c '
import urllib.request, json, sys
try:
    req = urllib.request.urlopen("https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest", timeout=15)
    data = json.loads(req.read().decode())
    print(data["tag_name"].lstrip("v"))
except Exception as e:
    print(f"{type(e).__name__}: {e}", file=sys.stderr)
    sys.exit(1)
'); then
    echo "❌ Fehler: Konnte die Versionsnummer von GitHub nicht abrufen (siehe Ursache oben)." >&2
    exit 1
fi

# 4. Validierung der extrahierten Versionsnummer
validate_version "$VERSION" || exit 1

# Lokale Version abrufen und normalisieren
LOCAL_VERSION=""
LOCAL_VERSION_NORMALIZED=""
if command -v fastfetch >/dev/null 2>&1; then
    LOCAL_VERSION=$(fastfetch --version | awk '{print $2}')
    LOCAL_VERSION_NORMALIZED=$(normalize_version "$LOCAL_VERSION")
fi

# 5. Zielverzeichnis, Zieldatei und Download-URL (werden in beiden Zweigen unten gebraucht)
DEST_DIR="$SCRIPT_DIR"
TARGET_RPM="$DEST_DIR/fastfetch-${VERSION}-linux-${DL_ARCH}.rpm"
URL="https://github.com/fastfetch-cli/fastfetch/releases/download/${VERSION}/fastfetch-linux-${DL_ARCH}.rpm"

# Versionsvergleich (inkl. Downgrade-Schutz)
if ! version_needs_update "$LOCAL_VERSION_NORMALIZED" "$VERSION"; then
    echo "✅ Fastfetch ist bereits aktuell (installiert: ${LOCAL_VERSION:-nicht installiert}, Release: $VERSION)."
    # Auch ohne anstehendes Update immer eine lokale RPM-Kopie der aktuellen Version sicherstellen
    if [ "$LOCAL_VERSION_NORMALIZED" == "$VERSION" ]; then
        ensure_local_backup "$URL" "$TARGET_RPM" "$DEST_DIR" "fastfetch-*.rpm" || true
    fi
    exit 0
fi

echo "🔄 Neue Version verfügbar: $VERSION (lokal: ${LOCAL_VERSION:-nicht installiert})"

# 6. Download, Prüfung, Installation und Aufräumen
install_rpm_update "Fastfetch" "$URL" "$TARGET_RPM" "fastfetch-*.rpm" || exit 1

echo "------------------------------------------------"
echo "✅ Update auf Version $VERSION erfolgreich abgeschlossen!"
echo "------------------------------------------------"
