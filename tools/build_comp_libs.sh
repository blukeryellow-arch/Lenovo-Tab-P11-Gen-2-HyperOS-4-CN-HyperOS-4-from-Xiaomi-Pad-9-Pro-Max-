#!/usr/bin/env bash
# Buduje biblioteki kompresji (lz4, zlib) POTRZEBNE do -zlz4 w mkfs.erofs - bez apt, bez
# roota, bez autoconfu. Skad ten skrypt: moj erofs-utils byl zbudowany bez HAVE_LZ4/HAVE_ZLIB,
# wiec system.img wyszedl 1 376 899 072 B zamiast ~937 MB (tyle mial source z HyperOS, bo
# HyperOS pakuje EROFS-em z kompresja). To nie jest drobnostka - to roznica miedzy 'zmiesci
# sie w partycji' a 'nie zmiesci'.
#
# oba projekty sa specjalne tym, ze NIE potrzebuja autoconfu:
#   zlib  - ./configure to zwykly skrypt powloki (działa bez automake) + Makefile
#   lz4   - Makefile w lib/ buduje liblz4.a wprost (BUILD_SHARED=no)
# Network: tylko codeload.github.com - reszta (kernel.org, apt, google) jest tu odcieta.
#
# Uzycie: tools/build_comp_libs.sh [KATALOG]      (domylnie /tmp/comp-build)
#Efekt:  $OUT/lib/lib{lz4,z}.a, $OUT/include/{lz4.h,zlib.h} + plik OUT.env do zrodlowania
set -uo pipefail
OUT=${1:-/tmp/comp-build}
case $OUT in /*) ;; *) echo "KATALOG musi byc bezwzgledny (dostalem: $OUT)"; exit 3;; esac
mkdir -p "$OUT/src" "$OUT/lib" "$OUT/include"

fetch() { # fetch <url> <plik>
  [ -s "$2" ] && { echo "  juz pobrane: $(basename "$2")"; return 0; }
  echo "  pobieram $(basename "$2")..."
  curl -fsSL --retry 3 --connect-timeout 20 -o "$2" "$1" || { echo "  BRAK SIECI: $1"; return 1; }
}

echo "== 1/3 zlib 1.3.1 (/configure jest shell-owy, nie autotools)"
cd "$OUT/src"
fetch https://codeload.github.com/madler/zlib/tar.gz/refs/tags/v1.3.1 zlib.tgz || exit 1
[ -d zlib-1.3.1 ] || tar xzf zlib.tgz
cd zlib-1.3.1
if [ ! -f libz.a ]; then
  # --static: nie generujemy .so, i tak linkujemy na stale w mkfs.erofs
  ./configure --static --prefix="$OUT" >/dev/null 2>&1 || { echo "  configure zwrocil blad"; exit 1; }
  make -j"$(nproc)" >/dev/null 2>&1 || { echo "  make zlib sie wywil"; exit 1; }
fi
[ -f libz.a ] || { echo "  brak libz.a po make"; exit 1; }
cp -f libz.a "$OUT/lib/"; cp -f zlib.h zconf.h "$OUT/include/" 2>/dev/null
echo "  libz.a: $(stat -c%s "$OUT/lib/libz.a") B"

echo "== 2/3 lz4 1.10.0 (make wprost w lib/)"
cd "$OUT/src"
fetch https://codeload.github.com/lz4/lz4/tar.gz/refs/tags/v1.10.0 lz4.tgz || exit 1
[ -d lz4-1.10.0 ] || tar xzf lz4.tgz
cd lz4-1.10.0/lib
if [ ! -f liblz4.a ]; then
  make -j"$(nproc)" BUILD_SHARED=no PREFIX="$OUT" >/dev/null 2>&1 || { echo "  make lz4 sie wywil"; exit 1; }
fi
[ -f liblz4.a ] || { echo "  brak liblz4.a po make"; exit 1; }
cp -f liblz4.a "$OUT/lib/"; cp -f lz4.h lz4frame.h lz4hc.h "$OUT/include/" 2>/dev/null
echo "  liblz4.a: $(stat -c%s "$OUT/lib/liblz4.a") B"

echo "== 3/3 zapisuje sredniki budowy"
cat > "$OUT/OUT.env" <<ENV
# wygenerowane przez tools/build_comp_libs.sh - do zrodlowania przed buildem erofs-utils
COMP_PREFIX="$OUT"
export CPPFLAGS="-I$OUT/include \$CPPFLAGS"
export LDFLAGS="-L$OUT/lib \$LDFLAGS"
# zlib i lz4 moga byc oba albo tylko jedno - mkfs.erofs dostosuje sie do config.h
ENV
cat > "$OUT/README.txt" <<TXT
Biblioteki zbudowane lokalnie (2026-09-23), bez pakietow -dev i bez autoconfu.
Po co: zeby mkfs.erofs umial '-zlz4' / '-zzlib'. Bez nich EROFS wychodzi
niekompresowany i o ~45 % wiekszy (patrz docs/06 §6.10).
TXT
echo "  $OUT/lib: $(ls "$OUT/lib" | tr '\n' ' ')"
echo "OK: COMP_PREFIX=$OUT"
