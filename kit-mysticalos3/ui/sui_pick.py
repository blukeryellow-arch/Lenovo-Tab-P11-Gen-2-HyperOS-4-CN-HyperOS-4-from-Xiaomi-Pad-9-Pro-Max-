#!/usr/bin/env python3
"""Introspekcja zasobow stockowego SystemUI (aapt2 dump resources).
args: <uidir>  (czyta sui-res.txt, pisze sui-dimens.xml + sui-found.txt)
Wybiera dimeny z 'corner' w nazwie (bez animation/corner_path) -> nadpis 24dp
(HyperOS-style zaokraglenia paneli QS/glosnosci). Zero trafien = overlay #2
SystemUI jest pomijany (workflow to obsluguje).
"""
import re
import sys

d = sys.argv[1]
names = set()
for ln in open(f'{d}/sui-res.txt', encoding='utf-8', errors='ignore'):
    m = re.match(r'\s*(?:EW\s+)?resource\s+0x[0-9a-fA-F]+\s+dimen/(\S+)', ln)
    if m:
        n = m.group(1)
        nl = n.lower()
        if ('corner' in nl and len(n) < 48
                and 'animation' not in nl and 'corner_path' not in nl):
            names.add(n)
names = sorted(names)
with open(f'{d}/sui-dimens.xml', 'w') as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n')
    for n in names:
        f.write(f'    <dimen name="{n}">24.0dp</dimen>\n')
    f.write('</resources>\n')
open(f'{d}/sui-found.txt', 'w').write('\n'.join(names))
print('SystemUI dimen-y corner do nadpisania:', len(names), names[:16])
