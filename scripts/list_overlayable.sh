#!/usr/bin/env bash
# Wypisuje, ktore zasoby frameworka NA TWOIM BUDZIE mozna legalnie nadpisac
# overlayem. Bez tej listy pisanie overlay.xml to zgadywanka.
#
# Potrzebne: adb (platform-tools). Opcjonalnie: aapt2 w PATH albo ANDROID_HOME.
# Uruchamia sie na komputerze, nie na tablecie.
set -euo pipefail

OUT=${OUT:-/tmp/overlayable}
PKG_TARGET=${PKG_TARGET:-android}
mkdir -p "$OUT"

have() { command -v "$1" >/dev/null 2>&1; }

if ! have adb; then
  echo "BRAK adb. Zainstaluj platform-tools po swojej stronie - stad nie sciagne." >&2
  exit 1
fi

echo "=> urzadzenie: $(adb get-serialno 2>/dev/null || echo '?')"
echo "   model:   $(adb shell getprop ro.product.model | tr -d '\r')"
echo "   build:   $(adb shell getprop ro.build.display.id | tr -d '\r')"
echo "   android: $(adb shell getprop ro.build.version.release | tr -d '\r')"

# 1) overlayable.xml - oficjalna lista "mozna nadpisac" dla overlayy dynamicznych.
#    Brak pliku dla pakietu = pakiet nie ma enforcementu = nadpisac mozna prawie
#    wszystko (typowe dla 'android' na wiekszosci buildow).
echo
echo "=> szukam plikow overlayable.xml na urzadzeniu"
adb shell 'for p in /vendor/etc/overlay/*.apk /product/etc/overlay/*.apk /system/etc/overlay/*.apk /product/overlay/*.apk /vendor/overlay/*.apk; do [ -e "$p" ] && echo "$p"; done' 2>/dev/null | tr -d '\r' > "$OUT/overlay_candidates.txt" || true
echo "   znaleziono plikow overlay w /product|/vendor: $(wc -l < "$OUT/overlay_candidates.txt")"
cat "$OUT/overlay_candidates.txt" | sed 's/^/     /' | head -30

# 2) framework-res.apk - realne nazwy, typy i wartosci.
echo
echo "=> sciagam framework-res.apk"
FW=$(adb shell 'for p in /system/framework/framework-res.apk /system/framework/frameworkres.apk; do [ -e "$p" ] && { echo "$p"; break; }; done' | tr -d '\r')
if [ -z "${FW:-}" ]; then
  echo "   NIE ZNALEZIONE framework-res.apk - na nowszych buildach moze byc w /system/framework/, sprawdz recznie" >&2
  exit 1
fi
adb pull "$FW" "$OUT/framework-res.apk" >/dev/null
echo "   src: $FW"

# 3) aktualne wartosci, ktore zamierzamy nadpisac - bez tego nie wiemy, co zmieniamy.
if have aapt2 || { [ -n "${ANDROID_HOME:-}" ] && have "$ANDROID_HOME/build-tools"/*/aapt2; }; then
  AAPT2=$(command -v aapt2 || ls "$ANDROID_HOME"/build-tools/*/aapt2 | head -1)
  echo
  echo "=> zrzucam dump zasobow ($AAPT2)"
  "$AAPT2" dump resources "$OUT/framework-res.apk" > "$OUT/framework-res.txt"
  echo "   pozycji: $(grep -cE '^\s+resource' "$OUT/framework-res.txt" 2>/dev/null || echo '?')"
  echo "   zapis: $OUT/framework-res.txt"
  echo
  echo "=> kandydaci przydatni przy 'look' HyperOS (nazwy istniejace w tym buildzie):"
  grep -oE 'resource [a-z]+/(config_[a-zA-Z]+|status_bar_height|navigation_bar_height|window_title_size)' \
    "$OUT/framework-res.txt" | sort -u | sed 's/resource //' | head -60
else
  echo
  echo "   aapt2 niedostepny - pomijam dump. W CI ten krok wykona runner (ma SDK)." >&2
  echo "   lokalnie wystarczy: $OUT/framework-res.apk zostal sciagniety." >&2
fi

echo
echo "=> gotowe. Katalog: $OUT"
echo "   Nastepny krok: scripts/extract_hyperos_assets.sh <katalog-z-hyperos>"
