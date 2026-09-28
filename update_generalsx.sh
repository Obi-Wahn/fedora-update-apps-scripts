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

if ! RELEASE_INFO=$(find_github_latest_asset "fbraz3/GeneralsX" "$ASSET_NAME"); then
    echo "❌ Fehler: Konnte die neueste GeneralsX-Release nicht abrufen (siehe Ursache oben)." >&2
    exit 1
fi

TAG=$(echo "$RELEASE_INFO" | cut -d'|' -f1)
URL=$(echo "$RELEASE_INFO" | cut -d'|' -f2)

# GeneralsX nutzt kein Semver (z.B. "GeneralsX-Beta-19"), daher nur ein loser
# Format-Check statt der strikten X.Y.Z-Validierung der übrigen Skripte
validate_identifier "$TAG" || exit 1

flatpak_update_app "GeneralsX (Zero Hour)" "$APP_ID" "$TARGET_FILE" "$MARKER_FILE" "$TAG" "$URL" || exit 1
