#!/usr/bin/env python3
"""sepolicy_patch.py - avc denied z logcatu -> per-domain permissive / allow do CIL.

Kontekst: nasz system to REPACK binarki Xiaomi (nie kompilacja ze zrodel), a
flashujemy wylacznie system+vbmeta - wiec androidboot.selinux=permissive z
cmdline (boot/vendor_boot, wlasciciel: Lenovo) jest nieosiagalny. Za to:
  - system/etc/selinux/plat_sepolicy.cil to TEKST w naszym obrazie,
  - przy systemie Xiaomi + vendorze Lenovo hashe precompiled_sepolicy sie NIE
    zgadzaja, wiec init i tak kompiluje polityke z CIL przy pierwszym boocie
    (treble) - dopisane regulacje WEJDĄ w zycie bez dotykania precompiled.

Tryby:
  ./sepolicy_patch.py parse <logcat.txt>            # wypisz domeny i regulacje
  ./sepolicy_patch.py parse <log.txt> --allow       # zamiast permissive: allow per para
  ./sepolicy_patch.py inject <cil> <logcat.txt>     # dopisz blok do plat_sepolicy.cil

Dlaczego domyslnie (permissive <domena>) a nie (allow ...):
  - permissive nie koliduje z neverallow (allow moglby odrzucic cala polityke
    przy kompilacji = gorszy bootloop niz byl),
  - efekt rowny lokalnemu permissive dla tej domeny, bez rozpieczania calego
    systemu; audyt dalej loguje naruszenia (widac w logcat, mozna zawezic pozniej).
"""
import re
import sys

AVC = re.compile(
    r'avc:\s+denied\s+\{([^}]+)\}\s+for\s+.*?'
    r'scontext=u:(?:r|object_r):(\S+?):\S+\s+'
    r'tcontext=u:(?:r|object_r):(\S+?):\S+\s+'
    r'tclass=(\S+)',
)


def parse(text):
    hits = []
    for m in AVC.finditer(text):
        perms = [p.strip() for p in m.group(1).split() if p.strip()]
        hits.append((m.group(2), m.group(3), m.group(4), perms))
    return hits


def gen(hits, allow=False):
    lines = []
    if allow:
        for s, t, c, perms in sorted(set(hits)):
            lines.append('(allow %s %s (%s (%s)))'
                         % (s, t, c, ' '.join(perms)))
    else:
        doms = sorted({s for s, _, _, _ in hits})
        lines = ['(permissive %s)' % d for d in doms]
    return lines


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        return 2
    mode, a = args[0], args[1]
    if mode == 'parse':
        allow = '--allow' in args[2:]
        hits = parse(open(a, encoding='utf-8', errors='replace').read())
        if not hits:
            print('brak linii avc: denied w logu')
            return 1
        print('# %d naruszen, %d domen' % (len(hits), len({h[0] for h in hits})))
        for line in gen(hits, allow):
            print(line)
        return 0
    if mode == 'inject' and len(args) >= 3:
        cil, log = a, args[2]
        hits = parse(open(log, encoding='utf-8', errors='replace').read())
        if not hits:
            print('brak avc w logu - nie ma czego wstrzykiwac')
            return 1
        body = gen(hits)
        cur = open(cil, encoding='utf-8', errors='replace').read()
        if ';;; arena-permissive-patch' in cur:
            print('blok juz istnieje - najpierw usun starego')
            return 1
        with open(cil, 'a', encoding='utf-8') as fh:
            fh.write('\n;;; arena-permissive-patch (auto z logcatu; usun po zawazeniu)\n')
            for line in body:
                fh.write(line + '\n')
        print('dopisano %d regulacji do %s' % (len(body), cil))
        return 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main())
