#!/usr/bin/env bash
# Read-only audit of a full Xiaomi recovery package requested by the user.
# The package is never treated as a Lenovo replacement: this extracts only the
# Xiaomi logical system payload so it can be compared with the supplied port.
set -Eeuo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 REPORT_PATH RECOVERY_ZIP PAYLOAD_DUMPER WORK_DIR" >&2
  exit 2
fi

report=$1
zip=$2
dumper=$3
work=$4
[[ -f $zip ]] || { echo "Missing recovery archive: $zip" >&2; exit 2; }
[[ -x $dumper ]] || { echo "Missing payload dumper: $dumper" >&2; exit 2; }
mkdir -p "$(dirname "$report")" "$work"

on_error() {
  local rc=$?
  trap - ERR
  {
    echo
    echo '## Recovery audit failure diagnostic'
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

{
  echo '# Full Xiaomi yingtian HyperOS recovery audit'
  echo
  echo '- requested source: Xiaomi Pad 9 Pro Max (yingtian), China Recovery, OS4.0.11.0.XBMCNXM'
  echo '- source class: third-party catalogue link supplied by the user; the archive is independently inspected before use'
  echo '- scope: extract and audit only the Xiaomi `system` payload; no Lenovo image is overwritten or copied'
  echo
  echo '## Archive identity'
  echo '```'
  stat -c '%n %s B' "$zip"
  sha256sum "$zip"
  file "$zip"
  echo '```'
} > "$report"

# ZIP central-directory inspection is cheap, whereas "unzip -t" validates all
# compressed payload data and catches an interrupted 10+ GiB transfer.
unzip -Z1 "$zip" | sort > "$work/zip-members.txt"
if ! grep -qx 'payload.bin' "$work/zip-members.txt"; then
  echo 'Recovery archive has no payload.bin; refusing to guess its layout.' >&2
  exit 1
fi
unzip -t "$zip" >"$work/unzip-test.log" 2>&1

{
  echo
  echo '## Recovery metadata and payload inventory'
  echo '```'
  for member in \
    'META-INF/com/android/metadata' \
    'payload_properties.txt' \
    'compatibility.zip'; do
    if grep -qx "$member" "$work/zip-members.txt"; then
      echo "--- $member ---"
      unzip -p "$zip" "$member" 2>/dev/null || true
    fi
  done
  echo '--- selected archive members ---'
  grep -E '(^payload\.bin$|metadata|build|manifest|property)' "$work/zip-members.txt" || true
  echo '```'
} >> "$report"

# Do not infer the release from a web page alone. Require the requested release
# token to be present in the package's own metadata, filename, or manifest.
if ! { grep -a -q 'OS4\.0\.11\.0\.XBMCNXM\|4\.0\.11\.0\.XBMCNXM' "$work/zip-members.txt" ||
       unzip -p "$zip" 'META-INF/com/android/metadata' 2>/dev/null | grep -q '4\.0\.11\.0\.XBMCNXM'; }; then
  echo 'The downloaded recovery archive does not identify itself as 4.0.11.0.XBMCNXM.' >&2
  exit 1
fi

"$dumper" -l "$zip" >"$work/payload-partitions.log" 2>&1
if ! grep -Eq '(^|[^[:alnum:]_])system([^[:alnum:]_]|$)' "$work/payload-partitions.log"; then
  echo 'payload.bin does not expose a system partition.' >&2
  exit 1
fi
mkdir -p "$work/extracted"
"$dumper" -p system -o "$work/extracted" "$zip" >"$work/extract-system.log" 2>&1
system=$(find "$work/extracted" -maxdepth 2 -type f -name 'system*.img' -print -quit)
[[ -n $system ]] || { echo 'Payload extraction did not produce system.img.' >&2; exit 1; }

{
  echo
  echo '## Extracted exact system payload'
  echo '```'
  stat -c '%n %s B' "$system"
  sha256sum "$system"
  file "$system"
  echo '```'
} >> "$report"

echo "Recovery audit complete: $report"
echo "EXTRACTED_SYSTEM=$system"
