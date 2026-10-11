#!/usr/bin/env python3
"""scale_bootanim.py — przeskaluj bootanimation.zip do rozdzielczosci ekranu.

Uzycie: scale_bootanim.py <in.zip> <szer> <wys> <out.zip> [fit|crop]

Tryby: fit = letterbox (cale kadry + czarne pasy), crop = wypelnij ekran
(powiekszenie + przyciecie nadmiaru; domyslne - najlepsze dla animacji
logo na pelnym ekranie).

Android bootanimation NIE skaluje klatek (rysuje 1:1); animacja z innego
urządzenia (np. 3408x2272) na ekranie 2000x1200 wychodzi przycięta/ogromna.
Ten skrypt: odczytuje desc.txt, przeskalowuje wszystkie klatki z zachowaniem
proporcji (LANCZOS), dokleja czarne pasy (letterbox), przepisuje desc.txt
na docelowy rozmiar. Zip wyjsciowy: desc.txt PIERWSZY, ZIP_STORED (wymóg
bootanimation), PNG.
"""
import io
import sys
import zipfile

from PIL import Image


def main():
    if len(sys.argv) not in (5, 6):
        print(__doc__)
        return 2
    src, W, H, dst = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    mode = sys.argv[5] if len(sys.argv) == 6 else 'crop'
    assert mode in ('fit', 'crop'), 'tryb: fit|crop'
    zin = zipfile.ZipFile(src)
    names = zin.namelist()
    assert names[0] == 'desc.txt', 'desc.txt nie jest pierwszy w zipie: %r' % names[0]
    desc_lines = zin.read('desc.txt').decode().splitlines()
    head = desc_lines[0].split()
    ow, oh = int(head[0]), int(head[1])
    if (ow, oh) == (W, H):
        # juz dobry rozmiar - przepisz 1:1
        with open(dst, 'wb') as f:
            f.write(open(src, 'rb').read())
        print('scale_bootanim: %dx%d = docelowe, przepisane 1:1' % (ow, oh))
        return 0
    if mode == 'crop':
        scale = max(W / ow, H / oh)
    else:
        scale = min(W / ow, H / oh)
    nw, nh = max(1, round(ow * scale)), max(1, round(oh * scale))
    ox, oy = (W - nw) // 2, (H - nh) // 2
    desc_lines[0] = '%d %d %s' % (W, H, ' '.join(head[2:]))
    frames = 0
    zout = zipfile.ZipFile(dst, 'w', zipfile.ZIP_STORED)
    zout.writestr('desc.txt', '\n'.join(desc_lines) + '\n')
    for n in names[1:]:
        if n.endswith('/'):
            continue
        data = zin.read(n)
        low = n.lower()
        if low.endswith(('.png', '.webp', '.jpg', '.jpeg')):
            im = Image.open(io.BytesIO(data)).convert('RGB')
            im = im.resize((nw, nh), Image.LANCZOS)
            if mode == 'crop':
                # ox/oy ujemne -> paste z paskami ujemnymi = przyciecie
                canvas = Image.new('RGB', (W, H))
                left = -ox if ox < 0 else 0
                top = -oy if oy < 0 else 0
                canvas.paste(im.crop((left, top, left + W, top + H)), (0, 0))
            else:
                canvas = Image.new('RGB', (W, H), (0, 0, 0))
                canvas.paste(im, (ox, oy))
            buf = io.BytesIO()
            canvas.save(buf, 'PNG', optimize=True)
            data = buf.getvalue()
            frames += 1
        zout.writestr(n, data)
    zout.close()
    print('scale_bootanim: %dx%d -> %dx%d (%s, klatki %dx%d), %d klatek'
          % (ow, oh, W, H, mode, nw, nh, frames))
    return 0


if __name__ == '__main__':
    sys.exit(main())
