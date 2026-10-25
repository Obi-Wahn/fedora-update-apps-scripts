#!/usr/bin/env bats
# Ablauftests der update_*.sh-Skripte und von update_all.sh mit Mocks
# (tests/mocks). Ausgangszustand: alles installiert und aktuell (siehe
# setup_workdir in test_helper.bash).

load test_helper

# Hinweis: update_all.sh startet einen sudo-Keepalive im Hintergrund. "3>&-"
# schließt den Ausgabekanal von Bats für diesen Prozess, sonst wartet Bats am
# Ende auf dessen "sleep 60".

setup() {
    setup_workdir
}

@test "update_all.sh: alles aktuell, Exit 0, keine Installation" {
    run ./update_all.sh 3>&-
    [ "$status" -eq 0 ]
    [[ "$output" == *"Alle Update-Vorgänge wurden erfolgreich abgeschlossen"* ]]
    [[ "$output" != *"Unerwarteter Fehler"* ]]
    [ "$(mock_calls '^dnf')" -eq 0 ]
    [ "$(mock_calls '^flatpak install')" -eq 0 ]
}

@test "update_all.sh: führt alle neun Updater aus" {
    run ./update_all.sh 3>&-
    local name
    for name in docker_desktop fastfetch generalsx linwood_butterfly linwood_flow moonfin OpenLogi processing talk_desktop; do
        [[ "$output" == *"Führe aus: $name"* ]] || { echo "fehlt: $name"; return 1; }
    done
}

@test "update_fastfetch.sh: neue Version wird installiert, alte Kopie entfernt" {
    FF_REMOTE=2.71.0 run ./update_fastfetch.sh
    [ "$status" -eq 0 ]
    [ "$(mock_calls 'dnf install -y .*fastfetch-2.71.0-linux-amd64.rpm')" -eq 1 ]
    [ -e fastfetch-2.71.0-linux-amd64.rpm ]
    [ ! -e fastfetch-2.70.0-linux-amd64.rpm ]
}

@test "Downgrade-Schutz: ältere Version auf GitHub wird nicht installiert" {
    FF_REMOTE=2.69.0 run ./update_fastfetch.sh
    [ "$status" -eq 0 ]
    [ "$(mock_calls '^dnf')" -eq 0 ]
}

@test "Lokale Kopie fehlt: wird ohne Installation nachgeladen" {
    rm openlogi-0.8.14-linux-amd64.rpm
    run ./update_OpenLogi.sh
    [ "$status" -eq 0 ]
    [ -e openlogi-0.8.14-linux-amd64.rpm ]
    [ "$(mock_calls '^dnf')" -eq 0 ]
}

@test "Nicht installiert, lokale Kopie vorhanden: Installation ohne Download" {
    INST_moonfin="" run ./update_moonfin.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installierte Version: nicht installiert"* ]]
    [[ "$output" == *"Nutze vorhandene lokale Kopie"* ]]
    [ "$(mock_calls 'curl https://example.invalid/moonfin.rpm')" -eq 0 ]
    [ "$(mock_calls 'dnf install -y .*moonfin-2.7.0-x86_64.rpm')" -eq 1 ]
}

@test "Docker Desktop: neue Version aus den Release Notes wird installiert" {
    DOCKER_REMOTE=4.96.0 run ./update_docker_desktop.sh
    [ "$status" -eq 0 ]
    [ "$(mock_calls 'dnf install -y .*docker-desktop-4.96.0-x86_64.rpm')" -eq 1 ]
    [ ! -e docker-desktop-4.95.0-x86_64.rpm ]
}

@test "Docker Desktop: große Release-Notes-Seite führt nicht zu SIGPIPE (Exit 141)" {
    # Viele Treffer: Mit "head -n 1" scheiterte die Extraktion hier mit Exit 141.
    DOCKER_REMOTE=4.96.0 DOCKER_PAGE_REPEAT=20000 run ./update_docker_desktop.sh
    [ "$status" -eq 0 ]
    [[ "$output" != *"Unerwarteter Fehler"* ]]
    [ "$(mock_calls 'dnf install -y .*docker-desktop-4.96.0-x86_64.rpm')" -eq 1 ]
}

