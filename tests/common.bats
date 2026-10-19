#!/usr/bin/env bats
# Tests der Hilfsfunktionen in common.sh (mit Mocks aus tests/mocks).

load test_helper

setup() {
    setup_workdir
}

# --- Versionen ---------------------------------------------------------------

@test "normalize_version: Tilde wird zu Bindestrich" {
    run_common normalize_version "2.6.1~rc.0"
    [ "$status" -eq 0 ]
    [ "$output" = "2.6.1-rc.0" ]
}

@test "validate_version: gültige Formate" {
    local v
    for v in 1.2.3 2.6.1-rc.0 1.0.0-beta.6 10.20.30rc1; do
        run_common validate_version "$v"
        [ "$status" -eq 0 ] || { echo "abgelehnt: $v"; return 1; }
    done
}

@test "validate_version: ungültige Formate" {
    local v
    for v in v1.2.3 1.2 "1.2.3 x" "1.2.3;rm" 1.2.3~rc1 ""; do
        run_common validate_version "$v"
        [ "$status" -eq 1 ] || { echo "angenommen: '$v'"; return 1; }
    done
}

@test "validate_identifier: erlaubt freie Tags, lehnt Sonderzeichen ab" {
    run_common validate_identifier "GeneralsX-Beta-19"
    [ "$status" -eq 0 ]
    run_common validate_identifier "1.0.4"
    [ "$status" -eq 0 ]
    local v
    for v in "a/b" "a b" "" '$(x)'; do
        run_common validate_identifier "$v"
        [ "$status" -eq 1 ] || { echo "angenommen: '$v'"; return 1; }
    done
}

@test "version_needs_update: Entscheidungen inkl. Downgrade-Schutz" {
    # lokal | entfernt | erwarteter Status (0 = Update, 1 = kein Update)
    local cases=(
        "|2.70.0|0"
        "2.70.0|2.70.0|1"
        "2.70.0|2.71.0|0"
        "2.71.0|2.70.0|1"
        "2.6.1-rc.0|2.6.1|0"
        "2.6.1-rc.0|2.6.1-rc.0|1"
        "1.9.0|1.10.0|0"
    )
    local c local_v remote_v expected
    for c in "${cases[@]}"; do
        IFS='|' read -r local_v remote_v expected <<< "$c"
        run_common version_needs_update "$local_v" "$remote_v"
        [ "$status" -eq "$expected" ] || { echo "Fall '$c': Status $status"; return 1; }
    done
}

@test "detect_arch: x86_64, aarch64 und nicht unterstützte Architektur" {
    MOCK_ARCH=x86_64 run_common detect_arch amd64 arm64
    [ "$output" = "amd64" ]
    MOCK_ARCH=aarch64 run_common detect_arch amd64 arm64
    [ "$output" = "arm64" ]
    MOCK_ARCH=armv7l run_common detect_arch amd64 arm64
    [ "$status" -eq 1 ]
    [[ "$output" == *"nicht unterstützt"* ]]
}

# --- Downloads und Dateien ---------------------------------------------------

@test "download_file: Erfolg ersetzt die Zieldatei, keine .part-Datei bleibt" {
    echo "alt" > ziel.flatpak
    run_common download_file "https://example.invalid/neu" "$WORK/ziel.flatpak"
    [ "$status" -eq 0 ]
    grep -q "RPMDATA https://example.invalid/neu" ziel.flatpak
    [ ! -e ziel.flatpak.part ]
}

@test "download_file: Fehlschlag lässt vorhandene Datei unverändert" {
    echo "alt" > ziel.flatpak
    CURL_FAIL=example.invalid run_common download_file "https://example.invalid/neu" "$WORK/ziel.flatpak"
    [ "$status" -eq 1 ]
    [ "$(cat ziel.flatpak)" = "alt" ]
    [ ! -e ziel.flatpak.part ]
}

