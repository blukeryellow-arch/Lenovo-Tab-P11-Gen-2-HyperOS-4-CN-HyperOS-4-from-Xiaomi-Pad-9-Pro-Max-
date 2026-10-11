#!/usr/bin/env bash
# ============================================================================
# MYSTICALOS LOCAL EMU - lokalny klon harnessu emuboot (CI) na Twoim PC/WSL2
# Dokladnie te same kroki co workflow v2.22 (udowodnione w CI):
#   vendor-mod (debugfs) -> ramdisk fstab -> fix obrazu (property_contexts,
#   zygote rc, /data rc) -> super 4-partycyjny (mksuper.py) -> qemu TCG
#   + LIVE statusy bootu (fatal/loops/zyg/data/bc) i adb na porcie 5555
# Uzycie (w WSL2/Linux):
#   bash run-local-emu.sh /sciezka/do/MysticalOS_0.5_DSU_nofooter.img
# ============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$HERE/../tools"
WORK="$HERE/emu-work"
SYSIMG_ZIP="${SYSIMG_ZIP:-}"          # opcjonalnie: wlasny zip system-image
SDKDIR_CANDIDATES=(
  "$HOME/Android/Sdk"
  "/mnt/c/Users/$USER/AppData/Local/Android/Sdk"
  "/mnt/c/Users/*/AppData/Local/Android/Sdk"
)
API=33
TAG=google_apis
ABI=arm64-v8a
PORT=5555

say() { echo -e "\e[1;32m== $*\e[0m"; }
die() { echo -e "\e[1;31m!! $*\e[0m" >&2; exit 1; }

IMG="${1:-}"
[ -z "$IMG" ] && die "Podaj sciezke do obrazu, np.: bash run-local-emu.sh ~/Downloads/MysticalOS_0.5_DSU_nofooter.img"
[ -f "$IMG" ] || die "Nie ma pliku: $IMG"
IMG="$(readlink -f "$IMG")"

# ---- 0. zaleznosci ----------------------------------------------------------
MISSING=""
for c in qemu-system-aarch64 cpio sfdisk debugfs mkfs.ext4 python3 adb gzip lz4; do
  command -v "$c" >/dev/null 2>&1 || MISSING="$MISSING $c"
done
if [ -n "$MISSING" ]; then
  say "Brakuje:$MISSING"
  echo "Zainstaluj i uruchom ponownie:"
  echo "  sudo apt-get update && sudo apt-get install -y qemu-system-arm cpio fdisk e2fsprogs adb lz4"
  exit 1
fi
# miejsce: pelny dysk = cicha czesciowa ekstrakcja ramdisku / ENOSPC przy super
AVAIL_KB=$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2{print $4}')
if [ -n "$AVAIL_KB" ] && [ "$AVAIL_KB" -lt 10000000 ]; then
  die "Za malo miejsca na dysku WSL (potrzeba ~10 GB wolnego, jest $((AVAIL_KB/1024/1024)) GB). Sprzatnij i sprobuj ponownie."
fi

mkdir -p "$WORK"
cd "$WORK"

