#!/usr/bin/env bash
# Sciaganie kawalkow obrazu do sandboxa agenta przez git transport (najszybsza
# dzialajaca trasa) + skladanie + weryfikacja sha256 + geometria FS.
#
# Dlaczego git, a nie Drive ani REST:
#   - konektor Google Drive: twardy pre-check 104 857 600 B na plik, bez zakresow
#   - api.github.com /git/blobs: dziala, ale base64 -> 2.6-3.7 MB/s (policzone)
#   - git transport (codeload/github.com): 19.8-31.3 MB/s przy 48 MB (policzone ponizej)
#   - Git LFS i Release assets: nieosiagalne stad (media.githubusercontent.com = 000,
#     objects.githubusercontent.com = 000, brak binarki git-lfs)
#
# ZMIERZONE 2026-09-23 na wlasnych pomiarach w tym repo:
#   12 MB -> 0.93 s = 13.5 MB/s | 48 MB -> 1.54 s = 31.3 MB/s, 2.42 s = 19.8 MB/s
#   sha256 zlozonego pliku identyczny z oryginaliem w kazdym przebiegu
#   Ekstrapolacja przy 19.8 MB/s: system.img 0.8 min, product.img 5.4 min,
#   piec obrazow (11.9 GB) ~10 min.
#
# Uzycie (po stronie agenta, po tym jak uzytkownik wypchnal transfer/):
#   ./pull_via_git.sh <repo-url> <galaz> [katalog-docelowy]
# Oczekuje w galazi plikow transfer/MANIFEST.tsv o formacie:
#   <nazwa>\t<sha256>\t<bajty>\t<liczba-czastek>
#   transfer/<nazwa>.part.NN            (ewentualnie \t<blob-sha> na koncu linii)
set -uo pipefail

URL=${1:?podaj URL repo}
BRANCH=${2:?podaj galaz z transfer/}
DEST=${3:-$PWD/incoming}
WORK=$(mktemp -d /tmp/pull.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

echo "klone $BRANCH (plasko, bez historii) -> $WORK"
git clone -q --depth 1 --single-branch -b "$BRANCH" "$URL" "$WORK" || {
  echo "clone nie udalo sie - sprawdz galaz '$BRANCH' i dostep" >&2; exit 1; }
du -sh "$WORK" | sed 's/^/  drzewo: /'

MAN="$WORK/transfer/MANIFEST.tsv"
[ -f "$MAN" ] || { echo "BRAK transfer/MANIFEST.tsv w $BRANCH" >&2; exit 2; }
mkdir -p "$DEST"

python3 - "$MAN" "$WORK" "$DEST" <<'PY'
import hashlib, os, re, sys

man, work, dest = sys.argv[1], sys.argv[2], sys.argv[3]
lines = [l for l in open(man, encoding='utf-8').read().splitlines() if l.strip() and not l.startswith('#')]
i, fails = 0, 0
while i < len(lines):
    parts = lines[i].split('\t')
    if len(parts) < 4:
        i += 1
        continue
    name, want, size, nparts = parts[0], parts[1].lower(), int(parts[2]), int(parts[3])
    i += 1
    paths = []
    for _ in range(nparts):
        if i < len(lines):
            paths.append(lines[i].split('\t')[0].strip())
            i += 1
    out = os.path.join(dest, name)
    print(f"-- {name}: {size} B z {len(paths)} czastek")
    blob = b''
    for p in paths:
        fp = os.path.join(work, p)
        if not os.path.exists(fp):
            print(f"   BRAK PLIKU {p}")
            fails += 1
            blob = None
            break
        with open(fp, 'rb') as f:
            d = f.read()
        blob += d
        print(f"   {os.path.basename(p)}: {len(d)/1e6:.2f} MB -> razem {len(blob)/1e6:.2f}/{size/1e6:.2f} MB")
    if blob is None:
        continue
    if len(blob) != size:
        print(f"   ROZJEZIE ROZMIARU: {len(blob)} != {size}")
        fails += 1
        continue
    got = hashlib.sha256(blob).hexdigest()
    if got != want:
        print(f"   ROZJEZIE SHA256: {got} != {want} - NIE UZYWAJ")
        fails += 1
        continue
    with open(out, 'wb') as f:
        f.write(blob)
    print(f"   OK {out}  (sha256 potwierdzony: {got[:16]}...)")
print(f"\nbledow: {fails}; pliki w {dest}:")
for f in sorted(os.listdir(dest)):
    print(f"  {f}  {os.path.getsize(os.path.join(dest, f))} B")
sys.exit(1 if fails else 0)
PY
RC=$?

echo
echo "=== geometria (tools/fs_probe.py) ==="
for f in "$DEST"/*; do
  [ -e "$f" ] || continue
  python3 "$(dirname "$0")/fs_probe.py" "$f" 2>&1 | head -20
done
exit $RC
