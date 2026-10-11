#!/usr/bin/env bash
# Wyciaga NADPISANE zasoby z apk-ow RRO (HyperOS) do pliku, ktory da sie przetworzyc
# dalej - po to, by zbudowac WLASNY overlay (podpisany kluczem targetu) zamiast probowac
# wgrac overlay Xiaomi (podpis MIUI c9009d01... -> framework go odrzuca).
#
# Dlaczego nie parser 'na rece': resources.arsc w tych apk-ach ma 768 B i nie zawiera
# res/values.xml - cala tresc jest w skompilowanej tablicy. Prubowalem minimalnego
# parsera (tools/arsc_dump.py, 2026-09-23) i przy realnym pliku zwrocil 0 stringow /
# 0 wpisow, bo layout puli 'key strings' zalezy od ResTable_pkgExt - polowiczny
# wynik jest gorszy niz brak wyniku, wiec narzedzie zostalo USUNIETE, a to jest
# sciezka przez aapt2 (Android SDK),  ktory JEST dostepny w jobie 'build-module'.
#
# Uzycie:
#   tools/extract_rro_values.sh KATALOG_Z_APKAMI [WYJSCIE.tsv]
#   AAPT2=/sciezka/aapt2 tools/extract_rro_values.sh ...
set -uo pipefail
SRC=${1:-staging/product/overlay}
OUT=${2:-diagnostics/hyperos_rro_values.tsv}
AAPT2=${AAPT2:-$(command -v aapt2 || ls -1 "$HOME"/android-sdk/build-tools/*/aapt2 2>/dev/null | tail -1)}

if [ -z "${AAPT2:-}" ]; then
  echo "BRAK aapt2 (Android SDK build-tools)." >&2
  echo "  Lokalnie w sandboxie go nie ma - to jest zmierzone, nie zalozene:" >&2
  echo "    command -v aapt2 -> $(command -v aapt2 || echo 'nic')" >&2
  echo "  Uruchom to w jobie 'build-module' (ma setup-java + SDK) albo:" >&2
  echo "    sdkmanager 'build-tools;34.0.0' && AAPT2=~/android-sdk/build-tools/34.0.0/aapt2 \$0 $SRC" >&2
  exit 3
fi
[ -d "$SRC" ] || { echo "FATAL: nie ma katalogu $SRC (sciagnij product/overlay przez tools/ingest_run.sh)"; exit 2; }
mkdir -p "$(dirname "$OUT")"
: > "$OUT"
n=0; ok=0
for a in $(find "$SRC" -name '*.apk' | sort); do
  n=$((n+1))
  echo "=== $a"
  if ! d=$("$AAPT2" dump resources "$a" 2>/dev/null) || [ -z "$d" ]; then
    echo "  aapt2 dump padl - pomijam (nie zgadywanie wartosci)"; continue
  fi
  ok=$((ok+1))
  # 'resource 0x7f... name dimen/foo' + ' (t=0x5 d=0x...) -> type=dimen data=... '
  base=$(basename "$a")
  printf '%s\n' "$d" | awk -v apk="$base" '
    /^resource / { id=$2; nm=$3; next }
    /\(t=/ {
      t="?"; v="?"
      if (match($0, /type=[a-z0-9_]+/))  { t=substr($0, RSTART+6, RLENGTH-6) }
      if (match($0, /data=0x[0-9a-f]+/)) { v=substr($0, RSTART+5, RLENGTH-5) }
      if (match($0, /\(Raw: "[^"]*"\)/)) { v=substr($0, RSTART+7, RLENGTH-8) }
      printf "%s\t%s\t%s\t%s\n", apk, nm, t, v
    }' >> "$OUT"
done
echo "  apk przejrza: $n, z czego z odczytanym zrzutem: $ok"
echo "  zapisano: $OUT ($(wc -l < "$OUT") linii)"
[ "$ok" -gt 0 ] || { echo "FATAL: zadny apk nie dal sie odczytac - plik jest pusty, nie udaje ze cos mam"; rm -f "$OUT"; exit 4; }
# przyklad tego, co to daje - do przejrzenia reka przed wklejeniem do overlayu
head -8 "$OUT" | sed 's/^/  /'
