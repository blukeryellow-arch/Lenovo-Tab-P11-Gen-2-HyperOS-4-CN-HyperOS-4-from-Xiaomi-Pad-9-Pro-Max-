#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

command -v fastboot >/dev/null || {
  echo "BLAD: brak fastboot w PATH (zainstaluj android-tools-fastboot / platform-tools)." >&2
  exit 1
}

[ -f super.img ] || { echo "BLAD: brak super.img w katalogu!" >&2; exit 1; }
[ -f boot.img ]  || { echo "BLAD: brak boot.img w katalogu!" >&2; exit 1; }

echo "==> Sprawdzam urzadzenie w fastboot..."
fastboot devices

read -r -p "Wpisz TAK aby rozpoczac wgrywanie na Redmi 9C (blossom): " CONF
[ "$CONF" = "TAK" ] || exit 0

echo "==> [1/4] vbmeta..."
fastboot flash vbmeta vbmeta.img
[ -f vbmeta_system.img ] && fastboot flash vbmeta_system vbmeta_system.img
[ -f vbmeta_vendor.img ] && fastboot flash vbmeta_vendor vbmeta_vendor.img

echo "==> [2/4] dtbo..."
[ -f dtbo.img ] && fastboot flash dtbo dtbo.img

echo "==> [3/4] boot (kernel 4.19 OSS)..."
fastboot flash boot boot.img

echo "==> [4/4] super (MysticalOS 1.0 + OSS vendor)..."
fastboot flash super super.img

read -r -p "Wykonać format danych fastboot -w (wymagane przy 1. instalacji)? [t/N]: " WIPE
if [[ "$WIPE" =~ ^[TtYy]$ ]]; then
  fastboot -w
fi

echo "==> Gotowe! Restart..."
fastboot reboot
