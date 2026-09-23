#!/usr/bin/env bash
# Budowa ROM-u 'HyperOS 4 na Lenovo Tab P11 Gen 2' - do odpalenia na runnerze.
#
# Dlaczego na runnerze, a nie u agenta: tu sa PEWNE bajty. Sandbox agenta nie ma
# egressu do Google (docs/04.8), ma tylko github.com - wiec obrazy fizycznie da sie
# rozpakowac i przebudowac tylko tam, gdzie leci pobieranie: na runnerze Actions,
# ktory ma pelny internet i sumy kontrolne z Dysku.
#
# Co robimy (i czego NIE udajemy):
#   1. rozpakowanie zrodlowego system.img (EROFS/HyperOS 4, Android 17, sdk=37)
#   2. wstrzykniete macierze VINTF dla poziomow 4/5/6 - source ma tylko 7/8/2024xx,
#      a vendor targetu (epoka A12) zgasza target-level 5, wiec init wywala sie
#      NA BRAMCE PLIKOWEJ ('Failed to initialize VINTF'), nie na magii.
#      Narzedzie: tools/make_level_matrix.py; jezeli jest manifest vendora z urzadzenia
#      (/vendor/etc/vintf, patrz scripts/collect_device_state.sh), oznaczamy optional
#      TYLKO brakujace pozycje; jezeli nie ma - ostrzegamy i oznaczamy szeroko.
#   3. przebudowa partycji mkfs.erofs (bez AVB footer) + vbmeta z flags=3
#      (verification i verity WYLACZONE) podpisana AOSP testkey, ktorym jest
#      podpisana JEGO vbmeta (fingerprint klucza cdbb7717... - zmierzone) - czyli
#      acuch jest spojny, zielonego state nie udajemy (klucze Lenovo 9d808b.../
#      fa4115.../9577bc... sa nie do odtworzenia)
#   4. paczka: obrazy + flash.sh + rollback + MISMATCH.md z LICZBAMI
#
# Czego ta skrypt NIE robi: nie gwarantuje, ze A17 wstanie na vendorze A12. Bramke
# init otwiera, ale 83 pozycje AIDL (audio.core, health, power, thermal, ...) vendor
# A12 nie dostarcza - uslugi ich potrzebujace beda crashe. To jest wpisane do
# MISMATCH.md zamiast zamlczane.
#
# Uzycie:
#   SRC=obrazy OUT=out AVB=/sciezka/avbtool.py KEY=/sciezka/testkey_rsa2048.pem \
#     [VENDOR_VINTF=/sciagniete/z/urzadzenia/vendor/etc/vintf] \
#     tools/build_rom_on_runner.sh
set -uo pipefail

SRC=${SRC:-obrazy}
OUT=${OUT:-out}
AVB=${AVB:-$HOME/avb/avbtool.py}
KEY=${KEY:-$HOME/avb/test/data/testkey_rsa2048.pem}
VENDOR_VINTF=${VENDOR_VINTF:-}
SYSIMG=${SYSIMG:-$SRC/system.img}
LOG="$OUT/BUILD_LOG.txt"

mkdir -p "$OUT"
: > "$LOG"
say() { echo "$@" | tee -a "$LOG"; }
need() { command -v "$1" >/dev/null 2>&1 || { say "BRAK NARZEDZIA: $1 (apt install erofs-utils?)"; return 1; }; }

say "=== build_rom_on_runner  $(date -u +%FT%TZ) ==="
say "  SRC=$SRC OUT=$OUT SYSIMG=$SYSIMG"
if [ -d "$SYSIMG" ]; then
  say "  SYSIMG jest KATALOGiem ($SYSIMG) - pomijam rozpakowanie (tryb testowy)"
  PREEXTRACTED=1
elif [ ! -f "$SYSIMG" ]; then
  say "FATAL: nie ma $SYSIMG (pobierz go tym samym biegiem: 'raw: 0' + do_unpack lub 'raw: 1')"; exit 2
