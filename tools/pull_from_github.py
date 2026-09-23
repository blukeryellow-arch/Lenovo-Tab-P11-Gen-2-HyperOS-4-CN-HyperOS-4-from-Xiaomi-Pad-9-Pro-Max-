#!/usr/bin/env python3
"""Sciaganie kawalkow obrazu z GitHuba i skladanie ich z powrotem w sandboxie agenta.

Powstal, bo konektor Google Drive ma twardy pre-check 104 857 600 B na plik, a
egress sandboxa dopuszcza TYLKO github.com i api.github.com (zmierzone:
drive.google.com, www.googleapis.com, media.githubusercontent.com,
objects.githubusercontent.com = 000). Kanat: GET /repos/{o}/{r}/git/blobs/{sha}
zwraca base64 w JSON przez api.github.com - zmierzone 3.70 MB/s, sha256 identyczny.

Czego NIE da sie zrobic tym kanalem:
  - Git LFS: pliki LFS ida z media.githubusercontent.com (000) i nie ma tu
    binarki git-lfs; limit LFS (2 GB/plik na Free, 1 GB/mies pasma) jest wiec
    nieistotny po stronie agenta;
  - Release assets: 2 GB/plik, ale sciaganie idzie przez objects.githubusercontent.com (000).

MANIFEST ma format (TSV, pole po polu, # = komentarz):
  name<TAB>sha256<TAB>bytes<TAB>parts
  <sciezka-w-repo-do-czastki 1>
  ...

Uzycie:
  ./pull_from_github.py --repo OWNER/REPO --branch rom-blobs --manifest transfer/MANIFEST.tsv --dest ./incoming
  ./pull_from_github.py --repo OWNER/REPO --shas <sha1,sha2,...> --out ./incoming/plik --sha256 ABC...
"""
import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import time

CHUNK_TIMEOUT = 600


def sh(args, stdin=None, binary=False):
    """gh z ponowieniami; zwrot (rc, stdout)."""
    last = b'' if binary else ''
    for attempt in range(4):
        try:
            p = subprocess.run(args, input=stdin, capture_output=True, timeout=CHUNK_TIMEOUT)
        except subprocess.TimeoutExpired:
            print(f"    timeout (proba {attempt + 1})", file=sys.stderr)
            time.sleep(2 * (attempt + 1))
            continue
        if p.returncode == 0:
            return 0, (p.stdout if binary else p.stdout.decode('utf-8', 'replace'))
        last = p.stderr.decode('utf-8', 'replace') if not binary else b''
        if attempt < 3:
            time.sleep(2 * (attempt + 1))
    return 1, last


