#!/usr/bin/env bash
# Forensic inventory for an Android sparse image whose filesystem is EROFS.
# Intended for a disposable build host / CI worker, not the device.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tools/investigate_prebuilt_system.sh INPUT_SPARSE_IMG OUTPUT_DIR

Requires: simg2img, fsck.erofs, unzip, zipgrep, strings, sha256sum.
Writes an extracted EROFS tree and a compact report identifying the JAR/APK/DEX
that contains Lenovo IBatteryServiceManager and updateHealthInfo.
EOF
}

[[ $# -eq 2 ]] || { usage >&2; exit 2; }
input="$1"
out="$2"
[[ -f "$input" ]] || { echo "Missing input image: $input" >&2; exit 2; }
command -v simg2img >/dev/null || { echo "simg2img is required" >&2; exit 2; }
command -v fsck.erofs >/dev/null || { echo "fsck.erofs is required" >&2; exit 2; }

mkdir -p "$out"
raw="$out/system.raw.img"
tree="$out/root"
report="$out/inventory.txt"

simg2img "$input" "$raw"
{
  echo "input: $input"
  sha256sum "$input"
  echo "raw: $raw"
  sha256sum "$raw"
  file "$raw"
  echo
  echo '== fsck.erofs help (for reproducibility) =='
  fsck.erofs --help 2>&1 || true
} > "$report"

rm -rf "$tree"
mkdir -p "$tree"
# erofs-utils 1.5+ accepts --extract=DIR; a small number of older packaged
# versions use --extract DIR. Try both forms without silently proceeding.
if fsck.erofs --extract="$tree" "$raw" >>"$report" 2>&1; then
  :
elif fsck.erofs --extract "$tree" "$raw" >>"$report" 2>&1; then
  :
else
  echo 'Unable to extract EROFS image; see inventory.txt.' >&2
  exit 1
fi

{
  echo
  echo '== candidate framework archives =='
  find "$tree" -type f \( -name '*.jar' -o -name '*.apk' \) -printf '%p\n' | sort
  echo
  echo '== archives containing Lenovo battery hook strings =='
  while IFS= read -r -d '' archive; do
    if ! unzip -Z1 "$archive" 2>/dev/null | grep -q '^classes[0-9]*\.dex$'; then
      continue
    fi
    matches="$(unzip -p "$archive" 'classes*.dex' 2>/dev/null | strings | grep -E 'com/lenovo/lgsi/server/battery|IBatteryServiceManager|updateHealthInfo' || true)"
    if [[ -n "$matches" ]]; then
      printf '\n-- %s --\n%s\n' "$archive" "$matches"
      unzip -Z1 "$archive" | grep '^classes[0-9]*\.dex$' || true
    fi
  done < <(find "$tree" -type f \( -name '*.jar' -o -name '*.apk' \) -print0)
  echo
  echo '== preoptimized counterparts =='
  find "$tree" -type f \( -name 'services.odex' -o -name 'services.vdex' -o -name 'services.art' \) -printf '%p\n' | sort
} >> "$report"

echo "Inventory complete: $report"
