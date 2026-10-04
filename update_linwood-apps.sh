#!/bin/bash

# Striktes Fehlermanagement
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Prüfen, ob die benötigten Werkzeuge vorhanden sind
require_cmd curl "curl ist nicht installiert."
require_cmd dnf "dnf ist nicht installiert."
require_cmd rpm "rpm ist nicht installiert."
require_cmd python3 "python3 ist nicht installiert."

# Zielverzeichnis dynamisch auf den Speicherort dieses Skripts setzen
DEST_DIR="$SCRIPT_DIR"

echo "🔍 Überprüfe Updates für Linwood Butterfly und Linwood Flow..."

# Architektur dynamisch ermitteln
DL_ARCH=$(detect_arch "x86_64" "aarch64") || exit 1

# Apps definieren: "Repository-Name|Installierter-Paketname"
APPS=(
    "butterfly|linwood-butterfly"
    "Flow|linwood-flow"
)

# Fehlgeschlagene Apps sammeln: Die Schleife läuft bei einem Fehler mit der nächsten
# App weiter, am Ende meldet das Skript den Fehlschlag aber per Exit-Code, damit
# update_all.sh ihn in seiner Zusammenfassung aufführt.
FAILED_APPS=()

for APP in "${APPS[@]}"; do
    echo "------------------------------------------------"
    IFS='|' read -r REPO PKG_NAME <<< "$APP"

    echo "🌐 Frage GitHub-API für $PKG_NAME ab..."

    if ! API_RESPONSE=$(find_latest_github_rpm_release "LinwoodDev/$REPO" "linux-${DL_ARCH}.rpm"); then
        echo "❌ Fehler: Konnte Release-Infos für $PKG_NAME nicht abrufen (siehe Ursache oben, oder API-Limit erreicht)." >&2
        FAILED_APPS+=("$PKG_NAME")
        continue
    fi

    NEW_VERSION=$(echo "$API_RESPONSE" | cut -d'|' -f1)
    URL=$(echo "$API_RESPONSE" | cut -d'|' -f2)

    # Validierung der extrahierten Versionsnummer (inklusive Beta-Suffixe)
    if ! validate_version "$NEW_VERSION"; then
        FAILED_APPS+=("$PKG_NAME")
        continue
    fi

    # Lokale Version abrufen und normalisieren
    LOCAL_VERSION=""
    LOCAL_VERSION_NORMALIZED=""

    if rpm -q "$PKG_NAME" >/dev/null 2>&1; then
        LOCAL_VERSION=$(rpm -q --queryformat '%{VERSION}' "$PKG_NAME")
        LOCAL_VERSION_NORMALIZED=$(normalize_version "$LOCAL_VERSION")
    fi

    echo "📦 Installierte Version ($PKG_NAME): ${LOCAL_VERSION:-nicht installiert}"
    echo "🆕 Neueste verfügbare Version:       ${NEW_VERSION}"

    # Zieldatei (wird in beiden Zweigen unten gebraucht)
    TARGET_RPM="$DEST_DIR/${PKG_NAME}-${NEW_VERSION}-linux-${DL_ARCH}.rpm"

    # Abgleich mit der normalisierten Version (inkl. Downgrade-Schutz)
    if ! version_needs_update "$LOCAL_VERSION_NORMALIZED" "$NEW_VERSION"; then
        echo "✅ $PKG_NAME ist bereits aktuell. Es ist kein Update nötig."
        # Auch ohne anstehendes Update immer eine lokale RPM-Kopie der aktuellen Version sicherstellen
        if [ "$LOCAL_VERSION_NORMALIZED" == "$NEW_VERSION" ]; then
            ensure_local_backup "$URL" "$TARGET_RPM" "$DEST_DIR" "${PKG_NAME}-*.rpm" || true
        fi
        continue
    fi

    echo "🔄 Update verfügbar! Starte Download..."

    if ! install_rpm_update "$PKG_NAME" "$URL" "$TARGET_RPM" "${PKG_NAME}-*.rpm"; then
        FAILED_APPS+=("$PKG_NAME")
        continue
    fi

    echo "✅ Installation von $PKG_NAME ($NEW_VERSION) erfolgreich abgeschlossen!"
done

echo "------------------------------------------------"
if [ "${#FAILED_APPS[@]}" -gt 0 ]; then
    echo "❌ Folgende Linwood-Apps konnten nicht aktualisiert werden: ${FAILED_APPS[*]}" >&2
    exit 1
fi
echo "🎉 Alle Vorgänge abgeschlossen."
