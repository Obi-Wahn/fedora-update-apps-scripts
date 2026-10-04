#!/bin/bash

# Striktes Fehlermanagement aktivieren
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 1. Prüfen, ob die benötigten Werkzeuge vorhanden sind
require_cmd curl "curl ist nicht installiert."
require_cmd dnf "dnf ist nicht installiert. Dieses Skript erfordert Fedora/RHEL."
require_cmd rpm "rpm ist nicht installiert."

echo "🔍 Suche nach der aktuellsten Docker Desktop Version..."

# 2. Architektur dynamisch ermitteln (Docker nutzt im Link amd64/arm64 und im Dateinamen x86_64/aarch64)
URL_ARCH=$(detect_arch "amd64" "arm64") || exit 1
FILE_ARCH=$(detect_arch "x86_64" "aarch64") || exit 1

NOTES_URL="https://docs.docker.com/desktop/release-notes/"

# 3. Webseite mit Timeout-Schutz abrufen, um unendliches Hängen zu vermeiden
if ! PAGE_CONTENT=$(fetch_text "$NOTES_URL"); then
    echo "❌ Fehler: Konnte die Docker Release Notes nicht abrufen (Timeout oder Netzwerkfehler)." >&2
    exit 1
fi

# 4. Den neuesten RPM-Downloadlink dynamisch auslesen
RPM_URL=$(echo "$PAGE_CONTENT" | grep -Eo "https://desktop\.docker\.com/linux/main/${URL_ARCH}/[0-9]+/docker-desktop-${FILE_ARCH}\.rpm" | head -n 1)

if [ -z "$RPM_URL" ]; then
    echo "❌ Fehler: Konnte den Fedora Download-Link für $(uname -m) in den Release Notes nicht finden." >&2
    exit 1
fi

# 5. Versionsnummer aus dem HTML-Text extrahieren
VERSION=$(echo "$PAGE_CONTENT" | grep -Eo '>[0-9]+\.[0-9]+\.[0-9]+<' | head -n 1 | tr -d '><')

if [ -z "$VERSION" ]; then
    echo "❌ Fehler: Konnte die Versionsnummer nicht aus der Webseite extrahieren." >&2
    exit 1
fi

# 6. Validierung der extrahierten Versionsnummer (Regex-Schutz)
validate_version "$VERSION" || exit 1

# 7. Lokale Version ermitteln und normalisieren
LOCAL_VERSION=""
LOCAL_VERSION_NORMALIZED=""
if rpm -q docker-desktop >/dev/null 2>&1; then
    LOCAL_VERSION=$(rpm -q --queryformat '%{VERSION}' docker-desktop)
    LOCAL_VERSION_NORMALIZED=$(normalize_version "$LOCAL_VERSION")
fi

# 8. Zielverzeichnis und Zieldatei (werden in beiden Zweigen unten gebraucht)
DEST_DIR="$SCRIPT_DIR"
TARGET_RPM="$DEST_DIR/docker-desktop-${VERSION}-${FILE_ARCH}.rpm"

# 9. Versionsabgleich (inkl. Downgrade-Schutz)
if ! version_needs_update "$LOCAL_VERSION_NORMALIZED" "$VERSION"; then
    echo "✅ Docker Desktop ist bereits aktuell (installiert: ${LOCAL_VERSION:-nicht installiert}, Release: $VERSION)."
    # Auch ohne anstehendes Update immer eine lokale RPM-Kopie der aktuellen Version sicherstellen
    if [ "$LOCAL_VERSION_NORMALIZED" == "$VERSION" ]; then
        ensure_local_backup "$RPM_URL" "$TARGET_RPM" "$DEST_DIR" "docker-desktop-*.rpm" || true
    fi
    exit 0
fi

echo "🔄 Neue Version verfügbar: $VERSION (lokal: ${LOCAL_VERSION:-nicht installiert})"

# 10. Download, Prüfung, Installation und Aufräumen
install_rpm_update "Docker Desktop" "$RPM_URL" "$TARGET_RPM" "docker-desktop-*.rpm" || exit 1

echo "------------------------------------------------"
echo "✅ Update auf Docker Desktop $VERSION erfolgreich abgeschlossen!"
echo "------------------------------------------------"
