#!/usr/bin/env python3
"""Macierz zgodnosci VINTF dla warstwy gościa DSU, z inwentarza HAL hosta.

Zrodlo inwentarza: diagnostics/logs/host-hal-inventory-v14.tsv - EKSTRAKCJA z
bugreport_v14 (Drive; lshal 'HARDWARE HALS' dla HIDL + service list dla AIDL).
To jest 'full compatibility matrix via log extraction': macierz poziomu N
opisuje DOKLADNIE to, co vendor hosta (Lenovo TB350FU, A14) realnie dostarcza.

Zasada bezpieczenstwa (receipt: gosc v14 zyl 42 min przy optional-missing,
a sciana 'Failed to initialize VINTF' pada tylko na wymagania NIESPELNIONE):
KAZDY wpis ma optional="true" - macierz jest pelna informacyjnie (pelny
inwentarz hosta), ale niczego nie egzekwuje. To jest jednoczesnie literalne
'bypass strict dynamic vendor-interface matching': zero strict wpisow =
zero mozliwosci paniki inita na niedopasowanym srodowisku A14.

Robi tez macierze dla poziomow 4 i 6 (ten sam inwentarz) - kit-era generowal
je 'na wszelki wypadek'; make_release i tak szanuje istniejacy plik
('nie dotkniety'), wiec pre-placed macierze trafiaja do obrazu bez zmian.

Uzycie:
  tools/make_host_matrix.py --inventory diagnostics/logs/host-hal-inventory-v14.tsv \
      --vintf-dir SCIEZKA/etc/vintf [--levels 4,5,6] [--dry-run]

Kod 0 = macierze zapisane (lub wypisane przy --dry-run) i sparsowane jako XML.
"""
import argparse
import collections
import sys
import xml.dom.minidom as minidom

HEADER = """<!--
  Macierz zgodnosci z inwentarza HAL HOSTA (ekstrakcja z bugreport_v14, Drive).
  Zrodlo: diagnostics/logs/host-hal-inventory-v14.tsv
  (bugreport-TB350FU_EEA-...-2026-09-28-15-20-24.txt, sha256 c664f57e...;
   lshal 'HARDWARE HALS' -> HIDL, service list -> AIDL).
  Kazdy wpis optional="true" (postawa v1+: zadne wymaganie nie jest egzekwowane
  na vendorze z innej epoki - to otwiera bramke VINTF bez ryzyka 'Failed to
  initialize VINTF'). Macierz jest pelnym OPISEM srodowiska DSU-guesta:
  system Xiaomi + vendor Lenovo A14 + inwentarz z logu.
-->"""


def read_inventory(path):
    """(format, name) -> {versions: set, interfaces: {iface: set(instances)}}"""
    groups = collections.defaultdict(
        lambda: {"versions": set(), "interfaces": collections.defaultdict(set)})
    n = 0
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        fmt, name, versions, iface, instances, _src = line.split("\t")
        g = groups[(fmt, name)]
        for v in versions.split(";"):
            if v:
                g["versions"].add(v)
        g["interfaces"][iface].update(i for i in instances.split(";") if i)
        n += 1
    return groups, n


def vkey(v):
    return tuple(int(x) for x in v.split("."))


def build_xml(groups, level):
    out = [HEADER, '<compatibility-matrix version="9.0" type="framework" level="%d">' % level]
    for (fmt, name) in sorted(groups, key=lambda k: (k[1], k[0])):
        g = groups[(fmt, name)]
        out.append('    <hal format="%s" optional="true">' % fmt)
        out.append('        <name>%s</name>' % name)
        for v in sorted(g["versions"], key=vkey):
            out.append('        <version>%s</version>' % v)
        for iface in sorted(g["interfaces"]):
            out.append('        <interface>')
            out.append('            <name>%s</name>' % iface)
            for inst in sorted(g["interfaces"][iface]):
                out.append('            <instance>%s</instance>' % inst)
            out.append('        </interface>')
        out.append('    </hal>')
    out.append('</compatibility-matrix>')
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--inventory", required=True)
    ap.add_argument("--vintf-dir", help="katalog etc/vintf drzewa systemu (zapis w miejsce)")
    ap.add_argument("--levels", default="4,5,6")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    groups, n = read_inventory(args.inventory)
    if not groups:
        print("pusty inwentarz", file=sys.stderr)
        return 1
    levels = [int(x) for x in args.levels.split(",") if x.strip()]
    written = []
    for lvl in levels:
        xml = build_xml(groups, lvl)
        minidom.parseString(xml)  # twarda bramka: zly XML = kod != 0
        if args.dry_run or not args.vintf_dir:
            print("=== level %d (%d wpisow hal) ===" % (lvl, len(groups)))
            print(xml)
        else:
            path = "%s/compatibility_matrix.%d.xml" % (args.vintf_dir.rstrip("/"), lvl)
            open(path, "w", encoding="utf-8").write(xml)
            written.append((path, len(xml)))
    for p, s in written:
        print("zapisano %s (%d B, hal=%d, wpisy inwentarza=%d)" % (p, s, len(groups), n))
    # sanity: kluczowe HAL-e dla tego portu MUSZA byc w macierzy
    names = {k[1] for k in groups}
    for must in ("android.hardware.graphics.composer",
                 "android.hardware.graphics.allocator",
                 "android.hardware.security.keymint"):
        if must not in names:
            print("BRAK kluczowego HAL w inwentarzu: %s" % must, file=sys.stderr)
            return 1
    print("kluczowe HAL-e (composer/allocator/keymint): OBECNE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
