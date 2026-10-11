#!/usr/bin/env bash
# Paczka modulu Magisk/KernelSU z katalogu -> ZIP gotowy do 'adb sideload'/Magisk.
#
# Magisk oczekuje module.prop W KORZENIU zipa (nie w podkatalogu!) i obok niego
# 'customize.sh', 'system/...'. 'zip -r' z katalogiem-nadrecznym robi najczestszy blad
# (ludzie pakuja 'modul/module.prop' i Magisk mowi 'invalid module'), dlatego pakujemy
# z -C "$SRC" '.' i natychmiast WERYFIKUJEMY liste.
#
# Uzycie: tools/pack_module.sh KATALOG_MODULU [WYJSCIE.zip]
set -uo pipefail
SRC=${1:-}; OUT=${2:-}
[ -n "$SRC" ] && [ -d "$SRC" ] || { echo "uzycie: $0 KATALOG_MODULU [WYJSCIE.zip]" >&2; exit 2; }
[ -f "$SRC/module.prop" ] || { echo "FATAL: w $SRC nie ma module.prop - to nie modul" >&2; exit 2; }
OUT=${OUT:-${SRC%/}.zip}
# sciezka MUSI byc absolutna PRZED wejściem do $SRC - inaczej 'cd' + "$OLDPWD/$OUT"
# sklada podwojna sciezke (zmierzone: "repo//tmp/..." -> zip padlo)
case "$OUT" in /*) :;; *) OUT="$PWD/$OUT";; esac
# wymagane pola module.prop (Magisk nie zainstaluje bez id/name/version/versionCode/author)
python3 - "$SRC/module.prop" <<'PY'
import sys
need = {'id', 'name', 'version', 'versionCode', 'description'}
got = {}
for line in open(sys.argv[1], encoding='utf-8', errors='replace'):
    if '=' in line:
        k, v = line.split('=', 1)
        got[k.strip()] = v.strip()
miss = sorted(need - set(got))
if miss:
    print(f"  FATAL: module.prop bez pol: {', '.join(miss)}"); sys.exit(3)
if not got['id'].replace('_', '').replace('-', '').isalnum():
    print(f"  FATAL: id '{got['id']}' zawiera znaki niedozwolone (tylko [a-z0-9_-])"); sys.exit(3)
if not got['versionCode'].isdigit():
    print(f"  FATAL: versionCode '{got['versionCode']}' nie jest liczba"); sys.exit(3)
print(f"  module.prop OK: id={got['id']} v{got['version']} ({got['versionCode']})")
PY
[ $? -eq 0 ] || exit 3
if ! command -v zip >/dev/null 2>&1; then
  echo "  (brak 'zip' - pakuję pythonem, deflate + rowne prawa)"
  python3 - "$SRC" "$OUT" <<'PY'
import os, sys, zipfile, stat
src, out = sys.argv[1], sys.argv[2]
n = 0
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for dirpath, dirs, files in os.walk(src):
        dirs[:] = [d for d in dirs if d not in ('.git', '__pycache__')]
        for f in sorted(files):
            if f in ('SHA256SUMS.txt', '.fontlist') or f.endswith('.zip'):
                continue
            p = os.path.join(dirpath, f)
            arc = os.path.relpath(p, src)
            zi = zipfile.ZipInfo(arc, date_time=(2026, 1, 1, 0, 0, 0))
            zi.compress_type = zipfile.ZIP_DEFLATED
            mode = 0o755 if (f.endswith('.sh') or os.access(p, os.X_OK)) else 0o644
            zi.external_attr = (mode & 0xFFFF) << 16
            z.writestr(zi, open(p, 'rb').read())
            n += 1
print(f"  dopisanych plikow: {n}")
PY
else
  rm -f "$OUT"
  ( cd "$SRC" && zip -q -r -X "$OUT" . -x 'SHA256SUMS.txt' -x '*.zip' ) || { echo "FATAL: zip padl"; exit 4; }
fi
[ -f "$OUT" ] || { echo "FATAL: nie powstal $OUT"; exit 4; }
# --- weryfikacja: pliki sa w korzeniu, sciezki bez '..'
python3 - "$SRC" "$OUT" <<'PY'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
try:
    z = zipfile.ZipFile(out)
except Exception as e:
    print(f"  FATAL: zip nieczytelny: {e}"); sys.exit(5)
names = z.namelist()
bad = 0
if 'module.prop' not in names:
    print("  FATAL: w zipie NIE MA module.prop w korzeniu (Magisk odrzuci)"); bad += 1
for n in names:
    if n.startswith('/') or '..' in n.split('/'):
        print(f"  FATAL: niebezpieczna sciezka w zipie: {n}"); bad += 1
# kazdy plik z katalogu musil wejsc (poza tymi, ktore odrzucilismy swiadomie)
want = set()
for dp, dn, fn in os.walk(src):
    dn[:] = [d for d in dn if d not in ('.git', '__pycache__')]
    for f in fn:
        if f in ('SHA256SUMS.txt', '.fontlist') or f.endswith('.zip'):
            continue
        want.add(os.path.relpath(os.path.join(dp, f), src))
missing = sorted(want - set(names))
if missing:
    print(f"  FATAL: w zipie brakuje {len(missing)} plik(ow), np. {missing[:3]}"); bad += 1
# CRC wszystkich wpisow
for ci in z.infolist()[:400]:
    try:
        z.read(ci)
    except Exception as e:
        print(f"  FATAL: CRC/nie da sie czytac {ci.filename}: {e}"); bad += 1; break
print(f"  w zipie: {len(names)} plik(ow), {os.path.getsize(out)} B; bladow: {bad}")
sys.exit(6 if bad else 0)
PY
rc=$?
[ $rc -eq 0 ] || { echo "PAKOWANIE: WALIDACJA PADLA (rc=$rc) - ten zip NIE idzie na urzadzenie" >&2; exit $rc; }
sha256sum "$OUT" | tee "$(dirname "$OUT")/$(basename "$OUT").sha256" >/dev/null
echo "== OK: $OUT ($(du -h "$OUT" | cut -f1)) sha256=$(sha256sum "$OUT" | cut -c1-16)..."
echo "   instalacja: adb push $OUT /data/local/tmp/ && adb shell su -c 'magisk --install-module /data/local/tmp/$(basename "$OUT")'"
echo "   albo recznie: adb push katalog /data/adb/modules/<id>/ i reboot"
