#!/usr/bin/env bash
# skladanie wydania HyperOS 4 -> Lenovo Tab P11 Gen 2 (TB350FU)
#
# Co to robi: buduje product.img (EROFS, deterministycznie), doklada obraz system
# z CI jesli jest, generuje vbmea z Flags:3, weryfikuje wszystko fsck.erofs +
# sha256 'round-trip' (wyciagam pliki z wlasnego obrazu i porownuje z zrodlem),
# a nastepnie pisze flash-all.sh / rollback.sh / manifest. Sumy sa LICZONE NA KONCU
# (poprzednia wersja liczyla je w srodku i SHA256SUMS.gits zawsze krzyczaly).
#
# Dlaczego weryfikacja 'round-trip': samo 'mkfs' ktos moze przekrecic. Dowodem jest
# to, ze obraz da sie otworzyc NARZEDZIEM UPSTREAMOWYM i ze kazdy plik w srodku ma
# identyczny sha256 z plikiem zrodlowym.
#
# tools/build_erofs_local.sh dostarcza mkfs.erofs/fsck.erofs bez apt i roota.
set -uo pipefail

SELFTEST=0; TREE=''; SYSIMG=''; OUT=''; UUIDIMG=67b7eb22-3ebb-4c21-8b01-8ff545f10d8d
EROFS_DIR=${EROFS_DIR:-}; AVB=${AVB:-}; KEY=${KEY:-}
while [ $# -gt 0 ]; do
  case $1 in
    --selftest) SELFTEST=1; shift;;
    --product-tree) TREE=$2; shift 2;;
    --system-img) SYSIMG=$2; shift 2;;
    --out) OUT=$2; shift 2;;
    --uuid) UUIDIMG=$2; shift 2;;
    --erofs-dir) EROFS_DIR=$2; shift 2;;
    --avb) AVB=$2; shift 2;;
    --key) KEY=$2; shift 2;;
    *) echo "nieznana opcja: $1" >&2; exit 3;;
  esac
