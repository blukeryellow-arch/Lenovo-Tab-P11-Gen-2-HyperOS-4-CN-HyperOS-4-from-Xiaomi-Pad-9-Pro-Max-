#!/usr/bin/env bash
# Czy modul faktycznie dziala po restarcie. Odpala sie wlasciwie zawsze - takze
# wtedy, gdy "cos nie dziala, ale nie wiemy co". Wypisuje konkrety, nie oceny.
set -uo pipefail

su_sh() { adb shell su -c "$1" 2>/dev/null || adb shell su 0 "$1" 2>/dev/null; }
line() { printf '%s\n' "$1"; }
val()  { printf '   %-38s %s\n' "$1" "$2"; }

if ! adb get-state >/dev/null 2>&1; then
  echo "BRAK urzadzenia w adb. Jesli reboot po module skonczyl sie bootloopem:" >&2
  echo "  adb reboot bootloader && fastboot flash vbmeta --disable-verity --disable-verification <vbmeta.stock.img>" >&2
  echo "  a w najgorszym razie: wejdz w recovery/Magisk 'Remove module' albo" >&2
  echo "  sbierz /data/adb/modules przez mtkclient - modul NIE rusza partycji, wiec" >&2
  echo "  usuniecie katalogu przywraca stan wyjsciowy." >&2
  exit 1
fi

echo "=== urzadzenie ==="
val "model"   "$(adb shell getprop ro.product.model | tr -d '\r')"
val "board"   "$(adb shell getprop ro.board.platform | tr -d '\r')"
val "android" "$(adb shell getprop ro.build.version.release | tr -d '\r') ($(adb shell getprop ro.build.id | tr -d '\r'))"
val "slot"    "$(adb shell getprop ro.boot.slot_suffix | tr -d '\r')"
val "vbmeta"  "$(adb shell getprop ro.boot.vbmeta.device_state | tr -d '\r') / verifiedbootstate=$(adb shell getprop ro.boot.verifiedbootstate | tr -d '\r')"
val "root"    "$(adb shell su -c id 2>/dev/null | tr -d '\r' || echo 'BRAK')"

echo
echo "=== modul ==="
DEST=/data/adb/modules/hyperos_look_p11g2
su_sh "test -d $DEST && echo obecny || echo NIEOBECNY" | sed 's/^/   /'
su_sh "test -f $DEST/disable && echo 'WYLACZONY (disable)' || echo 'wlaczony'" | sed 's/^/   /'
su_sh "cat $DEST/module.prop 2>/dev/null | head -4" | sed 's/^/   /'
su_sh "ls $DEST/system/product/overlay 2>/dev/null" | sed 's/^/   overlay w module: /'

echo
echo "=== nadmontowanie /product/overlay ==="
su_sh "ls -l /product/overlay/ 2>/dev/null | grep -i hyperos || echo '   (HyperOS Look nie widoczny w /product/overlay - Magisk moze montowac inaczej)'"

echo
echo "=== stan RRO ==="
adb shell 'cmd overlay list 2>/dev/null | grep -iE "hyperos|^\[x\].*com\.hyperos"' | tr -d '\r' | sed 's/^/   /' || line "   (cmd overlay list nie zwrocil hyperos - overlay nie zostal zarejestrowany)"
adb shell 'cmd overlay status com.hyperos.look 2>/dev/null' | tr -d '\r' | sed 's/^/   /'

echo
echo "=== log modulu (post-fs-data + service) ==="
adb shell 'cat /data/local/tmp/hyperos_look.log 2>/dev/null | tail -25' | tr -d '\r' | sed 's/^/   /' || line "   (brak logu - skryty nie odpalily: modul nie dojsc do etapu boot)"

echo
echo "=== pamiec (6 GB, to ma byc pod obserwacja) ==="
adb shell 'cat /proc/meminfo | head -3' | tr -d '\r' | sed 's/^/   /'
adb shell 'getprop | grep -E "dalvik.vm.heapsize|dalvik.vm.heapgrowthlimit"' | tr -d '\r' | sed 's/^/   /'

echo
echo "=== ostatnie awarie procesow (SystemUI to typowa ofiara zlego overlaya) ==="
adb shell 'logcat -b crash -d -t 60 2>/dev/null | grep -iE "SystemUI|hyperos|overlay" | tail -12' | tr -d '\r' | sed 's/^/   /' || line "   (brak)"
echo
line "Koniec. Caly ten wynik jest do wklejenia do czatu - na jego podstawie"
line "wiadomo, ktory z pieciu etapow (instalacja, montowanie, skan PMS, enable,"
line "aplikacja) sie urwal."