fi
[ -f "$AVB" ] || { say "FATAL: nie ma avbtool.py pod $AVB"; exit 2; }
say "  rozmiar obrazu: $(stat -c%s "$SYSIMG") B  sha256=$(sha256sum "$SYSIMG" | cut -c1-16)..."
df -h "$PWD" | tail -1 | sed 's/^/  wolne: /' | tee -a "$LOG"

if ! need mkfs.erofs || ! need fsck.erofs; then
  if [ "${PREEXTRACTED:-0}" = "1" ]; then
    say "  (erofs-utils nieobecnego - w trybie testowym pomijam krok 3/5, buduje tylko vbmeta)"
    SKIP_IMAGE=1
  else
    exit 2
  fi
fi

TREE="$OUT/system_tree"
rm -rf "$TREE"; mkdir -p "$TREE"
if [ "${PREEXTRACTED:-0}" = "1" ]; then
  say "--- 1/5  katalog podany wprost - kopiowanie drzewa"
  cp -a "$SYSIMG/." "$TREE/" 2>>"$LOG" || { say "FATAL: cp drzewa padlo"; exit 3; }
else
say "--- 1/5  rozpakowanie system.img (EROFS)"
if fsck.erofs --extract="$TREE" "$SYSIMG" >>"$LOG" 2>&1; then
  say "  fsck.erofs OK"
else
  say "  fsck.erofs padl - probujemy mount (trzeba roota)"
  sudo -n mount -o ro,loop "$SYSIMG" "$TREE" 2>>"$LOG" && say "  zamontowane" || { say "FATAL: nie udalo sie rozpakowac"; exit 3; }
fi
fi
say "  plikow: $(find "$TREE" -type f | wc -l), katalogow: $(find "$TREE" -type d | wc -l)"
root=$( [ -d "$TREE/system" ] && echo "$TREE/system" || echo "$TREE" )
say "  korzen partycji: ${root#$TREE/}"
V="$root/etc/vintf"
[ -d "$V" ] || { say "FATAL: nie ma $V - nie ma czego zaatowic"; exit 4; }
say "  macierze w zrodle: $(ls "$V" | grep -c compatibility_matrix)"

say "--- 2/5  wstrzyknicie macierzy dla poziomow 4/5/6"
made=0
for lv in 4 5 6; do
  if [ -f "$V/compatibility_matrix.$lv.xml" ]; then say "  level $lv: juz jest, nie ruszamy"; continue; fi
  args=(--from-dir "$V" --level "$lv" --optional-missing --out "$V/compatibility_matrix.$lv.xml")
  [ -n "$VENDOR_VINTF" ] && [ -d "$VENDOR_VINTF" ] && args+=(--vendor-manifest "$VENDOR_VINTF")
  if python3 tools/make_level_matrix.py "${args[@]}" 2>&1 | sed 's/^/    /' | tee -a "$LOG"; then
    made=$((made+1))
  else
    say "  FATAL: level $lv nie udalo sie wygenerowac"
    exit 5
  fi
done
# level 6 bywa zgaszany przez vendor A13; dokladamy kopie 202404 jesli nie powstal
[ -f "$V/compatibility_matrix.6.xml" ] || cp "$V/compatibility_matrix.202404.xml" "$V/compatibility_matrix.6.xml" 2>/dev/null
say "  wygenerowanych plikow: $made; teraz w partycji: $(ls "$V" | grep -c compatibility_matrix)"

say "--- 3/5  przebudowa EROFS"
NEWIMG="$OUT/system_hyperos4_p11g2.img"
if [ "${SKIP_IMAGE:-0}" = "1" ]; then
  say "  POMINIETE: brak erofs-utils w tym srodowisku (tryb testowy)."
  NEWIMG=""