@test "Docker Desktop: fehlender Download-Link ergibt eigene Fehlermeldung" {
    PATH="$BATS_TEST_TMPDIR/leer:$PATH"
    mkdir -p "$BATS_TEST_TMPDIR/leer"
    printf '#!/bin/bash\necho "<html>umgebaut</html>"\n' > "$BATS_TEST_TMPDIR/leer/curl"
    chmod +x "$BATS_TEST_TMPDIR/leer/curl"
    run ./update_docker_desktop.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"Download-Link"*"nicht finden"* ]]
    [[ "$output" != *"Unerwarteter Fehler"* ]]
}

@test "Linwood Butterfly: Beta-Version (rpm-Tilde) gilt als aktuell" {
    INST_linwood_butterfly="2.7.0~rc.1" BF_REMOTE="2.7.0-rc.1" run ./update_linwood_butterfly.sh
    [ "$status" -eq 0 ]
    [ "$(mock_calls '^dnf')" -eq 0 ]
}

@test "Linwood Butterfly: neue Version wird installiert, Flow bleibt unberührt" {
    BF_REMOTE=2.6.2 FL_REMOTE=0.8.0 run ./update_linwood_butterfly.sh
    [ "$status" -eq 0 ]
    [ "$(mock_calls 'dnf install -y .*linwood-butterfly-2.6.2-linux-x86_64.rpm')" -eq 1 ]
    [ "$(mock_calls 'LinwoodDev/Flow')" -eq 0 ]
    [ -e linwood-butterfly-2.6.2-linux-x86_64.rpm ]
    [ ! -e linwood-butterfly-2.6.1-linux-x86_64.rpm ]
    [ -e linwood-flow-0.7.0-linux-x86_64.rpm ]
}

@test "Linwood Flow: nicht installiert, wird installiert" {
    INST_linwood_flow="" run ./update_linwood_flow.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installierte Version: nicht installiert"* ]]
    [ "$(mock_calls 'dnf install -y .*linwood-flow-0.7.0-linux-x86_64.rpm')" -eq 1 ]
}

@test "Linwood Flow: lokale Kopie fehlt, wird ohne Installation nachgeladen" {
    rm linwood-flow-0.7.0-linux-x86_64.rpm
    run ./update_linwood_flow.sh
    [ "$status" -eq 0 ]
    [ -e linwood-flow-0.7.0-linux-x86_64.rpm ]
    [ "$(mock_calls '^dnf')" -eq 0 ]
}

@test "Linwood Flow: API-Fehler führt zu Exit 1" {
    FAIL_KEY=LinwoodDev/Flow run ./update_linwood_flow.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"Konnte Release-Infos für Linwood Flow nicht abrufen"* ]]
    [[ "$output" != *"Unerwarteter Fehler"* ]]
}

@test "update_all.sh: dnf-Fehler bei Butterfly, Flow wird trotzdem aktualisiert" {
    BF_REMOTE=2.6.2 FL_REMOTE=0.8.0 DNF_FAIL=linwood-butterfly run ./update_all.sh 3>&-
    [ "$status" -eq 1 ]
    [[ "$output" == *"   - linwood_butterfly"* ]]
    [[ "$output" != *"   - linwood_flow"* ]]
    [ "$(mock_calls 'dnf install -y .*linwood-flow-0.8.0')" -eq 1 ]
}

@test "update_all.sh --skip linwood_flow lässt Butterfly laufen" {
    run ./update_all.sh --skip linwood_flow 3>&-
    [ "$status" -eq 0 ]
    [[ "$output" == *"Übersprungen: linwood_flow (--skip)"* ]]
    [[ "$output" == *"Führe aus: linwood_butterfly"* ]]
}

@test "update_all.sh: Fehler werden gesammelt und am Ende gemeldet" {
    BF_REMOTE=2.6.2 DNF_FAIL=linwood-butterfly FAIL_KEY=AprilNEA run ./update_all.sh 3>&-
    [ "$status" -eq 1 ]
    [[ "$output" == *"   - OpenLogi"* ]]
    [[ "$output" == *"   - linwood_butterfly"* ]]
    [[ "$output" == *"Führe aus: talk_desktop"* ]]
    [[ "$output" != *"Unerwarteter Fehler"* ]]
}

