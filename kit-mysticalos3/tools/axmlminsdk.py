#!/usr/bin/env python3
"""axmlminsdk.py — patch minSdkVersion w SKOMPILOWANYM AndroidManifest.xml (binary AXML).

Uzycie: axmlminsdk.py <AndroidManifest.xml | APK> <nowe_minSdk> [out] [--if-needed]

- Dla APK: przepisuje zip (AndroidManifest.xml spatchowany, usuniete stare podpisy
  META-INF/*.SF|*.RSA|*.EC|MANIFEST.MF) do pliku wyjsciowego (domyslnie <in>.patched).
  UWAGA: po patchu APK wymaga ponownego podpisu (zipalign + apksigner)!
- Dla samego pliku AXML: patchuje w miejscu (albo do out, jesli podany).
- --if-needed: gdy <uses-sdk> nie istnieje albo nie ma atrybutu minSdkVersion,
  albo minSdk <= nowe — NIE rusza manifestu (no-op; minSdk nieobecny = 1 wg
  platformy, czyli APK i tak zainstaluje sie na nizszym API). Wypisuje wtedy
  skrot drzewa elementow (diagnoza).

Dzialanie: szuka elementu <uses-sdk> i atrybutu android:minSdkVersion
(resId 0x0101020c), przepisuje 4-bajtowa wartosc (dataType INT_DEC).
targetSdkVersion NIE jest ruszany (wyzszy target na nizszym API jest bezpieczny).
"""
import io
import struct
import sys
import zipfile

RES_STRING_POOL = 0x0001
RES_XML_START_ELEM = 0x0102
RES_XML_END_ELEM = 0x0103
RES_XML_RESMAP = 0x0180
MINSDK_RESID = 0x0101020C
TARGETSDK_RESID = 0x01010270
UTF8_FLAG = 0x100


def read_string_pool(data, off):
    """Zwraca liste stringow z chunku string-pool na offsetcie off."""
    (ctype, _hs, csize) = struct.unpack_from('<HHI', data, off)
    assert ctype == RES_STRING_POOL, 'to nie string pool'
    (str_count, _style_count, flags, str_start, _sty_start) = struct.unpack_from(
        '<IIIII', data, off + 8)
    is_utf8 = bool(flags & UTF8_FLAG)
    strings = []
    for i in range(str_count):
        (so,) = struct.unpack_from('<I', data, off + 28 + 4 * i)
        p = off + str_start + so
        if is_utf8:
            # u16 charCount (escape), u8 byteCount (escape), dane, 0x00
            (cn,) = struct.unpack_from('<H', data, p); p += 2
            if cn & 0x8000:
                (cn2,) = struct.unpack_from('<H', data, p); p += 2
            b = data[p]; p += 1
            if b & 0x80:
                b = ((b & 0x7F) << 8) | data[p]; p += 1
            strings.append(data[p:p + b].decode('utf-8', 'replace'))
        else:
            (n,) = struct.unpack_from('<H', data, p); p += 2
            if n & 0x8000:
                (n2,) = struct.unpack_from('<H', data, p); p += 2
                n = ((n & 0x7FFF) << 16) | n2
            strings.append(data[p:p + n * 2].decode('utf-16-le', 'replace'))
    return strings


