#!/bin/bash

# Striktes Fehlermanagement
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Linwood Flow (https://github.com/LinwoodDev/Flow) veröffentlicht RPM-Pakete in
# den GitHub-Releases. Gesucht wird das neueste Release mit passendem RPM-Asset,
# Vorabversionen (z.B. "-rc.1") eingeschlossen.

# Prüfen, ob die benötigten Werkzeuge vorhanden sind
require_cmd curl "curl ist nicht installiert."
require_cmd dnf "dnf ist nicht installiert."
require_cmd rpm "rpm ist nicht installiert."
require_cmd python3 "python3 ist nicht installiert."

PKG_NAME="linwood-flow"

echo "🔍 Überprüfe Updates für Linwood Flow..."

# Architektur dynamisch ermitteln
DL_ARCH=$(detect_arch "x86_64" "aarch64") || exit 1

if ! RELEASE_INFO=$(find_latest_github_rpm_release "LinwoodDev/Flow" "linux-${DL_ARCH}.rpm"); then
    echo "❌ Fehler: Konnte Release-Infos für Linwood Flow nicht abrufen (siehe Ursache oben, oder API-Limit erreicht)." >&2
    exit 1
fi

LATEST_VERSION=$(echo "$RELEASE_INFO" | cut -d'|' -f1)
LATEST_URL=$(echo "$RELEASE_INFO" | cut -d'|' -f2)

# Validierung der extrahierten Versionsnummer (inklusive Beta-Suffixe)
validate_version "$LATEST_VERSION" || exit 1

TARGET_RPM="$SCRIPT_DIR/${PKG_NAME}-${LATEST_VERSION}-linux-${DL_ARCH}.rpm"

rpm_update_app "Linwood Flow" "$PKG_NAME" "$LATEST_VERSION" "$LATEST_URL" "$TARGET_RPM" "${PKG_NAME}-*.rpm" || exit 1
