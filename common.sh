#!/bin/bash
# Gemeinsame Hilfsfunktionen für die update_*.sh-Skripte in diesem Repository.
# Wird per "source" eingebunden, nicht direkt ausgeführt.
# Wichtig: Der Dateiname beginnt bewusst NICHT mit "update_", damit update_all.sh
# diese Datei nicht fälschlich als eigenständiges Update-Skript ausführt.

# Prüft, ob ein Kommandozeilenwerkzeug installiert ist; bricht das Skript sonst ab.
require_cmd() {
    local cmd="$1"
    local msg="$2"
    command -v "$cmd" >/dev/null 2>&1 || { echo "❌ Fehler: $msg" >&2; exit 1; }
}

# Ermittelt die lokale CPU-Architektur und gibt den passenden Bezeichner aus,
# den der jeweilige Anbieter in Download-URLs/Dateinamen verwendet.
# Nutzung: WERT=$(detect_arch <wert_fuer_x86_64> <wert_fuer_aarch64>) || exit 1
detect_arch() {
    local x86_64_value="$1"
    local aarch64_value="$2"
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64) echo "$x86_64_value" ;;
        aarch64) echo "$aarch64_value" ;;
        *)
            echo "❌ Fehler: Architektur $arch wird von diesem Skript nicht unterstützt." >&2
            return 1
            ;;
    esac
}

# Prüft, ob eine Versionsnummer ein plausibles Format hat (X.Y.Z, optional mit Suffix
# wie "-rc1" oder "~beta2"), bevor sie in Dateinamen oder URLs verwendet wird.
validate_version() {
    local version="$1"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([a-zA-Z0-9.-]+)?$ ]]; then
        echo "❌ Fehler: Die abgerufene Version '$version' hat ein unerwartetes Format." >&2
        return 1
    fi
}

# Wandelt eine Tilde (~), wie sie rpm für Vorabversionen nutzt, in einen Bindestrich
# um, damit sich die lokale Version textuell mit einem GitHub-Tag vergleichen lässt.
normalize_version() {
    echo "${1//\~/-}"
}

