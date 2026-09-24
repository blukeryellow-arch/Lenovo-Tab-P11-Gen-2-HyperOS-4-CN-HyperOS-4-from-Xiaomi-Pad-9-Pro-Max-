#!/usr/bin/env python3
"""Wyprowadza brakujace macierze VINTF (level 4/5/6) z tych, ktore sumber dostarcza.

Dlaczego to istnieje (zmierzone na plikach, nie z forum):
  system.img z HyperOS 4 (Android 17, sdk=37) ma w /system/etc/vintf WYLACZNIE
  compatibility_matrix.7.xml, .8.xml, .202404/.202504/.202604.xml i device.xml.
  Plikow dla leveli 4/5/6 NIE MA. init (VintfObject) dobiera macierz wg
  <target-level> zgliszonego przez /vendor manifest Lenovo (epoka A12 = level 5);
  dla levelu 5 pliku nie ma -> 'Failed to initialize VINTF' i boot staje wczesniej
  niz zygote. To jest sciana, o ktorej mowia 'A17 nie dziala na vendorze A12' - ale
  jest sciana PLIKOWA, a nie magiczna: da sie ja usunac przez doklade macierzy.

Co robi skrypt: bierze NajNizsza dostepna macierz (202404 lub .7) i buduje z niej
plik dla poziomu P, zachowujac wylaczenie te wpisy, ktore mogla istniec juz wowczas:
  * odrzuca hal'e z min-level > P (nie istnialy w tamtej epoce),
  * odrzuca wpisy czysto AIDL, ktorych vendor level P nie umial deklarowac... NIE:
    AIDL istnieje od 29, a level 5 (A12) ma AIDL - zostawiamy AIDL, bo inaczej
    zmylimy wymagania,
  * zachowuje atrybuty max-level, bo one mowia 'wymagane do tej wersji HIDL'.
Efekt: macierz, ktora vendor A12 MOZE spelnic bez klamania, i ktora framework
zaakceptuje jako 'istniejaca'. To nie omija bezpieczenstwa - to obniza wymagania
interfejsow do epoki vendora; konsekwencje (crash-loop uslug, ktore potrzebuj
nowszych HAL-i) sa mierzalne dopiero na urzadzeniu i trzeba je zapisac.

UWAGA o uczciwosci: to NIE jest 'A17 na A12 bedzie dzialal'. To jest 'bramka plikowa
omineta, reszta do zweryfikowania na sprzecie'. Skrypt wypisuje ilu HAL-i vendor
level-5 nie ma szanse dostarczyc (brak odpowiadajacych HIDL/transportow) - te liczby
trafiaja do MISMATCH.md w paczce.

Uzycie:
  ./tools/make_level_matrix.py --from-dir KATALOG_Z_MACIERZAMI --level 5 --out plik.xml
  ./tools/make_level_matrix.py --from-dir ... --level 6 --report-only
"""
import argparse
import glob
import os
import re
import sys
import xml.etree.ElementTree as ET

DATE_LEVELS = {'202404': 6, '202504': 7, '202604': 8}


def level_of(fname):
    m = re.search(r'compatibility_matrix\.(?:(\d{6})|(\d+))\.xml$', fname)
    if not m:
        return None
    if m.group(1):
        return DATE_LEVELS.get(m.group(1), 8)
    return int(m.group(2))


def load_matrix(path):
    try:
        return ET.parse(path).getroot()
    except (ET.ParseError, OSError) as e:
        print(f"  (pominiete {os.path.basename(path)}: {e})", file=sys.stderr)
        return None


def build(root, want_level):
    """Nowy korzen macierzy dla poziomu `want_level`, wyciety z `root`."""
    kept, dropped = [], []
    for h in root.findall('hal'):
        mn = h.get('min-level') or h.findtext('min-level')
        mx = h.get('max-level') or h.findtext('max-level')
        mn = int(mn) if mn and mn.isdigit() else 0
        mx = int(mx) if mx and mx.isdigit() else 1000
        if mn > want_level:
            dropped.append((h, f"min-level {mn} > {want_level}"))
            continue
        if mx < want_level:
            dropped.append((h, f"max-level {mx} < {want_level}"))
            continue
        kept.append(h)
    new = ET.Element('compatibility-matrix')
    new.set('version', root.get('version', '9.0'))
    new.set('level', str(want_level))
    for c in list(root):
        if c.tag == 'hal':
            continue
        if c.tag in ('kernel', 'sepolicy'):
            continue          # te pola generuje sie razem z poziomem, nie przepiszemy ich wiernie
        new.append(c)
    for h in kept:
        new.append(h)
    # <level> to JEDYNE pole, ktore czyta init (VintfObject); atrybut 'level' jest dla naszych
    # narzedzi. 24 IX 2026 pierwszy test od konca do konca (wstrzyknij -> zbuduj -> rozpakuj)
    # pokazal, ze element byl kopiowany ze ZRODLA i nigdy nie nadpisywany: plik o nazwie
    # compatibility_matrix.5.xml mial w srodku '<level>6</level>', czyli bramka byla 'otwarta'
    # tylko w nazwie. Taki plik init moze odrzucic albo - gorzej - przyjac i dobrac nie ta
    # macierz co trzeba, a wtedy komunikat o VINTF zniknie bez zadnej poprawy.
    lev = new.find('level')
    if lev is None:
        lev = ET.Element('level')
        new.insert(0, lev)
    lev.text = str(want_level)
    return new, kept, dropped


