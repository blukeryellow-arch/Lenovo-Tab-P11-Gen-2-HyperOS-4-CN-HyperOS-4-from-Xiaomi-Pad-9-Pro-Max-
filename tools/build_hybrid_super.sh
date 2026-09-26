#!/usr/bin/env bash
# Build a flashable dynamic-super container with Lenovo TB350FU vendor/runtime
# partitions and the exact supplied Xiaomi HyperOS system image in both slots.
#
# This is deliberately a partition-layout operation, not a transplant of the
# Lenovo framework into HyperOS. It eliminates the stock Lenovo BatteryService
# callback from the executed /system classpath while retaining the Lenovo vendor
# battery HAL and device-specific partitions.
set -Eeuo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 REPORT_PATH LENOVO_SUPER_SPARSE HYPEROS_SYSTEM_IMG OUTPUT_DIR" >&2
  exit 2
fi

report=$1
lenovo_super=$2
hyperos_system=$3
out=$4
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
lpunpack_url='https://raw.githubusercontent.com/unix3dgforce/lpunpack/c59b8f3b069c5a8aa438a049fa4a091177172434/lpunpack.py'

[[ -f $lenovo_super ]] || { echo "Missing Lenovo super: $lenovo_super" >&2; exit 2; }
[[ -f $hyperos_system ]] || { echo "Missing HyperOS system image: $hyperos_system" >&2; exit 2; }
mkdir -p "$(dirname "$report")" "$out"

on_error() {
  local rc=$?
  trap - ERR
  {
    echo
    echo '## Build failure diagnostic'
    echo
    echo "- failed command: \`$BASH_COMMAND\`"
    echo "- exit code: \`$rc\`"
    echo
    echo '```'
    find "$out" -maxdepth 2 -type f -printf '%p %s B\n' 2>/dev/null | sort || true
    echo '```'
    for log in "$out"/*.log "$out"/*.stderr; do
      [[ -s $log ]] || continue
      echo
      echo "### $(basename "$log") (tail)"
      echo '```'
      tail -80 "$log" || true
      echo '```'
    done
  } >> "$report"
  exit "$rc"
}
trap on_error ERR

{
  echo '# TB350FU HyperOS 4 CN hybrid-super build'
  echo
  echo '- system payload: exact supplied Xiaomi Pad 9 Pro Max yingtian China OS4.0.11.0.XBMCNXM based image'
  echo '- vendor/product/system_ext and dynamic metadata: exact supplied TB350FU_S231044_260105_ROW super image'
  echo '- operation: replace only logical `system_a` and `system_b` payload prefixes; no Lenovo Java code is copied into HyperOS'
  echo '- expected effect: system_server loads HyperOS BatteryService, which has no unsafe Lenovo iBatteryService callback; Lenovo vendor battery HAL remains available to the device'
  echo
  echo '## Verified inputs'
  echo '```'
  stat -c '%n %s B' "$lenovo_super" "$hyperos_system"
  md5sum "$lenovo_super"
  sha256sum "$hyperos_system"
  echo '```'
} > "$report"

# The Lenovo super image is sparse. Materialise it once on the large disposable
# runner, edit only system logical extents, then convert it back to sparse.
raw_super="$out/TB350FU_HyperOS4_CN.raw.super.img"
simg2img "$lenovo_super" "$raw_super" >"$out/simg2img-super.log" 2>&1
raw_system="$hyperos_system"
if python3 - "$hyperos_system" <<'PY' | grep -qx sparse; then
import struct, sys
with open(sys.argv[1], 'rb') as f:
    print('sparse' if f.read(4) == struct.pack('<I', 0xed26ff3a) else 'raw')
PY
  raw_system="$out/hyperos-system.raw.img"
  simg2img "$hyperos_system" "$raw_system" >"$out/simg2img-system.log" 2>&1
fi

curl --fail --location --retry 3 --connect-timeout 45 --output "$out/lpunpack.py" \
  "$lpunpack_url" 2>"$out/lpunpack.stderr"
python3 "$script_dir/inject_logical_partition.py" \
  --lpunpack "$out/lpunpack.py" \
  --super-raw "$raw_super" \
  --system-image "$raw_system" \
  --partition system_a --partition system_b >"$out/injection.log" 2>&1

final_super="$out/TB350FU_HyperOS4_CN_yingtian_4.0.11.0_XBMCNXM.super.img"
img2simg "$raw_super" "$final_super" >"$out/img2simg.log" 2>&1
[[ $(python3 - "$final_super" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as f:
    print('sparse' if f.read(4) == struct.pack('<I', 0xed26ff3a) else 'raw')
PY
) == sparse ]]

# Validate the generated super metadata and test that both injected logical
# partition prefixes still hash to the exact HyperOS input after sparse packing.
python3 "$script_dir/extract_sparse_super_partitions.py" --lpunpack "$out/lpunpack.py" --list "$final_super" \
  >"$out/final-logical-partitions.txt" 2>"$out/final-lpunpack-list.stderr"
mkdir -p "$out/verify-logical"
python3 "$script_dir/extract_sparse_super_partitions.py" --lpunpack "$out/lpunpack.py" \
  --partition system_a --partition system_b "$final_super" "$out/verify-logical" \
  >"$out/final-lpunpack-extract.log" 2>&1
source_sha=$(sha256sum "$raw_system" | cut -d' ' -f1)
source_size=$(stat -c%s "$raw_system")
for slot in system_a system_b; do
  actual=$(head -c "$source_size" "$out/verify-logical/$slot.img" | sha256sum | cut -d' ' -f1)
  [[ $actual == "$source_sha" ]] || { echo "Post-pack verification failed for $slot" >&2; exit 1; }
done

# Split for browser download without putting multi-gigabyte binaries in Git.
parts_dir="$out/download-parts"
mkdir -p "$parts_dir"
split --bytes=1900M --numeric-suffixes=1 --suffix-length=3 "$final_super" \
  "$parts_dir/$(basename "$final_super").part-"
(
  cd "$parts_dir"
  sha256sum ./* > SHA256SUMS.txt
  cat > RESTORE.txt <<EOF
Join the verified parts before flashing:
  cat $(basename "$final_super").part-* > $(basename "$final_super")
  sha256sum -c SHA256SUMS.txt

Flash only from fastbootd, with an unlocked bootloader. Keep a backup of the
original Lenovo super image. This build writes HyperOS to system_a and system_b
while keeping the supplied Lenovo vendor/product/system_ext partitions.
EOF
)

{
  echo
  echo '## Output verification'
  echo '```'
  cat "$out/injection.log"
  echo "target-system SHA-256: $source_sha"
  echo "target-system bytes: $source_size"
  for slot in system_a system_b; do
    echo "$slot prefix SHA-256: $(head -c "$source_size" "$out/verify-logical/$slot.img" | sha256sum | cut -d' ' -f1)"
  done
  stat -c '%n %s B' "$final_super"
  sha256sum "$final_super"
  echo '```'
  echo
  echo '## Download parts'
  echo '```'
  (cd "$parts_dir" && find . -maxdepth 1 -type f -printf '%f %s B\n' | sort)
  echo '```'
} >> "$report"

echo "Hybrid super build complete: $final_super"
