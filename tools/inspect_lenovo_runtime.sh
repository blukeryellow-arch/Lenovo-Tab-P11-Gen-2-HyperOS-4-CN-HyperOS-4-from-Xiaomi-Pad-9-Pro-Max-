#!/usr/bin/env bash
# Read-only forensic inspection of the Lenovo runtime matching the TB350FU log.
#
# This NEVER supplies files to the HyperOS output image. It only locates the
# framework/ART artifact that implements the Lenovo battery hook seen in logcat.
set -Eeuo pipefail

readonly LENOVO_RUNTIME_URL='https://support.halabtech.com/index.php?a=downloads&b=file&c=download&id=1043822'
readonly LENOVO_RUNTIME_PAGE='https://filewale.com/files/lenovo-tab-p11-gen-2-tb350fu_user_s231044_2601050946_mp_row_filewalecomzip/45346'
readonly LPUNPACK_URL='https://raw.githubusercontent.com/unix3dgforce/lpunpack/c59b8f3b069c5a8aa438a049fa4a091177172434/lpunpack.py'

report=${1:?Usage: $0 REPORT_PATH}
work=${2:-lenovo-runtime-audit}
archive="$work/TB350FU_USER_S231044_2601050946_MP_ROW.zip"

mkdir -p "$work" "$(dirname "$report")"

fail_report() {
  rc=$?
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
      [[ -s "$log" ]] || continue
      echo
      echo "### $(basename "$log") (tail)"
      echo '```'
      tail -80 "$log" || true
      echo '```'
    done
  } >> "$report"
  exit "$rc"
}

{
  echo '# Lenovo TB350FU runtime audit'
  echo
  echo '- target build from device log: `TB350FU_S231044_260105_ROW`'
  echo "- downloaded forensic package: \`$LENOVO_RUNTIME_URL\`"
  echo '- scope: read-only identification of the classpath artifact behind the Lenovo battery NPE'
  echo '- this package is **not** used as a HyperOS donor or copied into an output image'
} > "$report"
trap fail_report ERR

curl --fail --location --retry 3 --connect-timeout 45 --output "$archive" \
  "$LENOVO_RUNTIME_URL" 2>"$work/download.stderr"
