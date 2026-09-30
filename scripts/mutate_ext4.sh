#!/usr/bin/env bash
# Exact, auditable ext4 edits. Called by build_v16.sh; not a general ROM kitchen.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-$ROOT/config/v16.json}"
WORK="$ROOT/work"
PARTS="$WORK/partitions"
LOG="$WORK/mutation.log"

[[ "${1:-}" == "--apply" && "${2:-}" == "--i-understand-avb" ]] || {
  echo "Refusing mutation without --apply --i-understand-avb" >&2; exit 2;
}
[[ $EUID -eq 0 ]] || { echo "ext4 loop mutation requires root" >&2; exit 2; }
for tool in python3 mount umount mountpoint e2fsck rsync setfattr file install; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 2; }
done
mkdir -p "$WORK/mnt"
: > "$LOG"

cleanup() {
  while read -r mountpoint; do
    [[ -n "$mountpoint" ]] && mountpoint -q "$mountpoint" && umount "$mountpoint" || true
  done < <(find "$WORK/mnt" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
}
trap cleanup EXIT

mapfile -t KEYS < <(python3 - "$CONFIG" <<'PY'
import json, sys
c=json.load(open(sys.argv[1]))
print(*sorted(set(c['partitions'].keys())), sep='\n')
PY
)

for key in "${KEYS[@]}"; do
  name="$(python3 - "$CONFIG" "$key" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))['partitions'][sys.argv[2]])
PY
)"
  image="$PARTS/$name.img"
  [[ -f "$image" ]] || { echo "missing extracted partition: $image" >&2; exit 2; }
  kind="$(file -b "$image")"
  [[ "$kind" == *"ext"*filesystem* ]] || {
    echo "$name is not recognized as ext filesystem ($kind); EROFS mutation is not implemented" >&2; exit 2;
  }
  # Android images may use shared extents; unshare before writable mounting.
  set +e
  e2fsck -fy -E unshare_blocks "$image" >>"$LOG" 2>&1
  rc=$?
  set -e
  (( rc <= 1 )) || { echo "e2fsck failed for $name (rc=$rc)" >&2; exit 2; }
  mnt="$WORK/mnt/$key"
  mkdir -p "$mnt"
  mount -o loop,rw "$image" "$mnt"
  echo "MOUNT $name -> $mnt" | tee -a "$LOG"
done

# Removal entries use Android namespace paths (system/..., product/...). The
# leading namespace is removed because each logical image is mounted at its root.
python3 - "$CONFIG" <<'PY' | while IFS=$'\t' read -r key relative; do
import json,sys
c=json.load(open(sys.argv[1]))
valid=set(c['partitions'])
for item in c['removal_allowlist']:
    prefix, sep, rest=item.partition('/')
    if sep and prefix in valid:
        print(prefix, rest, sep='\t')
PY
  target="$WORK/mnt/$key/$relative"
  if [[ -e "$target" ]]; then
    echo "REMOVE $key/$relative" | tee -a "$LOG"
    rm -rf --one-file-system "$target"
  else
    echo "ABSENT $key/$relative" >> "$LOG"
  fi
done

python3 - "$CONFIG" "$ROOT" <<'PY' | while IFS=$'\t' read -r source key destination context mode; do
import json,sys
from pathlib import Path
c=json.load(open(sys.argv[1])); root=Path(sys.argv[2])
for item in c['inject']:
    source=item.get('literal_source') or c['paths'][item['source_key']]
    source=Path(source)
    if not source.is_absolute(): source=root/source
    dest=item['destination'].split('/',1)
    relative=dest[1] if len(dest)==2 and dest[0]==item['partition_key'] else item['destination']
    print(source, item['partition_key'], relative, item['selinux_context'], item['mode'], sep='\t')
PY
  [[ -f "$source" ]] || { echo "missing injection source: $source" >&2; exit 2; }
  target="$WORK/mnt/$key/$destination"
  install -d -m 0755 "$(dirname "$target")"
  install -m "$mode" -o 0 -g 0 "$source" "$target"
  setfattr -n security.selinux -v "$context" "$target"
  # Directories created above need the normal system-file label as well.
  current="$(dirname "$target")"
  while [[ "$current" != "$WORK/mnt/$key" ]]; do
    setfattr -n security.selinux -v u:object_r:system_file:s0 "$current"
    current="$(dirname "$current")"
  done
  echo "INJECT $source -> $key/$destination [$context $mode]" | tee -a "$LOG"
done

cleanup
trap - EXIT
for key in "${KEYS[@]}"; do
  name="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["partitions"][sys.argv[2]])' "$CONFIG" "$key")"
  set +e; e2fsck -fy "$PARTS/$name.img" >>"$LOG" 2>&1; rc=$?; set -e
  (( rc <= 1 )) || { echo "post-mutation e2fsck failed for $name" >&2; exit 2; }
done
echo "Mutation complete. Review $LOG"
