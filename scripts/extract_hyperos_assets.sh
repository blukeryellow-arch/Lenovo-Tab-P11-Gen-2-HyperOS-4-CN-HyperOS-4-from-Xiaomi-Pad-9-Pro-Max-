#!/usr/bin/env bash
# Wyciaga z ROZPAKOWANEGO drzewa partycji HyperOS tylko to, co da sie przeniesc na
# urzadzenie z innym SoC bez naruszania warstwie HAL: zasoby (fonty, tapety, ikony,
# dzwieki, overlaye) i APK-e aplikacyjnej warstwy stylu.
#
# UZYCIE:  scripts/extract_hyperos_assets.sh <katalog-z-korzeniem-partycji> [wynik]
# PRZYKLAD: scripts/extract_hyperos_assets.sh ./unpacked/system ./modules/.../staging
#
# To NIE jest "zbuduj mi ROM". Kopiuje pliki i glosno mowi, czego nie skopiuje.
set -euo pipefail

SRC=${1:-}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DST=${2:-$ROOT/modules/hyperos-look/staging}

if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
  echo "UZYCIE: $0 <katalog z rozpakowanym zrodlem> [katalog wynikowy]" >&2
  echo "Podany katalog nie istnieje: '${SRC:-<pusty>}'" >&2
  exit 2
fi

rm -rf "$DST"
mkdir -p "$DST"
: > "$DST/copied.txt"
: > "$DST/refused.txt"

# --- BIALA LISTA: sciezki relative do korzenia partycji ------------------
ALLOW=(
  "media/fonts"
  "fonts"
  "media/wallpaper"
  "media/audio/ui"
  "media/audio/notifications"
  "media/audio/alarms"
  "media/overlay"
  "etc/overlay"
  "overlay"
  "media/theme"
  "app/ThemeManager"
  "priv-app/ThemeManager"
  "app/MiLauncher"
  "priv-app/MiLauncher"
  "app/MIUIHome"
  "priv-app/MIUIHome"
  "priv-app/SettingsControlCenter"
)

# --- LISTA ODMOWY: te pliki gwarantuja bootloop na innym SoC -------------
# Nie sa "niebezpieczne" ogolnie - sa skompilowane pod Xring O3 i pod kernel
# Xiaomi. Na Helio G99 nie mialby ich kto uzyc.
DENY_RE='libandroid_runtime\.so|libbinder|libhwbinder|android\.hardware[./]|hwcomposer|gralloc|camera|libsurfaceflinger|surfaceflinger|fingerprint|biometric|gatekeeper|keymaster|weaver|ril|telephony|audio\.primary|thermal|power\.hal|vibrator|sensors|libGLES|libegl|vulkan|mali|boot\.img|init_boot|vbmeta|dtbo|preloader|\.img$|sepolicy|fstab|ueventd|policy\.conf|services\.jar|framework\.jar|core\.jar|ext\.jar|mediadrm|keybox'

echo "=> zrodlo: $SRC"
echo "   wynik:  $DST"

copied=0
refused=0
scanned=0

for d in "${ALLOW[@]}"; do
  base="$SRC/$d"
  if [ ! -d "$base" ]; then
    continue
  fi
  echo "   katalog: $d"
  while IFS= read -r -d '' f; do
    scanned=$((scanned+1))
    rel=${f#"$SRC"/}
    if printf '%s' "$rel" | grep -qE "$DENY_RE"; then
      printf '%s\n' "$rel" >> "$DST/refused.txt"
      refused=$((refused+1))
      continue
    fi
    mkdir -p "$DST/$(dirname "$rel")"
    if cp -a "$f" "$DST/$rel"; then
      printf '%s\n' "$rel" >> "$DST/copied.txt"
      copied=$((copied+1))
    fi
  done < <(find "$base" -type f -print0 2>/dev/null)
done

{
  echo
  echo "Co zostalo skopiowane:"
  sed 's/^/  /' "$DST/copied.txt" | head -80
  echo
  echo "Co zostalo ODRZUCONE i dlaczego:"
  if [ -s "$DST/refused.txt" ]; then
    sed 's/^/  /' "$DST/refused.txt" | head -40
  else
    echo "  (nic z bialej listy nie trafilo na liste odmowy)"
  fi
} > "$DST/REPORT.txt"

echo
echo "=> przejrzane plikow: $scanned"
echo "   skopiowane:       $copied"
echo "   odrzucone:        $refused"
echo "   raport:           $DST/REPORT.txt"

if [ "$copied" -eq 0 ]; then
  cat >&2 <<'EOF'

  NIC NIE SKOPIOWANO. Prawdopodobnie:
   * podany katalog to obraz (.img), a nie rozpakowane drzewo partycji, albo
   * HyperOS ma te zasoby gdzie indziej (np. /system_ext zamiast /product) -
     wtedy dopisz sciezke do ALLOW w tym skrypcie i odpal ponownie.
EOF
  exit 1
fi

cat <<'EOF'

=> CO DALEJ
   1. Zasoby (fonty/tapety/dzwieki) trafiaja do systemu przez nadmontowanie
      katalogu w module - nie przez nadpisanie /system.
   2. Overlaye .apk ze zrodla to GOTOWE RRO Xiaomi: mozna je skopiowac do
      modules/hyperos-look/system/product/overlay/ TYLKO jesli ich cel
      (android:targetPackage) istnieje na Lenovo. Sprawdz:
         aapt2 dump xmltree --file AndroidManifest.xml <plik>
   3. Cokolwiek z refused.txt zostaje w zrodle. Nie da sie tego przeniesc
      i zaden skrypt tego nie obejdzie - to nie jest limit narzedzi, tylko
      roznica sprzetu.
EOF
