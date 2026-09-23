#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Wypisuje cel nakladek RRO (targetPackage) z binarnego AndroidManifest.xml.

Po co: nadpisanie resource'u przez RRO dziala WYLACZNIE jesli pakiet-docel istnieje na
urzadzeniu i jesli RRO moze byc do niego doczepione (uprawnienia + podpis). 'unzip -p … res/
values.xml' nic tu nie da (auto-RRO nie ma res/values.xml - patrz tools/extract_rro_values.sh),
a resources.arsc wymaga pelnego parsera. AXML jest prosty: naglowek, pula stringow,
START_ELEMENT (0x0102) z atrybutami jako indeksami do puli.

Ograniczenie, ktore sam o sobie mowie: czytam 'android:name' / '<overlay>' jako pary
(atak-nazwa, wartosc-string). Jezeli APK deklaruje target przez <resource-overlay> w innym
tagu, dostane pusty cel i to zglosze jako 'BRAK', a nie sprobuje zgadywac.

użycie: tools/rro_targets.py <katalog-z-apk> [--json] [--znane]
"""
import os
import re
import struct
import subprocess
import sys
import zipfile

RES_XML_TYPE = 0x0003
RES_STRING_POOL_TYPE = 0x0001
RES_XML_START_ELEMENT_TYPE = 0x0102
RES_XML_END_ELEMENT_TYPE = 0x0103


def string_pool(d, off):
    """(lista stringow, koniec chunku). UTF-16 i UTF-8 obsluzone."""
    typ, hdr, size = struct.unpack_from('<HHI', d, off)
    assert typ == RES_STRING_POOL_TYPE, f'spul nie jest pula stringow (0x{typ:04x})'
    count, _styled, flags, _smin, sofs = struct.unpack_from('<IIIII', d, off + 8)
    data_start = off + hdr + count * 4
    utf8 = bool(flags & (1 << 8))
    out = []
    for i in range(count):
        o = struct.unpack_from('<I', d, off + 20 + i * 4)[0]
        p = data_start + o
        if utf8:
            def dec(b):
                n = b[p]
                if n & 0x80:
                    n = ((n & 0x7f) << 8) | b[p + 1]
                    p2 = p + 2
                else:
                    p2 = p + 1
                ln = b[p2]
                if ln & 0x80:
                    ln = ((ln & 0x7f) << 8) | b[p2 + 1]
                    p2 += 1
                return b[p2:p2 + ln].decode('utf-8', 'replace')
            out.append(dec(d))
        else:
            n = struct.unpack_from('<H', d, p)[0]
            if n & 0x8000:
                n = ((n & 0x7fff) << 16) | struct.unpack_from('<H', d, p + 2)[0]
                p += 4
            else:
                p += 2
            out.append(d[p:p + n * 2].decode('utf-16-le', 'replace'))
    return out, off + size


def manifest_from(apk):
    with zipfile.ZipFile(apk) as z:
        names = [n for n in z.namelist() if n == 'AndroidManifest.xml']
        if not names:
            return None
        return z.read('AndroidManifest.xml')


def scan_all(d, start, pool):
    out = {'package': None, 'targetPackage': [], 'targetName': [], 'priority': [],
            'requiredOverlayPolicy': [], 'isStatic': [], 'tags': []}
    off = start
    while off + 8 <= len(d):
        typ, _h, size = struct.unpack_from('<HHI', d, off)
        if size < 8 or off + size > len(d):
            break
        if typ == RES_XML_START_ELEMENT_TYPE:
            _line, _cmt, _ind, ns, name = struct.unpack_from('<IIIII', d, off + 4)
            astart, asize, acount, aidxs, avalues = struct.unpack_from('<HHHHI', d, off + 28)
            attrs = {}
            for i in range(acount):
                base = off + aidxs + i * 20
                ans, aname, avalue = struct.unpack_from('<III', d, base)
                raw = d[base + 16:base + 24]
                vtype = raw[0] if raw else 0
                key = pool[aname] if aname < len(pool) else f'#{aname}'
                val = pool[avalue] if 0 <= avalue < len(pool) else None
                attrs[key] = val
            tag = pool[name] if name < len(pool) else '?'
            out['tags'].append(tag)
            if tag == 'manifest':
                out['package'] = attrs.get('package')
            for k in ('targetPackage', 'targetName', 'priority',
                      'requiredOverlayPolicy', 'isStatic'):
                if k in attrs and attrs[k] is not None:
                    out[k].append(attrs[k])
        off += size
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    as_json = '--json' in sys.argv
    if not args:
        print(__doc__)
        return 3
    root = args[0]
    apks = []
    for dirpath, _dirs, files in os.walk(root):
        for f in files:
            if f.lower().endswith('.apk'):
                apks.append(os.path.join(dirpath, f))
    apks.sort()
    if not apks:
        print(f"  BRAK APK w {root}")
        return 3
    rows = []
    for a in apks:
        try:
            info = scan_apk(a)
        except Exception as e:                              # noqa: BLE001
            info = {'err': f'{type(e).__name__}: {e}'}
        info['apk'] = os.path.relpath(a, root)
        rows.append(info)
    if as_json:
        import json
        print(json.dumps(rows, ensure_ascii=False, indent=1))
        return 0
    from collections import Counter
    ct = Counter()
    errn = 0
    for r in rows:
        if r.get('err'):
            errn += 1
            continue
        for t in (r.get('targetPackage') or [r.get('package') or '?']):
            ct[t] += 1
    print(f"  APK: {len(rows)}  z bledem parsera: {errn}")
    print("  pakiet-docelowy (targetPackage) x liczba nakladek:")
    for t, n in ct.most_common():
        print(f"    {n:3d}  {t}")
    print("  (jezeli tu wchodzi tylko 'package' bez targetPackage, plik NIE jest <overlay> - "
          "czyli to zwykly APK, nie RRO)")
    return 0


def scan_apk(apk):
    d = manifest_from(apk)
    if not d or len(d) < 16:
        return {'err': 'brak AndroidManifest.xml'}
    typ, _h, _s = struct.unpack_from('<HHI', d, 0)
    if typ != RES_XML_TYPE:
        return {'err': f'nie AXML 0x{typ:04x}'}
    pool, off = string_pool(d, 8)
    return scan_all(d, off, pool)


if __name__ == '__main__':
    sys.exit(main())
