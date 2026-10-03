#!/usr/bin/env python3
"""simg2img_stream.py - konwersja Android sparse -> raw W STRUMIENIU (stdin->stdout).

Cel: super.img w zipie lolinet TB350FU_S230982_251013_ROW jest SPARSE
(8 297 863 612 B sparse -> 9 663 676 416 B raw device; receipt runu 36725294534:
segmenty partycji _a do 8 365 445 120 raw > rozmiar pliku => plik NIE jest raw).
Pipeline: httpzip --entry super.img | simg2img_stream | stream_lpunpack --stdin.

Zachowanie:
  - stdin zaczyna sie od magic 0xED26FF3A (LE: 3a ff 26 ed) -> unsparse do stdout,
  - inny poczatek (np. raw super: zera + 'gDla' @4096) -> PRZEPUSC 1:1 (cat),
  - chunki: RAW 0xCAC1 (kopiuj), FILL 0xCAC2 (rozwin 4B), DONTCARE 0xCAC3 (zera),
    CRC 0xCAC4 (pomin),
  - BrokenPipeError na stdout = konsument zakonczyl (np. stream_lpunpack po
    ostatnim segmencie _a) => exit 0 (dane kompletne dla konsumenta),
  - chunky czytane exactnie; blad = exit 1 z komunikatem.

Test: lpmake -S mini-super -> simg2img_stream | stream_lpunpack == lpunpack(raw).
"""
import struct
import sys

SPARSE_MAGIC = 0xED26FF3A
CHUNK_RAW = 0xCAC1
CHUNK_FILL = 0xCAC2
CHUNK_DONT_CARE = 0xCAC3
CHUNK_CRC32 = 0xCAC4
BUF = 4 * 1024 * 1024


def read_exact(f, n):
    buf = b""
    while len(buf) < n:
        part = f.read(n - len(buf))
        if not part:
            raise EOFError(f"krotki odczyt: mam {len(buf)}/{n}")
        buf += part
    return buf


def main():
    stdin = sys.stdin.buffer
    stdout = sys.stdout.buffer

    head = read_exact(stdin, 28)
    magic, maj, mnr, fhs, chs, blk, nblk, nch, ck = struct.unpack("<IHHHHIIII", head)
    if magic == SPARSE_MAGIC and fhs > 28:
        # file header wiekszy niz 28B (np. 32) - pomin nadmiar
        read_exact(stdin, fhs - 28)
    if magic != SPARSE_MAGIC:
        # nie-sparse: przepusc glowe i reszte 1:1
        stdout.write(head)
        while True:
            try:
                buf = stdin.read(BUF)
            except Exception:
                break
            if not buf:
                break
            stdout.write(buf)
        stdout.flush()
        sys.stderr.write("# simg2img_stream: wejscie NIE sparse (magic "
                         f"{magic:#x}) - passthrough 1:1\n")
        return 0

    if blk == 0 or (fhs != 28 and fhs != 0):
        sys.stderr.write(f"# ostrzezenie: file_hdr_size={fhs} (zakladam 28)\n")
    sys.stderr.write(f"# simg2img_stream: sparse v{maj}.{mnr} blk={blk} "
                     f"chunks={nch} raw={nblk * blk} B\n")
    zeros = b"\0" * BUF
    try:
        for _ in range(nch):
            ch = read_exact(stdin, chs if chs >= 12 else 12)
            ct, res, n, total = struct.unpack("<HHII", ch[:12])
            if chs > 12:
                pass  # nadmiarowe bajty chunk-headera juz pominiete (czytane w ch)
            span = n * blk
            if ct == CHUNK_RAW:
                # total_sz OBEJMUJE header (receipt: FILL total=16=12+4) =>
                # danych jest total - chs
                left = total - (chs if chs >= 12 else 12)
                if left < 0:
                    raise SystemExit(f"simg2img_stream: RAW total={total} < hdr {chs}")
                while left > 0:
                    buf = read_exact(stdin, min(left, BUF))
                    stdout.write(buf)
                    left -= len(buf)
            elif ct == CHUNK_FILL:
                fillpay = total - (chs if chs >= 12 else 12)
                if fillpay <= 0:
                    fillpay = 4
                fill = read_exact(stdin, fillpay)[:4]
                pat = (fill * (BUF // 4 + 1))[:BUF]
                left = span
                while left > 0:
                    take = min(left, BUF)
                    stdout.write(pat[:take])
                    left -= take
            elif ct == CHUNK_DONT_CARE:
                left = span
                while left > 0:
                    take = min(left, BUF)
                    stdout.write(zeros[:take])
                    left -= take
            elif ct == CHUNK_CRC32:
                read_exact(stdin, 4)
            else:
                raise SystemExit(f"simg2img_stream: nieznany chunk {ct:#x}")
        stdout.flush()
    except BrokenPipeError:
        # konsument (stream_lpunpack) skonczyl po ostatnim segmencie _a -
        # jego dane sa kompletne; to nie jest blad
        sys.stderr.write("# simg2img_stream: konsument zamknal pipe (OK)\n")
        return 0
    except EOFError as e:
        sys.stderr.write(f"simg2img_stream: {e}\n")
        return 1
    sys.stderr.write("# simg2img_stream: OK (pelny unsparse)\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
