# Gemeinsame Hilfsfunktionen für die Bats-Tests.

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
MOCK_DIR="$BATS_TEST_DIRNAME/mocks"

# Legt ein Arbeitsverzeichnis mit Kopien aller Skripte an, stellt die Mocks
# (tests/mocks) vor den PATH und setzt einen Ausgangszustand, in dem alle Apps
# installiert und aktuell sind und die lokalen Kopien vorliegen.
setup_workdir() {
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK"
    cp "$REPO_DIR"/*.sh "$WORK"/
    export MOCK_LOG="$BATS_TEST_TMPDIR/mock.log"
    : > "$MOCK_LOG"
    export PATH="$MOCK_DIR:$PATH"

    export FF_LOCAL=2.70.0 FF_REMOTE=2.70.0
    export INST_docker_desktop=4.95.0 DOCKER_REMOTE=4.95.0
    export INST_linwood_butterfly=2.6.1 BF_REMOTE=2.6.1
    export INST_linwood_flow=0.7.0 FL_REMOTE=0.7.0
    export INST_moonfin=2.7.0 MF_REMOTE=2.7.0
    export INST_openlogi=0.8.14 OL_REMOTE=0.8.14
    export GX_REMOTE=1.0.4 TK_REMOTE=2.3.3 PR_REMOTE=4.5.6
    export FLATPAK_INSTALLED="com.fbraz3.GeneralsXZH com.nextcloud.talk org.processing.pde"
    export MOCK_ARCH=x86_64

    echo "$GX_REMOTE" > "$WORK/.generalsxzh-installed-version"
    echo "$TK_REMOTE" > "$WORK/.talk-desktop-installed-version"
    echo "$PR_REMOTE" > "$WORK/.processing-installed-version"
    local f
    for f in fastfetch-2.70.0-linux-amd64.rpm docker-desktop-4.95.0-x86_64.rpm \
        linwood-butterfly-2.6.1-linux-x86_64.rpm linwood-flow-0.7.0-linux-x86_64.rpm \
        moonfin-2.7.0-x86_64.rpm openlogi-0.8.14-linux-amd64.rpm \
        Linux-GeneralsXZH.flatpak Nextcloud.Talk-linux-x64.flatpak \
        processing-linux-x64.flatpak; do
        echo "lokale Kopie" > "$WORK/$f"
    done
    cd "$WORK" || return 1
}

# Führt eine Funktion aus common.sh in einer eigenen Bash aus, damit der
# ERR-Trap aus common.sh nicht die Traps von Bats überschreibt. Der Aufruf mit
# "|| exit" entspricht dem in den Skripten (z.B. "verify_rpm ... || return 1"),
# ein Fehlschlag gilt damit als behandelt und löst den ERR-Trap nicht aus.
# Nutzung: run_common <Funktion> [Argumente...]
run_common() {
    run bash -c 'set -Eeuo pipefail; source "$0"; "$@" || exit $?' "$REPO_DIR/common.sh" "$@"
}

# Zählt, wie oft ein Muster im Mock-Protokoll vorkommt.
mock_calls() {
    grep -c -- "$1" "$MOCK_LOG" || true
}