# Gibt Erfolg (0) zurück, wenn ein Update von local_version auf remote_version
# durchgeführt werden soll; Fehlschlag (1), wenn die lokale Version bereits gleich
# oder neuer ist. Ein Downgrade auf eine ältere Release-Version wird so vermieden.
# Der sort -V-Vergleich wird nur bei sauberem X.Y.Z-Format der lokalen Version
# durchgeführt: Bei Suffixen (z.B. "2.1.0-rc1") würde sort -V diese fälschlich als
# "neuer" einstufen und ein berechtigtes Update auf die finale Release blockieren.
version_needs_update() {
    local local_v="$1"
    local remote_v="$2"

    [ -z "$local_v" ] && return 0

    if [ "$local_v" == "$remote_v" ]; then
        return 1
    fi

    if [[ "$local_v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        local newest
        newest=$(printf '%s\n%s\n' "$local_v" "$remote_v" | sort -V | tail -n1)
        [ "$newest" == "$local_v" ] && return 1
    fi

    return 0
}

# Durchsucht die GitHub-Releases eines Repos nach dem neuesten Release, das ein
# Asset besitzt, dessen Name auf asset_suffix endet (z.B. "linux-x86_64.rpm"), und
# gibt "version|download_url" aus. Releases, deren Tag nicht mit X.Y.Z beginnt
# (z.B. reine Text-Tags), werden übersprungen; Beta-/RC-Suffixe sind erlaubt.
# Nutzung: find_latest_github_rpm_release "<org>/<repo>" "linux-${DL_ARCH}.rpm"
find_latest_github_rpm_release() {
    local repo="$1"
    local asset_suffix="$2"
    python3 -c '
import urllib.request, json, sys, re
try:
    req = urllib.request.urlopen(f"https://api.github.com/repos/{sys.argv[1]}/releases", timeout=15)
    releases = json.loads(req.read().decode())

    for release in releases:
        version = release.get("tag_name", "").lstrip("v")
        if not re.match(r"^\d+\.\d+\.\d+", version):
            continue
        for asset in release.get("assets", []):
            if asset.get("name", "").endswith(sys.argv[2]):
                download_url = asset["browser_download_url"]
                print(f"{version}|{download_url}")
                sys.exit(0)

    sys.exit(1)
except Exception as e:
    print(f"{type(e).__name__}: {e}", file=sys.stderr)
    sys.exit(1)
' "$repo" "$asset_suffix"
}

# Lädt eine Textressource (z.B. eine HTML-Seite) mit Timeout-Schutz und gibt den
# Inhalt auf stdout aus.
fetch_text() {
    curl --connect-timeout 10 --max-time 30 -fsSL "$1"
}

# Lädt eine beliebige Datei mit Timeout- und Retry-Schutz herunter (RPM-Pakete,
# Flatpak-Bundles, ...). Bei Fehlschlag wird eine unvollständige Datei entfernt.
download_file() {
    local url="$1"
    local target="$2"
    if ! curl --connect-timeout 10 --max-time 120 -fL -# --retry 3 -o "$target" "$url"; then
        echo "❌ Fehler: Download fehlgeschlagen (Timeout oder Netzwerkfehler)." >&2
        rm -f "$target"
        return 1
    fi
}

# Beibehalten als sprechender Name für die RPM-Skripte; identisch zu download_file.
download_rpm() {
    download_file "$@"
}

# Prüft die RPM-Struktur einer heruntergeladenen Datei; entfernt sie bei Beschädigung.
verify_rpm() {
    local target="$1"
    echo "🛡️ Prüfe Datei-Integrität (RPM-Struktur)..."
    if ! rpm -qip "$target" >/dev/null 2>&1; then
        echo "❌ Fehler: Die heruntergeladene Datei ist beschädigt oder kein gültiges RPM-Paket. Abbruch." >&2
        rm -f "$target"
        return 1
    fi
}

# Entfernt alte Dateien eines Programms (RPM, Flatpak-Bundle, ...) im
# Zielverzeichnis, mit Ausnahme der gerade installierten Version.
cleanup_old_files() {
    local dest_dir="$1"
    local name_pattern="$2"
    local keep_basename="$3"
    find "$dest_dir" -maxdepth 1 -name "$name_pattern" ! -name "$keep_basename" -delete
}

# Beibehalten als sprechender Name für die RPM-Skripte; identisch zu cleanup_old_files.
cleanup_old_rpms() {
    cleanup_old_files "$@"
}

# Prüft ein Versions-/Release-Tag auf ein sicheres, dateinamentaugliches Format
# (nur Buchstaben, Ziffern, Punkt, Bindestrich, Unterstrich), bevor es in
# Dateinamen oder Marker-Dateien verwendet wird. Anders als validate_version()
# erzwingt dies KEIN X.Y.Z-Schema - für Projekte mit freien Tag-Namen wie
# "GeneralsX-Beta-19", bei denen der Anbieter kein Semver nutzt.
validate_identifier() {
    local identifier="$1"
    if [[ ! "$identifier" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "❌ Fehler: Das abgerufene Release-Tag '$identifier' hat ein unerwartetes Format." >&2
        return 1
    fi
}

# Liest die zuletzt erfolgreich installierte Versions-/Release-Kennung aus einer
# einfachen Marker-Datei. Gibt eine leere Zeile aus, wenn die Datei fehlt. Gedacht
# für Formate wie Flatpak, bei denen es keine rpm -q-Entsprechung gibt, um die
# installierte Version zuverlässig abzufragen.
read_installed_marker() {
    local marker_file="$1"
    if [ -f "$marker_file" ]; then
        cat "$marker_file"
    fi
}

# Schreibt die aktuell installierte Versions-/Release-Kennung in die Marker-Datei.
write_installed_marker() {
    local marker_file="$1"
    local identifier="$2"
    printf '%s\n' "$identifier" > "$marker_file"
}

# Stellt sicher, dass für die aktuell installierte (= aktuelle) Version eine lokale
# RPM-Sicherung im Zielverzeichnis liegt, auch wenn kein Update ansteht. Lädt sie bei
# Bedarf nach, installiert dabei aber nichts (die Version läuft ja bereits). Ein
# Fehlschlag ist nicht fatal für das aufrufende Skript, da die bestehende Installation
# davon unberührt bleibt - nur eine Warnung wird ausgegeben.
ensure_local_backup() {
    local url="$1"
    local target="$2"
    local dest_dir="$3"
    local name_pattern="$4"

    [ -f "$target" ] && return 0

    echo "📦 Keine lokale RPM-Sicherung gefunden, lade sie zusätzlich herunter: $target"
    trap_download_cleanup "$target"
    if ! download_rpm "$url" "$target"; then
        clear_download_trap
        echo "⚠️ Warnung: Backup-Download der bereits installierten Version fehlgeschlagen." >&2
        return 1
    fi
    clear_download_trap

    if ! verify_rpm "$target"; then
        echo "⚠️ Warnung: Heruntergeladene Backup-Datei ist ungültig." >&2
        return 1
    fi

    cleanup_old_rpms "$dest_dir" "$name_pattern" "$(basename "$target")"
}

# Räumt eine unvollständige Zieldatei auf, falls der Download per Strg+C
# unterbrochen wird. clear_download_trap() nach einem erfolgreichen Download
# aufrufen, damit spätere Schritte (z.B. die Installation) davon nicht betroffen sind.
_DOWNLOAD_CLEANUP_TARGET=""

trap_download_cleanup() {
    _DOWNLOAD_CLEANUP_TARGET="$1"
    trap 'rm -f "$_DOWNLOAD_CLEANUP_TARGET"' INT TERM
}

clear_download_trap() {
    trap - INT TERM
    _DOWNLOAD_CLEANUP_TARGET=""
}
