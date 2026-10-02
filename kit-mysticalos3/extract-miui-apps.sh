#!/usr/bin/env bash
# ============================================================================
# extract-miui-apps.sh - wyciaga aplikacje MIUI/HyperOS z product.img donora
# ============================================================================
# Dlaczego: donor-cache w CI nie powstal (Drive dlawil 10,3 GB), a repo jest
# znowu private (= Actions niedostepne). Ale TY masz pliki donora lokalnie -
# ten skrypt wyciaga z nich aplikacje MIUI i instaluje je na MysticalOS 3
# przez adb. Bez CI, bez rebuildu super.img, 10 minut.
#
# Uzycie:
#   ./extract-miui-apps.sh <product.img>              -> ./miui-apps/
#   ./extract-miui-apps.sh <product.img> ./moje-appki  -> wybrane miejsce
#   ./extract-miui-apps.sh --install <product.img>    -> od razu adb install
#
# Wejscie: product.img z dumpa HyperOS (EROFS albo ext4 - rozpoznaje sam).
#   Jesli masz tylko payload.bin z OTA - powiedz agentowi, rozszerzymy.
# Wymagania: bash, python3, debugfs (apt install e2fsprogs) dla ext4;
#   EROFS obsluguje binarka z kitu (bin/fsck.erofs) - zero roota.
#
# Po instalacji: aplikacje sa zwyklymi APK - dzialaja obok stockowych
# Lenova (te zostaja jako fallback). MiuiCamera moze byc niepelna na
# sprzecie Lenova (aparaty MIUI sa sprzetowo zwiazane z Xiaomi) - kalkulator,
# notatki, pogoda, zegar, wideo, launcher sa przenosne.
# ============================================================================
set -euo pipefail

KDIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL=0
if [ "${1:-}" = "--install" ]; then INSTALL=1; shift; fi
IMG="${1:-}"
OUT="${2:-$KDIR/miui-apps}"
[ -s "$IMG" ] || { echo "BLAD: podaj sciezke do product.img (uzycie w naglowku)"; exit 1; }

# lista aplikacji do wyciagniecia (katalogi w product/{priv-,}app)
WANT="MiuiCalculator MiuiCamera MiuiVideo MiuiNotes NewMiuiNotes MiuiWeather2
MiuiClock MiuiSecurityCenter MiuiHome MiuiGallery MiuiGalleryNew MiuiMusic
MiuiFileManager"

mkdir -p "$OUT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "== 1/3: rozpoznaje system plikow =="
python3 - "$IMG" <<'EOF'
import struct, sys
with open(sys.argv[1], 'rb') as f:
    d = f.read(4096)
if len(d) >= 4036 and d[1024:1026] == b'\x53\xef':
    print("ext4"); sys.exit(0)
if d[0:4] == b'\xe0\x1f\xe1\xe2' or d[36:40] == b'\xe0\x1f\xe1\xe2':
    print("erofs"); sys.exit(0)
if d[0:4] == b'\x3a\xff\x26\xed':
    print("SPARSE! najpierw: python3 tools/simg2img.py product.img product_raw.img"); sys.exit(1)
print("nieznany"); sys.exit(1)
EOF
FS=$(python3 - "$IMG" <<'EOF'
import struct, sys
with open(sys.argv[1], 'rb') as f:
    d = f.read(4096)
print("ext4" if d[1024:1026] == b'\x53\xef' else "erofs")
EOF
)

echo "== 2/3: ekstrakcja drzewa product ($FS) =="
TREE="$TMP/product"
mkdir -p "$TREE"
if [ "$FS" = "erofs" ]; then
  "$KDIR/bin/fsck.erofs" --extract="$TREE" "$IMG" >/dev/null 2>&1 || {
    # starsze fsck.erofs wypakowuje do CWD bez = ; fallback:
    (cd "$TREE" && "$KDIR/bin/fsck.erofs" --extract "$IMG") >/dev/null 2>&1 || {
      echo "BLAD: fsck.erofs nie dal rady"; exit 1; }
  }
else
  command -v debugfs >/dev/null || { echo "BLAD: zainstaluj debugfs: sudo apt install e2fsprogs"; exit 1; }
  debugfs -R "rdump / $TREE" "$IMG" >/dev/null 2>&1 || { echo "BLAD: debugfs rdump nie wyszedl"; exit 1; }
fi
# fsck.erofs moze wypakowac root bezposrednio (bez podkatalogu product)
if [ -d "$TREE/product" ]; then TREE="$TREE/product"; fi

echo "== 3/3: szukam aplikacji MIUI =="
FOUND=0
for NAME in $WANT; do
  D=$(find "$TREE" -maxdepth 3 -type d -iname "$NAME" 2>/dev/null | head -1)
  [ -n "$D" ] || continue
  DEST="$OUT/$(basename "$D" | sed 's/New$//')"
  mkdir -p "$DEST"
  find "$D" -name '*.apk' -exec cp -a {} "$DEST/" \; 2>/dev/null || true
  N=$(ls "$DEST"/*.apk 2>/dev/null | wc -l)
  if [ "$N" -gt 0 ]; then FOUND=$((FOUND+1)); echo "  + $(basename "$DEST"): $N apk"; fi
done
[ "$FOUND" -gt 0 ] || { echo "BLAD: nie znaleziono zadnej z aplikacji MIUI w product.img"; exit 1; }

echo ""
echo "GOTOWE: $FOUND aplikacji w $OUT"
echo ""
if [ "$INSTALL" = "1" ]; then
  echo "== adb install =="
  command -v adb >/dev/null || { echo "BLAD: brak adb (platform-tools)"; exit 1; }
  find "$OUT" -name '*.apk' -print0 | while IFS= read -r -d '' A; do
    echo "install: $(basename "$A")"
    adb install -r "$A" || echo "  (pominieto: $(basename "$A"))"
  done
  echo "Wskazowka: MiuiHome jako domyslny launcher: Ustawienia -> Aplikacje -> Aplikacje domyslne."
else
  echo "Instalacja reczna: adb install -r miui-apps/*/*.apk"
  echo "albo ponownie z --install."
fi