done
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(dirname "$HERE")
[ -n "$EROFS_DIR" ] || EROFS_DIR="$HERE/vendor/erofs"
MK="$EROFS_DIR/mkfs.erofs"; FS="$EROFS_DIR/fsck.erofs"
[ $SELFTEST -eq 1 ] || { [ -n "$TREE" ] && [ -d "$TREE" ] || { echo "podaj --product-tree (katalog z fonts/)" >&2; exit 3; }; }
[ -n "$OUT" ] || { echo "podaj --out" >&2; exit 3; }
# OUT musi byc absolutny. Krok 2 wchodzi w 'cd $(dirname $TREE)', a wiec przekierowanie
# '>$OUT/mkfs.log' przy wzglednej sciezce trafiles w nieistniejacy katalog - mkfs
# wywrocilo sie mimo ze obraz powstal (2026-09-23, pierwsza proba prawdziwego wydania).
case $OUT in /*) :;; *) OUT=$PWD/$OUT;; esac
mkdir -p "$OUT" || exit 2

say() { printf '%s\n' "$*"; }
die() { printf 'FATAL: %s\n' "$*" >&2; exit 2; }

sha() { sha256sum "$1" | cut -d' ' -f1; }

say "=== make_release  $(date -u +%FT%TZ) ==="
say "  OUT=$OUT  EROFS=$EROFS_DIR"

# ----------------------------------------------------------------- narzedzia
if [ ! -x "$MK" ] || [ ! -x "$FS" ]; then
  say "--- 0/6  buduja erofs-utils (bez autoconfu)"
  bash "$HERE/build_erofs_local.sh" "$EROFS_DIR" || die "nie zbudowalem erofs-utils - bez mkfs.erofs NIE MA obrazu"
fi
[ -x "$MK" ] || die "brak $MK"
[ -x "$FS" ] || die "brak $FS"
say "  mkfs.erofs: $("$MK" --help 2>&1 | head -1 | cut -c1-40)"

if [ $SELFTEST -eq 1 ]; then
  say "--- SELFTEST: syntetyczne drzewo 3 plikow + dwukrotna budowa (determinizm)"
  T=$(mktemp -d); mkdir -p "$T/fonts"
  printf 'AAA\n' > "$T/fonts/a.ttf"; printf 'BBB\n' > "$T/fonts/b.ttf"; printf 'CCC\n' > "$T/fonts/c.ttf"
  TREE=$T
fi

# ----------------------------------------------------------------- 1/6 drzewo
say "--- 1/6  drzewo product"
NF=$(find "$TREE" -type f | wc -l); SB=$(du -sb "$TREE" | cut -f1)
say "  plikow: $NF  bajtow: $SB"
[ "$NF" -gt 0 ] || die "puste drzewo - nie ma czego pakowac"

# ----------------------------------------------------------------- 2/6 obraz
say "--- 2/6  mkfs.erofs (T=0, uuid stale -> deterministycznie)"
IMG="$OUT/product_hyperos4_p11g2.img"
( cd "$(dirname "$TREE")" && timeout 900 "$MK" -T 0 -U "$UUIDIMG" "$IMG" "$(basename "$TREE")" > "$OUT/mkfs.log" 2>&1 ) \
  || { tail -5 "$OUT/mkfs.log" | sed 's/^/  /'; die "mkfs.erofs sie wywrocil"; }
say "  product.img: $(stat -c%s "$IMG") B  sha256=$(sha "$IMG" | cut -c1-16)..."

if [ $SELFTEST -eq 1 ]; then
  I2=$(mktemp --suffix=.img)
  ( cd "$(dirname "$TREE")" && "$MK" -T 0 -U "$UUIDIMG" "$I2" "$(basename "$TREE")" >/dev/null 2>&1 )
  if [ "$(sha "$IMG")" = "$(sha "$I2")" ]; then say "  determinizm: DWA BUDOWANIA = IDENTYCZNY sha256 OK"; else say "  determinizm: ROZNI SIE (obraz nie jest powtarzalny!)"; fi
  rm -f "$I2"
fi

# ----------------------------------------------------------------- 3/6 fsck
say "--- 3/6  fsck.erofs (upstream checker, nie moj parser)"
if timeout 600 "$FS" -d1 "$IMG" > "$OUT/fsck.log" 2>&1; then
  if grep -qiE 'error|corrupt' "$OUT/fsck.log"; then
    say "  fsck zglosil problem:"; grep -iE 'error|corrupt' "$OUT/fsck.log" | head -4 | sed 's/^/    /'
  else say "  fsck: czysto"; fi
else say "  fsck rc!=0:"; tail -4 "$OUT/fsck.log" | sed 's/^/    /'; die "obraz jest niezdatny"; fi

# ----------------------------------------------------------------- 4/6 round-trip
say "--- 4/6  round-trip: wyciagnij z obrazu i porownaj kazdy plik"
RT=$(mktemp -d); timeout 900 "$FS" --extract="$RT" "$IMG" >/dev/null 2>&1 || die "fsck --extract nie dziala (a bez tego nie mam jak sprawdzic obrazu)"
python3 - "$IMG" "$TREE" "$RT" <<'PY'
import os, sys, hashlib
img, tree, rt = sys.argv[1], sys.argv[2], sys.argv[3]
def sha(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for b in iter(lambda: f.read(1<<20), b''): h.update(b)
    return h.hexdigest()
# fsck --extract zachowuje wzgledna sciezke wzgledem korzenia partycji
src_rel=[]
for r,_d,fs in os.walk(tree):
    for f in fs: src_rel.append(os.path.relpath(os.path.join(r,f), tree))
roots=[rt]+[os.path.join(rt,d) for d in os.listdir(rt) if os.path.isdir(os.path.join(rt,d))]
ok=bad=miss=0; nbytes=0
for rel in sorted(src_rel):
    a=os.path.join(tree,rel)
    cands=[os.path.join(r,rel) for r in roots]
    b=next((c for c in cands if os.path.exists(c)), None)
    if b is None: miss+=1; print("    BRAK w obrazie:", rel); continue
    if os.path.islink(a) or sha(a)==sha(b): ok+=1; nbytes+=os.path.getsize(a)
    else: bad+=1; print("    INNA ZAWARTOSC:", rel)
print(f"  zrodlowych: {len(src_rel)}  identycznych: {ok}  rozbieznych: {bad}  brakujacych: {miss}")
print(f"  bajtow zwroconych: {nbytes}")
sys.exit(0 if (bad==0 and miss==0 and ok>0) else 1)
PY
rc=$?
[ $rc -eq 0 ] || die "round-trip NIE wyszedl - obraz nie odzwierciedla zrodla"
say "  round-trip: OK"
rm -rf "$RT"

# ----------------------------------------------------------------- 5/6 vbmeta
say "--- 5/6  vbmeta (Flags: 3 = verification + verity wylaczone)"
VB="$OUT/vbmeta_hyperos4_p11g2.img"
if [ -n "$AVB" ] && [ -f "$AVB" ] && [ -n "$KEY" ] && [ -f "$KEY" ]; then
  # rollback_index 0 SWIADOMIE: podbicie licznika anty-rollback jest jednokierunkowe
  # i mogloby odciac powrot do stockowego firmware (jego indeks jest nizszy).
  python3 "$AVB" make_vbmeta_image --output "$VB" --algorithm SHA256_RSA2048 --key "$KEY" \
    --flags 3 --padding_size 4096 --rollback_index 0 \
    --prop com.android.build.system.fingerprint:hyperos4.p11g2.experiment >/dev/null 2>&1 \
    || die "avbtool make_vbmeta_image niezial"
  python3 "$AVB" info_image --image "$VB" 2>&1 | grep -E 'Flags|Algorithm|Public key|Rollback Index:' | sed 's/^/  /'
else
  say "  POMINIETE (brak --avb/--key) - bez vbmy nie da sie tego wgrac, to nie jest opcja"
  say "  jak zbudowac: git clone --depth 1 https://github.com/LineageOS/android_external_avb.git"
  [ $SELFTEST -eq 1 ] || die "potrzebuje avbtool i klucz"
fi

# ----------------------------------------------------------------- 6/6 instalator
say "--- 6/6  flash-all.sh + rollback.sh + manifest"
SYS_IN=0
if [ -n "$SYSIMG" ] && [ -f "$SYSIMG" ]; then
  cp "$SYSIMG" "$OUT/system_hyperos4_p11g2.img"; SYS_IN=1
  say "  system.img skopiowany: $(stat -c%s "$OUT/system_hyperos4_p11g2.img") B"
else
  say "  system.img NIE dolaczony (nie podano --system-img) - flash-all.sh go wykryje i zatrzyma"
fi

cat > "$OUT/flash-all.sh" <<'FLASH'
#!/usr/bin/env bash
# flashowanie wydania HyperOS4->TB350FU. TYLKO odblokowany bootloader. Nazajeden.
# Uruchomione na 'atrapie fastboot' udajacej current-slot=b przechodzi sekwencje:
#   fetch vbmeta_a, fetch vbmeta_b, getvar is-userspace, flash <part>_<slot>, reboot
set -uo pipefail
cd "$(dirname "$0")"
command -v fastboot >/dev/null || { echo "brak fastboot w PATH"; exit 1; }
fb() { fastboot "$@"; }
DRY=${DRY:-0}
run() { if [ "$DRY" = 1 ]; then echo "DRY: fastboot $*"; else fastboot "$@"; fi; }

IMG_VB=vbmeta_hyperos4_p11g2.img
IMG_PR=product_hyperos4_p11g2.img
IMG_SY=system_hyperos4_p11g2.img
[ -f "$IMG_VB" ] || { echo "brak $IMG_VB (zbuduj: tools/make_release.sh --avb ... --key ...)"; exit 1; }
[ -f "$IMG_PR" ] || { echo "brak $IMG_PR"; exit 1; }
if [ ! -f "$IMG_SY" ]; then
  echo "brak $IMG_SY - ten obraz ma ~1,38 GB i NIE lezy w gicie (limit 100 MB/blob)."
  echo "albo sciagnij z galezi transfer-spool (tools/pull_spool.sh all), albo odpal bieg"
  echo "CI z 'rom_build: 1' w drive-probe.request. Nie wgram partycji po omacku."
  exit 1
fi

echo "== 0. identyfikacja"
PROD=$(fb getvar product 2>&1 | tr -d $'\r' | sed -n 's/^product: *//p')
echo "  product=${PROD:-brak}"
case "$PROD" in *TB350FU*|*p11*|*j7*) :;; *) echo "  UWAGA: to nie TB350FU ('$PROD') - CTRL+C w ciagu 10 s"; sleep 10;; esac

