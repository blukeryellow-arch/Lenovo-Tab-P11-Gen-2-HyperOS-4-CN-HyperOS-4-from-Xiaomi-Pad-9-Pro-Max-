#!/usr/bin/env python3
"""Sklada surowe czastki (RAW_MANIFEST.tsv) i weryfikuje do konca.

Strona agenta dla `tools/raw_parts_on_runner.sh`. Robi trzy rzeczy, ktorych nie da
sie pominac, jesli rezultat ma byt podstawa do budowania ROM-u:

1. per-czastkowa suma kontrolna (wylapuje uszkodzony blob po srodku sciezki),
2. kompletnosc zakresu (0..N-1; brakujacy numer = czastki z kolejnego biegu, nie
   skladamy polowy obrazu i nie udajemy, ze to dziala),
3. porownanie calosci z sha256 runnera ORAZ - jesli podano --md5 - z suma kontrolna
   serwera Google (z `list_files`/`get_file`), czyli dowod "to sa te same bajty co na
   Dysku", a nie tylko "runner i agent sie zgadzaja".

Uzycie:
  ./tools/assemble_raw_parts.py --parts KATALOG --out images/system.img \
      [--md5 e8248a9a...] [--expect-sha256 ...] [--keep-parts]
  ./tools/assemble_raw_parts.py --parts KATALOG --inventory diagnostics/drive-inventory.tsv
      # ten sam katalog dla WIELU obrazow: sklada kazdy i weryfikuje po inwentarzu
Kod 0 = plik zapisany i zgodny. 1 = rozbieznosc. 3 = niekompletny zakres.
"""
import argparse
import hashlib
import os
import re
import sys


def sha256_of(path, chunk=1 << 20):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(chunk), b''):
            h.update(b)
    return h.hexdigest()


def md5_of(path, chunk=1 << 20):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(chunk), b''):
            h.update(b)
    return h.hexdigest()


def read_manifests(part_files):
    """(naglowki {base: {...}}, czastki {base: {idx: (sciezka, rozmiar, sha)}})."""
    heads, parts = {}, {}
    for mp in part_files:
        cur = None
        for ln in open(mp, encoding='utf-8', errors='replace'):
            c = ln.rstrip('\n').split('\t')
            if c[0] == '# RAW v1' and len(c) >= 7:
                base, size, sha, total, frm, to = c[1], int(c[2]), c[3], int(c[4]), int(c[5]), int(c[6])
                cur = base
                heads[base] = {'size': size, 'sha256': sha, 'total': total,
                               'ranges': heads.get(base, {}).get('ranges', []) + [(frm, to)]}
                parts.setdefault(base, {})
                d = os.path.dirname(mp)
                # czastki moga lezec obok manifestu albo w katalogu nadrzednym (--parts)
                for cand in (d, os.path.dirname(d)):
                    if os.path.exists(os.path.join(cand, f'{base}.part.0000')):
                        parts[base]['_dir'] = cand
                        break
            elif c[0] == 'part' and cur and len(c) >= 4:
                name, size, sh = c[1], int(c[2]), c[3]
                m = re.search(r'\.part\.(\d+)$', name)
                if not m:
                    # Paczka <= 90 MB NIE jest dzielona (unpack_on_runner pisze wtedy
                    # 'part\t<ojciec>'), wiec 'nazwa bez .part.NNN' to nie smieci - to
                    # caly plik. Wczesniej 'continue' zgłaszalo 'brakuje 1 z 1' dla
                    # system/odm, choc plik lezal obok (sprawdzone 2026-09-23).
                    pp = os.path.join(parts[base].get('_dir', os.path.dirname(mp)), name)
                    if os.path.isfile(pp):
                        parts[base][0] = (pp, size, sh)
                    continue
                base = cur
                d = parts[base].get('_dir', os.path.dirname(mp))
                p = os.path.join(d, name)
                parts[base][int(m.group(1))] = (p, size, sh)
    for base in parts:
        parts[base].pop('_dir', None)
    return heads, parts