def mark_optional(root, vendor_manifest_dir=None):
    # init panikuje TYLKO na brakujacych pozycjach OBOWIAZKOWYCH. Oznaczenie
    # 'optional' nie kamie co do istnienia HAL-i - mowi frameworkowi 'nie zatrzymuj
    # boot, jesli vendor tego nie ma'. Dlatego to jest jedyna bramka, ktora da sie
    # otworzy bez vendora z 2024+.
    #
    # Jezeli podamy katalog z manifestem vendora (adb: /vendor/etc/vintf), oznaczamy
    # optional tylko te pozycje, ktorych vendor NAPRAWDE nie ma - reszta zostaje
    # obowiazkowa, wiec nie zmiekcza sie wymagania bez potrzeby. Bez tego katalogu
    # oznaczamy WSZYSTKO (tryb 'brak danych z urzadzenia') i mowimy o tym wprost.
    have = set()
    if vendor_manifest_dir:
        for f in glob.glob(os.path.join(vendor_manifest_dir, '**', '*.xml'), recursive=True):
            r = load_matrix(f)
            if r is None:
                continue
            for h in r.iter('hal'):
                nm = (h.findtext('name') or '').strip()
                if not nm:
                    continue
                have.add(nm)
                for q in h.findall('fqname'):
                    have.add(f"{nm}@{(q.text or '').strip()}")
                for v in h.findall('version'):
                    have.add(f"{nm}@{v.text}")
            # AIDL w manifescie vendora uzywa <interface><name>X</name><instance>Y</instance>
            for it in h.findall('interface'):
                inm = (it.findtext('name') or '').strip()
                inst = (it.findtext('instance') or '').strip()
                if inm:
                    have.add(inm)
                    if inst:
                        have.add(f"{inm}/{inst}")
    n_opt = 0
    for h in root.findall('hal'):
        nm = (h.findtext('name') or '').strip()
        if not vendor_manifest_dir:
            present = False
        else:
            keys = {nm}
            for q in h.findall('fqname'):
                keys.add((q.text or '').strip())
                keys.add((q.text or '').strip().split('@')[-1])
            for it in h.findall('interface'):
                inm = (it.findtext('name') or '').strip()
                inst = (it.findtext('instance') or '').strip()
                if inm:
                    keys.add(inm)
                    keys.add(f"{inm}/{inst}" if inst else inm)
            present = bool(keys & have)   # dopasowanie po nazwie interfejsu (AIDL) lub name (HIDL)
        if not present:
            for old in h.findall('optional'):
                h.remove(old)
            e = ET.SubElement(h, 'optional')
            e.text = 'true'
            n_opt += 1
    return n_opt, (bool(vendor_manifest_dir) and len(have) or 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--from-dir', required=True, help='katalog z compatibility_matrix.*.xml')
    ap.add_argument('--level', type=int, required=True, help='ktory poziom wyprowadzic (4/5/6)')
    ap.add_argument('--out', default='')
    ap.add_argument('--report-only', action='store_true')
    ap.add_argument('--vendor-manifest', default='', help='katalog z /vendor/etc/vintf z urzadzenia (adb pull)')
    ap.add_argument('--optional-missing', action='store_true',
                    help='brakujace pozycje oznacz optional (otwiera bramke init)')
    a = ap.parse_args()

    cands = []
    for f in glob.glob(os.path.join(a.from_dir, 'compatibility_matrix.*.xml')):
        lv = level_of(os.path.basename(f))
        if lv is not None:
            cands.append((lv, f))
    if not cands:
        print("w katalogu nie ma macierzy do odczytu"); return 3
    cands.sort()
    print(f"dostepne macierze: " + ", ".join(f"{os.path.basename(f)}(lvl {lv})" for lv, f in cands))
    # najblizsza od gory: najmniej sie rozejdzie z epoka
    src_lvl, src = cands[0]
    if src_lvl <= a.level:
        print(f"  level {a.level} jest KRYTY poza zakresem (najnizszy dostepny {src_lvl}) - i tak tnemy")
    root = load_matrix(src)
    if root is None:
        return 3
    new, kept, dropped = build(root, a.level)

    hidl = sum(1 for h in kept if h.get('format', 'hidl') == 'hidl')
    aidl = sum(1 for h in kept if h.get('format') == 'aidl')
    print(f"z {src_lvl} -> {a.level}: zachowane {len(kept)} (HIDL {hidl}, AIDL {aidl}), "
          f"odrzucone {len(dropped)}")
    print("  przyklady odrzuconych (bo wymagaja nowszego vendora):")
    for h, why in dropped[:6]:
        print(f"    - {h.findtext('name')} [{why}]")
    print(f"  UWAGA: to znaczy, ze framework przy level {a.level} nie zazada {len(dropped)} "
          f"interfejsow - ich brak nie zatrzyma init, ale uslugi ktore ich potrzebuja "
          f"(np. nowe health/audio HAL) moga crashe.")

    n_opt = 0
    have_n = 0
    if a.optional_missing:
        n_opt, have_n = mark_optional(new, a.vendor_manifest or None)
        skel = ("na podstawie manifestu vendora (%d pozycji)" % have_n) if a.vendor_manifest \
            else "BRAK manifestu vendora - oznaczone NA SZEROKO wszystkie brakujace"
        print(f"  optional zaznaczone: {n_opt} pozycji [{skel}]")

    if a.report_only:
        return 0
    if not a.out:
        print("--out wymagany (albo --report-only)"); return 2
    ET.indent(new, space='  ')
    os.makedirs(os.path.dirname(os.path.abspath(a.out)) or '.', exist_ok=True)
    with open(a.out, 'wb') as f:
        f.write(b'<!-- wygenerowane przez tools/make_level_matrix.py z '
                + os.path.basename(src).encode()
                + f' dla poziomu {a.level}; NIE jest to plik AOSP -->\n'.encode())
        f.write(ET.tostring(new, encoding='utf-8', xml_declaration=False))
    print(f"  zapisano {a.out} ({os.path.getsize(a.out)} B)")
    if a.optional_missing:
        mp = os.path.splitext(a.out)[0] + '.komentarz.txt'
        with open(mp, 'w', encoding='utf-8') as f:
            f.write("Wygenerowane przez tools/make_level_matrix.py --optional-missing\n"
                    f"zrodlo: {os.path.basename(src)} (level {src_lvl}); cel: level {a.level}\n"
                    f"pozycje oznaczone optional: {n_opt}\n"
                    + ("podstawa: manifest vendora z urzadzenia\n" if a.vendor_manifest else
                       "podstawa: BRAK manifestu vendora - oznaczone wszystko, co nie jest\n"
                       "  dostarczone przez /system (frameworkowe). To otwiera bramke init,\n"
                       "  ale uslugi potrzebujace tych HAL-i (audio/health/power/thermal)\n"
                       "  beda crashe - patrz MISMATCH.md w paczce.\n"))
    # sanity: plik musi byc parsowalny i miec tyle hal-i co zatrzymalismy
    chk = ET.parse(a.out).getroot()
    n = len(chk.findall('hal'))
    # level odczytany z PARSED pliku (nie z tego, co chcielismy zapisac) - to jest asercja,
    # ze nazwa pliku i jego tresc mowia to samo. Bez niej plik compatibility_matrix.5.xml
    # z <level>6</level> w srodku przeszedlby dalej jako sukces (24 IX 2026).
    _lev = chk.find('level')
    _lv = (_lev.text or '').strip() if _lev is not None else 'BRAK'
    if _lv != str(a.level):
        print(f"  FATAL: plik deklaruje <level>{_lv}</level>, a zadano {a.level}")
        print("         taka macierz nie otwiera bramki init - ona ja zasloni jeszcze dokladniej")
        return 4
    print(f"  weryfikacja: level w pliku = {_lv} (zadany {a.level}), HAL-i w pliku = {n} (oczekiwane {len(kept)}) -> "
          + ("OK" if n == len(kept) else "BLAD"))
    return 0 if n == len(kept) else 1


if __name__ == '__main__':
    sys.exit(main())