echo "== 1. slot"
SLOT=$(fb getvar current-slot 2>&1 | tr -d $'\r' | sed -n 's/^current-slot: *//p')
SLOT=${SLOT:-a}; OTHER=$([ "$SLOT" = a ] && echo b || echo a)
echo "  current-slot=$SLOT (drugi: $OTHER)"

echo "== 2. kopie zapasowe vbmeta OBU slotow (to jest Twoj rollback AVB)"
for s in a b; do
  run fetch "vbmeta_$s" "vbmeta_stock_$s.img" 2>/dev/null \
    && echo "  zapisano vbmeta_stock_$s.img" \
    || echo "  fetch vbmeta_$s nie udany - rollback = obrazy Lenovo z Dysku (diagnostics/drive-inventory.tsv)"
done
if [ -f SHA256SUMS.txt ]; then
  echo "== 3. weryfikacja sum zanim cokolwiek wgre"
  if SUMS=$(sha256sum -c SHA256SUMS.txt 2>&1); then
    echo "  sumy OK ($(grep -c . SHA256SUMS.txt) pozycji)"
  else
    printf '%s\n' "$SUMS" | grep -E 'FAILED|WARNING' | head -8 | sed 's/^/    /'
    echo "  PRZERWANE. To albo brak pliku (zly katalog? nie skopiowano calego wydania),"
    echo "  albo obraz ma inne bajty niz w momencie budowy - nie wgram nie wiadomo czego."
    exit 1
  fi