# ---- 1. kernel + ramdisk + vendor emulatora ---------------------------------
SYSIMG=""
for d in "${SDKDIR_CANDIDATES[@]}"; do
  [ -d "$d" ] || continue
  found=$(ls -d "$d"/system-images/android-$API/*/$ABI 2>/dev/null | head -1)
  [ -n "$found" ] && SYSIMG="$found" && break
done
if [ -z "$SYSIMG" ]; then
  say "Nie znalazlem system-image android-$API $TAG $ABI - probuje sdkmanager"
  SDKM=""
  for d in "${SDKDIR_CANDIDATES[@]}"; do
    for p in "$d"/cmdline-tools/latest/bin/sdkmanager "$d"/cmdline-tools/*/bin/sdkmanager; do
      [ -x "$p" ] && SDKM="$p" && break 2
    done
  done
  [ -z "$SDKM" ] && command -v sdkmanager >/dev/null 2>&1 && SDKM="$(command -v sdkmanager)"
  if [ -n "$SDKM" ]; then
    yes | "$SDKM" --licenses >/dev/null 2>&1
    "$SDKM" "system-images;android-$API;$TAG;$ABI" || true
    for d in "${SDKDIR_CANDIDATES[@]}"; do
      found=$(ls -d "$d"/system-images/android-$API/*/$ABI 2>/dev/null | head -1)
      [ -n "$found" ] && SYSIMG="$found" && break
    done
  fi
fi
if [ -z "$SYSIMG" ] && [ -n "$SYSIMG_ZIP" ] && [ -f "$SYSIMG_ZIP" ]; then
  say "Rozpakowuje $SYSIMG_ZIP"
  unzip -q -o "$SYSIMG_ZIP" -d "$WORK/sysimg-zip"
  SYSIMG=$(find "$WORK/sysimg-zip" -type d -name "$ABI" | head -1)
fi
[ -z "$SYSIMG" ] && die "Nie moge zdobyc system-image. Otworz Android Studio ->
  More Actions -> SDK Manager -> SDK Platforms -> Android 13 (33), zaznacz
  'Google APIs ARM 64 v8a System Image' -> OK, potem uruchom skrypt ponownie."
say "system-image: $SYSIMG"
KERNEL="$SYSIMG/kernel-ranchu"
RAMDISK="$SYSIMG/ramdisk.img"
VENDORIMG="$SYSIMG/vendor.img"
for f in "$KERNEL" "$RAMDISK" "$VENDORIMG"; do
  [ -f "$f" ] || die "brak $f w system-image (uszkodzony instalator?)"
done

# ---- 2. vendor-mod: bez vendor_property_contexts i fstab.ranchu -------------
cp -f "$VENDORIMG" "$WORK/vendor-mod.img"
VNDSTART=$(sfdisk -d "$WORK/vendor-mod.img" 2>/dev/null | grep -o 'start= *[0-9]*' | head -1 | grep -o '[0-9]*')
VNDSIZE=$(sfdisk -d "$WORK/vendor-mod.img" 2>/dev/null | grep -o 'size= *[0-9]*' | head -1 | grep -o '[0-9]*')
[ -n "$VNDSTART" ] && [ -n "$VNDSIZE" ] || die "nie moge sparsowac partycji vendor"
dd if="$WORK/vendor-mod.img" of="$WORK/vendor-part.img" bs=512 skip="$VNDSTART" count="$VNDSIZE" status=none
debugfs -R "cat /etc/selinux/vendor_sepolicy.cil" "$WORK/vendor-part.img" > "$WORK/vendor_sepolicy.cil" 2>/dev/null
debugfs -w -R "rm /etc/selinux/vendor_property_contexts" "$WORK/vendor-part.img" >/dev/null 2>&1
debugfs -w -R "rm /etc/fstab.ranchu" "$WORK/vendor-part.img" >/dev/null 2>&1
dd if="$WORK/vendor-part.img" of="$WORK/vendor-mod.img" bs=512 seek="$VNDSTART" count="$VNDSIZE" conv=notrunc status=none
say "vendor-mod OK (vendor_property_contexts + fstab.ranchu usuniete)"

# ---- 3. ramdisk-mod: nasz fstab ---------------------------------------------
# ANDROID RAMDISK = KILKA SKLEJONYCH archiwow cpio! GNU cpio -i czyta TYLKO
# PIERWSZE (do TRAILER!!!) i cicho gubi reszte - w tym /lib/modules -> kernel
# bez virtio -> petla bootloader. Dlatego jak w CI (workflow v2.x, forensyka):
# cpio_multi_extract.py czyta WSZYSTKIE sklejone archiwa.
# (run lokalny 2026-10-11: wlasnie ten bug - bylo init+build.prop, modulow nie)
if gzip -t "$RAMDISK" 2>/dev/null; then DEC="gzip -dc"; else DEC="lz4 -dc"; fi
RDERR="$WORK/ramdisk-extract.log"; : > "$RDERR"
$DEC "$RAMDISK" > "$WORK/rd.cpio" 2>>"$RDERR"
rm -rf "$WORK/rd-all"; mkdir -p "$WORK/rd-all/first_stage_ramdisk"
python3 "$TOOLS/cpio_multi_extract.py" "$WORK/rd.cpio" "$WORK/rd-all" >>"$RDERR" 2>&1
say "ramdisk: rozpakowano $(find "$WORK/rd-all" -type f | wc -l) plikow (dekompresor: $DEC; log: $RDERR)"
if [ ! -d "$WORK/rd-all/lib/modules" ]; then
  { echo "--- pierwsze 4 bajty $RAMDISK:"; head -c 4 "$RAMDISK" | od -An -tx1; echo "--- df:"; df -h "$WORK"; } >> "$RDERR" 2>&1
  die "ramdisk bez /lib/modules - kernel NIE ZOBACZY dyskow (petla bootloader). Podeslij mi: $RDERR"
fi
# fstab 1:1 z CI v2.22 (workflow emuboot.yml): TYLKO system logical; vendor
# fizycznie przez by-name (vdc); product/system_ext NIE montujemy w first stage
# (w super sa to 16MB placeholdery - zawartosc siedzi w obrazie systemu).
# UWAGA: vendor/product/system_ext jako "logical" wiesza first-stage init
# ("Failed to mount required partitions early" -> reboot bootloader co ~16s).
cat > "$WORK/rd-all/first_stage_ramdisk/fstab.ranchu" <<'EOF'
system   /system     ext4    ro,barrier=1     wait,logical,first_stage_mount
/dev/block/platform/a003c00.virtio_mmio/by-name/vendor    /vendor    ext4    ro,barrier=1    wait,first_stage_mount
/dev/block/vda   /metadata   ext4   noatime,nosuid,nodev   wait,formattable,first_stage_mount
/dev/block/vdb   /data     ext4      noatime,nosuid,nodev,nomblk_io_submit,errors=panic   wait,check,quota,fileencryption=aes-256-xts:aes-256-cts,reservedsize=128M,fsverity,keydirectory=/metadata/vold/metadata_encryption,latemount
/dev/block/zram0 none swap  defaults zramsize=75%
EOF
( cd "$WORK/rd-all" && find . -print0 | cpio -0 -o -H newc -R 0:0 2>>"$RDERR" | gzip -1 > "$WORK/ramdisk-mod.img" )
# twarda weryfikacja koncowka-do-konca: spakowany ramdisk MUSI miec moduly virtio
if ! gzip -dc "$WORK/ramdisk-mod.img" 2>/dev/null | cpio -t 2>/dev/null | grep -q "lib/modules/virtio_blk"; then
  die "WERYFIKACJA: ramdisk-mod.img nie zawiera lib/modules/virtio_blk - nie bootnie. Log: $RDERR"
fi
say "ramdisk-mod OK (fstab 1:1 z CI + /lib/modules z modulami virtio zweryfikowane)"

# ---- 4. fix obrazu (kopia robocza!) -----------------------------------------
say "Kopiuje obraz do emu-work/our.img (oryginal nietkniety)"
cp -f "$IMG" "$WORK/our.img" || die "kopia obrazu nie wyszla (miejsce na dysku? uprawnienia?)"
sudo mkdir -p /tmp/myst-emu-mnt
sudo mount -o rw,loop "$WORK/our.img" /tmp/myst-emu-mnt || die "montowanie rw nie wyszlo"
for D in /system/etc/selinux /system/system_ext/etc/selinux /system/product/etc/selinux; do
  [ -d "/tmp/myst-emu-mnt$D" ] || continue
  sudo python3 "$TOOLS/propctx.py" fix "/tmp/myst-emu-mnt$D" \
    --extra-cil "$WORK/vendor_sepolicy.cil" || true
done
sudo mkdir -p /tmp/myst-emu-mnt/system/etc/init/hw
sudo cp "$TOOLS/init.zygote64.rc" /tmp/myst-emu-mnt/system/etc/init/hw/init.zygote64.rc
sudo cp "$TOOLS/zz-mystical-data.rc" /tmp/myst-emu-mnt/system/etc/init/zz-mystical-data.rc
sudo grep -q "^ro.zygote=" /tmp/myst-emu-mnt/system/build.prop \
  || sudo sh -c 'printf "\nro.zygote=zygote64\n" >> /tmp/myst-emu-mnt/system/build.prop'
sudo umount /tmp/myst-emu-mnt
say "fix obrazu OK (property_contexts + zygote + /data rc)"

# ---- 5. super 4-partycyjny + GPT --------------------------------------------
for P in product system_ext; do
  [ -s "$WORK/empty-$P.img" ] && continue
  truncate -s 16M "$WORK/empty-$P.img" && mkfs.ext4 -q -F "$WORK/empty-$P.img"
done
python3 "$TOOLS/mksuper.py" "$WORK/super-raw.img" \
  system="$WORK/our.img" vendor="$WORK/vendor-part.img" \
  product="$WORK/empty-product.img" system_ext="$WORK/empty-system_ext.img" \
  || die "mksuper.py padl - super-raw niepowstaly, nie idziemy dalej"
# oszczednosc miejsca: system siedzi juz w super-raw, our.img niepotrzebny (-3.4G)
rm -f "$WORK/our.img"
truncate -s 1M "$WORK/super-gpt.img"
cat "$WORK/super-raw.img" >> "$WORK/super-gpt.img" || die "sklejanie super-gpt padlo"
truncate -s +2M "$WORK/super-gpt.img"
SECT=$(( $(stat -c%s "$WORK/super-raw.img") / 512 ))
printf 'label: gpt\nstart=2048, size=%s, name=super\n' "$SECT" | sfdisk "$WORK/super-gpt.img" >/dev/null 2>&1
sfdisk -d "$WORK/super-gpt.img" 2>/dev/null | grep -q "name= super" || die "GPT super nie zapisany"
# oszczednosc miejsca: super-raw skopiowany do super-gpt, wiecej niepotrzebny (-3.2G)
rm -f "$WORK/super-raw.img"
say "super.img OK ($(numfmt --to=iec $(stat -c%s "$WORK/super-gpt.img")))"

# ---- 6. metadata + userdata --------------------------------------------------
[ -s "$WORK/meta.img" ] || { truncate -s 128M "$WORK/meta.img"; mkfs.ext4 -q -F "$WORK/meta.img"; }
[ -s "$WORK/userdata.img" ] || { truncate -s 4G "$WORK/userdata.img"; mkfs.ext4 -q -F "$WORK/userdata.img"; }

# ---- 7. QEMU + LIVE monitor --------------------------------------------------
say "Start qemu (TCG, 4 rdzenie; Ctrl-C = stop)"
qemu-system-aarch64 -M virt -cpu cortex-a76 -smp 4 -m 4096 \
  -kernel "$KERNEL" -initrd "$WORK/ramdisk-mod.img" \
  -append "console=ttyAMA0,115200 rdinit=/init androidboot.console=ttyAMA0 androidboot.hardware=ranchu androidboot.selinux=permissive audit=0 printk.devkmsg=on androidboot.adb.tcp.port=$PORT androidboot.boot_devices=a003e00.virtio_mmio,a003c00.virtio_mmio,a003a00.virtio_mmio,a003800.virtio_mmio" \
  -drive if=none,file="$WORK/super-gpt.img",format=raw,id=super \
  -device virtio-blk-device,drive=super \
  -drive if=none,file="$WORK/vendor-mod.img",format=raw,id=vendor \
  -device virtio-blk-device,drive=vendor \
  -drive if=none,file="$WORK/userdata.img",format=raw,id=userdata \
  -device virtio-blk-device,drive=userdata \
  -drive if=none,file="$WORK/meta.img",format=raw,id=meta \
  -device virtio-blk-device,drive=meta \
  -netdev user,id=n0,hostfwd=tcp::5555-:5555 \
  -device virtio-net-device,netdev=n0 \
  -display none -monitor none -serial file:"$WORK/console.log" &
QPID=$!
# AUDYT: qemu musi umierac ze skryptem - inaczej sierota blokuje port 5555
# i kazdy nastepny run pada od razu (widziane jako "nic sie nie dzieje")
trap 'kill $QPID 2>/dev/null' EXIT
trap 'echo; echo "== stop (console: $WORK/console.log)"; exit 0' INT TERM
say "LIVE status co 15 s: fatal/loops/zyg/data/bc (bc=1 = UKONCZONY BOOT)"
i=0
while kill -0 $QPID 2>/dev/null; do
  sleep 15; i=$((i+15))
  C="$WORK/console.log"
  ST="fatal=$(grep -ac 'Failed to initialize property area' "$C" 2>/dev/null) \
loops=$(grep -ac 'Run /init' "$C" 2>/dev/null) \
zyg=$(grep -ac "starting service 'zygote'" "$C" 2>/dev/null) \
data=$(grep -acE '__mount.*target=/data|EXT4-fs \(vdb\): mounted' "$C" 2>/dev/null) \
apexd=$(grep -ac 'apexd: Activated' "$C" 2>/dev/null)"
  BC=""
  timeout 5 adb connect localhost:$PORT >/dev/null 2>&1
  if timeout 5 adb -s localhost:$PORT shell true >/dev/null 2>&1; then
    BC=$(timeout 5 adb -s localhost:$PORT shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
    ST="$ST bc='$BC'"
  fi
  echo "t=${i}s  $ST"
  [ "$BC" = "1" ] && { say "BOOT UKONCZONY! (adb -s localhost:$PORT shell)"; break; }
done
echo; say "Ostatnie 25 linii konsoli:"; tail -25 "$WORK/console.log" 2>/dev/null
wait $QPID 2>/dev/null
