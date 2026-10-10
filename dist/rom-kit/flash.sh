#!/usr/bin/env bash
# Flashowanie TYLKO na odblokowanym bootloaderze. URUCHOM NAZAJEDEN.
#
# Zmierzone na tym firmware (nie z wiki): 'system' nie jest tu zwykla partycja blokowa -
# vbmeta targetu ma chain do vbmeta_system, a product/system_ext ida jako hashtree
# wewnatrz 'super' (uklad GSI). Dlatego najpierw sprawdzamy, w ktorym trybie fastboot
# jestesmy: bootloader (is-userspace: no) zwykle NIE umi flashowac partycji dynamicznych.
set -uo pipefail
cd "$(dirname "$0")"
command -v fastboot >/dev/null || { echo "brak fastboot w PATH"; exit 1; }
fb() { fastboot "$@"; }
IMG_SYS=system_hyperos4_p11g2.img
IMG_VB=vbmeta_hyperos4_p11g2.img
[ -f "$IMG_VB" ] || { echo "brak $IMG_VB"; exit 1; }
[ -f "$IMG_SYS" ] || { echo "brak $IMG_SYS - runner nie zbudowal obrazu (patrz BUILD_LOG.txt: 'POMINIETE (brak mkfs.erofs)')"; exit 1; }

echo "== 0. identyfikacja urzadzenia"
PROD=$(fb getvar product 2>&1 | tr -d $'\r' | sed -n 's/^product: *//p')
echo "  product=${PROD:-nieznany}"
case "$PROD" in
  *TB350FU*|*p11*|*j7*) echo "  OK, wyglada na Tab P11 Gen 2";;
  "") echo "  UWAGA: getvar nie zwrocil niczytaj - upewnij sie, ktore to urzadzenie";;
  *)  echo "  UWAGA: to NIE jest TB350FU ('$PROD'). CTRL+C jesli nie wiesz co robisz."; sleep 5;;
esac

echo "== 1. kopia zapasowa obecnej vbmeta (to jest Twoj rollback AVB)"
# Oba sloty, nie tylko a: przy current-slot=b urzadzenie weryfikuje vbmeta_b, a 25-liniowy
# flash.sh z biegu 35897100768egral/wgrywal tylko vbmeta_a -> stajacy device bez komunikatu.
for sfx in a b; do
  fb fetch "vbmeta_$sfx" "vbmeta_obecna_$sfx.img" 2>/dev/null \
    && echo "  zapisano vbmeta_obecna_$sfx.img" \
    || echo "  fetch vbmeta_$sfx nie udany - rollback = 3 pliki Lenovo z Dysku (diagnostics/drive-inventory.tsv)"
done

echo "== 2. tryb fastbootd (potrzebny do partycji w super)"
USER=$(fb getvar is-userspace 2>&1 | tr -d $'\r' | sed -n 's/^is-userspace: *//p')
echo "  userspace=${USER:-nieznany}"
if [ "$USER" != "yes" ]; then
  echo "  reboot do fastbootd..."
  fb reboot fastboot 2>/dev/null || true
  sleep 12
  USER=$(fb getvar is-userspace 2>&1 | tr -d $'\r' | sed -n 's/^is-userspace: *//p')
  echo "  teraz userspace=${USER:-nadal bootloader}"
  [ "$USER" = "yes" ] || echo "  FASTBOOTD NEDOSTEPNY - wowczas 'fastboot flash system' padnie;" \
    "trzeba wtedy zbudowac caly super.img (lpmake) albo flashowac z recovery;" \
    "nie udaje sie tego sprawdzic bez urzadzenia."
fi

fbp() { # $1=partycja (z przyrostkiem slotu), $2=plik - proboj z przyrostkiem, potem bez
  if ! fb flash "$1" "$2"; then
    echo "  '$1' nie wszedl - probe bez przyrostka slotu"
    fb flash "${1%_*}" "$2" || { echo "  FATAL: nie da sie wgrac '$1'"; return 1; }
  fi
}

echo "== 3. vbmeta z flags=3 (weryfikacja/verity wylaczone) i przebudowany system"
fbp vbmeta_a "$IMG_VB" || exit 1
fb flash vbmeta_b "$IMG_VB" || echo "  (slot b pominieto - nie krytyczne, boot idzie z a)"
fbp system_a "$IMG_SYS" || exit 1
fb flash system_b "$IMG_SYS" || echo "  (slot b pominieto)"

echo "== 4. dane"
echo "  framework inny niz poprzedni -> bez wipe /data typowa reakcja to boot loop."
read -r -p "  Usunac /data (usuwa wszystko z tableta)? [t/N] " a
case "$a" in
  t|T|tak|TAK) fb erase userdata && echo "  userdata wykasowane";;
  *) echo "  bez wipe - jesli urzadzenie wejdzie w petle, wrc tu i wykonaj erase userdata";;
esac

echo "== 5. reboot"
fb reboot || true
cat <<'NOTE'

Co dalej (to jest czesc 'nie wiemy, dopoki nie podlaczysz'):
  adb wait-for-device; adb logcat -b all | grep -E 'vintf|init|Zygote|SurfaceFlinger'
  - jesli widzisz 'Failed to initialize VINTF' -> plik macierzy nie wszedl do obrazu
    (sprawdz w paczce BUILD_LOG.txt linie 'wygenerowanych plikow: 3')
  - jesli boot dojdzie do 'Zygote 64-bit' i stoi -> to juz nie VINTF, tylko brak
    HAL-i vendora (patrz MISMATCH.md)
Rollback:
  fastboot flash vbmeta_a vbmeta_obecna_a.img   (albo vbmeta.img z Dysku)
  fastboot flash boot_a boot.img ; fastboot flash vendor_boot_a vendor_boot.img
  fastboot --set-active=a ; fastboot reboot
NOTE