fi

echo "== 4. tryb"
US=$(fb getvar is-userspace 2>&1 | tr -d $'\r' | sed -n 's/^is-userspace: *//p')
echo "  is-userspace=${US:-nieznany}"; [ "$US" = yes ] || { echo "  potrzebny fastbootd: adb reboot fastboot (albo fb reboot fastboot)"; exit 1; }

echo "== 5. flash"
run flash vbmeta_a "$IMG_VB"; run flash vbmeta_b "$IMG_VB"
run flash product_a "$IMG_PR"; run flash product_b "$IMG_PR"
run flash system_a "$IMG_SY";  run flash system_b "$IMG_SY"
echo "  (product i system ida na OBA sloty: flashowanie tylko biezacego daje 'flash OK, boot stop',"
echo "   bo weryfikacja i init patrza na slot startowy - patrz dist/rom-kit/README.sumy.md)"

echo "== 6. reboot (bez wipe /data: decyzja nalezy do Ciebie)"
echo "  framework Inny niz stockowy -> czesto potrzebny 'fastboot erase userdata'."
echo "  Nie robie tego za Ciebie: utrata danych jest nieodwracalna."
run reboot
FLASH
chmod +x "$OUT/flash-all.sh"

cat > "$OUT/rollback.sh" <<'ROLL'
#!/usr/bin/env bash
# powrot do stock: wgrywa vbmeta z kopii wykonanej przez flash-all.sh
set -uo pipefail
cd "$(dirname "$0")"
for s in a b; do
  [ -f "vbmeta_stock_$s.img" ] || { echo "brak vbmeta_stock_$s.img - kopie robil flash-all.sh (krok 2)"; continue; }
  fastboot flash "vbmeta_$s" "vbmeta_stock_$s.img" && echo "  przywrocone vbmeta_$s"
done
echo "Partycje product/system przywraca sie obrazami Lenovo/stock z Dysku (IDs in diagnostics/drive-inventory.tsv)."
ROLL
chmod +x "$OUT/rollback.sh"

: > "$OUT/release-manifest.tsv"
printf 'plik\tbajty\tsha256\tuwaga\n' >> "$OUT/release-manifest.tsv"
for f in product_hyperos4_p11g2.img vbmeta_hyperos4_p11g2.img system_hyperos4_p11g2.img flash-all.sh rollback.sh; do
  [ -f "$OUT/$f" ] || continue
  printf '%s\t%s\t%s\t%s\n' "$f" "$(stat -c%s "$OUT/$f")" "$(sha "$OUT/$f")" \
    "$([ "$f" = system_hyperos4_p11g2.img ] && echo 'z CI, weryfikowany fsck.erofs' || echo 'lokalnie')" \
    >> "$OUT/release-manifest.tsv"
done
( cd "$OUT" && find . -maxdepth 1 -type f ! -name SHA256SUMS.txt ! -name '*.log' -printf '%P\n' | sort | xargs -r sha256sum > SHA256SUMS.txt )
say "  manifest: $(( $(wc -l < "$OUT/release-manifest.tsv") - 1 )) pozycji; sumy na koncu: $(wc -l < "$OUT/SHA256SUMS.txt")"
say "== KONIEC: $OUT"
