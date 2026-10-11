#!/usr/bin/env bash
# Buduje APK overlayu (RRO) z modules/hyperos-look/overlay-app i wkłada go do
# katalogu modulu. Bez Gradla i bez Android Studia - wystarczy aapt2 + apksigner.
#
# UZYCIE: scripts/build_overlay_apk.sh [--debug-key]
# W CI (ubuntu-latest) dziala out-of-the-box, bo obraz runnera ma ANDROID_HOME.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP=$ROOT/modules/hyperos-look/overlay-app
OUT=$ROOT/modules/hyperos-look/system/product/overlay
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

MIN_SDK=${MIN_SDK:-31}
PKG=com.hyperos.look

# Kandydaci: PATH, potem znane lokalizacje SDK (runner GitHub ma SDK preinstalowany
# w /usr/local/lib/android/sdk - nie odwołujemy się do żadnych akcji zewnętrznych).
sdk_roots() {
  for c in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" /usr/local/lib/android/sdk "$HOME/Android/Sdk" /opt/android-sdk; do
    [ -n "$c" ] && [ -d "$c" ] && printf '%s\n' "$c"
  done
}

find_tool() {
  local name=$1 hit
  if command -v "$name" >/dev/null 2>&1; then command -v "$name"; return 0; fi
  while IFS= read -r root; do
    hit=$(find "$root/build-tools" "$root/cmdline-tools" -name "$name" -type f 2>/dev/null | sort -V | tail -1)
    [ -n "$hit" ] && { echo "$hit"; return 0; }
  done < <(sdk_roots)
  return 1
}

AAPT2=$(find_tool aapt2) || { echo "BRAK aapt2. Lokalnie: pobierz build-tools; w CI job ma setup-android." >&2; exit 1; }
APKSIGNER=$(find_tool apksigner) || { echo "BRAK apksigner." >&2; exit 1; }
ZIPALIGN=$(find_tool zipalign) || ZIPALIGN=""

echo "=> aapt2: $AAPT2"
echo "   cel:   $OUT/$PKG.apk"

# 1) kompilacja zasobow
"$AAPT2" compile --dir "$APP/res" -o "$WORK/compiled.zip"

# 2) link do APK-a. Framework musi byc podany, inaczej 'overlay' i 'targetPackage'
#    nie zostana rozpoznane, a aapt2 wywali sie na nieznanych atrybutach.
FW=()
ANDROID_JAR=""
while IFS= read -r root; do
  hit=$(find "$root/platforms" -name android.jar 2>/dev/null | sort -V | tail -1)
  if [ -n "$hit" ]; then ANDROID_JAR="$hit"; break; fi
done < <(sdk_roots)
if [ -n "$ANDROID_JAR" ]; then
  echo "   framework: $ANDROID_JAR"
  FW=(--manifest "$APP/AndroidManifest.xml" -I "$ANDROID_JAR")
fi
[ ${#FW[@]} -gt 0 ] || { echo "BRAK android.jar (platforms/*). Nie da sie zlinkowac RRO bez frameworka." >&2; exit 1; }

mkdir -p "$OUT"
"$AAPT2" link "${FW[@]}" \
  --min-sdk-version "$MIN_SDK" \
  --package-id 0x7f \
  -o "$WORK/unsigned.apk" \
  "$WORK/compiled.zip"

# 3) align (jesli dostepne)
if [ -n "$ZIPALIGN" ]; then
  "$ZIPALIGN" -f 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
  SRC_APK=$WORK/aligned.apk
else
  SRC_APK=$WORK/unsigned.apk
  echo "   zipalign niedostepny - pomijam" >&2
fi

# 4) podpis. Debug key jest OK dla RRO w /product/overlay - NIE wymaga on podpisu
#    platformowego, dopóki nie nadpisujemy rzeczy z <overlayable> przy
#    enforcement. Jesli urzadzenie odmówi, jedyna wlasciwa droga to podpis kluczem
#    systemowym danego buildu, a tego nie mamy i nie udajemy, ze mamy.
if [ "${1:-}" = "--debug-key" ] || [ ! -f "$ROOT/hyperos-look.pk8" ]; then
  KEY=$WORK/ksa.jks
  keytool -genkeypair -v -keystore "$KEY" -storepass android -keypass android \
    -alias androiddebugkey -dname "CN=Android Debug,O=Android,C=US" \
    -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
  "$APKSIGNER" sign --ks "$KEY" --ks-pass pass:android --key-pass pass:android \
    --out "$OUT/$PKG.apk" "$SRC_APK"
  echo "   podpisano kluczem tymczasowym (debug)"
else
  "$APKSIGNER" sign --key "$ROOT/hyperos-look.pk8" --cert "$ROOT/hyperos-look.x509.pem" \
    --out "$OUT/$PKG.apk" "$SRC_APK"
  echo "   podpisano kluczem z --key/--cert"
fi

"$APKSIGNER" verify --print-certs "$OUT/$PKG.apk" | sed 's/^/   /'
echo
echo "=> APK: $(du -h "$OUT/$PKG.apk" | cut -f1) w $OUT/$PKG.apk"
echo "   Nie wrzucaj tego do git-a (repozytorium sluzy do zrodel, nie binarek)."