def assemble(base, head, idx, outpath, verify=True):
    total = head['total']
    have = sorted(idx)
    missing = [i for i in range(total) if i not in idx]
    if missing:
        print(f"  {base}: NIEKOMPLETNE - brakuje {len(missing)} z {total} czastek "
              f"(np. {missing[:6]}{'...' if len(missing) > 6 else ''})")
        print(f"    dopisz part_from/part_count do kolejnych biegow; na razie nie skladam")
        return 3
    if verify:
        for i in have:
            p, size, sh = idx[i]
            if not os.path.exists(p):
                print(f"  {base}: czastka {i} wskazana w manifest, ale nie ma pliku {p}")
                return 3
            got = os.path.getsize(p)
            if size >= 0 and got != size:
                print(f"  {base}: czastka {i} rozmiar {got} != manifest {size}")
                return 1
            if len(sh) == 64:
                got_sha = sha256_of(p)
                if got_sha != sh:
                    print(f"  {base}: czastka {i} sha256 NIEZGODNA z manifestem")
                    return 1
    os.makedirs(os.path.dirname(os.path.abspath(outpath)) or '.', exist_ok=True)
    with open(outpath, 'wb') as out:
        for i in have:
            with open(idx[i][0], 'rb') as f:
                while True:
                    b = f.read(1 << 22)
                    if not b:
                        break
                    out.write(b)
    sz = os.path.getsize(outpath)
    if head['size'] >= 0 and sz != head['size']:
        print(f"  {base}: rozmiar zlozony {sz} != {head['size']} (manifest)")
        return 1
    full = sha256_of(outpath)
    if head['sha256'] and full != head['sha256']:
        print(f"  {base}: sha256 calosci NIEZGODNY z runnerem ({full[:16]}... vs {head['sha256'][:16]}...)")
        return 1
    sk = 'ZGODNY z runnerem' if head['sha256'] else 'bez opisu runniera - o wartosci decyduje md5 Dysku'
    print(f"  {base}: zapisano {sz} B, sha256={full[:24]}... {sk}")
    return 0


def adopt_orphans(parts_dir, heads, parts):
    # 'drive-<id>.img.part.NNNN' bez wpisu w manifescie i tak da sie zlozyc.
    # Bieg 35892866524 zgubil dwa manifesty (kasowany bufor 'raw/'), zostawiajac
    # czastki na spoolu. Inwentarz Dysku ma rozmiar i md5 Googlea, wiec weryfikacja
    # jest caly czas skonczona - nie odrzucamy danych tylko dlatego, ze opis zniknal.
    import glob
    for f in sorted(glob.glob(os.path.join(parts_dir, '**', '*.part.*'), recursive=True)):
        m = re.search(r'^(.*)\.part\.(\d+)$', os.path.basename(f))
        if not m:
            continue
        base, idx = m.group(1), int(m.group(2))
        if base in parts and idx in parts.get(base, {}):
            continue
        if base not in heads:
            heads[base] = {'size': -1, 'sha256': '', 'total': -1, 'ranges': [], 'z_orfana': True}
            parts.setdefault(base, {})
            print(f"  {base}: brak opisu w manifescie - skladam z samych czastek, "
                  f"weryfikacja po inwentarzu Dysku")
        parts[base][idx] = (f, os.path.getsize(f), '')
    for base, h in heads.items():
        if h.get('z_orfana') and h['total'] < 0:
            h['total'] = len(parts[base])
    return heads, parts


