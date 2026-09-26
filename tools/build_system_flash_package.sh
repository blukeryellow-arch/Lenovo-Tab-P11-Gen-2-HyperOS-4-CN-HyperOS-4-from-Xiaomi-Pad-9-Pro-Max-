#!/usr/bin/env bash
# Create a flashable, system-only HyperOS package for TB350FU.
# It never packages a Lenovo system image: the payload is the exact Xiaomi
# yingtian OS4.0.11.0.XBMCNXM system image extracted from the recovery archive.
set -Eeuo pipefail

if [[ $# -ne 5 ]]; then
  echo "Usage: $0 REPORT_PATH RECOVERY_ZIP PAYLOAD_DUMPER WORK_DIR OUTPUT_DIR" >&2
  exit 2
fi
report=$1
recovery=$2
dumper=$3
work=$4
out=$5
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
expected_system_sha='4d3c61fe358f78102f5cae7bdaacc9f7a5d5d3c726d881dbc0ee3dcc697ee462'
name='TB350FU_HyperOS4_CN_yingtian_4.0.11.0_XBMCNXM_system_flash'

mkdir -p "$(dirname "$report")" "$work" "$out"

on_error() {
  rc=$?
  trap - ERR
  {
    echo
    echo '## System flash package failure diagnostic'
    echo
    echo "- failed command: \`$BASH_COMMAND\`"
    echo "- exit code: \`$rc\`"
    echo '```'
    find "$work" "$out" -maxdepth 3 -type f -printf '%p %s B\n' 2>/dev/null | sort || true
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

# This does a CRC-checked ZIP test, confirms yingtian metadata, and extracts
# only system.img. It is intentionally read-only with regard to Lenovo images.
bash "$script_dir/inspect_hyperos_recovery.sh" "$report" "$recovery" "$dumper" "$work/recovery"
system=$(find "$work/recovery/extracted" -type f -name 'system*.img' -print -quit)
[[ -n $system ]] || { echo 'Could not locate extracted system image.' >&2; exit 1; }
actual_system_sha=$(sha256sum "$system" | awk '{print $1}')
[[ $actual_system_sha == "$expected_system_sha" ]] || {
  echo "Unexpected yingtian system SHA-256: $actual_system_sha" >&2
  exit 1
}

stage="$work/$name"
rm -rf "$stage"
mkdir -p "$stage"
cp --reflink=auto "$system" "$stage/system.img"
cat > "$stage/flash-system-hyperos4.sh" <<'SCRIPT'
#!/usr/bin/env bash
# Run on the computer hosting an unlocked TB350FU in fastboot mode.
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
command -v fastboot >/dev/null || { echo 'fastboot is not installed or not on PATH.' >&2; exit 1; }
[[ -f system.img ]] || { echo 'system.img is missing.' >&2; exit 1; }

echo 'This writes Xiaomi HyperOS system.img to the existing TB350FU logical system_a and system_b.'
echo 'It does NOT write vendor, product, system_ext, boot, vendor_boot, vbmeta, preloader, or userdata.'
echo 'Use only with an unlocked bootloader and a known-good backup.'
read -r -p 'Type FLASH-SYSTEM to continue: ' confirmation
[[ $confirmation == FLASH-SYSTEM ]] || { echo 'Cancelled.'; exit 1; }

fastboot devices
fastboot reboot fastboot
sleep 5
fastboot wait-for-device
fastboot flash system_a system.img
fastboot flash system_b system.img
fastboot set_active a
fastboot reboot
SCRIPT
chmod 0755 "$stage/flash-system-hyperos4.sh"
cat > "$stage/flash-system-hyperos4.bat" <<'BAT'
@echo off
setlocal
cd /d "%~dp0"
if not exist system.img (
  echo system.img is missing.
  exit /b 1
)
echo This writes HyperOS system.img to the existing TB350FU logical system_a and system_b.
echo It does NOT write vendor, product, system_ext, boot, vendor_boot, vbmeta, preloader, or userdata.
echo Use only with an unlocked bootloader and a known-good backup.
set /p answer=Type FLASH-SYSTEM to continue:
if not "%answer%"=="FLASH-SYSTEM" (
  echo Cancelled.
  exit /b 1
)
fastboot devices
fastboot reboot fastboot
timeout /t 5 /nobreak >nul
fastboot flash system_a system.img
if errorlevel 1 exit /b 1
fastboot flash system_b system.img
if errorlevel 1 exit /b 1
fastboot set_active a
fastboot reboot
BAT
cat > "$stage/README.txt" <<EOF
TB350FU HyperOS 4 China system flash package
=============================================

Payload identity
----------------
- Xiaomi Pad 9 Pro Max (yingtian) China HyperOS 4 OS4.0.11.0.XBMCNXM
- system.img SHA-256: $expected_system_sha
- filesystem: EROFS

What this package changes
-------------------------
It writes the exact Xiaomi system image to BOTH existing logical slots:
  system_a
  system_b
It then selects slot a. This ensures system_server loads the HyperOS
BatteryService rather than a stale Lenovo system framework.

What it does NOT change
-----------------------
It does not flash Lenovo stock system or touch vendor, product, system_ext,
boot, vendor_boot, vbmeta, preloader, recovery, or userdata. The currently
installed Lenovo device-specific vendor/HAL partitions remain in place.

Requirements
------------
- Lenovo TB350FU only
- unlocked bootloader
- Android platform-tools fastboot installed on the computer
- a complete recovery backup before flashing

Flash from the host computer
----------------------------
Linux/macOS: ./flash-system-hyperos4.sh
Windows:     flash-system-hyperos4.bat

The scripts reboot to fastbootd before writing dynamic logical partitions.
Do not use these scripts on a different model.
EOF
(
  cd "$stage"
  sha256sum system.img flash-system-hyperos4.sh flash-system-hyperos4.bat README.txt > SHA256SUMS.txt
)
archive=$(realpath -m "$out/$name.zip")
(
  cd "$work"
  zip -q -0 -r "$archive" "$name"
)
unzip -t "$archive" >"$work/package-unzip-test.log" 2>&1

{
  echo
  echo '## Flash package verification'
  echo '```'
  echo "system SHA-256: $actual_system_sha"
  stat -c '%n %s B' "$archive"
  sha256sum "$archive"
  (cd "$stage" && cat SHA256SUMS.txt)
  echo '```'
} >> "$report"
echo "System flash package complete: $archive"
