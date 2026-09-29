#!/usr/bin/env python3
"""sparse_head.py - rekonstruuje pierwsze N bajtow RAW obrazu ze strumienia
SPARSE (stdin lub plik), bez materializacji calego obrazu.

Do weryfikacji zbudowanego super: cat czastki | sparse_head.py 4194304 > head.bin
-> lpinfo.py head.bin (geometria/metadane). Semantyka chunkow: total_sz ZAWIERA
naglowek 12B (RAW=12+data, FILL=12+4, DONT-CARE=12, CRC=12+4).

Uzycie: sparse_head.py N [plik1 plik2 ...] > head.bin
       sparse_head.py N --stdin            (< z cat czastek)
       sparse_head.py N --file plik

Czyta kolejne pliki (czastki sparse) jako JEDEN strumien i konczy po
rekonstrukcji N bajtow raw (bez SIGPIPE dla producenta).
"""
import struct
import sys

SPARSE_MAGIC = 0xED26FF3A


class FilesSrc:
    """Zrodlo czytajace sekwencyjnie z listy plikow (jak jeden strumien)."""

    def __init__(self, paths):
        self.paths = list(paths)
        self.i = 0
        self.f = None

    def read(self, n):
        out = b""
        while len(out) < n and self.i < len(self.paths):
            if self.f is None:
                self.f = open(self.paths[self.i], "rb")
            buf = self.f.read(n - len(out))
            if buf:
                out += buf
            else:
                self.f.close()
                self.f = None
                self.i += 1
        return out


def main():
    argv = sys.argv[1:]
    n = int(argv[0])
    rest = argv[1:]
    if rest and rest[0] == "--stdin":
        src = sys.stdin.buffer
    elif rest and rest[0] == "--file":
        src = open(rest[1], "rb")
    elif rest:
        src = FilesSrc(rest)   # lista czastek jako jeden strumien
    else:
        src = sys.stdin.buffer
    hdr = src.read(28)
    magic, maj, mnr, fhs, chs, blk, nblk, nch, ck = struct.unpack("<IHHHHIIII", hdr)
    if magic != SPARSE_MAGIC:
        raise SystemExit(f"to nie sparse (magic {magic:#x})")
    if fhs > 28:
        src.read(fhs - 28)
    out = bytearray(n)
    pos = 0
    chunks = {"raw": 0, "fill": 0, "dc": 0, "crc": 0}
    for _ in range(nch):
        ch = src.read(12)
        if len(ch) < 12:
            break
        ct, res, nb, total = struct.unpack("<HHII", ch)
        data_len = total - 12
        if pos >= n:
            break
        if ct == 0xCAC1:  # RAW
            data = src.read(data_len)
            chunks["raw"] += 1
            take = min(len(data), n - pos)
            out[pos:pos + take] = data[:take]
            pos += take
        elif ct == 0xCAC2:  # FILL
            fill = src.read(4)
            chunks["fill"] += 1
            for i in range(nb * blk):
                if pos >= n:
                    break
                out[pos] = fill[i % 4]
                pos += 1
        elif ct == 0xCAC3:  # DONT-CARE
            chunks["dc"] += 1
            pos = min(pos + nb * blk, n)
        elif ct == 0xCAC4:  # CRC
            chunks["crc"] += 1
            src.read(data_len)
        else:
            raise SystemExit(f"nieznany chunk {ct:#x}")
    sys.stdout.buffer.write(bytes(out))
    print(f"# sparse_head: {n} B raw z {nch} chunkow {chunks} (device {nblk * blk} B)",
          file=sys.stderr)


if __name__ == "__main__":
    main()
