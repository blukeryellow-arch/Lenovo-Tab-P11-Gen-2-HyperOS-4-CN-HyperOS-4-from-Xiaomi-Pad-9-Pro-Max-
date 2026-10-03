#!/usr/bin/env bash
# Weryfikacja pobranych plikow zestawu HyperOS4 P11Gen2.
# Uzycie:  bash sprawdz.sh   (w katalogu z plikami; potrzebuje python3)
set -u
RAW_SHA=4836dcd4c8d5f6c0f9a6adbde94c65917e70ac1b054bd7acc05705ec9f66b816
rc=0

echo "== 1/2: sha256sum -c SHA256SUMS.txt =="
sha256sum -c SHA256SUMS.txt || rc=1

echo
echo "== 2/2: unsparse system_hyperos4_p11g2.img w pamieci =="
python3 - "$RAW_SHA" <<'PYEOF' || rc=1
import hashlib, struct, sys
expect = sys.argv[1]
with open('system_hyperos4_p11g2.img', 'rb') as f:
    head = f.read(28)
    magic, maj, mnr, hsz, csz, bsz, blocks, chunks, csum = struct.unpack('<4sHHHHIIII', head)
    assert magic == b'\x3a\xff\x26\xed', 'to nie jest obraz Android sparse'
    assert hsz == 28 and csz == 12, 'nieoczekiwane rozmiary naglowkow'
    h = hashlib.sha256()
    pos = hsz
    for _ in range(chunks):
        f.seek(pos)
        ctype, res, cblks, tsz = struct.unpack('<HHII', f.read(12))
        payload = tsz - 12
        if ctype == 0xCAC1:        # RAW
            left = payload
            while left:
                b = f.read(min(1 << 20, left))
                if not b:
                    raise SystemExit('ucity obraz (RAW)')
                h.update(b); left -= len(b)
        elif ctype == 0xCAC2:      # FILL: 4 bajty rozszerzane do cblks*bsz
            h.update(f.read(4) * (cblks * bsz // 4))
        elif ctype in (0xCAC3, 0xCAC4):  # DONTCARE / CRC - nic do danych
            pass
        else:
            raise SystemExit('nieznany typ chunka %#x' % ctype)
        pos += 12 + payload
got = h.hexdigest()
print('unsparse sha256:', got)
print('oczekiwane     :', expect)
sys.exit(0 if got == expect else 1)
PYEOF

echo
if [ $rc -eq 0 ]; then echo "WSZYSTKO ZGODNE - pliki sa kompletne."; else echo "NIEZGODNE - pobierz pliki ponownie."; fi
exit $rc
