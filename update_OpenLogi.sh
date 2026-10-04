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

echo "🔍 Suche nach der neuesten OpenLogi-Version mit verfügbarem RPM-Paket..."

# Architektur dynamisch ermitteln
DL_ARCH=$(detect_arch "amd64" "arm64") || exit 1

# API-Abfrage mit sicherem Error-Handling
if ! READ_DATA=$(find_latest_github_rpm_release "AprilNEA/OpenLogi" "linux-${DL_ARCH}.rpm"); then
    echo "❌ Fehler: Konnte in den GitHub-Releases kein passendes RPM-Paket finden (siehe Ursache oben, oder API-Limit erreicht)." >&2
    exit 1
fi

LATEST_VERSION=$(echo "$READ_DATA" | cut -d'|' -f1)
LATEST_URL=$(echo "$READ_DATA" | cut -d'|' -f2)

# Validierung der extrahierten Versionsnummer (Regex-Schutz)
validate_version "$LATEST_VERSION" || exit 1

LOCAL_VERSION=""
LOCAL_VERSION_NORMALIZED=""
if rpm -q openlogi >/dev/null 2>&1; then
    LOCAL_VERSION=$(rpm -q --queryformat '%{VERSION}\n' openlogi)
    LOCAL_VERSION_NORMALIZED=$(normalize_version "$LOCAL_VERSION")
fi

echo "📦 Installierte Version: ${LOCAL_VERSION:-none}"
echo "🌐 Neueste verfügbare Version mit RPM: ${LATEST_VERSION}"

# Zielverzeichnis und Zieldatei (werden in beiden Zweigen unten gebraucht)
DEST_DIR="$SCRIPT_DIR"
TARGET_RPM="$DEST_DIR/openlogi-${LATEST_VERSION}-linux-${DL_ARCH}.rpm"

# Versionsvergleich (inkl. Downgrade-Schutz)
if ! version_needs_update "$LOCAL_VERSION_NORMALIZED" "$LATEST_VERSION"; then
    echo "✅ Du hast bereits die aktuellste Version mit RPM-Paket installiert. Es ist kein Update nötig."
    # Auch ohne anstehendes Update immer eine lokale RPM-Kopie der aktuellen Version sicherstellen
    if [ "$LOCAL_VERSION_NORMALIZED" == "$LATEST_VERSION" ]; then
        ensure_local_backup "$LATEST_URL" "$TARGET_RPM" "$DEST_DIR" "openlogi-*.rpm" || true
    fi
    exit 0
fi

echo "🔄 Ein Update auf Version $LATEST_VERSION ist verfügbar! Starte Download..."

install_rpm_update "OpenLogi" "$LATEST_URL" "$TARGET_RPM" "openlogi-*.rpm" || exit 1

echo "------------------------------------------------"
echo "✅ Update auf OpenLogi $LATEST_VERSION erfolgreich abgeschlossen!"
echo "------------------------------------------------"
