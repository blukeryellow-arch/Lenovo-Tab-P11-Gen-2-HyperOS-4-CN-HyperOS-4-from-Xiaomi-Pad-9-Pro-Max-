#!/usr/bin/env bash
# zloz.sh - skleja czesci (.bin) w pelne obrazy + dekoduje vbmeta z .b64.
# Dołączany do kitu wydania na Google Drive (bez rozszerzenia .sh w nazwie).
# Linux/macOS (sha256sum albo shasum -a 256).
#
# Historia: wersja z 25 IX tylko WYPISYWARA sumy obrazow i kazala userowi
# porownac je z SHA256SUMS.txt recznie - latwe do pominiecia, a przeklamana
# czesc przy pobieraniu wyszlabym dopiero przy flash-all (bramka 0). Od 26 IX
# zloz sam weryfikuje sklejone obrazy i odmawia sukcesu (exit 1), gdy sumy
# sie nie zgadzaja.
set -uo pipefail
cd "$(dirname "$0")" || exit 1

sum256() { # sha256 pliku: sha256sum (Linux) albo shasum -a 256 (macOS/BSD)
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

for n in system system_ext product; do
  f="${n}_hyperos4_p11g2.img"
  [ -f "$f" ] && { echo "pomijam $f (juz istnieje)"; continue; }
  echo "sklejam $f ..."
  cat "$f".part-*.bin > "$f" || { echo "BLAD sklejania $f"; exit 1; }
done

if [ -f vbmeta_hyperos4_p11g2.img.b64 ] && [ ! -f vbmeta_hyperos4_p11g2.img ]; then
  echo "dekoduje vbmeta z .b64 ..."
  base64 -d vbmeta_hyperos4_p11g2.img.b64 > vbmeta_hyperos4_p11g2.img || exit 1
fi

if [ -f SHA256SUMS.txt ]; then
  echo "--- weryfikacja sum obrazow (SHA256SUMS.txt) ---"
  RC=0
  while read -r want name; do
    case "$name" in ''|*.img) ;; *) continue;; esac   # sprawdzamy tylko obrazy
    [ -f "$name" ] || { echo "  BRAK  $name (pominieto)"; continue; }
    got=$(sum256 "$name")
    if [ "$got" = "$want" ]; then
      echo "  OK    $name (${got:0:16}...)"
    else
      echo "  ZLE   $name"
      echo "        dostalem:  $got"
      echo "        wydanie:   $want"
      RC=1
    fi
  done < SHA256SUMS.txt
  if [ "$RC" = 0 ]; then
    echo "SUMY ZGODNE - sklejone bajty sa identyczne z wydaniem."
  else
    echo "UWAGA: suma ktoregos obrazu sie NIE zgadza (przeklamane pobieranie?)."
    echo "NIE flashuj. Skasuj wszystkie .part-*.bin i pobierz folder jeszcze raz."
    exit 1
  fi
else
  echo "--- sha256 obrazow (brak SHA256SUMS.txt - porownaj z wydaniem) ---"
  for f in *.img; do [ -f "$f" ] && sum256 "$f"; done
fi

echo "Gotowe. Flashuj: ./device-probe.sh && ./flash-all.sh"
