#!/usr/bin/env python3
"""Dobor fontow + generowanie fonts.xml dla modulu (Lenovo Tab P11 Gen 2 <- HyperOS 4).

Dlaczego osobny plik, a nie heredoc w bashu: zagniezdzanie '<<PY' w '<<PY' ucinalo
skrypt po cichu (zmierzone 2026-09-23 - 'SyntaxError: unterminated triple-quoted').

Zasady, ktore tu siedza (wszystkie wyprowadzone z pomiarow, nie z opisow):
  * FontListParser (AOSP) akceptuje <family> tylko z atrybutem 'name' albo 'lang'.
    Rodzina bez obu jest odrzucana po cichu - wiec kazdy font trafia albo do rodziny
    nazwanej (sans-serif/serif/monospace), albo do rodziny jezykowej, albo NIE trafia.
  * W zrodlowym HyperOS 4 '/system/etc/fonts.xml' i 'font_fallback.xml' to SYMLINKI do
    '/data/system/fonts/theme_webview/...' (motyw Xiaomi). Kopia tego pliku na tablecie
    Lenovo wolalaby sie o sciezki, ktorych tam nie ma - dlatego plik jest GENEROWANY.
  * '/system/fonts/*.ttf' w HyperOS to w duzej mierze symlinki do '/product/fonts/...'
    (np. MiSansLatinVF.ttf) - realne bajty sa w image 'product', nie 'system'.
  * Bajty weryfikowane sygnatura (00 01 00 00 / OTTO / ttcf), nie rozszerzeniem.
"""
import os
import re
import struct
import sys
import glob
import shutil

MAGIC = {b'\x00\x01\x00\x00': 'ttf', b'OTTO': 'otf', b'ttcf': 'ttc', b'true': 'ttc-old'}
LANG = [('TraditionalChinese', 'zh-Hant'), ('SimplifiedChinese', 'zh-Hans'), ('Taiwan', 'zh-TW'),
        ('Hongkong', 'zh-HK'), ('Chinese', 'zh-Hans'), ('Japanese', 'ja-JP'), ('Korean', 'ko-KR'),
        ('Arabic', 'ar'), ('Hebrew', 'iw-IL'), ('Persian', 'fa-IR'), ('Urdu', 'ur-PK'),
        ('Thai', 'th-TH'), ('Devanagari', 'hi-IN'), ('Bengali', 'bn-BD'), ('Gurmukhi', 'pa-IN'),
        ('Gujarati', 'gu-IN'), ('Odia', 'or-IN'), ('Tamil', 'ta-IN'), ('Telugu', 'te-IN'),
        ('Kannada', 'kn-IN'), ('Malayalam', 'ml-IN'), ('Sinhala', 'si-LK'), ('Sinhalese', 'si-LK'),
        ('Myanmar', 'my-MM'), ('Khmer', 'km-KH'), ('Lao', 'lo-LA'), ('Tibetan', 'bo'),
        ('Ethiopic', 'am-ET'), ('Cherokee', 'chr'), ('Georgian', 'ka-GE'), ('Armenian', 'hy-AM'),
        ('Nepali', 'ne-NP'), ('Thai', 'th-TH')]
WEIGHTS = [('ExtraBold', 800), ('Semibold', 600), ('SemiBold', 600), ('ExtraLight', 200),
           ('Thin', 100), ('Light', 300), ('Medium', 500), ('Bold', 700), ('Black', 900),
           ('Regular', 400), ('Book', 350)]


def wt(n):
    for k, v in WEIGHTS:
        if k.lower() in n.lower():
            return v
    return 400


def isitalic(n):
    return 'italic' in n.lower()


def has(n, *keys):
    return any(k.lower() in n.lower() for k in keys)


def scan(src):
    out = []
    for p in sorted(glob.glob(os.path.join(src, '**', '*'), recursive=True)):
        if os.path.islink(p):
            continue
        if not os.path.isfile(p):
            continue
        if not re.search(r'\.(ttf|otf|ttc)$', p, re.I):
            continue
        try:
            with open(p, 'rb') as f:
                head = f.read(4)
        except OSError as e:
            print(f"  czytam {os.path.basename(p)}: {e} - odpuszczam")
            continue
        kind = MAGIC.get(head)
        if not kind:
            print(f"  odrzucam {os.path.basename(p)}: bajty startowe {head!r} to nie font")
            continue
        sz = os.path.getsize(p)
        if sz < 1024:
            print(f"  odrzucam {os.path.basename(p)}: {sz} B to nie font")
            continue
        out.append((p, os.path.basename(p), kind, sz))
    return out