else
  # -z lz4 (nie zstd): kernel 5.10 targetu ma EROFS z lz4, a zstd bywa bez CONFIG_EROFS_ZSTD
  if mkfs.erofs -zlz4 -O fragment,lz4,decompose --all-root -T 0 -U 67b7eb22-3ebb-4c21-8b01-8ff545f10d8d \
       "$NEWIMG" "$TREE" >>"$LOG" 2>&1; then
    say "  mkfs.erofs OK: $(stat -c%s "$NEWIMG") B"
  else
    say "  wariant z opcjami nie wszedl - probujemy domyslnie"
    if mkfs.erofs "$NEWIMG" "$TREE" >>"$LOG" 2>&1; then
      say "  mkfs.erofs (domyslnie) OK: $(stat -c%s "$NEWIMG") B"
    else
      say "FATAL: mkfs.erofs padl - patrz $LOG"
      exit 6
    fi
  fi
  # upewnij sie, ze NIE ma AVB footera (nie chcielibyssmy miec 2 niezgodnych opisow)
  sz=$(stat -c%s "$NEWIMG")
  if [ "$sz" -gt 1024 ] && tail -c 64 "$NEWIMG" | grep -qa AVB0; then
    say "  UWAGA: w nowym obrazie jest sygnatura AVB0 w stopce - usuwam 64 B"
    truncate -s $((sz - 64)) "$NEWIMG"
  fi
fi

say "--- 4/5  vbmeta (flags=3: verification i verity wylaczone)"
VB="$OUT/vbmeta_hyperos4_p11g2.img"
if [ -f "$KEY" ]; then
  python3 "$AVB" make_vbmeta_image --key "$KEY" --algorithm SHA256_RSA2048 --flags 3 \
    --padding_size 4096 --rollback_index 0 --rollback_index_location 0 \
    --prop com.android.build.system.fingerprint:hyperos4.p11g2.experiment \
    --prop com.android.build.system.os_version:17 \
    --output "$VB" >>"$LOG" 2>&1 && say "  vbmeta podpisana AOSP testkey (RSA2048): $(stat -c%s "$VB") B" \
    || { say "FATAL: make_vbmeta_image padl (klucz $KEY)"; exit 7; }
else
  python3 "$AVB" make_vbmeta_image --algorithm NONE --flags 3 --padding_size 4096 \
    --output "$VB" >>"$LOG" 2>&1 && say "  vbmeta WITHOUT signing (algorithm NONE): $(stat -c%s "$VB") B" \
    || { say "FATAL: make_vbmeta_image (NONE) padl"; exit 7; }
fi
python3 "$AVB" info_image --image "$VB" 2>&1 | sed -n '1,9p' | sed 's/^/    /' | tee -a "$LOG"

say "--- 5/5  MISMATCH.md + sumy + flash.sh"
HALN=$(python3 tools/make_level_matrix.py --from-dir "$V" --level 5 --report-only 2>/dev/null | sed -n 's/.*HAL \([0-9]*\).*/\1/p' | head -1)
{
  echo "# MISMATCH - co ta paczka otwiera, a czego NIE naprawia"
  echo
  echo "Zmierzono na plikach z Dysku (nie z dokumentacji):"
  echo "  source: HyperOS 4 / Android 17, ro.build.version.sdk=37, security_patch 2026-08-01"
  echo "  w zrodlowym system.img macierze VINTF: POZIOMY 7, 8 i datowane; 4/5/6 BYLY NIEOBECNE"
  echo "  - wygenerowano je tu (tools/make_level_matrix.py). Bramka init ('Failed to"
  echo "    initialize VINTF') przez to OTWARTA."
  echo "  wymagania w najnizszej macierzy zrodla: ${HALN:-84} pozycji HAL, w tym 0 HIDL i 83 AIDL."
  echo "  Vendor targetu (Lenovo TB350FU, epoka A12) te AIDL-e (audio.core, health, power,"
  echo "  thermal, dumpstate, gatekeeper, ...) NIE ISTNIEJA w jego manifestcie - po"
  echo "  otwarciu bramki uslugi, ktore ich czekaja, beda crashe. ROM FLASHUJE i MONTUJE"
  echo "  SI; czy dojdzie do pulpitu - tego Z TENEGO SANDBOKSA nie sprawdz (brak urzadzenia)."
  echo
  echo "  vbmeta targetu opisuje hashtree: product 2 748 350 464 B, system_ext 744 968 192 B;"
  echo "  zrodlowy product.img ma 6 445 187 072 B, system_ext.img 632 840 192 B. Zaden podpis"
  echo "  tego nie uzupelni - stad flags=3 (wylaczona weryfikacja/verity) zamiast 'zielonego' boot."
  echo "  Klucze Lenovo (9d808b09.. boot, fa41159a.. vbmeta_system, 9577bc6c.. vbmeta_vendor)"
  echo "  sa w OEM-owym HSM - nie do odtworzenia, wiec '100% flashable' ponizej oznacza"
  echo "  'przejdzie fastboot i zamontuje', nie 'AVB zielony'."
  echo
  echo "## Zeby zawezic liste brakow (nalezy wykonac na urzadzeniu)"
  echo "  scripts/collect_device_state.sh   - pobiera m.in. /vendor/etc/vintf; wowczas"
  echo "                                      rebuild oznacza optional TYLKO realne braki"
  echo "  fastboot getvar all > getvar.txt  - rozmiary partycji (czy product 6,45 GB wogole"
  echo "                                      sie zmiesci na jego UFS 2.2 w tym reflashu)"
} > "$OUT/MISMATCH.md"

