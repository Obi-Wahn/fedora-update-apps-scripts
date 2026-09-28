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

if ! RELEASE_INFO=$(find_github_latest_asset "nextcloud-releases/talk-desktop" "$ASSET_NAME"); then
    echo "❌ Fehler: Konnte die neueste stabile Nextcloud-Talk-Desktop-Release nicht abrufen (siehe Ursache oben)." >&2
    exit 1
fi

TAG=$(echo "$RELEASE_INFO" | cut -d'|' -f1)
URL=$(echo "$RELEASE_INFO" | cut -d'|' -f2)
VERSION="${TAG#v}"

validate_version "$VERSION" || exit 1

flatpak_update_app "Nextcloud Talk Desktop" "$APP_ID" "$TARGET_FILE" "$MARKER_FILE" "$VERSION" "$URL" || exit 1
