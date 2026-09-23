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
