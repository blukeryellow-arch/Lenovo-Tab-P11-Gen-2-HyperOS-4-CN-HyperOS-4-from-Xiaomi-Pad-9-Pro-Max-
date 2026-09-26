#!/usr/bin/env bash
# Read-only audit of the exact user-supplied HyperOS system image.
# It proves which BatteryService implementation is actually packaged by the
# Xiaomi-based target before any binary modification is attempted. Its workflow
# is deliberately activated only by an explicit [target-runtime] audit commit.
set -Eeuo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 REPORT_PATH SYSTEM_IMG WORK_DIR" >&2
  exit 2
fi

report=$1
image=$2
work=$3
[[ -f $image ]] || { echo "Missing system image: $image" >&2; exit 2; }
mkdir -p "$(dirname "$report")" "$work"

on_error() {
  local rc=$?
  trap - ERR
  {
    echo
    echo '## Audit failure diagnostic'
    echo
    echo "- failed command: \`$BASH_COMMAND\`"
    echo "- exit code: \`$rc\`"
    echo
    echo '```'
    find "$work" -maxdepth 3 -type f -printf '%p %s B\n' 2>/dev/null | sort || true
    echo '```'
    for log in "$work"/*.log "$work"/*.stderr; do
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

raw=$image
kind=$(python3 - "$image" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as f:
    print('sparse' if f.read(4) == struct.pack('<I', 0xed26ff3a) else 'raw')
PY
)
if [[ $kind == sparse ]]; then
  raw="$work/system.raw.img"
  simg2img "$image" "$raw"
fi
root="$work/system.root"
mkdir -p "$root"

{
  echo '# Exact HyperOS target-system audit'
  echo
  echo '- role: original Xiaomi yingtian China OS4.0.11.0.XBMCNXM based system image supplied for the Lenovo port'
  echo '- scope: read-only classpath comparison with the supplied stock TB350FU runtime'
  echo '- no Lenovo framework file is copied into this image by the audit'
  echo
  echo '## Input image'
  echo '```'
  stat -c '%n %s B' "$image"
  sha256sum "$image"
  file "$raw"
  echo '```'
} > "$report"

if file "$raw" | grep -qi EROFS; then
  fsck.erofs --extract="$root" --no-preserve "$raw" >"$work/extract.log" 2>&1 || \
    fsck.erofs --extract="$root" "$raw" >>"$work/extract.log" 2>&1
elif file "$raw" | grep -qiE 'ext[234] filesystem|Linux rev 1\.0'; then
  debugfs -R "rdump / $root" "$raw" >"$work/extract.log" 2>&1
else
  echo "Unsupported target filesystem: $(file -b "$raw")" >&2
  exit 1
fi

services=$(find "$root" -type f -path '*/framework/services.jar' -print -quit)
[[ -n $services ]] || { echo 'Target services.jar was not found' >&2; exit 1; }
artifact_dir="$work/target-framework"
mkdir -p "$artifact_dir"
cp --reflink=auto "$services" "$artifact_dir/services.jar"

{
  echo
  echo '## Target classpath inventory'
  echo '```'
  find "$root" -type f \( -path '*/framework/services.jar' -o -path '*/framework/miui-services.jar' -o -name 'services.odex' -o -name 'services.vdex' -o -name 'systemserverclasspath.pb' \) \
    -printf '%p %s B\n' | sort
  sha256sum "$services"
  echo '```'
  echo
  echo '## Lenovo battery-hook strings in target framework'
  echo '```'
  unzip -p "$services" 'classes*.dex' 2>/dev/null | strings | \
    grep -E 'IBatteryServiceManager|mBatteryServiceManager|iBatteryService|com[./]lenovo[./]lgsi|ZuiBatteryManager|vendor\.lenovo\.hardware\.battery' | sort -u || true
  echo '```'
} >> "$report"

# Decode the target's actual BatteryService so a future patch can be rejected
# rather than silently applied to an unrelated code base.
dex_dir="$work/dex"
smali_dir="$work/smali"
mkdir -p "$dex_dir" "$smali_dir"
mapfile -t entries < <(unzip -Z1 "$services" | grep -E '^classes[0-9]*\.dex$' || true)
[[ ${#entries[@]} -gt 0 ]] || { echo 'services.jar has no DEX entries' >&2; exit 1; }
for entry in "${entries[@]}"; do
  dex="$dex_dir/${entry//\//_}"
  unzip -p "$services" "$entry" >"$dex"
  if command -v baksmali >/dev/null; then
    baksmali d "$dex" -o "$smali_dir" >"$work/baksmali-${entry}.log" 2>&1
  elif [[ -f /usr/share/java/baksmali.jar ]]; then
    java -jar /usr/share/java/baksmali.jar d "$dex" -o "$smali_dir" >"$work/baksmali-${entry}.log" 2>&1
  else
    echo 'baksmali is required for target audit' >&2
    exit 1
  fi
done
battery=$(find "$smali_dir" -path '*/com/android/server/BatteryService.smali' -type f -print -quit)
[[ -n $battery ]] || { echo 'Target BatteryService.smali not found' >&2; exit 1; }
awk '
  /^\.method .*processValuesLocked/ { show=1 }
  show { print }
  show && /^\.end method/ { show=0 }
' "$battery" >"$work/target-processValuesLocked.smali"

{
  echo
  echo '## Decompiled target BatteryService compatibility surface'
  echo '```smali'
  grep -n -C 4 -E 'iBatteryService|mBatteryServiceManager|ZuiBatteryManager|lenovo' "$battery" | head -800 || true
  echo '```'
  echo
  echo '### Target `processValuesLocked`'
  echo '```smali'
  sed -n '1,1800p' "$work/target-processValuesLocked.smali"
  echo '```'
} >> "$report"

echo "HyperOS target audit complete: $report"
