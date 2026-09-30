#!/usr/bin/env bash
# ============================================================================
# MysticalOS 3 - LOKALNY BUILD super.img (TB350FU_S230982_251013_ROW)
# ============================================================================
# Pelny pipeline na TWOIM komputerze (Linux / WSL2) - bez GitHub Actions.
#
# Co robi: pobiera baze Lenovo (lolinet, 4,7G) -> streamuje super.img z zipa
# (bez zapisywania 9,7G raw) -> ekstrahuje partycje (debugfs/fsck.erofs) ->
# PURGE GMS (system+product+system_ext; WebView zostaje) -> INJECT microG +
# FakeStore (+Aurora jesli dostepna) -> props MysticalOS + display mitigation
# -> repack EROFS z kontekstami SELinux -> lpmake -S (fabryczna geometria
# 9 663 676 416 B, VAB, slot A) -> super_mystical3.img (sparse) + vbmeta_disable
# (flags=3) x3 + boot_S230982 + SHA256SUMS.
#
# Wymagania: bash, python3, curl, unzip, debugfs (e2fsprogs), ~20G wolnego.
# NIE wymaga roota (debugfs rdump zamiast mount; mkfs.erofs/lpmake usermode).
# Czas: ~30-60 min (zaleznie od lacza i dysku).
#
# Uzycie:  ./build-mystical3.sh [katalog-roboczy]   (domyslnie ./build)
# ============================================================================
set -euo pipefail

KDIR="$(cd "$(dirname "$0")" && pwd)"
WORK="${1:-$KDIR/build}"
OUT="$WORK/out"

LOLINET_ZIP_URL="https://mirrors.lolinet.com/firmware/lenowow/2022/Tab_P11_2nd_Gen/TB350FU/TB350FU_S230982_251013_ROW.zip"
LOLINET_SIZE=4692836474
BASE_ENTRY_PREFIX="TB350FU_S230982_251013_ROW/image"
BASE_BUILD="TB350FU_S230982_251013_ROW"
SIZE_SYSTEM=3678793728
SIZE_PRODUCT=2792497152
SIZE_SYSTEM_EXT=756998144
SIZE_VENDOR=916553728
SIZE_VENDOR_DLKM=31363072
SIZE_ODM_DLKM=348160
LOLINET_BOOT_LEN=67108864
SUPER_SIZE=9663676416
MAIN_GROUP_SIZE=9661579264
GMS_APK_URL="https://github.com/microg/GmsCore/releases/download/v0.3.16.252432/com.google.android.gms-252432032.apk"
VENDING_APK_URL="https://github.com/microg/GmsCore/releases/download/v0.3.16.252432/com.android.vending-84022632.apk"
AURORA_URLS=(
  "https://gitlab.com/AuroraOSS/AuroraStore/uploads/3376fef895820893ddeb7154b056a07e/AuroraStore-preload-4.8.4.apk"
  "https://github.com/AuroraOSS/AuroraStore/releases/download/4.8.4/AuroraStore_4.8.4.apk"
)

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31mBLAD:\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

# ---------- 0) zaleznosci ----------
say "Sprawdzam zaleznosci"
command -v python3 >/dev/null || die "brak python3"
command -v curl    >/dev/null || die "brak curl"
command -v unzip   >/dev/null || die "brak unzip"
command -v debugfs >/dev/null || die "brak debugfs (sudo apt-get install e2fsprogs)"
python3 -c "import sys; sys.exit(0 if sys.version_info >= (3,7) else 1)" || die "python3 >= 3.7 wymagany"
AV=$(( $(df --output=avail -B1G "$KDIR" | tail -1) ))
[ "$AV" -ge 20 ] || die "za malo miejsca: ${AV}G < 20G (zip 4,5G + partycje 7,9G + super 4,5G + zapas)"
mkdir -p "$WORK/one" "$WORK/tree" "$WORK/img" "$OUT"
cd "$WORK"
say "katalog roboczy: $WORK (dysk: ${AV}G wolne)"

# ---------- 1) baza ----------
if [ ! -f base.zip ]; then
  say "Pobieram baze Lenovo z lolinet (4,4G - najdluzszy etap)"
  curl -fL --retry 5 -C - --connect-timeout 30 \
    --speed-limit 100000 --speed-time 300 -o base.zip "$LOLINET_ZIP_URL" \
    || die "pobieranie lolinet padlo (sprawdz internet / sprobuj ponownie - wznowi od polowy)"