@test "download_file: kein festes Zeitlimit, Abbruch nur bei stockendem Download" {
    run_common declare -f download_file
    [[ "$output" == *"--speed-limit 1024 --speed-time 60"* ]]
    [[ "$output" != *"--max-time"* ]]
}

@test "Strg+C-Trap entfernt nur die .part-Datei" {
    echo "alt" > ziel.flatpak
    echo "halb" > ziel.flatpak.part
    run bash -c 'source "$0"; trap_download_cleanup "$1"; kill -INT $$; sleep 1' \
        "$REPO_DIR/common.sh" "$WORK/ziel.flatpak"
    [ "$(cat ziel.flatpak)" = "alt" ]
    [ ! -e ziel.flatpak.part ]
}

@test "cleanup_old_files: entfernt nur ältere Dateien desselben Programms" {
    touch moonfin-2.6.0-x86_64.rpm zoom_x86_64.rpm
    run_common cleanup_old_files "$WORK" "moonfin-*.rpm" "moonfin-2.7.0-x86_64.rpm"
    [ "$status" -eq 0 ]
    [ ! -e moonfin-2.6.0-x86_64.rpm ]
    [ -e moonfin-2.7.0-x86_64.rpm ]
    [ -e zoom_x86_64.rpm ]
}

# --- RPM-Prüfung (gemockte rpm-Ausgaben in beiden Formaten) ------------------

# Schreibt einen rpm-Mock, der für "-Kv --nodigest" die übergebene Zeile ausgibt,
# und gibt das Verzeichnis aus, das vor den PATH gestellt werden muss.
mock_rpm_signature() {
    local dir
    dir="$(mktemp -d "$BATS_TEST_TMPDIR/sigbin.XXXX")"
    printf '%s\n' "$1" > "$dir/zeile"
    cat > "$dir/rpm" <<EOF
#!/bin/bash
case "\$1" in
    -qip|-K) exit 0 ;;
    -Kv) echo "\${!#}:"; cat "$dir/zeile" ;;
esac
EOF
    chmod +x "$dir/rpm"
    echo "$dir"
}

@test "verify_rpm: Signaturzeilen im RPM-4- und RPM-6-Format" {
    # Ausgabezeile | erwarteter Status | erwarteter Text
    local cases=(
        "    Header V4 RSA/SHA256 Signature, key ID ab12: BAD|1|ungültig"
        "    Header V4 RSA/SHA256 Signature, key ID ab12: NOKEY|0|nicht importiert"
        "    Header V4 RSA/SHA256 Signature, key ID ab12: OK|0|gültig"
        "    Header OpenPGP V4 RSA/SHA512 signature, key fingerprint: 0a1b: BAD|1|ungültig"
        "    Header OpenPGP V4 RSA/SHA512 signature, key ID e2b5: NOKEY|0|nicht importiert"
        "    Header OpenPGP V4 RSA/SHA512 signature, key fingerprint: 0a1b: OK|0|gültig"
        "    Header OpenPGP signature: NOTFOUND|0|nicht signiert"
        "|0|nicht signiert"
    )
    local c line expected text dir
    for c in "${cases[@]}"; do
        IFS='|' read -r line expected text <<< "$c"
        dir="$(mock_rpm_signature "$line")"
        echo "x" > paket.rpm
        PATH="$dir:$PATH" run_common verify_rpm "$WORK/paket.rpm"
        [ "$status" -eq "$expected" ] || { echo "Fall '$c': Status $status, $output"; return 1; }
        [[ "$output" == *"$text"* ]] || { echo "Fall '$c': $output"; return 1; }
        if [ "$expected" -eq 1 ]; then
            [ ! -e paket.rpm ] || { echo "Fall '$c': Datei nicht gelöscht"; return 1; }
        fi
    done
}

