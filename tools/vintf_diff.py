#!/usr/bin/env python3
"""Roznice VINTF: czego zadaja pliki /system a co dostarcza /vendor.

Po co. 'czy HyperOS 4 (A17) wstanie na vendorze epoki A12' nie jest pytania o opinie -
jest pytania o zbior etykiet. Framework trzyma wymogi w
/system/etc/vintf/compatibility_matrix*.xml, a urzadzenie odpowiada plikiem
/vendor/etc/vintf/manifest.xml (+ /vendor/etc/vintf/manifest/*.xml). init wstrzymuje
ladowanie, jesli BRAKUJE ktoregos obowiazkowego HAL-a, a 'obowiazkowy' znaczy
bez znacznika 'optional'. To liczymy.

Uzycie:
  # co wymaga framework A17 z obrazu zrodlowego:
  ./tools/vintf_diff.py --matrix images/system_assets/system/etc/vintf --report

  # czy vendor targetu to spelnia (manifest z adb, patrz scripts/collect_device_state.sh):
  ./tools/vintf_diff.py --matrix KATALOG_MACIERZY --manifest SCIEZKA_DO_MANIFESTU \
      --vendor-katalog KATALOG_Z_MANIFESTAMI

Kod 0 = brak brakow obowiazkowych, 1 = sa braki, 3 = nie ma czego czytac.
Format 'name@version' (HIDL) i 'name/V-version-service' (AIDL) ujednolicamy, bo
inaczej porownanie kamie.
"""
import argparse
import glob
import os
import re
import sys
import xml.etree.ElementTree as ET


def norm_fqname(name, ver, fq=None):
    """(nazwa, wersja) -> kanoniczny klucz porownania."""
    if fq:
        fq = fq.strip()
        m = re.match(r'^([^/]+)/([^:]+):(.+)$', fq)          # AIDL: pkg/if:version
        if m:
            return f"{m.group(1)}.{m.group(2)}@{m.group(3).lstrip('V')}"
        m = re.match(r'^(.+?)@(.*?)(?:/(.*))?$', fq)
        if m:
            v = (m.group(2) or '').lstrip('V')
            return f"{m.group(1)}@{v}" if v else m.group(1)
    ver = (ver or '').lstrip('V')
    return f"{name}@{ver}" if name and ver else (name or '?')


def collect_halset(path, tag='hal'):
    """{klucz: {'optional': bool, 'versions': [...]}} dla katalogu lub pliku."""
    files = []
    if os.path.isdir(path):
        for pat in ('**/*.xml',):
            files += glob.glob(os.path.join(path, pat), recursive=True)
    elif os.path.exists(path):
        files = [path]
    out = {}
    used = []
    for f in sorted(set(files)):
        base = os.path.basename(f)
        if tag == 'hal' and 'compatibility_matrix' not in base and base != 'manifest.xml' \
                and 'manifest' not in base:
            continue
        try:
            root = ET.parse(f).getroot()
        except ET.ParseError:
            continue
        except OSError:
            continue
        used.append(f)
        for h in root.iter(tag):
            name = (h.findtext('name') or '').strip()
            if not name:
                continue
            opt = (h.findtext('optional') or '').strip().lower() in ('true', '1')
            vers = [v.text for v in h.findall('version') if v.text]
            fqs = [q.text for q in h.findall('fqname') if q.text]
            keys = set()
            for fq in fqs:
                keys.add(norm_fqname(name, '', fq))
            for v in vers:
                keys.add(norm_fqname(name, v))
            if not keys:
                keys = {name}
            for k in keys:
                prev = out.get(k)
                out[k] = {'optional': (prev['optional'] if prev else False) and opt,
                          'src': os.path.basename(f),
                          'names': sorted(set((prev or {}).get('names', [])) | {name})}
    return out, used


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--matrix', help='katalog lub plik z compatibility_matrix*.xml')
    ap.add_argument('--manifest', help='katalog lub plik z manifestem vendora')
    ap.add_argument('--report', action='store_true', help='wypisz samo wymaganie (bez porownania)')
    ap.add_argument('--top', type=int, default=40)
    a = ap.parse_args()

    if not a.matrix:
        print("podaj --matrix (katalog z compatibility_matrix*.xml)"); return 3
    req, rfiles = collect_halset(a.matrix, 'hal')
    if not req:
        print(f"w {a.matrix} nie ma HAL-i do odczytania"); return 3
    mand = {k: v for k, v in req.items() if not v['optional']}
    opt = {k: v for k, v in req.items() if v['optional']}
    print(f"MACIERZ: {len(rfiles)} plik(6), pozycji HAL {len(req)} "
          f"(obowiazkowych {len(mand)}, opcjonalnych {len(opt)})")
    by_file = {}
    for k, v in req.items():
        by_file.setdefault(v['src'], set()).add(k.split('@')[0])
    for f in sorted(by_file):
        print(f"  {f:44s} unikalnych nazw: {len(by_file[f])}")

    if a.report or not a.manifest:
        print("\nOBOWIAZKOWE pozycje (pierwsze %d):" % a.top)
        for k in sorted(mand)[:a.top]:
            print(f"  {k}")
        print(f"  ... razem {len(mand)}")
        return 0

    got, gfiles = collect_halset(a.manifest, 'hal')
    if not got:
        print(f"W {a.manifest} nie znaleziono manifestu vendora (za malo plikow? adb root?)")
        return 3
    gnames = {k.split('@')[0] for k in got} | set(got)
    missing = sorted(k for k in mand if k not in got and k.split('@')[0] not in gnames)
    print(f"\nMANIFEST VENDORA: {len(gfiles)} plik(6), pozycji {len(got)}")
    print(f"BRAKI obowiazkowych: {len(missing)}")
    for k in missing[:60]:
        print(f"  - {k}")
    if len(missing) > 60:
        print(f"  ... i {len(missing)-60} dalej")
    extra = sorted(k for k in got if k not in req)
    print(f"Pozycje vendora nie wspominane w macierzy (bez znaczenia dla init): {len(extra)}")
    print("\nWYROK:", "VINTF SPOJNE - init nie stanie na HAL-u" if not missing
          else f"INIT STANIE: {len(missing)} obowiazkowych HAL-i brak - podmiana frameworka "
               "bezu tych HAL-i nie przejdzie")
    return 0 if not missing else 1


if __name__ == '__main__':
    sys.exit(main())
