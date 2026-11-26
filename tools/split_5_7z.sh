#!/usr/bin/env bash
# Pack output directory into a 7z archive split into EXACTLY 5 volumes (.7z.001 .. .7z.005)
# and verify full multi-volume extraction integrity via `7z t` and `7z x` + SHA-256 check.
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <input_dir> <out_dir> <archive_base_name>" >&2
  exit 2
fi

IN_DIR="$1"
OUT_DIR="$2"
NAME="$3"

command -v 7z >/dev/null || { echo "ERROR: 7z not found (install p7zip-full / 7zip)" >&2; exit 1; }
[ -d "$IN_DIR" ] || { echo "ERROR: missing input_dir: $IN_DIR" >&2; exit 1; }

mkdir -p "$OUT_DIR"
WORK_TMP="$(mktemp -d)"
trap 'rm -rf "$WORK_TMP"' EXIT

ARCHIVE_SINGLE="$WORK_TMP/${NAME}.7z"
echo "==> Creating single 7z archive from $IN_DIR ..."
(
  cd "$IN_DIR"
  7z a -t7z -mx=3 -mmt=on -md=32m -ms=on "$ARCHIVE_SINGLE" .
)

TOTAL_SZ=$(stat -c%s "$ARCHIVE_SINGLE")
[ "$TOTAL_SZ" -gt 1024 ] || { echo "ERROR: archive suspiciously small: $TOTAL_SZ B" >&2; exit 1; }

VOL_SZ=$(( (TOTAL_SZ + 4) / 5 ))
echo "==> Archive size: ${TOTAL_SZ} B -> splitting into 5 parts of max ${VOL_SZ} B each..."
rm -f "${OUT_DIR}/${NAME}.7z."*
split -b "$VOL_SZ" -d --numeric-suffixes=1 -a 3 "$ARCHIVE_SINGLE" "${OUT_DIR}/${NAME}.7z."
rm -f "$ARCHIVE_SINGLE"

PARTS=( "${OUT_DIR}/${NAME}.7z."[0-9][0-9][0-9] )
PART_COUNT="${#PARTS[@]}"
echo "==> Created $PART_COUNT part(s):"
ls -lh "${PARTS[@]}"

if [ "$PART_COUNT" -ne 5 ]; then
  echo "ERROR: expected exactly 5 parts, got $PART_COUNT" >&2
  exit 1
fi

# Verify each part fits GitHub Release 2 GiB (2147483648 B) asset limit
for P in "${PARTS[@]}"; do
  PSZ=$(stat -c%s "$P")
  if [ "$PSZ" -ge 2147483648 ]; then
    echo "ERROR: part $P is $PSZ B (>= 2 GiB GitHub limit)" >&2
    exit 1
  fi
done

echo "==> Testing multi-volume 7z integrity via ${NAME}.7z.001 ..."
7z t "${OUT_DIR}/${NAME}.7z.001"

echo "==> Verifying full extract from .7z.001 and SHA-256 parity ..."
VERIFY_DIR="$WORK_TMP/verify"
mkdir -p "$VERIFY_DIR"
7z x -y "${OUT_DIR}/${NAME}.7z.001" "-o${VERIFY_DIR}" >/dev/null

(
  cd "$IN_DIR"
  find . -type f | sort | while read -r REL; do
    S1=$(sha256sum "$REL" | awk '{print $1}')
    S2=$(sha256sum "${VERIFY_DIR}/${REL}" | awk '{print $1}')
    if [ "$S1" != "$S2" ]; then
      echo "ERROR: SHA-256 mismatch on extracted $REL ($S1 != $S2)" >&2
      exit 1
    fi
    echo "  OK: $REL ($S1)"
  done
)

echo "==> Generating SHA256SUMS-7Z.txt ..."
(
  cd "$OUT_DIR"
  sha256sum "${NAME}.7z."[0-9][0-9][0-9] > "${NAME}-7Z-SHA256SUMS.txt"
)
cat "${OUT_DIR}/${NAME}-7Z-SHA256SUMS.txt"
echo "==> 5-part 7z packaging and verification PASSED."
