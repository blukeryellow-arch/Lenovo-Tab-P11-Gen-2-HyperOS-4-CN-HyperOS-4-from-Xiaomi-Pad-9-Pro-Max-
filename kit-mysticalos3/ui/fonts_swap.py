#!/usr/bin/env python3
"""Zamiana Roboto -> MiSans w /system/etc/fonts.xml (HyperOS Typography).
args: <sysroot> <workdir>   (uruchamiac z sudo na drzewie sysroota)
- przetwarza rodziny sans-serif* (BEZ condensed - zostaje Roboto Condensed),
- mapuje wagi: 300->Light 400->Regular 500->Medium 600->Medium 700/800/900->Bold,
- usuwa <axis> z podmienionych wpisow (MiSans statyczne = bez osi),
- backup oryginalu do <workdir>/fonts.xml.stock (POZA obrazem),
- twarda weryfikacja: XML parsuje sie + wszystkie wskazane pliki istnieja.
"""
import os
import shutil
import sys
import xml.etree.ElementTree as ET

S, W = sys.argv[1], sys.argv[2]
fx = os.path.join(S, 'etc/fonts.xml')
assert os.path.isfile(fx), 'brak etc/fonts.xml w sysroot!'

WMAP = {300: 'Light', 400: 'Regular', 500: 'Medium',
        600: 'Medium', 700: 'Bold', 800: 'Bold', 900: 'Bold'}

tree = ET.parse(fx)
root = tree.getroot()
replaced = []
for fam in root.findall('family'):
    name = fam.get('name')
    if not name or not name.startswith('sans-serif') or 'condensed' in name:
        continue
    for font in fam.findall('font'):
        w = int(font.get('weight', '400'))
        txt = (font.text or '').strip()
        if 'Roboto' not in txt:
            continue
        wname = WMAP.get(w)
        if wname is None:
            continue
        fn = f'MiSans-{wname}.ttf'
        if not os.path.exists(os.path.join(S, 'fonts', fn)):
            continue
        font.text = fn
        for ax in list(font):
            font.remove(ax)
        replaced.append(f'{name}[{w}/{font.get("style", "normal")}]: {txt} -> {fn}')

assert len(replaced) >= 6, f'fonts.xml: zastapiono tylko {len(replaced)} wpisow (oczekiwano >= 6)!'
shutil.copy2(fx, os.path.join(W, 'fonts.xml.stock'))
try:
    ET.indent(tree, space='    ')
except AttributeError:
    pass
tree.write(fx, encoding='utf-8', xml_declaration=True)

# twarda weryfikacja: cale fonts.xml parsuje sie, wszystkie pliki istnieja
root2 = ET.parse(fx).getroot()
missing = []
for fam in root2.findall('family'):
    for font in fam.findall('font'):
        f = (font.text or '').strip()
        if f and not f.startswith('/') and not os.path.exists(os.path.join(S, 'fonts', f)):
            missing.append(f)
assert not missing, f'fonts.xml wskazuje nieistniejace pliki: {missing}'
print(f'fonts.xml: MiSans jako sans-serif ({len(replaced)} wpisow):')
for r in replaced:
    print('  ', r)
