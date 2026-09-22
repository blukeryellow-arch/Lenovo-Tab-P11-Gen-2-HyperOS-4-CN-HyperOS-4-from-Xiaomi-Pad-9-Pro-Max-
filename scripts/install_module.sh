#!/usr/bin/env bash
# Instalacja modulu PRZEZ KATALOG, nie przez ZIP. Dlaczego:
#   * flashable ZIP wymaga META-INF/com/google/android/update-binary, ktorego tu
#     nie wygenerujemy wiarygodnie (wzoruje sie go z Magisk'a, nie z tutoriala),
#   * katalog w /data/adb/modules/<id>/ jest obslugiwany bezposrednio przez
#     Magisk i KernelSU: uruchamiany jest module.prop + post-fs-data.sh +
#     service.sh + nadmontowanie system/,
#   * a do dev-iteracji i tak wazniejsze jest to, ze zdjecie modulu to jedno
#     rm -rf + reboot, bez wgrawania czegokolwiek w partycje.
#
# UZYCIE:
#   scripts/install_module.sh            # wgranje + reboot
#   scripts/install_module.sh --no-reboot
#   scripts/install_module.sh --disable  # wyloguj modul (jedno dotkniecie pliku)
#   scripts/install_module.sh --remove
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MOD=$ROOT/modules/hyperos-look
ID=$(sed -n 's/^id=//p' "$MOD/module.prop" | tr -d '[:space:]')
[ -n "$ID" ] || { echo "Nie mozna odczytac id z module.prop" >&2; exit 1; }
DEST=/data/adb/modules/$ID

have_su() { adb shell su -c id >/dev/null 2>&1 || adb shell su 0 id >/dev/null 2>&1; }
su_sh()   { adb shell su -c "$1" 2>/dev/null || adb shell su 0 "$1"; }

if ! command -v adb >/dev/null 2>&1; then echo "BRAK adb." >&2; exit 1; fi
if ! adb get-state >/dev/null 2>&1; then echo "Brak urzadzenia w adb (sprawdz 'adb devices'; tryb offline = ekran zablokowany)." >&2; exit 1; fi
have_su || { echo "Brak dostepu root przez adb (odmowa su). Odblokuj 'Root' w Magisk/KSU dla ADB." >&2; exit 1; }

echo "=> urzadzenie: $(adb shell getprop ro.product.model | tr -d '\r')"
echo "   modul id:    $ID"

case "${1:-}" in
  --disable)
    su_sh "touch $DEST/disable"
    echo "   modul wylaczony. Reboot: adb reboot"
    exit 0 ;;
  --enable)
    su_sh "rm -f $DEST/disable"
    echo "   modul wlaczony. Reboot: adb reboot"
    exit 0 ;;
  --remove)
    su_sh "rm -rf $DEST"
    echo "   modul usuniety. Reboot: adb reboot"
    exit 0 ;;
esac

# Bezpiecznik: nigdy nie nadpisujemy vendora, nawet gdybys cos tam wlozyl.
if find "$MOD/system" -path '*vendor*' -print 2>/dev/null | grep -q .; then
  echo "PRZERWANE: w module/system/ sa sciezki z 'vendor'. Ten modul nie rusza vendora." >&2
  exit 1
fi

echo "=> sprzatam stara wersje"
su_sh "rm -rf $DEST.tmp && mkdir -p $DEST.tmp"

echo "=> paczke i wgranje"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -a "$MOD"/. "$STAGE"/
rm -rf "$STAGE/overlay-app" "$STAGE/staging"
cd "$STAGE" && tar czf module.tgz .
adb push module.tgz /data/local/tmp/hyperos_look.tgz >/dev/null

su_sh "tar xzf /data/local/tmp/hyperos_look.tgz -C $DEST.tmp \
       && chmod 0755 $DEST.tmp/post-fs-data.sh $DEST.tmp/service.sh 2>/dev/null; \
       chown -R 0:0 $DEST.tmp; \
       rm -f $DEST.tmp/update; \
       rm -rf $DEST.old; mv $DEST $DEST.old 2>/dev/null; mv $DEST.tmp $DEST; \
       rm -f /data/local/tmp/hyperos_look.tgz"

# Kontrola, czy module.prop ma wszystkie pola wymagane przez Magisk - bez tego
# instalator pomija katalog bez komunikatu (najczestszy powod "modul nie dziala").
for f in id name version versionCode author description; do
  grep -q "^=" "$MOD/module.prop" || echo "   BRAK pola = w module.prop" >&2
done

echo
echo "=> weryfikacja"
su_sh "ls -l $DEST" | sed 's/^/   /'
su_sh "cat $DEST/module.prop" | sed 's/^/   /'

if [ "${1:-}" != "--no-reboot" ]; then
  echo
  echo "=> reboot"
  adb reboot
  echo "   poczekaj ~60s, potem: scripts/verify_module.sh"
else
  echo
  echo "   pominieto reboot (--no-reboot)"
fi