def patch_axml(buf, new_min, if_needed=False):
    """Patchuje binary AXML w buforze; zwraca (nowy_bufor, info).

    info = lista krotek akcji; przy if_needed moze byc pusta (no-op).
    Rzuca AssertionError gdy wymaga patcha, a nie da sie go zrobic
    (bez if_needed rowniez gdy uses-sdk/minSdk w ogole brak).
    """
    data = bytearray(buf)
    # glowny naglowek pliku
    (ftype, _hs, fsize) = struct.unpack_from('<HHI', data, 0)
    assert ftype == 0x0003, 'nie jest to binary XML (magic %04x)' % ftype
    strings = None
    resmap = {}  # string index -> resId
    off = 8
    patched = []
    elems = []          # (nazwa, [(attr, data)]) - diagnoza
    found_uses_sdk = False
    found_minsdk = False
    cur = None
    while off < fsize:
        (ctype, chs, csize) = struct.unpack_from('<HHI', data, off)
        if csize <= 0:
            break
        if ctype == RES_STRING_POOL:
            strings = read_string_pool(data, off)
        elif ctype == RES_XML_RESMAP:
            n = (csize - 8) // 4
            for i in range(n):
                (rid,) = struct.unpack_from('<I', data, off + 8 + 4 * i)
                resmap[i] = rid
        elif ctype == RES_XML_START_ELEM:
            (_line, _com, _ns, name_idx, attr_start, attr_size, attr_count) = (
                struct.unpack_from('<IIIIHHH', data, off + 8))
            nm = strings[name_idx] if (strings and name_idx < len(strings)) else '?'
            cur = [nm, []]
            elems.append(cur)
            if nm == 'uses-sdk':
                found_uses_sdk = True
                # atrybuty: attributeStart liczone od poczatku struktury attrExt
                # (off+16), standardowo 0x14=20 -> atrybuty @ off+36; fallback:
                # gdyby attributeStart byl juz absolutny wzgledem chunku.
                base = off + 16 + attr_start
                if base + attr_size * attr_count > off + csize:
                    base = off + attr_start
                for i in range(attr_count):
                    a = base + i * attr_size
                    (a_ns, a_name, a_raw, v_size, v_res0, v_type, v_data) = (
                        struct.unpack_from('<IIIHBBI', data, a))
                    rid = resmap.get(a_name)
                    an = strings[a_name] if a_name < len(strings) else '?'
                    cur[1].append((an, v_type, v_data))
                    if rid == MINSDK_RESID or an == 'minSdkVersion':
                        found_minsdk = True
                        if v_data > new_min:
                            assert v_type == 0x10, \
                                'minSdkVersion nie jest INT_DEC (type=%02x) - reczna interwencja' % v_type
                            struct.pack_into('<I', data, a + 16, new_min)
                            patched.append(('minSdkVersion', v_data, new_min))
                        else:
                            patched.append(('minSdkVersion', 'juz<=nowego (%d)' % v_data, 'no-op'))
                    # targetSdk zostawiamy
        elif ctype == RES_XML_END_ELEM:
            cur = None
        off += csize
    if not patched:
        if if_needed and not found_minsdk:
            # uses-sdk nieobecny albo bez minSdkVersion -> wg platformy minSdk=1
            why = ('uses-sdk NIEOBECNY' if not found_uses_sdk
                   else 'uses-sdk bez atrybutu minSdkVersion')
            sys.stderr.write('[axmlminsdk] no-op: %s -> minSdk platf. = 1 '
                             '(APK ok na nizszym API)\n' % why)
            sys.stderr.write('[axmlminsdk] elementy manifestu: %s\n'
                             % ', '.join(e[0] for e in elems))
            for e in elems:
                if e[1]:
                    sys.stderr.write('[axmlminsdk]   <%s> attr: %s\n'
                                     % (e[0], '; '.join('%s(t%02x)=%s' % a for a in e[1])))
            return bytes(buf), []
        raise AssertionError(
            'nie znaleziono atrybutu minSdkVersion w <uses-sdk>! '
            '(uses-sdk=%s; elementy: %s)'
            % (found_uses_sdk, ', '.join(e[0] for e in elems) or 'pusto'))
    return bytes(data), patched


def main():
    argv = [a for a in sys.argv[1:] if a != '--if-needed']
    if_needed = '--if-needed' in sys.argv[1:]
    if len(argv) < 2:
        print(__doc__)
        return 2
    path, new_min = argv[0], int(argv[1])
    out = argv[2] if len(argv) > 2 else None
    raw = open(path, 'rb').read()
    if raw[:2] == b'PK':  # APK
        src = zipfile.ZipFile(io.BytesIO(raw))
        man = src.read('AndroidManifest.xml')
        newman, info = patch_axml(man, new_min, if_needed)
        dst = out or (path[:-4] + '-minsdk' + str(new_min) + '.apk')
        with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as z:
            for it in src.infolist():
                if it.filename == 'AndroidManifest.xml':
                    z.writestr('AndroidManifest.xml', newman)
                elif (it.filename.startswith('META-INF/')
                      and (it.filename.endswith(('.SF', '.RSA', '.EC'))
                           or it.filename == 'META-INF/MANIFEST.MF')):
                    continue  # stare podpisy OUT
                else:
                    z.writestr(it, src.read(it.filename))
        print('OK: %s -> %s %s (wymaga zipalign+apksigner!)' % (path, dst, info or '(no-op)'))
        return 0
    newdata, info = patch_axml(raw, new_min, if_needed)
    dst = out or path
    open(dst, 'wb').write(newdata)
    print('OK: %s %s' % (dst, info or '(no-op)'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
