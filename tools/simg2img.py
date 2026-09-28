#!/usr/bin/env python3
"""Konwersja Android sparse image -> raw image (python, zero zaleznosci).

Sandbox/runner nie maja android-sdk-libsparse-utils, a GSI Google przychodzi
jako system.img w formacie sparse (magic 0x3A69ED55). Format jest trywialny:
naglowek 28 B + N chunkow (12 B naglowek + dane). Obslugiwane typy: RAW 0xCAC1,
FILL 0xCAC2 (4-bajtowy wzorzec), DONTCARE 0xCAC3 (zera), CRC32 0xCAC4 (pomijany).

Uzycie:
  tools/simg2img.py IN.img OUT.img [--info]

--info: tylko statystyki (typy/rozmiary chunkow), bez zapisu.
Kod 0 = OK; 1 = to nie jest sparse image (albo inny blad).
"""
import struct
import sys

MAGIC = 0x3A69ED55  # Android sparse image magic (fix: bylo bledne 0x3AED2684 -
                    # round-trip self-test tego nie zlapal, bo testowal wlasny zapis)
TYPE_RAW = 0xCAC1
TYPE_FILL = 0xCAC2
TYPE_DONTCARE = 0xCAC3
TYPE_CRC32 = 0xCAC4


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    info = "--info" in sys.argv
    if len(args) != 2:
        print(__doc__)
        return 1
    src, dst = args
    with open(src, "rb") as f:
        head = f.read(28)
        if len(head) < 28 or struct.unpack_from("<I", head, 0)[0] != MAGIC:
            print("NIE-sparse (brak magic 0x3A69ED55) - plik jest chyba raw albo inny format")
            return 1
        (magic, major, minor, file_hdr_sz, chunk_hdr_sz, blk_sz,
         total_blks, total_chunks, _crc) = struct.unpack("<IHHHHIIII", head)
        print("sparse v%d.%d  file_hdr=%d chunk_hdr=%d blk_sz=%d total_blks=%d chunks=%d"
              % (major, minor, file_hdr_sz, chunk_hdr_sz, blk_sz, total_blks, total_chunks))
        if file_hdr_sz > 28:
            f.read(file_hdr_sz - 28)
        out = None if info else open(dst, "wb")
        written = 0
        stats = {}
        for i in range(total_chunks):
            ch = f.read(chunk_hdr_sz)
            (chunk_type, reserved, nblks, _total_sz) = struct.unpack_from("<HHII", ch, 0)
            data_len = nblks * blk_sz
            if chunk_type == TYPE_RAW:
                stats["raw"] = stats.get("raw", 0) + nblks
                if out:
                    left = data_len
                    while left:
                        buf = f.read(min(1 << 20, left))
                        if not buf:
                            raise SystemExit("truncated RAW chunk %d" % i)
                        out.write(buf)
                        left -= len(buf)
                else:
                    f.seek(data_len, 1)
            elif chunk_type == TYPE_FILL:
                pat = f.read(4)
                stats["fill"] = stats.get("fill", 0) + nblks
                if out:
                    block = pat * (blk_sz // 4)
                    for _ in range(nblks):
                        out.write(block)
            elif chunk_type == TYPE_DONTCARE:
                stats["dontcare"] = stats.get("dontcare", 0) + nblks
                if out:
                    out.write(b"\x00" * data_len)
                # nic nie czytamy - DONTCARE nie niesie danych
            elif chunk_type == TYPE_CRC32:
                f.read(4 if chunk_hdr_sz >= 12 else 0)
                stats["crc"] = stats.get("crc", 0) + 1
            else:
                raise SystemExit("nieznany typ chunka 0x%x (chunk %d)" % (chunk_type, i))
            written += nblks
        if out:
            out.close()
        print("chunki: %s" % ", ".join("%s=%d blk" % (k, v) for k, v in sorted(stats.items())))
        print("blokow zapisanych: %d / oczekiwanych %d %s"
              % (written, total_blks, "OK" if written == total_blks else "NIEZGODNE!"))
        return 0 if written == total_blks else 1


if __name__ == "__main__":
    sys.exit(main())