def coverage(path):
    """(liczba_kodow, czy_lacina, czy_CJK) z cmap. None jesli plik nie jest sfnt.

    Po co: w HyperOS 4 w product/fonts obok pelnego MiSansVF.ttf (20 MB, 29 572
    kodow, 20 976 CJK) leza 'LatinVF' (1 337 kodow, CJK=0) i 'MiSerif.ttf'
    (14 kodow - zakladka demo). Generator sortowal po nazwie i wybral LatinVF
    jako sans-serif, a MiSerif jako serif: UI bez chińskich glifow w rodzinie
    podstawowej. Pomiar cmap jest rozstrzygajacy, nazwa nie (2026-09-23)."""
    try:
        d = open(path, 'rb').read()
    except OSError:
        return None
    if d[:4] not in (b'\x00\x01\x00\x00', b'OTTO', b'true', b'ttcf'):
        return None
    try:
        n, = struct.unpack_from('>H', d, 4)
        off_cmap = None
        for i in range(n):
            tag = d[12 + i * 16:16 + i * 16]
            o, _ = struct.unpack_from('>II', d, 20 + i * 16)
            if tag == b'cmap':
                off_cmap = o
        if off_cmap is None:
            return (0, False, False)
        rc, = struct.unpack_from('>H', d, off_cmap + 2)
        cps = set()
        for i in range(rc):
            _, _, so = struct.unpack_from('>HHI', d, off_cmap + 4 + i * 8)
            fmt, = struct.unpack_from('>H', d, off_cmap + so)
            if fmt == 4:
                seg2, = struct.unpack_from('>H', d, off_cmap + so + 6)
                sc = seg2 // 2
                ends = [struct.unpack_from('>H', d, off_cmap + so + 14 + j * 2)[0] for j in range(sc)]
                starts = [struct.unpack_from('>H', d, off_cmap + so + 16 + seg2 + j * 2)[0] for j in range(sc)]
                for a, b in zip(starts, ends):
                    if b > a:
                        cps.update(range(a, min(b, 0xFFFF) + 1))
            elif fmt == 12:
                ng, = struct.unpack_from('>I', d, off_cmap + so + 12)
                for j in range(ng):
                    a, b, _ = struct.unpack_from('>III', d, off_cmap + so + 16 + j * 12)
                    cps.update(range(a, min(b, 0x10FFFF) + 1))
        lat = any(0x41 <= c <= 0x7A for c in cps)
        cjk = any(0x4E00 <= c <= 0x9FFF for c in cps)
        return (len(cps), lat, cjk)
    except (struct.error, IndexError):
        return None