fi
BSZ=$(stat -c%s base.zip)
say "base.zip: $BSZ B"
[ "$(( BSZ > LOLINET_SIZE ? BSZ - LOLINET_SIZE : LOLINET_SIZE - BSZ ))" -lt 10000000 ] \
  || die "rozmiar base.zip odbiega od pinu ($BSZ vs $LOLINET_SIZE) - pobrano uszkodzone? skasuj base.zip i sprobuj ponownie"
unzip -l base.zip | grep -q "${BASE_ENTRY_PREFIX}/super.img" || die "w zipie nie ma image/super.img"

# ---------- funkcje pipeline ----------
purge_gms() { # $1=tree; stdout = liczba usunietych
  local T="$1" N=0 D
  local HITS
  HITS=$(find "$T/app" "$T/priv-app" -maxdepth 1 -type d 2>/dev/null | grep -iE \
    'gms|google|Phonesky|SetupWizard|PrebuiltGmsCore|GoogleServicesFramework|GooglePartnerSetup|GoogleFeedback|GoogleOneTimeInitializer|GoogleRestore|ConfigUpdater|CarrierServices|AndroidPlatformServices|GoogleExt' || true)
  [ -n "$HITS" ] && printf '%s\n' "$HITS" >&2
  for D in $HITS; do
    case "$(basename "$D")" in
      com.google.android.webview|WebView) echo "  ZOSTAWIAM (webview): $(basename "$D")" >&2; continue ;;
    esac
    rm -rf "$D"; N=$((N+1))
  done
  find "$T/etc/permissions" "$T/etc/sysconfig" -name '*.xml' 2>/dev/null | \
    xargs -r grep -il 'gms\|google' | xargs -r rm -f || true
  echo "$N"
}

fs_type() { # $1=img -> "erofs"|"ext4"|"?"
  python3 - "$1" <<'FSEOF'
import struct, sys
with open(sys.argv[1], "rb") as f:
    f.seek(1024); sb = f.read(64)
if len(sb) >= 58 and struct.unpack("<H", sb[56:58])[0] == 0xEF53:
    print("ext4"); raise SystemExit
if len(sb) >= 4 and struct.unpack("<I", sb[0:4])[0] == 0xE0F5E1E2:
    print("erofs"); raise SystemExit
print("?")
FSEOF
}