def fetch_blob(repo, sha, binary=False):
    """Blok vbmeta/chunk przez blob API. Dla plikow <= 100 MB GitHub zwraca
    calosc w baz64; powyzej - 404/'too large' i trzeba LFS (dla nas nieosiagalne)."""
    rc, out = sh(['gh', 'api', f'repos/{repo}/git/blobs/{sha}', '--jq', '.content'], binary=binary)
    if rc != 0:
        return None, str(out)[:300]
    txt = out if not binary else out.decode('ascii', 'ignore')
    raw = txt.replace('\n', '').replace('\r', '')
    try:
        data = base64.b64decode(raw + '=' * (-len(raw) % 4))
    except Exception as e:
        return None, f'base64 decode: {e}'
    return data, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo', required=True)
    ap.add_argument('--branch', default='rom-blobs')
    ap.add_argument('--manifest', default='transfer/MANIFEST.tsv')
    ap.add_argument('--dest', default='./incoming')
    ap.add_argument('--shas', help='bez manifestu: jawna lista sha blobow, po przecinku')
    ap.add_argument('--out', help='bez manifestu: plik wynikowy')
    ap.add_argument('--sha256', help='bez manifestu: oczekiwany sum kontrolny')
    ap.add_argument('--max-bytes', type=int, default=0, help='uciach wynik (do testow)')
    a = ap.parse_args()
    os.makedirs(a.dest, exist_ok=True)
    t0 = time.time()

    if a.shas:
        shas = [s for s in a.shas.split(',') if s.strip()]
        blob = b''
        for i, s in enumerate(shas, 1):
            data, err = fetch_blob(a.repo, s, binary=True)
            if data is None:
                print(f"BRAK bloba {s}: {err}", file=sys.stderr)
                return 3
            blob += data
            print(f"  [{i}/{len(shas)}] {s[:10]} {len(data) / 1e6:.2f} MB  "
                  f"(razem {len(blob) / 1e6:.2f} MB)")
        if a.max_bytes:
            blob = blob[:a.max_bytes]
        out = a.out or os.path.join(a.dest, 'assembled.bin')
        with open(out, 'wb') as f:
            f.write(blob)
        got = hashlib.sha256(blob).hexdigest()
        print(f"zapisano {out}: {len(blob)} B sha256={got}")
        if a.sha256 and got != a.sha256.lower():
            print(f"ROZJEZIE SHA256: oczekiwano {a.sha256}", file=sys.stderr)
            return 4
        dt = time.time() - t0
        print(f"kanal: {len(blob) / 1e6 / max(dt, 0.001):.2f} MB/s w {dt:.1f} s")
        return 0

    # sciezka z manifestem
    print(f"pobieram manifest {a.manifest} z {a.branch}...")
    rc, txt = sh(['gh', 'api', f'repos/{a.repo}/contents/{a.manifest}?ref={a.branch}',
                  '--jq', '.content'])
    if rc != 0:
        print("BRACK manifestu (" + str(txt)[:160] + ")", file=sys.stderr)
        return 2
    man = base64.b64decode(txt.replace('\n', '')).decode('utf-8', 'replace')
    print(man)
    lines = [l for l in man.splitlines() if l.strip() and not l.startswith('#')]
    i = 0
    fails = 0
    while i < len(lines):
        parts = lines[i].split('\t')
        if len(parts) < 4:
            i += 1
            continue
        name, want_sha, size, nparts = parts[0], parts[1], int(parts[2]), int(parts[3])
        i += 1
        paths = []          # (sciezka, blob_sha albo None)
        for _ in range(nparts):
            if i < len(lines):
                ln = lines[i]; i += 1
                if '\t' in ln:
                    pth, bsh = ln.split('\t', 1)
                    paths.append((pth.strip(), bsh.strip()))
                else:
                    paths.append((ln.strip(), None))
        out = os.path.join(a.dest, name)
        if os.path.exists(out) and hashlib.sha256(open(out, 'rb').read()).hexdigest() == want_sha:
            print(f"  {name}: juz na dysku i sumy sie zgadzaja - pomijam")
            continue
        print(f"  {name}: {size} B z {len(paths)} czastek")
        blob = b''
        for p, bsha in paths:
            bsha = (bsha or '').strip()
            if not bsha:
                rc, t2 = sh(['gh', 'api', f'repos/{a.repo}/contents/{p}?ref={a.branch}',
                            '--jq', '.sha'])
                if rc != 0:
                    print(f"    BRACK sha dla {p}", file=sys.stderr); fails += 1; break
                bsha = t2.strip()
            data, err = fetch_blob(a.repo, bsha, binary=True)
            if data is None:
                print(f"    BLAD {p}: {err}", file=sys.stderr); fails += 1; break
            blob += data
            print(f"    {os.path.basename(p)}: +{len(data) / 1e6:.2f} MB "
                  f"= {len(blob) / 1e6:.2f}/{size / 1e6:.2f} MB")
        if len(blob) != size:
            print(f"    ROZJEZIE ROZMIARU: {len(blob)} != {size}", file=sys.stderr)
            fails += 1
            continue
        got = hashlib.sha256(blob).hexdigest()
        if got != want_sha:
            print(f"    ROZJEZIE SHA256: {got} != {want_sha} - NIE UZYWAJ", file=sys.stderr)
            fails += 1
            continue
        with open(out, 'wb') as f:
            f.write(blob)
        print(f"    OK -> {out} (sha256 potwierdzony)")
    dt = time.time() - t0
    print(f"\nsuma: {os.path.getsize(a.dest) if os.path.isdir(a.dest) else 0} B w {dt:.1f} s; "
          f"bledow: {fails}")
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
