#!/usr/bin/env bash
# Read-only audit of the user-provided TB350FU dynamic-partition image.
#
# The output is forensic evidence only.  No Lenovo file is copied into the
# HyperOS image by this script.
set -Eeuo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 REPORT_PATH SUPER_IMG WORK_DIR" >&2
  exit 2
fi

report=$1
super=$2
work=$3
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
lpunpack_url='https://raw.githubusercontent.com/unix3dgforce/lpunpack/c59b8f3b069c5a8aa438a049fa4a091177172434/lpunpack.py'

[[ -f $super ]] || { echo "Missing super image: $super" >&2; exit 2; }
mkdir -p "$(dirname "$report")" "$work"

report_failure() {
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
trap report_failure ERR

{
  echo '# Lenovo TB350FU runtime audit from supplied super.img'
  echo
  echo '- target requested by the user: `TB350FU_S231044_260105_ROW`'
  echo '- source: user-supplied Google Drive `super.img` from the SP Flash Tool package'
  echo '- scope: read-only identification of framework, battery HAL and SELinux evidence'
  echo '- this image is an inspection input only; the output ROM remains based on Xiaomi yingtian China OS4.0.11.0.XBMCNXM'
  echo
  echo '## Input image'
  echo '```'
  stat -c '%n %s B' "$super"
  md5sum "$super"
  python3 - "$super" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as f:
    magic = f.read(4)
print('format=' + ('android-sparse' if magic == struct.pack('<I', 0xed26ff3a) else 'raw'))
PY
  echo '```'
} > "$report"

curl --fail --location --retry 3 --connect-timeout 45 --output "$work/lpunpack.py" \
  "$lpunpack_url" 2>"$work/lpunpack.stderr"
python3 "$script_dir/extract_sparse_super_partitions.py" --lpunpack "$work/lpunpack.py" --list "$super" \
  >"$work/logical-partitions.txt" 2>"$work/lpunpack-list.stderr"
{
  echo
  echo '## Logical partitions'
  echo '```'
  cat "$work/logical-partitions.txt"
  echo '```'
} >> "$report"

# Extract only partitions relevant to framework and vendor policy.  Do not
# materialize a full raw super image.
parts=()
# The framework callback and its SELinux/HAL dependencies live in system,
# system_ext and vendor.  Avoid extracting product in this first pass: it is
# unrelated to system_server's classpath and costs several GiB on the runner.
for base in system system_ext vendor; do
  for candidate in "$base" "${base}_a"; do
    if grep -Fxq "$candidate" "$work/logical-partitions.txt"; then
      parts+=("$candidate")
      break
    fi
  done
done
[[ ${#parts[@]} -gt 0 ]] || { echo 'No system/vendor logical partitions found' >&2; exit 1; }
part_args=()
for part in "${parts[@]}"; do
  part_args+=(--partition "$part")
done
mkdir -p "$work/logical"
python3 "$script_dir/extract_sparse_super_partitions.py" --lpunpack "$work/lpunpack.py" \
  "${part_args[@]}" "$super" "$work/logical" >"$work/lpunpack-extract.log" 2>&1

extract_partition() {
  local image=$1 label=$2 raw root kind
  raw=$image
  kind=$(python3 - "$image" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as f:
    print('sparse' if f.read(4) == struct.pack('<I', 0xed26ff3a) else 'raw')
PY
)
  if [[ $kind == sparse ]]; then
    raw="$work/${label}.raw.img"
    simg2img "$image" "$raw"
  fi
  root="$work/${label}.root"
  rm -rf "$root"
  mkdir -p "$root"
  {
    echo
    echo "## $label partition"
    echo '```'
    stat -c '%n %s B' "$image"
    file "$raw"
    sha256sum "$raw"
    echo '```'
  } >> "$report"

  if file "$raw" | grep -qi EROFS; then
    fsck.erofs --extract="$root" --no-preserve "$raw" >"$work/${label}-extract.log" 2>&1 || \
      fsck.erofs --extract="$root" "$raw" >>"$work/${label}-extract.log" 2>&1
  elif file "$raw" | grep -qiE 'ext[234] filesystem|Linux rev 1\.0'; then
    # Android's ext4 images are sometimes labelled "Linux rev 1.0 ext2" by
    # libmagic despite carrying ext4 features. debugfs handles all ext2/3/4.
    debugfs -R "rdump / $root" "$raw" >"$work/${label}-extract.log" 2>&1
  else
    echo "Unsupported $label filesystem: $(file -b "$raw")" >&2
    return 1
  fi

  {
    echo
    echo "### $label build fingerprints"
    echo '```'
    find "$root" -type f -name 'build.prop' -print0 | while IFS= read -r -d '' prop; do
      echo "-- $prop"
      grep -E '^(ro\.build\.(id|fingerprint)|ro\.product\.(device|vendor\.device)|ro\.system\.build\.fingerprint)=' "$prop" || true
    done
    echo '```'
  } >> "$report"
}

for part in "${parts[@]}"; do
  image="$work/logical/${part}.img"
  [[ -f $image ]] || { echo "Extractor did not create $image" >&2; exit 1; }
  extract_partition "$image" "$part"
done

artifact_dir="$work/selected-framework"
mkdir -p "$artifact_dir"
services_jar=''
{
  echo
  echo '## System-server and Lenovo battery-hook inventory'
  echo '```'
  for part in "${parts[@]}"; do
    root="$work/${part}.root"
    [[ -d $root ]] || continue
    echo "-- $part framework artifacts"
    find "$root" -type f \( -name 'services.jar' -o -name 'miui-services.jar' -o -name 'services.odex' -o -name 'services.vdex' -o -name 'services.art' \) \
      -printf '%p %s B\n' | sort

    # Preserve framework jars as a short-lived CI artifact for bytecode review;
    # not in Git and not in the generated ROM.
    while IFS= read -r -d '' jar; do
      relative=${jar#"$root"/}
      dest="$artifact_dir/$part/$relative"
      mkdir -p "$(dirname "$dest")"
      cp --reflink=auto "$jar" "$dest"
      if [[ $part == system_a || $part == system ]] && [[ $relative == system/framework/services.jar ]]; then
        services_jar=$jar
      fi
      echo "sha256 $(sha256sum "$jar" | cut -d' ' -f1)  $part/$relative"
      matches=$(unzip -p "$jar" 'classes*.dex' 2>/dev/null | strings | \
        grep -E 'IBatteryServiceManager|mBatteryServiceManager|com[./]lenovo[./]lgsi|updateHealthInfo|vendor\.lenovo\.hardware\.battery' || true)
      if [[ -n $matches ]]; then
        echo "hook strings: $part/$relative"
        printf '%s\n' "$matches" | sort -u
      fi
    done < <(find "$root" -type f \( -name 'services.jar' -o -name 'miui-services.jar' \) -print0)
  done
  echo '```'

  echo
  echo '## Vendor battery HAL and SELinux inventory'
  echo '```'
  for part in "${parts[@]}"; do
    root="$work/${part}.root"
    [[ -d $root ]] || continue
    find "$root" -type f \( -path '*/etc/vintf/*' -o -path '*/etc/selinux/*' -o -name '*battery*.rc' -o -name '*battery*.xml' \) \
      -printf '%p %s B\n' | sort | head -500
  done
  for root in "$work"/vendor*.root; do
    [[ -d $root ]] || continue
    grep -R -a -E -m 3 'lenovo\.hardware\.battery|vendor\.lenovo\.hardware\.battery|IBattery' \
      "$root/etc/vintf" "$root/etc/selinux" 2>/dev/null || true
  done
  echo '```'
} >> "$report"

# Render the actual failing code path to text on the disposable runner. This
# provides a reviewable, precise patch target without putting the stock Lenovo
# framework archive into Git or treating it as a HyperOS donor.
if [[ -n $services_jar ]]; then
  dex_dir="$work/services-dex"
  smali_dir="$work/services-smali"
  mkdir -p "$dex_dir" "$smali_dir"
  mapfile -t dex_entries < <(unzip -Z1 "$services_jar" | grep -E '^classes[0-9]*\.dex$' || true)
  [[ ${#dex_entries[@]} -gt 0 ]] || { echo "No DEX entries in $services_jar" >&2; exit 1; }
  for entry in "${dex_entries[@]}"; do
    dex="$dex_dir/${entry//\//_}"
    unzip -p "$services_jar" "$entry" >"$dex"
    if command -v baksmali >/dev/null; then
      baksmali d "$dex" -o "$smali_dir" >"$work/baksmali-${entry}.log" 2>&1
    elif [[ -f /usr/share/java/baksmali.jar ]]; then
      java -jar /usr/share/java/baksmali.jar d "$dex" -o "$smali_dir" >"$work/baksmali-${entry}.log" 2>&1
    else
      echo 'baksmali is required to inspect the exact battery callback' >&2
      exit 1
    fi
  done

  battery_smali=$(find "$smali_dir" -path '*/com/android/server/BatteryService.smali' -type f -print -quit)
  manager_smali=$(find "$smali_dir" -path '*/com/lenovo/lgsi/server/battery/IBatteryServiceManager.smali' -type f -print -quit)
  [[ -n $battery_smali ]] || { echo 'BatteryService.smali not found after disassembly' >&2; exit 1; }
  awk '
    /^\.method .*processValuesLocked/ { show=1 }
    show { print }
    show && /^\.end method/ { show=0 }
  ' "$battery_smali" >"$work/processValuesLocked.smali"
  {
    echo
    echo '## Decompiled exact Lenovo BatteryService evidence'
    echo
    echo '- source archive: `system/framework/services.jar` from the supplied TB350FU build'
    echo '- this identifies the null-safe callback patch target; it does not authorize replacing Xiaomi HyperOS services.jar with Lenovo services.jar'
    echo
    echo '### BatteryService fields and callback references'
    echo '```smali'
    grep -n -C 5 -E 'iBatteryService|mBatteryServiceManager' "$battery_smali" | head -800 || true
    echo '```'
    echo
    echo '### `processValuesLocked`'
    echo '```smali'
    sed -n '1,1800p' "$work/processValuesLocked.smali"
    echo '```'
    echo
    echo '### Lenovo IBatteryServiceManager declaration'
    echo '```smali'
    if [[ -n $manager_smali ]]; then
      sed -n '1,700p' "$manager_smali"
    else
      echo 'IBatteryServiceManager.smali was not found after disassembly.'
    fi
    echo '```'
    echo
    echo '### Vendor SELinux battery-related rules'
    echo '```'
    # Restrict the text scan to CIL/context inputs. Grepping the binary
    # precompiled policy would inject NUL bytes into the Markdown report.
    find "$work"/vendor*.root/etc/selinux -type f \( -name '*.cil' -o -name '*contexts' \) -print0 2>/dev/null | \
      xargs -0 -r grep -a -E 'hal_battery|lenovo\.hardware\.battery|vendor\.lenovo\.hardware\.battery' | \
      head -500 || true
    echo '```'
  } >> "$report"
fi

echo "Lenovo super audit complete: $report"