stream_parts() { # $1=csv partycji -> $WORK/one/*.img (+ weryfikacja pinow)
  rm -f "$WORK"/one/*.img 2>/dev/null || true
  unzip -p base.zip "${BASE_ENTRY_PREFIX}/super.img" \
    | python3 "$KDIR/tools/simg2img_stream.py" \
    | python3 "$KDIR/tools/stream_lpunpack.py" --stdin --out "$WORK/one" --only "$1" \
    | tee "$WORK/stream-manifest.txt"
  local P PINVAR PINV AWKRC
  for P in $(echo "$1" | tr ',' ' '); do
    PINVAR="SIZE_$(echo "$P" | tr 'a-z' 'A-Z')"
    PINV=$(eval "echo \${$PINVAR:-0}")
    awk -F'\t' -v p="$P" -v pin="$PINV" \
      '$1=="P" && $2==p { if (pin>0 && $3!=pin) { print "BLAD: "p" rozmiar "$3" != pin "pin; bad=1 } f=1 } END { exit (bad?1:(f?0:2)) }' \
      "$WORK/stream-manifest.txt"
    AWKRC=$?
    [ "$AWKRC" -eq 1 ] && die "$P: rozmiar odbiega od pinu (inna wersja bazy?)"
    [ "$AWKRC" -eq 2 ] && die "$P nie ma w manifeście streamu"
    awk -F'\t' -v p="$P" '$1=="W" && $2==p && $5!="OK" && $5!="SKIP" { bad=1 } END { exit bad?1:0 }' \
      "$WORK/stream-manifest.txt" || die "$P NIEPELNY w streamie"
    echo "  pin OK: $P"
  done
}

extract_tree() { # $1=part: one/$1.img -> tree/$1
  local IMG="$WORK/one/$1.img" FST
  FST=$(fs_type "$IMG")
  echo "  $1: fs=$FST"
  rm -rf "$WORK/tree/$1"; mkdir -p "$WORK/tree/$1"
  if [ "$FST" = "erofs" ]; then
    "$KDIR/bin/fsck.erofs" --extract="$WORK/tree/$1" "$IMG" >/dev/null 2>&1 \
      || die "$1: fsck.erofs extract padl"
    [ -d "$WORK/tree/$1/$1" ] && { mv "$WORK/tree/$1/$1" "$WORK/tree/${1}_i"; rm -rf "$WORK/tree/$1"; mv "$WORK/tree/${1}_i" "$WORK/tree/$1"; }
  elif [ "$FST" = "ext4" ]; then
    debugfs -R "rdump / $WORK/tree/$1" "$IMG" >/dev/null 2>&1 || die "$1: debugfs rdump padl"
    if [ ! -d "$WORK/tree/$1/app" ] && [ ! -d "$WORK/tree/$1/priv-app" ]; then
      local INNER
      INNER=$(find "$WORK/tree/$1" -maxdepth 2 -type d -name app | head -1)
      [ -n "$INNER" ] || die "$1: rdump bez /app"
      INNER=$(dirname "$INNER")
      mv "$INNER" "$WORK/tree/${1}_i"; rm -rf "$WORK/tree/$1"; mv "$WORK/tree/${1}_i" "$WORK/tree/$1"
    fi
  else
    die "$1: nieznany fs (magic?)"
  fi
  rm -f "$IMG"
}

# ---------- 2) SYSTEM ----------
say "SYSTEM: stream + PURGE GMS + INJECT microG"
stream_parts system
extract_tree system
T="$WORK/tree/system"
[ -d "$T/app" ] || die "system: drzewo bez /app"
N=$(purge_gms "$T"); echo "system: USUNIETO $N katalogow Google"
curl -fsSL --retry 5 -o "$WORK/gmscore.apk" "$GMS_APK_URL"   || die "nie pobral sie microG GmsCore"
curl -fsSL --retry 5 -o "$WORK/fakestore.apk" "$VENDING_APK_URL" || die "nie pobral sie FakeStore"
AURORA=""
for U in "${AURORA_URLS[@]}"; do
  if curl -fsI --connect-timeout 20 "$U" >/dev/null 2>&1; then AURORA="$U"; break; fi
done
mkdir -p "$T/priv-app/microG" "$T/priv-app/FakeStore"
cp "$WORK/gmscore.apk"   "$T/priv-app/microG/GmsCore.apk"
cp "$WORK/fakestore.apk" "$T/priv-app/FakeStore/FakeStore.apk"
AURORA_STATUS="skipped"
if [ -n "$AURORA" ]; then
  if curl -fsSL --retry 3 -o "$WORK/aurora.apk" "$AURORA"; then
    mkdir -p "$T/app/AuroraStore"
    cp "$WORK/aurora.apk" "$T/app/AuroraStore/AuroraStore.apk"
    AURORA_STATUS="present"; echo "Aurora: wstrzyknieta"
  fi
else
  echo "UWAGA: AuroraStore niedostepna - build bez niej (doinstaluj z auroraoss.com)"
fi
cat > "$T/etc/permissions/privapp-permissions-mystical.xml" <<'XEOF'
<?xml version="1.0" encoding="utf-8"?>
<permissions>
  <privapp-permissions package="com.google.android.gms">
    <permission name="android.permission.FAKE_PACKAGE_SIGNATURE"/>
    <permission name="android.permission.INSTALL_LOCATION_PROVIDER"/>
    <permission name="android.permission.UPDATE_DEVICE_STATS"/>
    <permission name="android.permission.UPDATE_APP_OPS_STATS"/>
    <permission name="android.permission.CHANGE_DEVICE_IDLE_TEMP_WHITELIST"/>
    <permission name="android.permission.MANAGE_USB"/>
    <permission name="android.permission.MODIFY_PHONE_STATE"/>
    <permission name="android.permission.FOREGROUND_SERVICE"/>
    <permission name="android.permission.LOCAL_MAC_ADDRESS"/>
    <permission name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
  </privapp-permissions>
  <privapp-permissions package="com.android.vending">
    <permission name="android.permission.FAKE_PACKAGE_SIGNATURE"/>
  </privapp-permissions>
</permissions>
XEOF
BP="$T/build.prop"
{ echo ""
  echo "# === MysticalOS 3 ==="
  echo "ro.mysticalos.version=3"
  echo "ro.mysticalos.base=${BASE_BUILD}"
  echo "ro.surface_flinger.use_content_detection_for_refresh_rate=false"; } >> "$BP"
FC="$T/etc/selinux/plat_file_contexts"
[ -f "$FC" ] || die "brak plat_file_contexts w systemie"
say "mkfs system (EROFS + konteksty SELinux)"
"$KDIR/bin/mkfs.erofs" -zlz4 -T 0 -U 6d797374-6963-4000-8000-616c00000003 \
  --file-contexts="$FC" "$WORK/img/system.img" "$T" >/dev/null \
  || die "mkfs system padl"
cp "$FC" "$WORK/plat_file_contexts"
rm -rf "$T"
# weryfikacja obrazu systemu
rm -rf "$WORK/imgcheck"; mkdir -p "$WORK/imgcheck"
"$KDIR/bin/fsck.erofs" --extract="$WORK/imgcheck" "$WORK/img/system.img" >/dev/null 2>&1 || die "fsck.erofs extract system_m3 padl"
C="$WORK/imgcheck"; [ -d "$WORK/imgcheck/system" ] && C="$WORK/imgcheck/system"
for CHK in "priv-app/microG/GmsCore.apk" "priv-app/FakeStore/FakeStore.apk" "etc/permissions/privapp-permissions-mystical.xml" "build.prop"; do
  [ -f "$C/$CHK" ] || die "imgcheck: BRAK $CHK"
done
grep -q "mysticalos.version=3" "$C/build.prop" || die "imgcheck: brak mysticalos.version=3"
[ "$AURORA_STATUS" = "present" ] && { [ -f "$C/app/AuroraStore/AuroraStore.apk" ] || die "imgcheck: brak Aurora"; }
echo "  system_m3: $(stat -c%s "$WORK/img/system.img") B (baza ${SIZE_SYSTEM}); weryfikacja OK"
rm -rf "$WORK/imgcheck"

# ---------- 3) PRODUCT + SYSTEM_EXT ----------
for P in product system_ext; do
  say "${P^^}: stream + PURGE GMS"
  stream_parts "$P"
  extract_tree "$P"
  TT="$WORK/tree/$P"
  if [ -d "$TT/app" ] || [ -d "$TT/priv-app" ]; then
    M=$(purge_gms "$TT")
    if [ "$M" -gt 0 ]; then
      echo "$P: usunieto $M -> repack"
      DF="$TT/etc/selinux/${P}_file_contexts"
      [ -f "$DF" ] || DF="$WORK/plat_file_contexts"
      [ -f "$DF" ] || die "$P: brak kontekstow"
      U2=13; [ "$P" = "system_ext" ] && U2=23
      "$KDIR/bin/mkfs.erofs" -zlz4 -T 0 -U "6d797374-6963-4000-8000-616c000000$U2" \
        --file-contexts="$DF" "$WORK/img/$P.img" "$TT" >/dev/null || die "mkfs $P padl"
      echo "  ${P}_m3: $(stat -c%s "$WORK/img/$P.img") B (baza $(eval echo \$SIZE_$(echo $P | tr 'a-z' 'A-Z')))"
    else
      echo "$P: brak pakietow Google - oryginal"
      stream_parts "$P"; mv "$WORK/one/$P.img" "$WORK/img/$P.img"
    fi
  else
    echo "$P: drzewo bez /app - oryginal"
    mv "$WORK/one/$P.img" "$WORK/img/$P.img"
  fi
  rm -rf "$TT"
done

# ---------- 4) VENDOR* (bez modyfikacji) + boot ----------
say "VENDOR/VENDOR_DLKM/ODM_DLKM + boot.img"
stream_parts "vendor,vendor_dlkm,odm_dlkm"
for P in vendor vendor_dlkm odm_dlkm; do mv "$WORK/one/$P.img" "$WORK/img/$P.img"; done
unzip -p base.zip "${BASE_ENTRY_PREFIX}/boot.img" > "$OUT/boot_${BASE_BUILD}.img"
B=$(stat -c%s "$OUT/boot_${BASE_BUILD}.img")
[ "$B" = "$LOLINET_BOOT_LEN" ] || die "boot.img $B != pin $LOLINET_BOOT_LEN"

# ---------- 5) super.img (lpmake -S, fabryczna geometria) ----------
say "super.img: lpmake -S (geometria fabryczna ${SUPER_SIZE} B, slot A)"
TOTAL=0; ARGS=()
for P in system system_ext product vendor vendor_dlkm odm_dlkm; do
  [ -s "$WORK/img/$P.img" ] || continue
  SZ=$(stat -c%s "$WORK/img/$P.img")
  SZR=$(( (SZ + 4095) / 4096 * 4096 ))
  TOTAL=$(( TOTAL + SZR ))
  ARGS+=(--partition="${P}_a:readonly:$SZR:main_a" --image="${P}_a=$WORK/img/$P.img")
  echo "  ${P}_a: $SZ B"
done
echo "  SUMA: $TOTAL / $MAIN_GROUP_SIZE"
[ "$TOTAL" -le "$MAIN_GROUP_SIZE" ] || die "obrazy nie mieszcza sie w main_a!"
"$KDIR/bin/lpmake" \
  --device-size="$SUPER_SIZE" --metadata-size=65536 --metadata-slots=3 \
  --block-size=4096 --alignment=1048576 --super-name=super -S \
  --group="main_a:$MAIN_GROUP_SIZE" "${ARGS[@]}" \
  -o "$OUT/super_mystical3.img" || die "lpmake padl"
echo "  super_mystical3.img: $(stat -c%s "$OUT/super_mystical3.img") B (sparse)"

# weryfikacja geometrii zbudowanego super (glowa sparse -> lpinfo)
python3 - "$OUT/super_mystical3.img" "$WORK/super_head.img" <<'PYEOF'
import struct, sys
src, dst = sys.argv[1], sys.argv[2]
f = open(src, 'rb')
hdr = f.read(28)
magic, maj, mnr, fhs, chs, blk, nblk, nch, ck = struct.unpack('<IHHHHIIII', hdr)
assert magic == 0xED26FF3A, f"bad sparse magic {magic:#x}"
HEAD = 4 * 1024 * 1024
out = bytearray(HEAD)
pos = 0
for _ in range(nch):
    ch = f.read(12)
    ct, res, n, total = struct.unpack('<HHII', ch)
    if ct == 0xCAC1:
        data = f.read(total)
        for i in range(n):
            o = i * blk
            if pos + o < HEAD:
                end = min(pos + o + blk, HEAD)
                out[pos + o:end] = data[o:o + (end - pos - o)]
    elif ct == 0xCAC2:
        fill = f.read(4)
        for i in range(n):
            o = i * blk
            if pos + o < HEAD:
                end = min(pos + o + blk, HEAD)
                out[pos + o:end] = (fill * blk)[:end - pos - o]
    else:
        if ct != 0xCAC3:
            f.seek(total, 1)
    pos += n * blk
open(dst, 'wb').write(out)
print(f"  glowa sparse: {nch} chunkow, device {nblk*blk} B")
PYEOF
python3 "$KDIR/tools/lpinfo.py" "$WORK/super_head.img" | tee "$WORK/super-built-geometry.txt"
grep -q "size=9663676416" "$WORK/super-built-geometry.txt" || die "geometria zbudowanego super niezgodna"
grep -q "system_a" "$WORK/super-built-geometry.txt" || die "brak system_a w super"
say "GEOMETRIA super: ZWERYFIKOWANA"

# ---------- 6) vbmeta_disable x3 ----------
say "vbmeta_disable (flags=3 = disable verification) x3"
# avbtool 1.3.0: --output (bez -o); potem pad do rozmiaru partycji
python3 "$KDIR/tools/avbtool.py" make_vbmeta_image --flags 3 --output "$OUT/vbmeta_disable.img"
truncate -s 8192 "$OUT/vbmeta_disable.img"
python3 "$KDIR/tools/avbtool.py" info_image --image "$OUT/vbmeta_disable.img" | grep -q "Flags:                    3" \
  || die "vbmeta_disable: flags != 3"
cp "$OUT/vbmeta_disable.img" "$OUT/vbmeta_system_disable.img"; truncate -s 4096 "$OUT/vbmeta_system_disable.img"
cp "$OUT/vbmeta_disable.img" "$OUT/vbmeta_vendor_disable.img"; truncate -s 4096 "$OUT/vbmeta_vendor_disable.img"

# ---------- 7) final ----------
cp "$KDIR/FLASH-M3.md" "$OUT/"
cp "$KDIR/tools/simg2img.py" "$KDIR/tools/simg2img_stream.py" "$OUT/" 2>/dev/null || true
cd "$OUT"
sha256sum super_mystical3.img vbmeta_disable.img vbmeta_system_disable.img vbmeta_vendor_disable.img "boot_${BASE_BUILD}.img" FLASH-M3.md > SHA256SUMS.txt
rm -f "$WORK/super_head.img" "$WORK"/one/*.img 2>/dev/null || true
say "GOTOWE: $OUT"
echo ""
echo "  super_mystical3.img          $(stat -c%s super_mystical3.img) B (sparse; fastbootd przyjmie wprost)"
echo "  vbmeta_disable.img + _system_ + _vendor_   (flashujemy 3x przed super)"
echo "  boot_${BASE_BUILD}.img       (rollback jesli bootloop)"
echo ""
echo "  Nastepny krok: FLASH-M3.md (fastbootd: vbmeta x3 -> super -> set-active=a)"