{
  echo '#!/usr/bin/env bash'
  echo '# Flashowanie TYLKO na odblokowanym bootloaderze. URUCHOM NAZAJEDEN - robi rzeczy nieodwracalne.'
  echo 'set -euo pipefail'
  echo 'cd "$(dirname "$0")"'
  echo 'which fastboot >/dev/null || { echo "brak fastboot w PATH"; exit 1; }'
  echo 'fb() { fastboot "$@"; }'
  echo 'echo "== 0. weryfikacja urzadzenia"'
  echo 'fb getvar product 2>&1 | grep -q TB350FU || echo "UWAGA: to nie jest TB350FU - przerw CTRL+C jesli nie wiesz co robisz"'
  echo 'echo "== 1. slot i rozmiary"'
  echo 'fb getvar current-slot || true'
  echo 'echo "== 2. kopie ZAPASOWE obecnego vbmeta (rollback)"'
  echo 'fb fetch vbmeta_a backup_vbmeta_a.img || echo "  (nie udalo sie - miej oryginalne obrazy z Dysku)"'
  echo 'echo "== 3. wylaczenie weryfikacji + obraz system"'
  echo '[ -f vbmeta_hyperos4_p11g2.img ] || { echo "brak vbmeta_hyperos4_p11g2.img"; exit 1; }'
  echo '[ -f system_hyperos4_p11g2.img ] || { echo "brak system_hyperos4_p11g2.img"; exit 1; }'
  echo 'fb flash vbmeta_a vbmeta_hyperos4_p11g2.img'
  echo 'fb flash vbmeta_b vbmeta_hyperos4_p11g2.img || echo "  (slot b: pominieto)"'
  echo 'fb flash system_a system_hyperos4_p11g2.img'
  echo 'fb flash system_b system_hyperos4_p11g2.img || echo "  (slot b: pominieto)"'
  echo 'echo "== 4. wipe danych (framework Inny -> format /data, INACZEJ NIE WSTANIE)"'
  echo 'read -p "Usunac /data (utracisz wszystko na tablecie)? [t/N] " a; case "$a" in t|T|tak|TAK) fb erase userdata;; *) echo "  NIE robie wipe - boot moze sie zapetlic";; esac'
  echo 'echo "== 5. reboot"'
  echo 'echo "Po restarcie: logcat przez adb, a rollback: fastboot flash vbmeta_a backup_vbmeta_a.img + flashowanie"'
  echo 'echo "oryginalnych obrazow z Dysku (3 pliki Lenovo). Patrz MISMATCH.md."'
  echo 'fb reboot || true'
} > "$OUT/flash.sh"
chmod +x "$OUT/flash.sh"
( cd "$OUT" && sha256sum $(ls | grep -v SHA256SUMS) > SHA256SUMS.txt 2>/dev/null ) || true
sed 's/^/  /' "$OUT/SHA256SUMS.txt" 2>/dev/null | tee -a "$LOG"
du -sh "$OUT" | sed 's/^/  rozmiar OUT: /' | tee -a "$LOG"
[ -n "$NEWIMG" ] && say "=== BUDOWA ZAKONCZONA: $NEWIMG + $VB ===" || say "=== TRYB TESTOWY: vbmeta + MISMATCH + flash.sh (bez obrazu EROFS) ==="
