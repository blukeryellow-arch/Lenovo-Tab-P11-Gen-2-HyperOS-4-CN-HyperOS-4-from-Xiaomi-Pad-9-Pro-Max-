#!/usr/bin/env bash
# powrot do stock: wgrywa vbmeta z kopii wykonanej przez flash-all.sh
set -uo pipefail
cd "$(dirname "$0")"
for s in a b; do
  [ -f "vbmeta_stock_$s.img" ] || { echo "brak vbmeta_stock_$s.img - kopie robil flash-all.sh (krok 2)"; continue; }
  fastboot flash "vbmeta_$s" "vbmeta_stock_$s.img" && echo "  przywrocone vbmeta_$s"
done
cat <<'WARN'

UWAGA - to NIE przywraca partycji product ani system. Ten skrypt odkreca wylacznie
weryfikacje AVB (vbmeta). Obrazy Lenovo, ktore leza na Dysku, to boot / vendor_boot /
vbmeta - NIE ma tam stockowego system.img ani product.img (te dwie pozycje na dysku to
HyperOS z Xiaomi Pad 9 Pro Max i NIE odtworza Twojego fabrycznego firmware).
Wiec kolejnosc po awarii jest taka:
  1) ten skrypt (vbmeta z powrotem na stock),
  2) fastboot flash boot boot.img   (i vendor_boot, jesli ruszales) - to przywraca kernel,
  3) product/system: odtworz z OFICJALNEJ paczki firmware Lenovo dla TB350FU (albo z kopii
     zrobionej PRZED flashem - patrz README, sekcja 'Awaria'). Jezli kopii nie masz, NIE
     flashuj: to jest ten jeden krok, ktorego zadny skrypt w tym katalogu nie zrobi za Ciebie.
WARN