test -s "$archive"
if ! unzip -tqq "$archive"; then
  # HalabTech currently redirects anonymous requests to its login form. Retain
  # a compact, non-sensitive record of the alternative public page's download
  # route instead of mistaking HTML for a firmware ZIP.
  mv "$archive" "$work/halab-response.html"
  curl --fail --location --retry 3 --connect-timeout 45 --output "$work/filewale-page.html" \
    "$LENOVO_RUNTIME_PAGE" 2>"$work/filewale.stderr" || true
  {
    echo
    echo '## Download-route diagnostic'
    echo
    echo '- HalabTech returned an HTML/login response instead of a ZIP to an anonymous request.'
    echo "- alternative public page: \`$LENOVO_RUNTIME_PAGE\`"
    echo '```'
    grep -Eio 'https?[^"<>[:space:]]+' "$work/filewale-page.html" 2>/dev/null | \
      grep -Ei 'download|api|zip|cloud|s3|r2' | sort -u | head -100 || true
    echo '```'
    echo
    echo '### Filewale client route hints'
    echo '```'
    mkdir -p "$work/filewale-js"
    grep -Eo '(/_next/static/[^"?[:space:]]+\.js)' "$work/filewale-page.html" | sort -u | while IFS= read -r path; do
      name=$(basename "$path")
      curl --fail --location --silent --show-error --connect-timeout 30 \
        "https://filewale.com$path" -o "$work/filewale-js/$name" 2>>"$work/filewale-js.stderr" || continue
    done
    grep -Eio '.{0,100}(download|presign|fileurl|api/).{0,180}' "$work"/filewale-js/*.js 2>/dev/null | \
      sort -u | head -120 || true
    echo '```'
    echo
    echo '### Filewale public-request parameters'
    echo '```'
    grep -Eio '.{0,220}(fileItemId|fileItem|request-download|TB350FU).{0,420}' "$work/filewale-page.html" | \
      sort -u | head -60 || true
    grep -Eio '.{0,220}(baseURL|axios\.create|uE=|apiUrl|api-url).{0,480}' "$work"/filewale-js/*.js 2>/dev/null | \
      sort -u | head -80 || true
    echo '```'
    echo
    echo '### Filewale public download-request probe'
    echo '```'
    # This is the documented client-side request used by Filewale's own public
    # file page.  It deliberately follows neither a returned URL nor a login
    # flow: the probe only records whether anonymous access is authorized.
    curl --location --silent --show-error --connect-timeout 30 --max-time 90 \
      --dump-header "$work/filewale-request.headers" \
      'https://filewale.com/api/v1/file-manager/public/file-items/45346/request-download' \
      -o "$work/filewale-request.json" 2>>"$work/filewale-request.stderr" || true
    printf '%s\n' 'response headers:'
    sed -n '1,40p' "$work/filewale-request.headers" 2>/dev/null || true
    printf '%s\n' 'JSON/text response (redacted to status, keys and non-secret messages):'
    python3 - "$work/filewale-request.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
try:
    value = json.loads(p.read_text())
except Exception:
    print('not JSON; bytes=' + str(p.stat().st_size if p.exists() else 0))
    raise SystemExit(0)
if isinstance(value, dict):
    print('top-level keys=' + ','.join(sorted(value)))
    for key in ('status', 'message', 'error', 'code'):
        if key in value:
            print(f'{key}={value[key]!r}')
    data = value.get('data')
    if isinstance(data, dict):
        print('data keys=' + ','.join(sorted(data)))
        for key in ('message', 'code', 'status', 'token', 'expiresAt'):
            if key in data:
                print(f'data.{key}={data[key]!r}')
        print('data.url present=' + str(bool(data.get('url'))))
else:
    print('JSON type=' + type(value).__name__)
PY
    echo '```'
  } >> "$report"
  false
fi
unzip -Z1 "$archive" > "$work/archive-files.txt"
{
  echo "- archive bytes: \`$(stat -c%s "$archive")\`"
  echo "- archive SHA-256: \`$(sha256sum "$archive" | cut -d' ' -f1)\`"
  echo
  echo '## Runtime image candidates'
  echo '```'
  grep -Ei '(^|/)(system|system_ext|super)(_[a-z])?\.img$' "$work/archive-files.txt" || true
  echo '```'
} >> "$report"

mapfile -t images < <(grep -Ei '(^|/)(system|system_ext)(_[a-z])?\.img$' "$work/archive-files.txt")
extract="$work/extract"
mkdir -p "$extract"
if [[ ${#images[@]} -gt 0 ]]; then
  unzip -q "$archive" "${images[@]}" -d "$extract"
else
  mapfile -t super_images < <(grep -Ei '(^|/)super\.img$' "$work/archive-files.txt")
  test "${#super_images[@]}" -gt 0
  unzip -q "$archive" "${super_images[@]}" -d "$extract"
  super=$(find "$extract" -type f -iname super.img | head -1)
  test -n "$super"
  curl --fail --location --retry 3 --connect-timeout 45 --output "$work/lpunpack.py" \
    "$LPUNPACK_URL" 2>"$work/lpunpack.stderr"
  python3 tools/extract_sparse_super_partitions.py --lpunpack "$work/lpunpack.py" --list "$super" \
    >"$work/logical-partitions.txt" 2>"$work/lpunpack-list.stderr"
  mapfile -t logical_parts < <(grep -Ex 'system(_a)?|system_ext(_a)?' "$work/logical-partitions.txt")
  test "${#logical_parts[@]}" -gt 0
  part_args=()
  for part in "${logical_parts[@]}"; do part_args+=(--partition "$part"); done
  python3 tools/extract_sparse_super_partitions.py --lpunpack "$work/lpunpack.py" "${part_args[@]}" \
    "$super" "$extract/logical" >"$work/lpunpack.log" 2>&1
fi

scan_tree() {
  local label=$1 image=$2 raw root kind
  raw="$image"
  kind=$(python3 - "$image" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as source:
    print('sparse' if source.read(4) == struct.pack('<I', 0xed26ff3a) else 'raw')
PY
)
  if [[ $kind == sparse ]]; then
    raw="$work/${label}.raw.img"
    simg2img "$image" "$raw"
  fi
  root="$work/${label}.root"
  rm -rf "$root"; mkdir -p "$root"
  {
    echo
    echo "## $label image"
    echo '```'
    file "$raw"
    sha256sum "$raw"
    echo '```'
  } >> "$report"

  if file "$raw" | grep -qi 'EROFS'; then
    fsck.erofs --extract="$root" --no-preserve "$raw" >"$work/${label}-extract.log" 2>&1 || \
      fsck.erofs --extract="$root" "$raw" >>"$work/${label}-extract.log" 2>&1
  elif file "$raw" | grep -qi 'ext4'; then
    debugfs -R "rdump / $root" "$raw" >"$work/${label}-extract.log" 2>&1
  else
    echo "Unsupported filesystem for $label: $(file -b "$raw")" >&2
    return 1
  fi

  {
    echo
    echo "### $label system-server artifacts"
    echo '```'
    find "$root" -type f \( -name 'services.jar' -o -name 'miui-services.jar' -o -name '*.odex' -o -name '*.vdex' \) \
      -printf '%p %s B\n' | sort
    echo '```'
    echo
    echo "### $label services archive SHA-256"
    echo '```'
    find "$root" -type f \( -name 'services.jar' -o -name 'miui-services.jar' \) -exec sha256sum {} \; | sort
    echo '```'
    echo
    echo "### $label Lenovo battery-hook strings"
    echo '```'
    while IFS= read -r -d '' artifact; do
      matches=''
      if [[ $artifact == *.jar || $artifact == *.apk ]]; then
        matches=$(unzip -p "$artifact" 'classes*.dex' 2>/dev/null | strings | \
          grep -E 'IBatteryServiceManager|mBatteryServiceManager|com[./]lenovo[./]lgsi|updateHealthInfo' || true)
      else
        matches=$(strings "$artifact" | \
          grep -E 'IBatteryServiceManager|mBatteryServiceManager|com[./]lenovo[./]lgsi|updateHealthInfo' || true)
      fi
      if [[ -n $matches ]]; then
        echo "-- $artifact"
        printf '%s\n' "$matches" | sort -u
      fi
    done < <(find "$root" -type f \( -name '*.jar' -o -name '*.apk' -o -name '*.odex' -o -name '*.vdex' \) -print0)
    echo '```'
  } >> "$report"
}

mapfile -t target_images < <(find "$extract" -type f \( -iname 'system.img' -o -iname 'system_ext.img' -o -iname 'system_a.img' -o -iname 'system_ext_a.img' \) | sort)
test "${#target_images[@]}" -gt 0
for image in "${target_images[@]}"; do
  base=$(basename "$image")
  label=${base%.img}
  scan_tree "$label" "$image"
done

test -s "$report"
echo "Lenovo runtime audit complete: $report"
