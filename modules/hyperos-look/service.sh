#!/system/bin/sh
# shellcheck disable=SC2039
# Etap late_start: system gotowy, PMS przeskanowal /product/overlay.
# Tu wlaczamy overlaye i ustawiamy globalne, które wymagają działającego
# WindowManagera. Wszystko idempotentne - modul moze byt odpalany wielokrotnie.

MODDIR=${0%/*}
LOG=/data/local/tmp/hyperos_look.log
PKG=com.hyperos.look

ui() { printf '[%s] %s\n' "hyperos_look" "$1" >> "$LOG" 2>/dev/null; }

enable_overlay() {
  target="$1"
  if cmd overlay list "$target" >/dev/null 2>&1; then
    out=$(cmd overlay enable "$PKG" 2>&1)
    ui "overlay enable dla $target: ${out:-OK}"
  else
    ui "cel $target nie istnieje - pomijam"
  fi
}

# Overlay statyczne (android:isStatic="true") aplikują się same, przy starcie PMS.
# Powyższe wywolanie jest dla overlayy dynamicznych i dla przypadków, gdy któryś
# zostal wylaczony recznie przez `cmd overlay disable`.
enable_overlay android

# --- Krzywe animacji -------------------------------------------------------
# Najbardziej odczuwalna czesc "portu" stylu. To settings globalne, wiec w ogole
# nie potrzeba overlaya - ale musza byc ponawiane przy boot, bo backup/restore i
# czesciowe factory reset je kasuja.
for pair in "window_animation_scale 0.85" \
            "transition_animation_scale 0.8" \
            "animator_duration_scale 0.85"; do
  set -- $pair
  cur=$(settings get global "$1" 2>/dev/null)
  [ "$cur" = "$2" ] || settings put global "$1" "$2" 2>/dev/null
  ui "settings global $1: $cur -> $2"
done


ui "service zakonczone; aktywne overlaye: $(cmd overlay list 2>/dev/null | grep -c '^\[x\]')"
exit 0
