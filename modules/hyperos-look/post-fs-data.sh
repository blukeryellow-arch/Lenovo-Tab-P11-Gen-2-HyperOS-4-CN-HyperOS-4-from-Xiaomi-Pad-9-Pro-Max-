#!/system/bin/sh
# shellcheck disable=SC2039
# Etap post-fs-data: /data jest zamontowane, serwisy jeszcze nie wystartowaly.
# Tu NIE restartujemy niczego i NIE nadpisujemy vendora.

MODDIR=${0%/*}
LOG=/data/local/tmp/hyperos_look.log

ui() { printf '[%s] %s\n' "hyperos_look" "$1" >> "$LOG" 2>/dev/null; }

: > "$LOG"
ui "modul: $MODDIR"
ui "urzadzenie: $(getprop ro.product.model) / $(getprop ro.board.platform)"
ui "android: $(getprop ro.build.version.release) ($(getprop ro.build.display.id))"
ui "slot: $(getprop ro.boot.slot_suffix)  vbmeta: $(getprop ro.boot.vbmeta.device_state)"

# --- Presja pamieci na 6 GB LPDDR4X --------------------------------------
# Ustawiane przy kazdym boocie, bo init LMK przy starcie nadpisuje czesc z tych
# wartosci wlasnymi. Dobrane pod 6 GB, nie skopiowane ze zrodla.
write_if_differs() {
  # $1 sciezka, $2 wartosc
  [ -w "$1" ] || { ui "pominieto (brak zapisu): $1"; return 0; }
  cur=$(cat "$1" 2>/dev/null)
  if [ "$cur" != "$2" ]; then
    echo "$2" > "$1" 2>/dev/null && ui "$1: $cur -> $2" || ui "zapis udaremniony: $1"
  fi
}

# Za agresywny swappiness na wolnym UFS 2.2 = sekanie; za niski = LMK zaczyna
# zabijac aplikacje za wczesnie. 120 to kompromis do weryfikacji na tym sprzecie.
write_if_differs /proc/sys/vm/swappiness 120
write_if_differs /proc/sys/vm/vfs_cache_pressure 100
write_if_differs /proc/sys/vm/dirty_ratio 10
write_if_differs /proc/sys/vm/dirty_background_ratio 5

# Zram - tylko jesli urzadzenie go w ogóle ma. Nie tworzymy nowego urzadzenia,
# bo konfiguracja zram jest na tym modelu w init Lenovo i ruszanie jej to
# recepta na bootloop.
if [ -b /dev/block/zram0 ]; then
  ui "zram obecny, statystyki: $(cat /sys/block/zram0/mm_stat 2>/dev/null)"
else
  ui "zram nieobecny - nic nie ruszamy"
fi

# --- Stan overlayy, do diagnostyki ----------------------------------------
cmd overlay list >/data/local/tmp/hyperos_look_overlays.txt 2>/dev/null

ui "post-fs-data zakonczone"
exit 0