def build(src, out, family='MiSans', primary='', maxf=48):
    cand = scan(src)
    print(f"  plikow ze sygnatura fontu: {len(cand)} (katalog: {src})")
    if not cand:
        print("  FATAL: w tym katalogu nie ma zadnego pliku z sygnatura TTF/OTF/TTC")
        return 3
    fam_pool = [c for c in cand if c[1].lower().startswith(family.lower())]
    # Ranża: glownym fontem sans-serif NIE moze zostac font skryptowy (Arabic/CJKjp/Thai).
    # Bez tego sortowanie alfabetyczne dawalo 'MiSansArabic.ttc' jako regularny sans-serif
    # (test B, 2026-09-23) - caly UI dostalby glify arabskie zamiast laciny.
    SCRIPTY = ('Arabic', 'Hebrew', 'Thai', 'Devanagari', 'Bengali', 'Gurmukhi', 'Gujarati',
               'Odia', 'Tamil', 'Telugu', 'Kannada', 'Malayalam', 'CJK', 'Japanese', 'Korean',
               'Sinhala', 'Myanmar', 'Khmer', 'Lao', 'Ethiopic', 'Armenian', 'Georgian')
    def rank(c):
        n = c[1]
        script = any(k.lower() in n.lower() for k in SCRIPTY)
        latin = ('Latin' in n) or ('Roman' in n)
        plain = bool(re.search(r'(Regular|Medium|Semibold|Bold|Light|Thin|Book)', n, re.I))
        cv = coverage(c[0]) or (0, False, False)
        # 'pelny font' = ma i lacine, i CJK, i >= 5000 kodow. To jest glowne kryterium
        # sans-serif, a nie napis 'Latin' w nazwie (patrz docstring coverage()).
        pelny = 0 if (cv[1] and cv[2] and cv[0] >= 5000) else 1
        return (1 if script and not latin else 0, pelny, 0 if plain else 1,
                 {400: 0, 500: 1, 600: 2, 700: 3, 300: 4, 100: 5, 900: 6}.get(wt(n), 7),
                 0 if not isitalic(n) else 1, -cv[0], n)
    fam_pool.sort(key=rank)
    if primary:
        pp = [c for c in fam_pool if c[1] == primary]
        fam_pool = pp + [c for c in fam_pool if c[1] != primary]
    if not fam_pool:
        rob = [c for c in cand if c[1] == 'Roboto-Regular.ttf']
        pool = rob or [c for c in cand if has(c[1], 'Roboto') and not isitalic(c[1])] or cand
        print(f"  UWAGA: rodziny '{family}' TU NIE MA - używam tego, co jest ({pool[0][1]}),"
              " żeby nie udawać MiSansa tam gdzie go nie ma")
    else:
        pool = fam_pool
        print(f"  rodzina '{family}': {len(fam_pool)} plik(ów)")

    def pick(p, w, italic=False):
        for c in p:
            if wt(c[1]) == w and isitalic(c[1]) == italic:
                return c
        return None

    prim4 = pick(pool, 400) or pool[0]
    cv4 = coverage(prim4[0])
    if cv4 and cv4[0] < 2000:
        print(f'  AWARIA: sans-serif mialby byc {prim4[1]} z {cv4[0]} kodami - szukam pelniejszego')
        lepszy = [c for c in pool if (coverage(c[0]) or (0,))[0] >= 5000]
        if lepszy:
            prim4 = lepszy[0]
            print(f'  naprawione: sans-serif = {prim4[1]} ({coverage(prim4[0])[0]} kodow)')
    prim4i = pick(pool, 400, True)
    prim7 = pick(pool, 700)
    mono = next((c for c in cand if has(c[1], 'CutiveMono', 'DroidSansMono', 'RobotoMono',
                                       'JetBrains', 'monospace')), prim4)
    def godny(c, min_kodow=400):
        cv = coverage(c[0])
        return cv is None or cv[0] >= min_kodow
    serif = next((c for c in cand if 'serif' in c[1].lower() and not has(c[1], 'sans')
                  and godny(c)), None)
    if serif is None:
        print('  UWAGA: serif pominiety - zadny kandydat nie ma godziwego pokrycia cmap'
              ' (MiSerif.ttf w HyperOS to 14 kodow, nie rodzina) - zostaje font systemowy')
    main = {'sans-serif': [c for c in (prim4, prim4i, prim7) if c],
            'serif': [c for c in (serif,) if c and c[0] != prim4[0]],
            'monospace': [c for c in (mono,) if c and c[0] != prim4[0]]}
    used = []
    for v in main.values():
        used += v
    lang_fam, skipped = {}, []
    for c in cand:
        if c in used or len(used) >= maxf:
            continue
        lang = next((l for k, l in LANG if has(c[1], k)), None)
        if lang is None:
            skipped.append(c)
            continue
        lang_fam.setdefault(lang, []).append(c)
        used.append(c)
    os.makedirs(os.path.join(out, 'system/product/fonts'), exist_ok=True)
    for p, name, kind, sz in used:
        shutil.copy2(p, os.path.join(out, 'system/product/fonts', name))
    L = ['<?xml version="1.0" encoding="utf-8"?>',
         f'<!-- tools/fontgen.py: rodzina "{family}"; kazdy <font> istnieje w module;',
         '     <family> ma zawsze name albo lang (FontListParser odrzuca reszte);',
         '     wygenerowane, bo w HyperOS 4 ten plik jest symlinkiem do motywu z /data. -->',
         '<familyset>']
    for fname, items in main.items():
        if not items:
            continue
        L.append(f'    <family name="{fname}">')
        for c in items:
            L.append(f'        <font weight="{wt(c[1])}" style="{"italic" if isitalic(c[1]) else "normal"}">{c[1]}</font>')
        L.append('    </family>')
    for lang, items in sorted(lang_fam.items()):
        L.append(f'    <family lang="{lang}">')
        for c in items[:4]:
            L.append(f'        <font weight="{wt(c[1])}" style="{"italic" if isitalic(c[1]) else "normal"}">{c[1]}</font>')
        L.append('    </family>')
    L.append('</familyset>')
    path = os.path.join(out, 'system/etc/fonts.xml')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(L) + '\n')
    with open(os.path.join(out, '.fontlist'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(c[1] for c in used) + '\n')
    print(f"  fonts.xml: {os.path.getsize(path)} B | rodzin nazwanych: {sum(1 for v in main.values() if v)},"
          f" jezykowych: {len(lang_fam)} | fontow w module: {len(used)}")
    if skipped:
        print(f"  POMINIETE (bez rozpoznanego jezyka/skryptu - nie wchodza do fonts.xml): {len(skipped)}")
        for c in skipped[:8]:
            print(f"    - {c[1]}")
        if len(skipped) > 8:
            print(f"    ... i {len(skipped) - 8} wiecej")
    return 0


if __name__ == '__main__':
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--fonts', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--family', default='MiSans')
    ap.add_argument('--primary', default='')
    ap.add_argument('--max-fonts', type=int, default=48)
    a = ap.parse_args()
    sys.exit(build(a.fonts, a.out, a.family, a.primary, a.max_fonts))