@test "update_all.sh: überspringt nicht ausführbare Skripte" {
    chmod -x update_moonfin.sh
    run ./update_all.sh 3>&-
    [ "$status" -eq 0 ]
    [[ "$output" == *"nicht ausführbar"* ]]
}

@test "GeneralsX: neue Version wird system-weit installiert, Marker aktualisiert" {
    GX_REMOTE=1.0.5 run ./update_generalsx.sh
    [ "$status" -eq 0 ]
    [ "$(mock_calls 'flatpak install --system --or-update -y .*Linux-GeneralsXZH.flatpak')" -eq 1 ]
    [ "$(cat .generalsxzh-installed-version)" = "1.0.5" ]
}

@test "Talk: Marker aktuell, App aber deinstalliert, wird neu installiert" {
    FLATPAK_INSTALLED="com.fbraz3.GeneralsXZH" run ./update_talk_desktop.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"nicht (mehr) installiert"* ]]
    [ "$(mock_calls 'flatpak install --system --or-update -y .*Nextcloud.Talk-linux-x64.flatpak')" -eq 1 ]
}

@test "Processing: neue Version wird installiert, Marker aktualisiert" {
    PR_REMOTE=4.5.7 run ./update_processing.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"Neueste verfügbare Version:  4.5.7"* ]]
    [ "$(mock_calls 'flatpak install --system --or-update -y .*processing-linux-x64.flatpak')" -eq 1 ]
    [ "$(cat .processing-installed-version)" = "4.5.7" ]
}

@test "Processing: bereits aktuell, keine Installation" {
    run ./update_processing.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"Processing ist bereits aktuell (4.5.6)"* ]]
    [ "$(mock_calls '^flatpak install')" -eq 0 ]
}

@test "Processing: aarch64 nutzt das aarch64-Bundle" {
    MOCK_ARCH=aarch64 PR_REMOTE=4.5.7 run ./update_processing.sh
    [ "$status" -eq 0 ]
    [ "$(mock_calls ' -linux-aarch64.flatpak$')" -eq 1 ]
    [ "$(mock_calls 'flatpak install --system --or-update -y .*processing-linux-aarch64.flatpak')" -eq 1 ]
}

@test "Processing: unerwartetes Tag-Format ergibt eigene Fehlermeldung" {
    PR_TAG="v4.5.7" run ./update_processing.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"Release-Tag 'v4.5.7' hat ein unerwartetes Format"* ]]
    [[ "$output" != *"Unerwarteter Fehler"* ]]
    [ "$(mock_calls '^flatpak install')" -eq 0 ]
}

@test "Flatpak: fehlgeschlagener Download lässt die lokale Kopie unverändert" {
    TK_REMOTE=2.3.4 CURL_FAIL=talk.flatpak run ./update_talk_desktop.sh
    [ "$status" -eq 1 ]
    [ "$(cat Nextcloud.Talk-linux-x64.flatpak)" = "lokale Kopie" ]
    [ "$(cat .talk-desktop-installed-version)" = "2.3.3" ]
}

@test "update_all.sh verweigert den Start als root" {
    MOCK_ROOT=1 run ./update_all.sh 3>&-
    [ "$status" -eq 1 ]
    [[ "$output" == *"Bitte nicht als root"* ]]
    [[ "$output" != *"Führe aus"* ]]
}

@test "Einzelnes Skript verweigert den Start als root" {
    MOCK_ROOT=1 run ./update_fastfetch.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"Bitte nicht als root"* ]]
    [ "$(mock_calls '^python3')" -eq 0 ]
}

@test "Unerwarteter Fehler wird mit Skript, Zeile und Befehl gemeldet" {
    QF_FAIL=moonfin run ./update_moonfin.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unerwarteter Fehler in update_moonfin.sh, Zeile "*"rpm -q --queryformat"* ]]
}

@test "update_all.sh | tee wartet nicht auf den sudo-Keepalive" {
    run timeout 20 bash -c './update_all.sh | cat' 3>&-
    [ "$status" -eq 0 ]
}

@test "update_all.sh --list zeigt die Programmnamen ohne sudo" {
    run ./update_all.sh --list 3>&-
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 9 ]
    [[ "$output" == *"docker_desktop"* ]]
    [[ "$output" == *"talk_desktop"* ]]
    [[ "$output" == *"linwood_butterfly"* ]]
    [[ "$output" == *"linwood_flow"* ]]
    [[ "$output" != *"all"* ]]
    [[ "$output" != *"Starte"* ]]
}

