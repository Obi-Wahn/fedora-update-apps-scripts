#!/bin/bash

# Striktes Fehlermanagement
set -euo pipefail
# Verhindert fehlerhafte Schleifen, wenn keine Skripte existieren
shopt -s nullglob

echo "🚀 Starte das globale Update-Programm..."

# Einmal vorab sudo-Rechte anfordern
sudo -v

# Sudo-Keepalive im Hintergrund mit sauberem Cleanup
SUDO_PID=""
trap '[ -n "$SUDO_PID" ] && kill "$SUDO_PID" 2>/dev/null || true' EXIT
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_PID=$!

# Verzeichnis dynamisch auf den Speicherort dieses Skripts setzen
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MASTER_SCRIPT="$SCRIPT_DIR/$(basename "$0")"

# Array für fehlgeschlagene Skripte
FAILED=()

# Alle Dateien suchen, die mit "update_" beginnen und auf ".sh" enden
for script in "$SCRIPT_DIR"/update_*.sh; do

    # Das Master-Skript überspringen
    if [ "$script" == "$MASTER_SCRIPT" ]; then
        continue
    fi

    CLEAN_NAME=$(basename "$script" | sed -e 's/update_//' -e 's/\.sh//')

    echo "========================================"
    echo "🔄 Führe aus: $CLEAN_NAME"

    # Sicherheitsprüfung: Gehört das Skript dem aktuellen Nutzer?
    if [ ! -O "$script" ]; then
        echo "⚠️ Übersprungen: Skript gehört nicht dir (Sicherheitsrisiko)."
        continue
    fi

    # Ausführbarkeitsprüfung
    if [ ! -x "$script" ]; then
        echo "⚠️ Übersprungen: Skript ist nicht ausführbar (chmod +x fehlt)."
        continue
    fi

    # Das Skript ausführen und bei Fehler erfassen
    if ! "$script"; then
        echo "⚠️ Fehler bei $CLEAN_NAME aufgetreten."
        FAILED+=("$CLEAN_NAME")
    fi
done

echo "========================================"

# Fehler-Zusammenfassung und Exit-Code
if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "❌ Abschluss mit Fehlern! Folgende Updates sind fehlgeschlagen:"
    for failed_script in "${FAILED[@]}"; do
        echo "   - $failed_script"
    done
    exit 1
else
    echo "🎉 Alle Update-Vorgänge wurden erfolgreich abgeschlossen!"
fi
