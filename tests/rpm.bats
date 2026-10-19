#!/usr/bin/env bats
# Prüft verify_rpm() und rpm_file_is_intact() gegen das ECHTE rpm, mit den
# Test-RPMs aus tests/build-test-rpms.sh. In der CI läuft das im aktuellen
# Fedora-Container, so fallen Änderungen am Ausgabeformat von rpm (wie
# "Signature" -> "signature" in RPM 6) sofort auf.
#
# Voraussetzungen:
#   TEST_RPM_DIR      - Verzeichnis mit den Test-RPMs
#   key-known.asc     - muss vorab importiert sein (rpmkeys --import, als root)
#   REQUIRE_RPM_TESTS - =1: fehlende Voraussetzungen sind ein Fehler statt "skip"

load test_helper

setup() {
    if [ -z "${TEST_RPM_DIR:-}" ] || ! command -v rpm >/dev/null 2>&1; then
        if [ "${REQUIRE_RPM_TESTS:-0}" = 1 ]; then
            echo "TEST_RPM_DIR oder rpm fehlt" >&2
            return 1
        fi
        skip "TEST_RPM_DIR nicht gesetzt oder rpm nicht installiert"
    fi
    # Bewusst ohne Mocks: echtes rpm
    WORK="$BATS_TEST_TMPDIR"
}

# Kopiert ein Test-RPM ins Testverzeichnis (verify_rpm löscht ungültige Dateien)
# und prüft es mit verify_rpm.
verify_test_rpm() {
    cp "$TEST_RPM_DIR/$1" "$WORK/$1"
    run_common verify_rpm "$WORK/$1"
    echo "$output"
}

@test "rpm: Version ausgeben (Info für das CI-Protokoll)" {
    run rpm --version
    echo "# $output" >&3
    [ "$status" -eq 0 ]
}

@test "echtes rpm: unsigniertes Paket wird akzeptiert" {
    verify_test_rpm unsigned.rpm
    [ "$status" -eq 0 ]
    [[ "$output" == *"nicht signiert"* ]]
    [ -e "$WORK/unsigned.rpm" ]
}

@test "echtes rpm: Signatur mit importiertem Schlüssel ist gültig" {
    verify_test_rpm signed-known.rpm
    [ "$status" -eq 0 ]
    [[ "$output" == *"GPG-Signatur des RPM-Pakets ist gültig"* ]]
}

@test "echtes rpm: Signatur mit unbekanntem Schlüssel ergibt nur einen Hinweis" {
    verify_test_rpm signed-unknown.rpm
    [ "$status" -eq 0 ]
    [[ "$output" == *"Schlüssel ist aber nicht importiert"* ]]
    [ -e "$WORK/signed-unknown.rpm" ]
}

@test "echtes rpm: manipulierte Signatur bricht ab und löscht die Datei" {
    # RPM 6 verweigert bei einer ungültigen Signatur (mit importiertem Schlüssel)
    # schon die Abfrage per "rpm -qip"; ältere Versionen fallen erst bei der
    # Signaturprüfung auf. Entscheidend ist: Abbruch und Datei gelöscht.
    verify_test_rpm bad-signature.rpm
    [ "$status" -eq 1 ]
    [[ "$output" == *"GPG-Signatur des RPM-Pakets ist ungültig"* ]] ||
        [[ "$output" == *"kein gültiges RPM-Paket"* ]]
    [ ! -e "$WORK/bad-signature.rpm" ]
}

@test "echtes rpm: beschädigter Inhalt fällt bei den Prüfsummen auf" {
    verify_test_rpm corrupt-payload.rpm
    [ "$status" -eq 1 ]
    [[ "$output" == *"Prüfsummen des RPM-Pakets stimmen nicht"* ]]
    [ ! -e "$WORK/corrupt-payload.rpm" ]
}

@test "echtes rpm: Datei ohne RPM-Struktur wird abgelehnt" {
    verify_test_rpm not-an-rpm.rpm
    [ "$status" -eq 1 ]
    [[ "$output" == *"kein gültiges RPM-Paket"* ]]
}

@test "echtes rpm: rpm_file_is_intact erkennt intakte und beschädigte Dateien" {
    run_common rpm_file_is_intact "$TEST_RPM_DIR/unsigned.rpm"
    [ "$status" -eq 0 ]
    run_common rpm_file_is_intact "$TEST_RPM_DIR/signed-unknown.rpm"
    [ "$status" -eq 0 ]
    run_common rpm_file_is_intact "$TEST_RPM_DIR/corrupt-payload.rpm"
    [ "$status" -eq 1 ]
    # rpm liest eine Datei ohne RPM-Struktur als "Manifest" und meldet Exit 4
    run_common rpm_file_is_intact "$TEST_RPM_DIR/not-an-rpm.rpm"
    [ "$status" -ne 0 ]
}
