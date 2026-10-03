#!/usr/bin/env bash
# FLASH-ALL.sh - JEDNA KOMENDA = caly flash MysticalOS 3 (TB350FU)
# Linux/WSL/macOS: bash FLASH-ALL.sh
#
# DZIALA W DWUCH SYTUACJACH:
#  A) jest JUZ super_mystical3.img (np. z zipa CALOSC) -> tylko weryfikuje+flashuje
#  B) sa 32 czesci .part.00-.31 -> sam skleja je w img.
set -uo pipefail
cd "$(dirname "$0")"
WANT_SHA=1d5f480922e5db47455915c822705ab749025f0004c776203b9d21ee1985b16e
WANT_SZ=6313495592
FB=fastboot
command -v "$FB" >/dev/null 2>&1 || { echo "[BLAD] brak fastboot w PATH (zainstaluj platform-tools)"; exit 1; }

szof() { stat -c%s "$1" 2>/dev/null || stat -f%z "$1"; }

echo "[1/6] Obraz..."
if [ -f super_mystical3.img ] && [ "$(szof super_mystical3.img)" = "$WANT_SZ" ]; then
  echo "       super_mystical3.img JUZ GOTOWY - nie sklejam."
else
  rm -f super_mystical3.img
  NP=$(ls super_mystical3.part.* 2>/dev/null | wc -l)
  [ "$NP" = "32" ] || { echo "[BLAD] czesci: $NP/32 - pobierz wszystkie z release albo rozpakuj zip CALOSC"; exit 1; }
  echo "       Sklejam 32 czesci (2-10 min)..."
  cat super_mystical3.part.* > super_mystical3.img || { echo "[BLAD] sklejanie"; exit 1; }
fi

echo "[2/6] Rozmiar + SHA256..."
SZ=$(szof super_mystical3.img)
[ "$SZ" = "$WANT_SZ" ] || { echo "[BLAD] rozmiar $SZ != $WANT_SZ - pobierz ponownie"; exit 1; }
SHA=$(sha256sum super_mystical3.img 2>/dev/null | cut -d' ' -f1 || shasum -a 256 super_mystical3.img | cut -d' ' -f1)
[ "$SHA" = "$WANT_SHA" ] || { echo "[BLAD] sha $SHA - pobierz ponownie"; exit 1; }
echo "       OK - plik zweryfikowany."

echo "[3/6] Tablet w fastboot..."
"$FB" devices | grep -q fastboot || { echo "[BLAD] nie widze tabletu (wylaczony, trzymaj Vol- + Power)"; exit 1; }
"$FB" flash vbmeta vbmeta_disable.img || { echo "[BLAD] vbmeta"; exit 1; }
"$FB" flash vbmeta_system vbmeta_system_disable.img || { echo "[BLAD] vbmeta_system"; exit 1; }
"$FB" flash vbmeta_vendor vbmeta_vendor_disable.img || { echo "[BLAD] vbmeta_vendor"; exit 1; }
echo "       vbmeta x3 OK."

echo "[4/6] Restart do fastbootd (do 60 s)..."
"$FB" reboot fastboot || true
OK=0
for i in $(seq 1 12); do
  sleep 5
  if "$FB" devices 2>/dev/null | grep -q fastboot; then OK=1; break; fi
done
[ "$OK" = 1 ] || { echo "[BLAD] tablet nie wrocil do fastboot(d)"; exit 1; }

echo "[5/6] Flashuje super (10-20 min, NIE ODLACZAJ!)..."
"$FB" flash super super_mystical3.img || { echo "[BLAD] flash super"; exit 1; }

echo "[6/6] Slot A + restart..."
"$FB" --set-active=a
echo "=============================================================="
echo " GOTOWE! Pierwszy boot 10-15 min czarnego ekranu = normalne."
echo " microG: Settings -> Google Account -> Sign in"
echo " Launcher MIUI: Aplikacje domyslne -> MiuiHome"
echo " Bootloop: $FB flash boot boot_TB350FU_S230982_251013_ROW.img"
echo " Rollback: $FB --set-active=b"
echo "=============================================================="
"$FB" reboot
