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

@test "update_all.sh: führt alle sieben Updater aus" {
    run ./update_all.sh 3>&-
    local name
    for name in docker_desktop fastfetch generalsx linwood-apps moonfin OpenLogi talk_desktop; do
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

@test "Linwood: Beta-Version (rpm-Tilde) gilt als aktuell" {
    INST_linwood_butterfly="2.7.0~rc.1" BF_REMOTE="2.7.0-rc.1" run ./update_linwood-apps.sh
    [ "$status" -eq 0 ]
    [ "$(mock_calls '^dnf')" -eq 0 ]
}

@test "Linwood: dnf-Fehler bei einer App, die andere wird trotzdem aktualisiert" {
    BF_REMOTE=2.6.2 FL_REMOTE=0.8.0 DNF_FAIL=linwood-butterfly run ./update_linwood-apps.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"nicht aktualisiert werden: linwood-butterfly"* ]]
    [ "$(mock_calls 'dnf install -y .*linwood-flow-0.8.0')" -eq 1 ]
}

@test "update_all.sh: Fehler werden gesammelt und am Ende gemeldet" {
    BF_REMOTE=2.6.2 DNF_FAIL=linwood-butterfly FAIL_KEY=AprilNEA run ./update_all.sh 3>&-
    [ "$status" -eq 1 ]
    [[ "$output" == *"   - OpenLogi"* ]]
    [[ "$output" == *"   - linwood-apps"* ]]
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
