#!/usr/bin/env bash
# Jeden przebieg, caly wynik do wklejenia w czat. Zbiera to, czego nie da sie
# przewidziec po nazwie modelu: layout partycji, rozmiar grupy w super, wersje
# HAL-i, stan blokady. Bez tego kazdy skrypt do skladania obrazu jest wrrozeniem.
set -uo pipefail

OUT=${1:-/tmp/p11g2-state-$(date +%Y%m%d-%H%M).txt}
: > "$OUT"

sh_run() { echo "\$ adb shell $1" >> "$OUT"; adb shell "$1" >> "$OUT" 2>&1; echo >> "$OUT"; }

echo "zbieram do $OUT"

{
  echo "### data: $(date -Is)"
  echo "### adb:  $(adb get-serialno 2>&1)"
  echo
} >> "$OUT"

echo "-- identyfikacja --"
for p in ro.product.model ro.product.device ro.product.name ro.board.platform \
         ro.soc.model ro.soc.manufacturer ro.mediatek.platform ro.hardware \
         ro.build.fingerprint ro.build.display.id ro.build.version.release \
         ro.build.version.sdk ro.build.type ro.bootmode; do
  v=$(adb shell getprop "$p" 2>/dev/null | tr -d '\r')
  printf '  %-28s %s\n' "$p" "${v:-<puste>}"
  echo "  $p = ${v:-<puste>}" >> "$OUT"
done

echo
echo "-- blokada / weryfikacja --"
for p in ro.boot.flash.locked ro.boot.verifiedbootstate ro.boot.vbmeta.device_state \
         ro.boot.vbmeta.avb_version ro.boot.veritymode ro.oem_unlock_supported; do
  v=$(adb shell getprop "$p" 2>/dev/null | tr -d '\r')
  printf '  %-28s %s\n' "$p" "${v:-<puste>}"
  echo "  $p = ${v:-<puste>}" >> "$OUT"
done

echo
echo "-- partycje (to rozstrzyga, czy jakikolwiek duzy system sie zmiesci) --"
for p in ro.boot.dynamic_partitions ro.virtual_ab.enabled ro.virtual_ab.retrofit \
         ro.boot.slot_suffix ro.boot.super_partition partition.system.verified \
         ro.product.cpu.abi ro.zygote; do
  v=$(adb shell getprop "$p" 2>/dev/null | tr -d '\r')
  printf '  %-28s %s\n' "$p" "${v:-<puste>}"
  echo "  $p = ${v:-<puste>}" >> "$OUT"
done

sh_run 'ls -l /dev/block/by-name'
sh_run 'cat /proc/partitions'
sh_run 'df -h | head -30'
echo "  (lpdump / dmctl - ponizej, moga nie istniec)" >> "$OUT"
sh_run 'lpdump 2>/dev/null | head -80'
sh_run 'dmctl stats 2>/dev/null | head -40'

echo
echo "-- pamiec --"
sh_run 'cat /proc/meminfo | head -4'
sh_run 'getprop | grep -E "dalvik.vm.heap|ro.config.low_ram|ro.kernel.zio"'
sh_run 'cat /sys/block/zram0/disksize 2>/dev/null'

echo
echo "-- HAL-e i ich wersje (baza do oceny VINTF) --"
sh_run 'ls /vendor/etc/vintf 2>/dev/null'
sh_run 'cat /vendor/etc/vintf/manifest.xml 2>/dev/null | head -60'
sh_run 'cat /system/etc/vintf/compatibility_matrix.xml 2>/dev/null | head -40'
sh_run 'getprop | grep -E "graphics|hwc|camera.provider" | head -20'

echo
echo "-- /vendor/etc/vintf: surowe pliki (adb pull, do --vintf-vendor-manifest) --"
VOUT="${OUT%.txt}-vendor-vintf"
rm -rf "$VOUT"; mkdir -p "$VOUT"
if adb pull /vendor/etc/vintf/. "$VOUT" >/dev/null 2>&1 && [ "$(find "$VOUT" -type f | wc -l)" -gt 0 ]; then
  n=$(find "$VOUT" -type f | wc -l)
  echo "  pobrano $n plikow do $VOUT"
  echo "  (manifest.xml i katalog manifest/ - make_level_matrix czyta katalog rekurencyjnie)"
  echo "  uzycie: tools/make_release.sh ... --vintf-optional-missing --vintf-vendor-manifest '$VOUT'"
  echo "  wtedy 'optional' dostana WYLACZNIE pozycje, ktorych ten vendor nie ma,"
  echo "  zamiast oznaczania NA SZEROKO."
  echo "  pobrano $n plikow /vendor/etc/vintf -> $VOUT (do --vintf-vendor-manifest)" >> "$OUT"
else
  echo "  NIE pobrano (adb nie dziala albo sciezki nie ma) - bez tego pliku rebuild"
  echo "  oznacza optional NA SZEROKO, czyli bez rozrozniania realnych brakow."
  echo "  NIE pobrano /vendor/etc/vintf (brak adb lub sciezki)" >> "$OUT"
fi

echo
echo "-- dostepnosc narzedzi na urzadzeniu --"
sh_run 'for c in lpdump dmctl magisk ksud su; do printf "%s: " "$c"; command -v $c || echo brak; done'
sh_run 'magisk -v 2>/dev/null; magisk -V 2>/dev/null'

echo
echo "=== GOTOWE ==="
echo "Wklej zawartosc $OUT do czatu (albo jej pierwszych ~200 linii)."
echo "Ten plik nie zawiera zadnych sekretow - czysta metadata buildu."
echo "Zapisano: $OUT ($(wc -l < "$OUT") linii, $(du -h "$OUT" | cut -f1))"
