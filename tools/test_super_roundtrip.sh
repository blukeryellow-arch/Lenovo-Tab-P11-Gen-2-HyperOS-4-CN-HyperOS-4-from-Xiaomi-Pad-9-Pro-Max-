#!/usr/bin/env bash
# test_super_roundtrip.sh - pelny test lokalny narzedzi streamingowych m3.
# Buduje mini-super (lpmake AOSP), potem:
#   1) stream_lpunpack --file / --stdin / --only  ==  lpunpack AOSP (cmp)
#   2) super_patch.py (wlasne metadane + sparse on-the-fly) -> parts ->
#      cat -> simg2img -> lpunpack AOSP (cmp obrazow + checksumy liblp!)
# Uzycie: test_super_roundtrip.sh [katalog-roboczy]
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
T=${1:-/tmp/srt}; rm -rf "$T"; mkdir -p "$T"; cd "$T"

echo "== toolchain lp (codeload) =="
curl -fsSL --max-time 120 "https://codeload.github.com/Rprop/aosp15_partition_tools/tar.gz/refs/heads/main" | tar -xz
LPT=$(ls -d aosp15_partition_tools-*/linux_glibc_x86_64 | head -1); chmod +x "$LPT"/*

echo "== fixture: 3 partycje z przerwami =="
mkdir -p src
head -c 3145728 /dev/urandom > src/system.img
head -c 1572864 /dev/urandom > src/product.img
head -c 7340032 /dev/urandom > src/vendor.img
"$LPT/lpmake" --device-size=20971520 --metadata-size=65536 --metadata-slots=3 \
  --block-size=4096 --alignment=1048576 --super-name=super \
  --group=main_a:18874368 \
  --partition=system_a:readonly:3145728:main_a --image=system_a=src/system.img \
  --partition=product_a:readonly:1572864:main_a --image=product_a=src/product.img \
  --partition=vendor_a:readonly:7340032:main_a --image=vendor_a=src/vendor.img \
  -o super_base.img 2>/dev/null
mkdir -p ref && "$LPT/lpunpack" super_base.img ref/ >/dev/null 2>&1

echo "== 1a) stream_lpunpack --file =="
python3 "$REPO/tools/stream_lpunpack.py" --file super_base.img --out o1 >/dev/null
for P in system product vendor; do cmp "ref/${P}_a.img" "o1/$P.img"; done && echo "OK: --file IDENTYCZNE"

echo "== 1b) --stdin =="
python3 "$REPO/tools/stream_lpunpack.py" --stdin --out o2 --head head.bin < super_base.img >/dev/null
for P in system product vendor; do cmp "ref/${P}_a.img" "o2/$P.img"; done && echo "OK: --stdin IDENTYCZNE"

echo "== 1c) --only (per-partycja, osobne przebiegi) =="
for P in system product vendor; do
  rm -rf "oo_$P"
  python3 "$REPO/tools/stream_lpunpack.py" --file super_base.img --out "oo_$P" --only "$P" >/dev/null
  cmp "ref/${P}_a.img" "oo_$P/$P.img"
done && echo "OK: --only IDENTYCZNE"

echo "== 1d) metadane z glowy (lpinfo) =="
python3 "$REPO/tools/lpinfo.py" head.bin | grep -q "main_a" && echo "OK: lpinfo na glowie"

echo "== 2) super_patch: symulacja m3 (mniejsze obrazy system/product) =="
head -c 2097152 src/system.img  > m3_system.img       # "po purge" 2M
head -c 1048576 src/product.img > m3_product.img      # "po purge" 1M
cp src/vendor.img m3_vendor.img                        # unmod
mkdir -p parts kit
python3 "$REPO/tools/super_patch.py" --head head.bin --device-size 20971520 --keep \
  --img system=m3_system.img --img product=m3_product.img --img vendor=m3_vendor.img \
  --out-dir parts --parts 4 --prefix p. 2> patch.log
awk -F'\t' '$1=="S"{print $3"  "$2}' patch.log > parts.sha
cat parts.sha
NP=$(ls parts/p.* | wc -l); echo "czastek: $NP (cel: <=4)"
[ "$NP" -le 4 ] || { echo "ZA DUZO CZASTEK"; exit 1; }
(cd parts && sha256sum -c ../parts.sha | head -4)
cat parts/p.* > super_m3_sparse.img
python3 "$REPO/tools/simg2img.py" super_m3_sparse.img super_m3_raw.img
python3 "$REPO/tools/lpinfo.py" super_m3_raw.img | tee lpinfo-m3.txt
grep -q "size=20971520" lpinfo-m3.txt
"$LPT/lpunpack" super_m3_raw.img refm3/ >/dev/null 2>&1 || { mkdir -p refm3; "$LPT/lpunpack" super_m3_raw.img refm3/ >/dev/null 2>&1; }
cmp m3_system.img  refm3/system_a.img  && echo "OK: system_a w nowym super IDENTYCZNY"
cmp m3_product.img refm3/product_a.img && echo "OK: product_a IDENTYCZNY"
cmp m3_vendor.img  refm3/vendor_a.img  && echo "OK: vendor_a IDENTYCZNY"
echo ""
echo "WSZYSTKIE TESTY ROUNDTRIP: PASS"
