#!/usr/bin/env bash
# Dzieli SUROWY obraz na kawalki <=90 MB i robi MANIFEST do zlozenia po stronie agenta.
#
# Dlaczego surowe kawalki, a nie paczka z rozpakowanego fs:
#   * `product.img` ma 6 452 271 104 B. Ciagle archiwum z allowlisty zajelo dla
#     `system.img` 716 MB z 894 MB (EROFS ju jest spakowany ZSTD/LZ4, gzip -1 nie ma
#     czego sciskac), wiec caly `product` i tak przekroczylby 2 GB na push.
#   * agent potrzebuje PEWNYCH bajtow (AVB, super geometry, lp metadata, build.prop),
#     a te da sie odczytac tylko z surowego obrazu.
#   * Drive nie umozliwia anonimowego pobierania z zakresem (HTTP Range ignorowany),
#     wiec kazdy bieg pobiera caly plik i wypycha WYBRANY zakres czastek - to jest
#     wlasnie "przesylaj powoli malymi czesciami".
#
# Uzycie:
#   tools/raw_parts_on_runner.sh <plik> <katalog-docelowy> [part_od] [ile]
# Zmienne srodowiska:
#   PART_SIZE (domylnie 90m)  - musi byc < 100 MB (twardy limit bloba GitHuba)
# Krytyczne: caly obraz ma znany sha256 policzony tutaj, dzieki czemu agent liczy
# sume kontrolna ZOZONEGO pliku i porownuje z Google (md5 z metadanych Dysku) -
# koncowka do koncowki, nie "ufa runnerowi".
set -uo pipefail

SRC=${1:?podaj plik do podzialu}
DST=${2:?podaj katalog docelowy}
FROM=${3:-0}
COUNT=${4:-0}          # 0 = do konca
PART_SIZE=${PART_SIZE:-90m}

[ -f "$SRC" ] || { echo "BRAK PLIKU: $SRC" >&2; exit 2; }
mkdir -p "$DST"
base=$(basename "$SRC")
tmp="$DST/.split-$base"
rm -rf "$tmp"; mkdir -p "$tmp"

full_size=$(stat -c%s "$SRC")
full_sha=$(sha256sum "$SRC" | cut -d' ' -f1)
echo "  surowy: $base $full_size B sha256=${full_sha:0:16}..."

split -b "$PART_SIZE" -d -a 4 "$SRC" "$tmp/$base.part."
mapfile -t parts < <(ls -1v "$tmp" | sed "s|^|$tmp/|")
np=${#parts[@]}
echo "  podzielone na $np czastek (rozmiar partii $PART_SIZE)"

if [ "$FROM" -gt 0 ] || [ "$COUNT" -gt 0 ]; then
  end=$np
  [ "$COUNT" -gt 0 ] && end=$(( FROM + COUNT )) && [ "$end" -gt "$np" ] && end=$np
  sel=("${parts[@]:FROM:end-FROM}")
else
  sel=("${parts[@]}")
fi
[ "${#sel[@]}" -gt 0 ] || { echo "  pusty zakres [$FROM..] - nic do wypchniecia" >&2; exit 3; }

# katalog docelowy: tylko wybrane czastki + manifest tego obrazka
rm -f "$DST/$base.part."* 2>/dev/null
moved=0
for f in "${sel[@]}"; do mv "$f" "$DST/"; moved=$((moved+1)); done
rm -rf "$tmp"

# Rozmiar i sha256 licimy DOPIERO po przeniesieniu i po sciezce docelowej -
# wczesniejsza wersja liczyla na path w skasowanym katalogu tymczasowym, przez co
# w RAW_MANIFEST-ie siedziely puste pola (test 2026-09-23 to wydal).
{
  printf '# RAW v1\t%s\t%s\t%s\t%s\t%s\t%s\n' "$base" "$full_size" "$full_sha" "$np" "$FROM" "$((FROM+moved-1))"
  for f in "${sel[@]}"; do
    d="$DST/$(basename "$f")"
    printf 'part\t%s\t%s\t%s\n' "$(basename "$f")" "$(stat -c%s "$d" 2>/dev/null || echo -1)" "$(sha256sum "$d" 2>/dev/null | cut -d' ' -f1)"
  done
} >> "$DST/RAW_MANIFEST.tsv"

echo "  wypchniete czastki $FROM..$((FROM+moved-1)) z $np ($moved szt.)"
echo "  RAZEM w katalogu: $(du -sh "$DST" | cut -f1)"
echo "RAWPARTS: $base czastki $FROM-$((FROM+moved-1))/$np sha256=$full_sha"