def resolve_name(base, inv):
    # Runner nie zna nazwy pliku (metadane Drive ida przez 403 bez klucza API), wiec
    # plik nazywa sie 'drive-<ID>.img'. Inwentarz ma ID -> odzyskujemy 'boot.img' itd.
    m = re.match(r'^drive-([A-Za-z0-9_-]{20,})\.img$', base)
    if m:
        for nm, row in inv.items():
            if row.get('id') == m.group(1):
                return nm
    for nm, row in inv.items():
        if row.get('size', -1) == -1:
            continue
    return base


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--parts', required=True, help='katalog z RAW_MANIFEST.tsv i czastkami')
    ap.add_argument('--out', default='')
    ap.add_argument('--md5', default='')
    ap.add_argument('--expect-sha256', default='')
    ap.add_argument('--inventory', default='', help='diagnostics/drive-inventory.tsv - sklada i weryfikuje wszystko naraz')
    ap.add_argument('--keep-parts', action='store_true')
    a = ap.parse_args()

    # kazdy bieg dopisal wlasny plik (RAW_MANIFEST-<run>.tsv) - inaczej nadpisalby
    # manifest poprzedniego zakresu i czastki zostalyby bez opisow
    manifests = sorted(os.path.join(dp, f) for dp, _, fs in os.walk(a.parts) for f in fs
                       if f.startswith('RAW_MANIFEST') and f.endswith('.tsv'))
    if not manifests:
        print(f"w {a.parts} nie ma RAW_MANIFEST*.tsv - najpierw sciagnij kawalki z galazi transfer-spool")
        return 2
    heads, parts = read_manifests(manifests)
    heads, parts = adopt_orphans(a.parts, heads, parts)
    if not heads:
        print("manifest pusty lub w innym formacie (oczekuje '# RAW v1')")
        return 2
    print(f"katalog {a.parts}: {len(heads)} obraz(y), "
          f"sumy partii: {sum(len(p) for p in parts.values())}")

    rc = 0
    if a.inventory:
        inv = {}
        for ln in open(a.inventory, encoding='utf-8'):
            if ln.startswith('#') or not ln.strip():
                continue
            c = ln.rstrip('\n').split('\t')
            if len(c) >= 4:
                inv[c[0]] = {'size': int(c[2]), 'md5': c[3], 'id': c[1]}
        for base in sorted(heads):
            tgt = resolve_name(base, inv)
            r = assemble(base, heads[base], parts[base], os.path.join('images', tgt))
            if r == 0 and tgt in inv:
                exp_sz = inv[tgt].get('size', -1)
                got_sz = os.path.getsize(os.path.join('images', tgt))
                if exp_sz >= 0 and got_sz != exp_sz:
                    print(f"    rozmiar {got_sz} != {exp_sz} podany przez Google -> ODRZUCONE")
                    rc = 1
                    continue
                m = md5_of(os.path.join('images', tgt))
                exp = inv[tgt]['md5']
                same = (m == exp)
                print(f"    vs Google: md5 {m[:12]}... vs {exp[:12]}... -> "
                      f"{'TE SAME BAJTY CO NA DYSKU' if same else 'ROZBIEZNOSC'}")
                if not same:
                    rc = 1
            rc = rc or r
    else:
        if not a.out:
            print("--out wymagany, gdy nie podano --inventory")
            return 2
        base = os.path.basename(a.out)
        # 28 IX (utrwalone po incydencie na sandboxie): --out o nazwie niebedacej baza
        # w manifeście NIE MOZE skladac "pierwszego z brzegu" - wlasnie tak pod
        # /tmp/rom-kit2.tar.gz zlozyl sie obraz o sha 7340a836 (system_ext) zamiast
        # kitu 537eb4ea; uratowal dopiero --expect-sha256. Od teraz: przy
        # --expect-sha256 baza wybierana wg sumy (jednoznacznie albo twardy blad).
        basename_ok = base in heads and (not a.expect_sha256
                                         or heads[base].get('sha256') == a.expect_sha256)
        if not basename_ok and a.expect_sha256:
            cands = [b for b in sorted(heads) if heads[b].get('sha256') == a.expect_sha256]
            if len(cands) == 1:
                print(f"  (nazwa --out nie jest baza w manifeście; --expect-sha256 "
                      f"jednoznacznie wskazuje '{cands[0]}' - skladam ja)")
                base = cands[0]
            elif not cands:
                print("  FATAL: --expect-sha256 nie pasuje do ZADNEJ bazy w manifestach.")
                print("  dostepne bazy (nazwa = sha256 z manifestu):")
                for b in sorted(heads):
                    print(f"    {b} = {heads[b].get('sha256', '?') or '(brak)'}")
                print("  nie skladam nic - popraw --expect-sha256 albo wybierz --out po nazwie bazy")
                return 2
            else:
                print(f"  FATAL: --expect-sha256 pasuje do wielu baz: {cands} - wybierz --out po nazwie")
                return 2
        elif base not in heads:
            base = sorted(heads)[0]
            print(f"  (w manifescie jest '{base}', nie '{os.path.basename(a.out)}' - skladam pierwszy)")
        r = assemble(base, heads[base], parts[base], a.out)
        rc = r
        if r == 0:
            if a.expect_sha256:
                got = sha256_of(a.out)
                if got != a.expect_sha256:
                    print(f"  --expect-sha256 NIEZGODNY: {got}")
                    rc = 1
            if a.md5:
                got = md5_of(a.out)
                good = (got == a.md5)
                print(f"  md5 vs Google: {got} -> {'ZGODNY' if good else 'NIEZGODNY'}")
                if not good:
                    rc = 1
    if rc == 0 and not a.keep_parts:
        print("  (czastki zostawione - usun recznie po weryfikacji: rm parts/*.part.*)")
    print("SKLADANIE:", "OK" if rc == 0 else ("NIEKOMPLETNE" if rc == 3 else "BLAD"))
    return rc


if __name__ == '__main__':
    sys.exit(main())
