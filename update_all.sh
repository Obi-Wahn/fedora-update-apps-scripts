#!/bin/bash

# Striktes Fehlermanagement
set -Eeuo pipefail
# Verhindert fehlerhafte Schleifen, wenn keine Skripte existieren
shopt -s nullglob

# Nicht als root bzw. mit sudo starten: Die Eigentümer-Prüfung unten würde sonst
# jedes Skript überspringen, und heruntergeladene Dateien würden root gehören.
if [ "$(id -u)" -eq 0 ]; then
    echo "❌ Fehler: Bitte nicht als root bzw. mit sudo starten. Das Skript fordert sudo-Rechte selbst an." >&2
    exit 1
fi

# Unerwartete Fehler mit Zeile, Befehl und Exit-Code melden (Gegenstück zum Trap in
# common.sh; update_all.sh bindet common.sh nicht ein). Nur im Hauptprozess, nicht
# im Sudo-Keepalive.
_report_unexpected_error() {
    local rc="$1"
    local line="$2"
    local cmd="$3"
    [ "$BASH_SUBSHELL" -eq 0 ] || return 0
    echo "❌ Unerwarteter Fehler in update_all.sh, Zeile $line: '$cmd' (Exit-Code $rc)" >&2
}
trap '_report_unexpected_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

# Verzeichnis dynamisch auf den Speicherort dieses Skripts setzen
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MASTER_SCRIPT="$SCRIPT_DIR/$(basename "$0")"

# Dauerhafte Ausschlussliste: ein Programmname pro Zeile, "#" leitet Kommentare ein.
# Der Pfad lässt sich per UPDATE_ALL_SKIP_FILE überschreiben.
SKIP_FILE="${UPDATE_ALL_SKIP_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/fedora-update-apps/skip}"

usage() {
    cat <<USAGE
Aufruf: $(basename "$0") [Optionen]

Führt alle update_*.sh-Skripte in diesem Verzeichnis nacheinander aus.

Optionen:
  --skip NAME[,NAME...]  Diese Programme überspringen (zusätzlich zur Ausschlussliste)
  --only NAME[,NAME...]  Nur diese Programme ausführen (Ausschlussliste wird ignoriert)
  --list                 Verfügbare Programmnamen anzeigen und beenden
  -h, --help             Diese Hilfe anzeigen

Beide Optionen dürfen mehrfach angegeben werden. Groß-/Kleinschreibung ist egal.

Ausschlussliste (ein Name pro Zeile, # für Kommentare):
  $SKIP_FILE
USAGE
}

# Programmname aus dem Skriptpfad: update_fastfetch.sh -> fastfetch
clean_name() {
    local name
    name=$(basename "$1")
    name="${name#update_}"
    echo "${name%.sh}"
}

# Alle Programmnamen (ohne das Master-Skript) einsammeln
AVAILABLE=()
for script in "$SCRIPT_DIR"/update_*.sh; do
    if [ "$script" == "$MASTER_SCRIPT" ]; then
        continue
    fi
    AVAILABLE+=("$(clean_name "$script")")
done

# Liefert 0, wenn der Name (ohne Beachtung der Groß-/Kleinschreibung) in der
# übergebenen Liste steht. Nutzung: in_list <Name> [Listeneinträge...]
in_list() {
    local needle="${1,,}"
    shift
    local entry
    for entry in "$@"; do
        [ "${entry,,}" == "$needle" ] && return 0
    done
    return 1
}

# Kommagetrennte Namen prüfen und an das genannte Array anhängen. Unbekannte Namen
# auf der Kommandozeile sind ein Fehler, damit Tippfehler nicht unbemerkt bleiben.
add_names() {
    local -n target="$1"
    local option="$2"
    local value="$3"
    local name
    local -a names
    IFS=',' read -r -a names <<< "$value"
    if [ "${#names[@]}" -eq 0 ]; then
        echo "❌ Fehler: $option erwartet mindestens einen Programmnamen." >&2
        exit 2
    fi
    for name in "${names[@]}"; do
        name="${name//[[:space:]]/}"
        [ -n "$name" ] || continue
        if ! in_list "$name" "${AVAILABLE[@]}"; then
            echo "❌ Fehler: Unbekanntes Programm '$name' bei $option. Verfügbar: ${AVAILABLE[*]}" >&2
            exit 2
        fi
        target+=("$name")
    done
}

SKIP_CLI=()
ONLY=()
ONLY_SET=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --skip|--only)
            if [ "$#" -lt 2 ]; then
                echo "❌ Fehler: $1 erwartet einen Programmnamen." >&2
                exit 2
            fi
            if [ "$1" == "--skip" ]; then
                add_names SKIP_CLI "$1" "$2"
            else
                add_names ONLY "$1" "$2"
                ONLY_SET=1
            fi
            shift 2
            ;;
        --skip=*)
            add_names SKIP_CLI --skip "${1#*=}"
            shift
            ;;
        --only=*)
            add_names ONLY --only "${1#*=}"
            ONLY_SET=1
            shift
            ;;
        --list)
            printf '%s\n' "${AVAILABLE[@]}"
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "❌ Fehler: Unbekannte Option '$1'." >&2
            usage >&2
            exit 2
            ;;
    esac
