#!/usr/bin/env python3
"""axmlminsdk.py — patch minSdkVersion w SKOMPILOWANYM AndroidManifest.xml (binary AXML).

Uzycie: axmlminsdk.py <AndroidManifest.xml | APK> <nowe_minSdk> [out]

- Dla APK: przepisuje zip (AndroidManifest.xml spatchowany,/usuniete stare podpisy
  META-INF/*.SF|*.RSA|*.EC|MANIFEST.MF) do pliku wyjsciowego (domyslnie <in>.patched).
  UWAGA: po patchu APK wymaga ponownego podpisu (zipalign + apksigner)!
- Dla samego pliku AXML: patchuje w miejscu (albo do out, jesli podany).

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
            p += 2
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


def patch_axml(buf, new_min):
    """Patchuje binary AXML w buforze; zwraca (nowy_bufor, info)."""
    data = bytearray(buf)
    # glowny naglowek pliku
    (ftype, _hs, fsize) = struct.unpack_from('<HHI', data, 0)
    assert ftype == 0x0003, 'nie jest to binary XML (magic %04x)' % ftype
    strings = None
    resmap = {}  # string index -> resId
    off = 8
    patched = []
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
            if strings and name_idx < len(strings) and strings[name_idx] == 'uses-sdk':
                for i in range(attr_count):
                    a = off + attr_start + i * attr_size
                    (a_ns, a_name, a_raw, v_size, v_res0, v_type, v_data) = (
                        struct.unpack_from('<IIIHBBI', data, a))
                    rid = resmap.get(a_name)
                    nm = strings[a_name] if a_name < len(strings) else '?'
                    if rid == MINSDK_RESID or nm == 'minSdkVersion':
                        assert v_type == 0x10, \
                            'minSdkVersion nie jest INT_DEC (type=%02x) - reczna interwencja' % v_type
                        struct.pack_into('<I', data, a + 16, new_min)
                        patched.append(('minSdkVersion', v_data, new_min))
                    # targetSdk zostawiamy
        off += csize
    assert patched, 'nie znaleziono atrybutu minSdkVersion w <uses-sdk>!'
    return bytes(data), patched


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    path, new_min = sys.argv[1], int(sys.argv[2])
    out = sys.argv[3] if len(sys.argv) > 3 else None
    raw = open(path, 'rb').read()
    if raw[:2] == b'PK':  # APK
        src = zipfile.ZipFile(io.BytesIO(raw))
        man = src.read('AndroidManifest.xml')
        newman, info = patch_axml(man, new_min)
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
        print('OK: %s -> %s %s (wymaga zipalign+apksigner!)' % (path, dst, info))
        return 0
    newdata, info = patch_axml(raw, new_min)
    dst = out or path
    open(dst, 'wb').write(newdata)
    print('OK: %s %s' % (dst, info))
    return 0


if __name__ == '__main__':
    sys.exit(main())
