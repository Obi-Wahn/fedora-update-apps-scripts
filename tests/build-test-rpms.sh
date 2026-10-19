#!/bin/bash
# Baut die Test-RPMs für tests/rpm.bats, damit verify_rpm() gegen das echte rpm
# (in der CI: aktuelles Fedora) geprüft werden kann:
#   unsigned.rpm        - nicht signiert
#   signed-known.rpm    - signiert mit Schlüssel "imported" (wird in der CI importiert)
#   signed-unknown.rpm  - signiert mit Schlüssel "foreign" (wird NICHT importiert)
#   bad-signature.rpm   - signed-known.rpm mit manipulierter Signatur
#   corrupt-payload.rpm - unsigned.rpm mit beschädigtem Inhalt (Prüfsummenfehler)
#   not-an-rpm.rpm      - gar kein RPM
#   key-known.asc       - öffentlicher Schlüssel "imported" zum Importieren
# Benötigt: rpmbuild, rpmsign, gpg, python3
# Nutzung: tests/build-test-rpms.sh <Zielverzeichnis>
set -Eeuo pipefail

OUT_DIR="${1:?Nutzung: $0 <Zielverzeichnis>}"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. Minimales Paket bauen
mkdir -p "$WORK/rpmbuild/SPECS"
cat > "$WORK/rpmbuild/SPECS/testpkg.spec" <<'EOF'
Name:           testpkg
Version:        1.0.0
Release:        1
Summary:        Testpaket für die Bats-Tests
License:        MIT
BuildArch:      noarch

%description
Testpaket für die Bats-Tests von fedora-update-apps-scripts.

%install
mkdir -p %{buildroot}/usr/share/testpkg
echo "Testinhalt" > %{buildroot}/usr/share/testpkg/inhalt.txt

%files
/usr/share/testpkg/inhalt.txt
EOF
rpmbuild --quiet --define "_topdir $WORK/rpmbuild" -bb "$WORK/rpmbuild/SPECS/testpkg.spec"
cp "$WORK/rpmbuild/RPMS/noarch/testpkg-1.0.0-1.noarch.rpm" "$OUT_DIR/unsigned.rpm"

# 2. Zwei Testschlüssel ohne Passphrase erzeugen
export GNUPGHOME="$WORK/gnupg"
mkdir -m 700 "$GNUPGHOME"
# Schlüssel immer über "<E-Mail>" ansprechen: gpg sucht sonst nach Teilstrings.
for name in imported foreign; do
    gpg --batch --quiet --passphrase '' \
        --quick-gen-key "Test Key $name <$name@example.invalid>" rsa2048 sign never
done
gpg --batch --quiet --armor --export "<imported@example.invalid>" > "$OUT_DIR/key-known.asc"

# 3. Signierte Varianten
sign() {
    local key="$1"
    local file="$2"
    rpmsign --define "_gpg_name <$key@example.invalid>" --define "_gpg_path $GNUPGHOME" \
        --addsign "$file" >/dev/null
}
cp "$OUT_DIR/unsigned.rpm" "$OUT_DIR/signed-known.rpm"
sign imported "$OUT_DIR/signed-known.rpm"
cp "$OUT_DIR/unsigned.rpm" "$OUT_DIR/signed-unknown.rpm"
sign foreign "$OUT_DIR/signed-unknown.rpm"

# 4. Manipulierte Signatur: In jeder Signatur im Signatur-Header wird ein Byte
#    kurz vor dem Ende verändert. Prüfsummen und Inhalt bleiben gültig, nur die
#    Signatur passt nicht mehr ("BAD").
cp "$OUT_DIR/signed-known.rpm" "$OUT_DIR/bad-signature.rpm"
python3 - "$OUT_DIR/bad-signature.rpm" <<'EOF'
import base64, struct, sys

path = sys.argv[1]
data = bytearray(open(path, "rb").read())
off = 96  # Lead
assert data[off:off + 3] == b"\x8e\xad\xe8", "kein RPM-Signatur-Header"
count, _ = struct.unpack(">II", data[off + 8:off + 16])
store = off + 16 + 16 * count

BIN_SIG_TAGS = {267, 268, 1002, 1005}  # DSA, RSA, PGP, GPG
OPENPGP_TAG = 278                       # RPM 6: Base64-kodierte Signaturen
changed = 0
for i in range(count):
    tag, typ, pos, cnt = struct.unpack(">iiii", data[off + 16 + 16 * i:off + 32 + 16 * i])
    if tag in BIN_SIG_TAGS and typ == 7:
        data[store + pos + cnt - 8] ^= 0x01
        changed += 1
    elif tag == OPENPGP_TAG and typ == 8:
        start = store + pos
        for _ in range(cnt):
            end = data.index(b"\0", start)
            raw = bytearray(base64.b64decode(bytes(data[start:end])))
            raw[-8] ^= 0x01
            enc = base64.b64encode(bytes(raw))
            assert len(enc) == end - start
            data[start:end] = enc
            start = end + 1
            changed += 1
assert changed, "keine Signatur im Signatur-Header gefunden"
open(path, "wb").write(data)
EOF

# 5. Beschädigter Inhalt: ein Byte im komprimierten Payload am Dateiende ändern
cp "$OUT_DIR/unsigned.rpm" "$OUT_DIR/corrupt-payload.rpm"
python3 - "$OUT_DIR/corrupt-payload.rpm" <<'EOF'
import sys
path = sys.argv[1]
data = bytearray(open(path, "rb").read())
data[-20] ^= 0xFF
open(path, "wb").write(data)
EOF

# 6. Gar kein RPM
echo "Das ist kein RPM-Paket." > "$OUT_DIR/not-an-rpm.rpm"

echo "Test-RPMs erstellt in: $OUT_DIR"
