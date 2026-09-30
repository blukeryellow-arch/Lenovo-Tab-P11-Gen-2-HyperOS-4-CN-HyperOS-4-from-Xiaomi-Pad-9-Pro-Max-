#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
CONFIG="${CONFIG:-config/v16.json}"
PHASE="${1:-help}"
WORK="$ROOT/work"
OUT="$ROOT/out"
RAW="$WORK/super.raw.img"
PARTS="$WORK/partitions"
LPDUMP="$WORK/lpdump.txt"

json_path() {
  python3 - "$CONFIG" "$1" <<'PY'
import json,sys
v=json.load(open(sys.argv[1]))
for k in sys.argv[2].split('.'): v=v[k]
print(v)
PY
}
require_consent() {
  [[ "${2:-}" == "--apply" && "${3:-}" == "--i-understand-avb" ]] || {
    echo "Refusing write phase without: $PHASE --apply --i-understand-avb" >&2; exit 2;
  }
}

case "$PHASE" in
  extract)
    mkdir -p "$WORK" "$PARTS" "$OUT"
    python3 tools/preflight.py --config "$CONFIG" --json-report "$WORK/preflight.json"
    stock="$(json_path paths.stock_super)"
    magic="$(od -An -tx4 -N4 "$stock" | tr -d ' ')"
    if [[ "$magic" == "ed26ff3a" ]]; then
      echo "Converting Android sparse super to raw..."
      simg2img "$stock" "$RAW"
    else
      cp --reflink=auto --sparse=always "$stock" "$RAW"
    fi
    lpdump "$RAW" > "$LPDUMP"
    rm -rf "$PARTS" && mkdir -p "$PARTS"
    lpunpack "$RAW" "$PARTS"
    python3 tools/lp_metadata.py "$LPDUMP" --images "$PARTS" \
      --output "$OUT/super-v16.img" --json "$WORK/lp-metadata.json" \
      --shell "$WORK/lpmake.sh"
    echo "Extracted $(find "$PARTS" -maxdepth 1 -name '*.img' | wc -l) logical images."
    ;;
  plan)
    [[ -f "$WORK/lp-metadata.json" ]] || { echo "run extract first" >&2; exit 2; }
    mkdir -p "$WORK/reports"
    python3 - "$CONFIG" "$ROOT" > "$WORK/plan.txt" <<'PY'
import json,sys
from pathlib import Path
c=json.load(open(sys.argv[1])); root=Path(sys.argv[2])
print('MYSTICALOS 3 V16 MUTATION PLAN — REVIEW BEFORE APPLYING')
print('\nREMOVALS (exact allowlist; absent paths are logged):')
for p in c['removal_allowlist']: print('  -', p)
print('\nINJECTIONS:')
for x in c['inject']:
    src=x.get('literal_source') or c['paths'][x['source_key']]
    print(f"  - {src} -> {x['partition_key']}:{x['destination']} context={x['selinux_context']} mode={x['mode']}" + (' EXPERIMENTAL' if x.get('experimental') else ''))
print('\nNOT PERFORMED:')
print('  - framework signature-spoofing patch (version-specific source/bytecode work required)')
print('  - Xiaomi SystemUI replacement (platform signature/framework coupling unresolved)')
print('  - AVB OEM signing (Lenovo private keys unavailable)')
print('  - arbitrary 32-way chunk split (requires exact Lenovo manifest format)')
print('  - binary-to-Rust Binder rewriting (not technically valid without source)')
PY
    cat "$WORK/plan.txt"
    ;;
  mutate)
    require_consent "$@"
    [[ -f "$WORK/plan.txt" ]] || { echo "run plan and review it first" >&2; exit 2; }
    exec env CONFIG="$ROOT/$CONFIG" "$ROOT/scripts/mutate_ext4.sh" --apply --i-understand-avb
    ;;
  assemble)
    require_consent "$@"
    [[ -x "$WORK/lpmake.sh" && -f "$WORK/mutation.log" ]] || { echo "run extract, plan, and mutate first" >&2; exit 2; }
    mkdir -p "$OUT"
    # Regenerate from trusted parser instead of executing a user-edited stale command.
    python3 tools/lp_metadata.py "$LPDUMP" --images "$PARTS" \
      --output "$OUT/super-v16.img" --json "$WORK/lp-metadata-final.json" \
      --shell "$WORK/lpmake-final.sh"
    "$WORK/lpmake-final.sh"
    sha256sum "$OUT/super-v16.img" > "$OUT/SHA256SUMS"
    python3 - "$CONFIG" "$WORK" "$OUT" > "$OUT/build-report.json" <<'PY'
import datetime,json,sys
from pathlib import Path
config=json.load(open(sys.argv[1])); work=Path(sys.argv[2]); out=Path(sys.argv[3])
report={'project':config['project'],'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'bootloader_requirement':'unlocked','avb_status':'NOT OEM-SIGNED; NOT FLASH-READY',
        'geometry':json.load(open(work/'lp-metadata-final.json')),
        'mutation_log':(work/'mutation.log').read_text().splitlines(),
        'sha256sums':(out/'SHA256SUMS').read_text().strip()}
print(json.dumps(report,indent=2))
PY
    echo "Assembled engineering artifact at $OUT/super-v16.img (not OEM-signed)."
    ;;
  verify)
    image="$OUT/super-v16.img"
    [[ -f "$image" ]] || { echo "no assembled image: $image" >&2; exit 2; }
    rm -rf "$WORK/verify" && mkdir -p "$WORK/verify/partitions"
    simg2img "$image" "$WORK/verify/super.raw.img"
    lpdump "$WORK/verify/super.raw.img" > "$WORK/verify/lpdump.txt"
    lpunpack "$WORK/verify/super.raw.img" "$WORK/verify/partitions"
    python3 tools/lp_metadata.py "$WORK/verify/lpdump.txt" --images "$WORK/verify/partitions" \
      --output /dev/null --json "$WORK/verify/lp-metadata.json"
    python3 - "$WORK/lp-metadata-final.json" "$WORK/verify/lp-metadata.json" <<'PY'
import json,sys
before=json.load(open(sys.argv[1])); after=json.load(open(sys.argv[2]))
for d in (before,after): d.pop('lpmake_argv',None)
if before != after:
    print('ERROR: rebuilt LP geometry differs',file=sys.stderr); raise SystemExit(2)
print('LP geometry round-trip: OK')
PY
    sha256sum -c "$OUT/SHA256SUMS"
    echo "Structural verification passed. This does not establish bootability or AVB trust."
    ;;
  help|*)
    cat <<'EOF'
Usage:
  scripts/build_v16.sh extract
  scripts/build_v16.sh plan
  sudo scripts/build_v16.sh mutate --apply --i-understand-avb
  scripts/build_v16.sh assemble --apply --i-understand-avb
  scripts/build_v16.sh verify
EOF
    [[ "$PHASE" == help ]] || exit 2
    ;;
esac