done

# Ausschlussliste einlesen (nur ohne --only). Unbekannte Namen dort führen nur zu
# einer Warnung, damit z.B. ein entferntes Skript den Lauf nicht blockiert.
SKIP_FILE_NAMES=()
if [ "$ONLY_SET" -eq 0 ] && [ -f "$SKIP_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line="${line//[[:space:]]/}"
        [ -n "$line" ] || continue
        if ! in_list "$line" "${AVAILABLE[@]}"; then
            echo "⚠️ Warnung: Unbekanntes Programm '$line' in $SKIP_FILE wird ignoriert." >&2
            continue
        fi
        SKIP_FILE_NAMES+=("$line")
    done < "$SKIP_FILE"
fi

echo "🚀 Starte das globale Update-Programm..."

# Einmal vorab sudo-Rechte anfordern
sudo -v

# Sudo-Keepalive im Hintergrund mit sauberem Cleanup. Alle Ausgaben gehen nach
# /dev/null, damit z.B. "./update_all.sh | tee log.txt" am Ende nicht auf den noch
# laufenden Hintergrundprozess wartet.
SUDO_PID=""
trap '[ -n "$SUDO_PID" ] && kill "$SUDO_PID" 2>/dev/null || true' EXIT
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done >/dev/null 2>&1 &
SUDO_PID=$!

# Arrays für fehlgeschlagene und übersprungene Skripte
FAILED=()
SKIPPED=()

# Alle Dateien suchen, die mit "update_" beginnen und auf ".sh" enden
for script in "$SCRIPT_DIR"/update_*.sh; do

    # Das Master-Skript überspringen
    if [ "$script" == "$MASTER_SCRIPT" ]; then
        continue
    fi

    CLEAN_NAME=$(clean_name "$script")

    # Mit --only werden alle anderen Programme kommentarlos ausgelassen
    if [ "$ONLY_SET" -eq 1 ] && ! in_list "$CLEAN_NAME" "${ONLY[@]}"; then
        continue
    fi

    echo "========================================"

    if in_list "$CLEAN_NAME" "${SKIP_CLI[@]}"; then
        echo "⏭️ Übersprungen: $CLEAN_NAME (--skip)"
        SKIPPED+=("$CLEAN_NAME")
        continue
    fi
    if in_list "$CLEAN_NAME" "${SKIP_FILE_NAMES[@]}"; then
        echo "⏭️ Übersprungen: $CLEAN_NAME (Ausschlussliste)"
        SKIPPED+=("$CLEAN_NAME")
        continue
    fi

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

if [ "${#SKIPPED[@]}" -gt 0 ]; then
    echo "⏭️ Übersprungen: ${SKIPPED[*]}"
fi

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