@test "rpm_file_is_intact: fehlende und beschädigte Datei" {
    run_common rpm_file_is_intact "$WORK/gibt-es-nicht.rpm"
    [ "$status" -eq 1 ]
    echo "KAPUTT" > kaputt.rpm
    run_common rpm_file_is_intact "$WORK/kaputt.rpm"
    [ "$status" -eq 1 ]
    echo "ok" > gut.rpm
    run_common rpm_file_is_intact "$WORK/gut.rpm"
    [ "$status" -eq 0 ]
}

# --- install_rpm_update ------------------------------------------------------

@test "install_rpm_update: intakte lokale Kopie wird ohne Download installiert" {
    run_common install_rpm_update Moonfin https://example.invalid/m.rpm \
        "$WORK/moonfin-2.7.0-x86_64.rpm" "moonfin-*.rpm"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nutze vorhandene lokale Kopie"* ]]
    [ "$(mock_calls '^curl')" -eq 0 ]
    [ "$(mock_calls 'dnf install -y .*moonfin-2.7.0-x86_64.rpm')" -eq 1 ]
}

@test "install_rpm_update: beschädigte lokale Kopie wird neu geladen" {
    echo "KAPUTT" > moonfin-2.7.0-x86_64.rpm
    run_common install_rpm_update Moonfin https://example.invalid/m.rpm \
        "$WORK/moonfin-2.7.0-x86_64.rpm" "moonfin-*.rpm"
    [ "$status" -eq 0 ]
    [[ "$output" == *"beschädigt, lade sie neu herunter"* ]]
    [ "$(mock_calls '^curl')" -eq 1 ]
    grep -q RPMDATA moonfin-2.7.0-x86_64.rpm
}

@test "install_rpm_update: neue Version wird geladen, installiert, alte entfernt" {
    run_common install_rpm_update Moonfin https://example.invalid/m.rpm \
        "$WORK/moonfin-2.8.0-x86_64.rpm" "moonfin-*.rpm"
    [ "$status" -eq 0 ]
    [ -e moonfin-2.8.0-x86_64.rpm ]
    [ ! -e moonfin-2.7.0-x86_64.rpm ]
}

@test "install_rpm_update: Download-Fehler bricht ohne dnf ab" {
    CURL_FAIL=example.invalid run_common install_rpm_update Moonfin https://example.invalid/m.rpm \
        "$WORK/moonfin-2.8.0-x86_64.rpm" "moonfin-*.rpm"
    [ "$status" -eq 1 ]
    [ "$(mock_calls '^dnf')" -eq 0 ]
    [ -e moonfin-2.7.0-x86_64.rpm ]
}

@test "install_rpm_update: dnf-Fehler wird gemeldet, alte Pakete bleiben" {
    DNF_FAIL=moonfin run_common install_rpm_update Moonfin https://example.invalid/m.rpm \
        "$WORK/moonfin-2.8.0-x86_64.rpm" "moonfin-*.rpm"
    [ "$status" -eq 1 ]
    [[ "$output" == *"dnf install für Moonfin fehlgeschlagen"* ]]
    [ -e moonfin-2.7.0-x86_64.rpm ]
}

# --- Schutzmechanismen -------------------------------------------------------

@test "common.sh verweigert den Start als root" {
    MOCK_ROOT=1 run bash -c 'source "$0"; echo "nicht erreicht"' "$REPO_DIR/common.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Bitte nicht als root"* ]]
    [[ "$output" != *"nicht erreicht"* ]]
}

@test "ERR-Trap meldet unerwartete Fehler mit Zeile und Befehl" {
    cat > fehler.sh <<'EOF'
set -Eeuo pipefail
source "$1"
false || true
if ! false; then :; fi
X=$(false || true)
ls /gibt/es/nicht >/dev/null 2>&1
echo "nicht erreicht"
EOF
    run bash fehler.sh "$REPO_DIR/common.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unerwarteter Fehler in fehler.sh, Zeile 6: 'ls /gibt/es/nicht"* ]]
    [ "$(grep -c 'Unerwarteter Fehler' <<< "$output")" -eq 1 ]
    [[ "$output" != *"nicht erreicht"* ]]
}
