#!/system/bin/sh
# shellcheck disable=SC2034,SC2039
# Uruchamiane przez instalator Magisk przy flashowaniu jako ZIP.
# Przy instalacji przez scripts/install_module.sh (adb) ten plik jest ignorowany.

SKIPUNZIP=1

ui_print "- HyperOS Look dla Tab P11 Gen 2"
ui_print "- sprawdzam urzadzenie..."

PLATFORM=$(getprop ro.board.platform)
RELEASE=$(getprop ro.build.version.release)

if [ "${SKIP_DEVICE_CHECK:-0}" != "1" ]; then
  case "$PLATFORM" in
    mt6789*|helio_g99*)
      ui_print "  SoC: $PLATFORM (OK)"
      ;;
    *)
      ui_print "  UWAGA: ro.board.platform = '$PLATFORM', oczekiwano mt6789 (Helio G99)."
      ui_print "  Modul nie jest na tym sprzecie testowany."
      ui_print "  Instalacje przerwano. Wymus: SKIP_DEVICE_CHECK=1."
      abort
      ;;
  esac
fi

if [ "$(getprop ro.boot.flash.locked)" = "1" ]; then
  abort "Bootloader zablokowany - /data/adb/modules jest niedostepne."
fi

# Model nie nadpisuje vendora ani zadnej partycji. Jedyna rzecznia, ktora robimy
# przed rozpakowaniem, to sprzatanie po ewentualnej poprzedniej wersji, zeby nie
# zostaly nieaktualne overlaye.
if [ -d "/data/adb/modules/hyperos_look_p11g2/system" ]; then
  ui_print "- aktualizacja: czyszczony stary system/ z poprzedniej instalacji"
fi
rm -rf "$MODPATH/system"

ui_print "- rozpakowuje pliki modulu"
unzip -o "$ZIPFILE" 'module.prop' 'post-fs-data.sh' 'service.sh' 'system.prop' 'customize.sh' 'system/*' -d "$MODPATH" >/dev/null 2>&1

ui_print "- ustawiam uprawnienia"
set_perm_recursive "$MODPATH" 0 0 0755 0644
[ -f "$MODPATH/post-fs-data.sh" ] && set_perm 0 0 0755 "$MODPATH/post-fs-data.sh"
[ -f "$MODPATH/service.sh" ]      && set_perm 0 0 0755 "$MODPATH/service.sh"
if [ -d "$MODPATH/system/product/overlay" ]; then
  set_perm_recursive "$MODPATH/system/product/overlay" 0 0 0755 0644
fi

if [ ! -f "$MODPATH/module.prop" ]; then
  abort "module.prop nie zostal rozpakowany - ZIP jest niekompletny."
fi

ui_print "- gotowe. Po restarcie sprawdz:"
ui_print "    adb shell cmd overlay list | grep hyperos"
ui_print "  Pusta lista = overlay nie zostal zeskanowany (patrz docs/02, punkt 'diagnostyka')."
