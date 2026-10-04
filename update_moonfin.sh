#!/bin/bash

# Striktes Fehlermanagement aktivieren
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Prüfen, ob die benötigten Werkzeuge vorhanden sind
require_cmd curl "curl ist nicht installiert."
require_cmd dnf "dnf ist nicht installiert."
require_cmd rpm "rpm ist nicht installiert."
require_cmd python3 "python3 ist nicht installiert."

echo "🔍 Überprüfe auf neue Moonfin-Versionen..."

# Architektur dynamisch ermitteln (mit Positiv- und Negativ-Listen)
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    DL_ARCH="x86_64"
    VALID_ARCHS="x86_64 amd64 x64"
    INVALID_ARCHS="aarch64 arm64 armv"
elif [ "$ARCH" = "aarch64" ]; then
    DL_ARCH="aarch64"
    VALID_ARCHS="aarch64 arm64"
    INVALID_ARCHS="x86_64 amd64 x64"
else
    echo "❌ Fehler: Architektur $ARCH wird von diesem Skript nicht unterstützt." >&2
    exit 1
fi

# API abfragen (Mit intelligentem Ausschlussverfahren)
if ! API_RESPONSE=$(python3 -c '
import urllib.request, json, sys, re
try:
    req = urllib.request.urlopen("https://api.github.com/repos/Moonfin-Client/Moonfin-Core/releases/latest", timeout=15)
    data = json.loads(req.read().decode())
    version = data.get("tag_name", "").lstrip("v")

    valid_archs = sys.argv[1].split()
    invalid_archs = sys.argv[2].split()
    download_url = ""

    # 1. Priorität: Exakter Architektur-Treffer im Dateinamen
    for asset in data.get("assets", []):
        name = asset.get("name", "").lower()
        if name.endswith(".rpm") and any(a in name for a in valid_archs):
            download_url = asset["browser_download_url"]
            break

    # 2. Priorität: Fallback auf ein RPM-Paket, das KEINE falsche Architektur im Namen trägt
    if not download_url:
        for asset in data.get("assets", []):
            name = asset.get("name", "").lower()
            if name.endswith(".rpm") and not any(i in name for i in invalid_archs):
                download_url = asset["browser_download_url"]
                break

    if download_url:
        print(f"{version}|{download_url}")
        exit(0)
    exit(1)
except Exception as e:
    print(f"{type(e).__name__}: {e}", file=sys.stderr)
    exit(1)
' "$VALID_ARCHS" "$INVALID_ARCHS"); then
    echo "❌ Fehler: Konnte kein passendes RPM-Paket für $ARCH auf GitHub finden (siehe Ursache oben, oder API-Limit erreicht)." >&2
    exit 1
fi

LATEST_VERSION=$(echo "$API_RESPONSE" | cut -d'|' -f1)
LATEST_URL=$(echo "$API_RESPONSE" | cut -d'|' -f2)

# Validierung der extrahierten Versionsnummer
validate_version "$LATEST_VERSION" || exit 1

# Lokale Version abrufen und normalisieren
LOCAL_VERSION=""
LOCAL_VERSION_NORMALIZED=""
if rpm -q moonfin >/dev/null 2>&1; then
    LOCAL_VERSION=$(rpm -q --queryformat '%{VERSION}\n' moonfin)
    LOCAL_VERSION_NORMALIZED=$(normalize_version "$LOCAL_VERSION")
fi

echo "📦 Installierte Version: ${LOCAL_VERSION:-nicht installiert}"
echo "🌐 Neueste Version:      ${LATEST_VERSION}"

# Zielverzeichnis und Zieldatei (werden in beiden Zweigen unten gebraucht)
DEST_DIR="$SCRIPT_DIR"
TARGET_RPM="$DEST_DIR/moonfin-${LATEST_VERSION}-${DL_ARCH}.rpm"

# Versionsvergleich (inkl. Downgrade-Schutz)
if ! version_needs_update "$LOCAL_VERSION_NORMALIZED" "$LATEST_VERSION"; then
    echo "✅ Du hast bereits die aktuellste Version installiert. Es ist kein Update nötig."
    # Auch ohne anstehendes Update immer eine lokale RPM-Kopie der aktuellen Version sicherstellen
    if [ "$LOCAL_VERSION_NORMALIZED" == "$LATEST_VERSION" ]; then
        ensure_local_backup "$LATEST_URL" "$TARGET_RPM" "$DEST_DIR" "moonfin-*.rpm" || true
    fi
    exit 0
fi

install_rpm_update "Moonfin" "$LATEST_URL" "$TARGET_RPM" "moonfin-*.rpm" || exit 1

echo "------------------------------------------------"
echo "✅ Installation von Moonfin $LATEST_VERSION erfolgreich abgeschlossen!"
echo "------------------------------------------------"