@test "update_all.sh --help zeigt die Hilfe" {
    run ./update_all.sh --help 3>&-
    [ "$status" -eq 0 ]
    [[ "$output" == *"--skip"* ]]
    [[ "$output" == *"--only"* ]]
}

@test "update_all.sh --skip überspringt die genannten Programme" {
    run ./update_all.sh --skip moonfin,GeneralsX --skip=openlogi 3>&-
    [ "$status" -eq 0 ]
    [[ "$output" == *"Übersprungen: moonfin (--skip)"* ]]
    [[ "$output" == *"Übersprungen: generalsx (--skip)"* ]]
    [[ "$output" == *"Übersprungen: OpenLogi (--skip)"* ]]
    [[ "$output" != *"Führe aus: moonfin"* ]]
    [[ "$output" != *"Führe aus: generalsx"* ]]
    [[ "$output" != *"Führe aus: OpenLogi"* ]]
    [[ "$output" == *"Führe aus: fastfetch"* ]]
    [[ "$output" == *"Alle Update-Vorgänge wurden erfolgreich abgeschlossen"* ]]
}

@test "update_all.sh --only führt nur die genannten Programme aus" {
    run ./update_all.sh --only fastfetch --only processing 3>&-
    [ "$status" -eq 0 ]
    [[ "$output" == *"Führe aus: fastfetch"* ]]
    [[ "$output" == *"Führe aus: processing"* ]]
    [ "$(grep -c 'Führe aus' <<< "$output")" -eq 2 ]
    [[ "$output" != *"Übersprungen"* ]]
}

@test "update_all.sh: Ausschlussliste wird beachtet, Kommentare ignoriert" {
    printf '# kein Docker auf diesem Rechner\ndocker_desktop\n  moonfin  # später\n\n' > skip
    UPDATE_ALL_SKIP_FILE="$PWD/skip" run ./update_all.sh 3>&-
    [ "$status" -eq 0 ]
    [[ "$output" == *"Übersprungen: docker_desktop (Ausschlussliste)"* ]]
    [[ "$output" == *"Übersprungen: moonfin (Ausschlussliste)"* ]]
    [[ "$output" == *"Führe aus: fastfetch"* ]]
    [[ "$output" != *"Warnung"* ]]
}

@test "update_all.sh: Standardpfad der Ausschlussliste unter XDG_CONFIG_HOME" {
    mkdir -p cfg/fedora-update-apps
    echo "fastfetch" > cfg/fedora-update-apps/skip
    XDG_CONFIG_HOME="$PWD/cfg" run ./update_all.sh 3>&-
    [ "$status" -eq 0 ]
    [[ "$output" == *"Übersprungen: fastfetch (Ausschlussliste)"* ]]
}

@test "update_all.sh: unbekannter Name in der Ausschlussliste nur Warnung" {
    printf 'gibtsnicht\n' > skip
    UPDATE_ALL_SKIP_FILE="$PWD/skip" run ./update_all.sh 3>&-
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unbekanntes Programm 'gibtsnicht'"* ]]
    [[ "$output" == *"Alle Update-Vorgänge wurden erfolgreich abgeschlossen"* ]]
}

@test "update_all.sh: --only ignoriert die Ausschlussliste" {
    echo "fastfetch" > skip
    UPDATE_ALL_SKIP_FILE="$PWD/skip" run ./update_all.sh --only fastfetch 3>&-
    [ "$status" -eq 0 ]
    [[ "$output" == *"Führe aus: fastfetch"* ]]
}

@test "update_all.sh: unbekannter Name bei --skip bricht vor sudo ab" {
    run ./update_all.sh --skip fastfetsch 3>&-
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unbekanntes Programm 'fastfetsch' bei --skip"* ]]
    [[ "$output" != *"Starte"* ]]
}

@test "update_all.sh: unbekannte Option und fehlendes Argument ergeben Exit 2" {
    run ./update_all.sh --foo 3>&-
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unbekannte Option '--foo'"* ]]
    run ./update_all.sh --only 3>&-
    [ "$status" -eq 2 ]
    [[ "$output" == *"--only erwartet"* ]]
}
