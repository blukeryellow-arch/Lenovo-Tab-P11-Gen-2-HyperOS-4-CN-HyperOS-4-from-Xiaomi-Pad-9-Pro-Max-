#!/usr/bin/env bash
# Build a system image from a fully populated Android/HyperOS source checkout.
# This script cannot turn an arbitrary prebuilt system.img into a source build.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  tools/build_system_image.sh --android-root DIR --lunch TARGET [--jobs N] \
      [--out-dir DIR] [--compress lz4hc|gz|none]

Examples:
  tools/build_system_image.sh --android-root ~/src/hyperos \
      --lunch aosp_tb350fu-userdebug --compress lz4hc

The selected lunch target must build both the patched framework and the
boot/vendor_boot artifact whose BoardConfig.mk contains the SELinux boot arg.
EOF
}

android_root=""
lunch_target=""
jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
out_dir=""
compression="lz4hc"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --android-root) android_root="$2"; shift 2 ;;
    --lunch) lunch_target="$2"; shift 2 ;;
    --jobs) jobs="$2"; shift 2 ;;
    --out-dir) out_dir="$2"; shift 2 ;;
    --compress) compression="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$android_root" && -n "$lunch_target" ]] || { usage >&2; exit 2; }
[[ -f "$android_root/build/envsetup.sh" ]] || { echo "Missing $android_root/build/envsetup.sh" >&2; exit 2; }
case "$compression" in lz4hc|gz|none) ;; *) echo "Unsupported compression: $compression" >&2; exit 2;; esac

android_root="$(cd "$android_root" && pwd)"
out_dir="${out_dir:-$PWD/out}"
mkdir -p "$out_dir"

# shellcheck source=/dev/null
source "$android_root/build/envsetup.sh"
cd "$android_root"
lunch "$lunch_target"

# systemimage rebuilds framework/services.jar after the BatteryService source patch.
m -j"$jobs" systemimage

: "${ANDROID_PRODUCT_OUT:?lunch did not set ANDROID_PRODUCT_OUT}"
source_image="$ANDROID_PRODUCT_OUT/system.img"
[[ -f "$source_image" ]] || { echo "Build did not create $source_image" >&2; exit 1; }

base="$out_dir/system_hyperos4_p11g2_fixed.img"
cp --reflink=auto "$source_image" "$base"
sha256sum "$base" | tee "$base.sha256"

case "$compression" in
  lz4hc)
    command -v lz4 >/dev/null || { echo "lz4 is required for --compress lz4hc" >&2; exit 1; }
    # -12 is LZ4's high-compression mode; the .lz4hc suffix documents the intent.
    lz4 -12 -f "$base" "$base.lz4hc"
    sha256sum "$base.lz4hc" | tee "$base.lz4hc.sha256"
    ;;
  gz)
    gzip -9 -c "$base" > "$base.gz"
    sha256sum "$base.gz" | tee "$base.gz.sha256"
    ;;
  none) ;;
esac

echo "Created artifacts in: $out_dir"
