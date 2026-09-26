#!/usr/bin/env python3
# sparse_img.py - Android sparse image format w czystym Pythonie (bez adb/libsparse).
# img2simg: raw -> sparse (zerowe bloki -> chunk FILL, reszta -> RAW).
# simg2img: sparse -> raw (FILL rozplywa sie w zera, DONT-CARE to dziura=offs).
# info:     struktura pliku sparse.
# Format: sparse v1.0 (libsparse/sparse_format.h), magic 0x3AED41C8, LE.
import struct, sys, hashlib

MAGIC = 0x3AED41C8
CHUNK_RAW, CHUNK_FILL, CHUNK_DONT_CARE, CHUNK_CRC32 = 0xCAC1, 0xCAC2, 0xCAC3, 0xCAC4
FILE_HDR_SZ, CHUNK_HDR_SZ, BLK = 28, 12, 4096

def die(msg):
    print(f"FATAL: {msg}", file=sys.stderr); sys.exit(2)

def img2simg(src, dst, blk=BLK):
    if blk % 512 or blk <= 0: die("block size musi byc dodatnim wielokrotnoscia 512")
    data = open(src, 'rb').read()
    if len(data) % blk: die(f"rozmiar raw ({len(data)}) nie jest wielokrotnoscia bloku {blk}")
    nblk = len(data) // blk
    chunks = []; i = 0
    while i < nblk:
        block = data[i*blk:(i+1)*blk]
        if block == b'\x00' * blk:
            j = i
            while j < nblk and data[j*blk:(j+1)*blk] == b'\x00' * blk: j += 1
            chunks.append((CHUNK_FILL, j - i, b'\x00\x00\x00\x00')); i = j
        else:
            j = i
            while j < nblk and data[j*blk:(j+1)*blk] != b'\x00' * blk: j += 1
            chunks.append((CHUNK_RAW, j - i, data[i*blk:j*blk])); i = j
    with open(dst, 'wb') as f:
        f.write(struct.pack('<IHHHHIIII', MAGIC, 1, 0, FILE_HDR_SZ, CHUNK_HDR_SZ,
                            blk, nblk, len(chunks), 0))
        for typ, cblks, payload in chunks:
            f.write(struct.pack('<HHII', typ, 0, cblks, CHUNK_HDR_SZ + len(payload)))
            f.write(payload)
    fills = sum(c[1] for c in chunks if c[0] == CHUNK_FILL)
    sparse_sz = FILE_HDR_SZ + len(chunks) * CHUNK_HDR_SZ + sum(len(c[2]) for c in chunks)
    print(f"sparse: {nblk} blokow w {len(chunks)} chunkach; raw {len(data)} B -> sparse {sparse_sz} B")
    print(f"sha256 raw: {hashlib.sha256(data).hexdigest()}")

def simg2img(src, dst):
    f = open(src, 'rb')
    hdr = f.read(FILE_HDR_SZ)
    if len(hdr) != FILE_HDR_SZ: die("plik krotszy niz naglowek sparse")
    magic, maj, mnr, fhs, chs, blk, total_blks, total_chunks, csum = \
        struct.unpack('<IHHHHIIII', hdr)
    if magic != MAGIC: die(f"to NIE jest obraz sparse (magic {magic:#x})")
    if fhs < FILE_HDR_SZ: f.read(FILE_HDR_SZ - fhs)
    out = open(dst, 'wb'); written = 0
    for _ in range(total_chunks):
        ch = f.read(chs if chs >= CHUNK_HDR_SZ else CHUNK_HDR_SZ)
        if chs > CHUNK_HDR_SZ: ch += f.read(chs - CHUNK_HDR_SZ)
        if len(ch) < CHUNK_HDR_SZ: die("urwany naglowek chunka")
        typ, _res, cblks, total_sz = struct.unpack('<HHII', ch[:CHUNK_HDR_SZ])
        payload = f.read(total_sz - chs if total_sz > chs else 0)
        if typ == CHUNK_RAW:
            if len(payload) != cblks * blk: die("chunk RAW: rozjazd danych")
            out.write(payload)
        elif typ == CHUNK_FILL:
            if len(payload) != 4: die("chunk FILL bez 4-bajtowej wartosci")
            out.write(payload * (cblks * blk // 4))
        elif typ == CHUNK_DONT_CARE:
            out.seek(cblks * blk, 1)
        elif typ == CHUNK_CRC32:
            pass
        else:
            die(f"nieznany typ chunka {typ:#x}")
        written += cblks
    out.close()
    print(f"raw: {written * blk} B (z {total_chunks} chunkow)")

def info(src):
    f = open(src, 'rb')
    magic, maj, mnr, fhs, chs, blk, total_blks, total_chunks, csum = \
        struct.unpack('<IHHHHIIII', f.read(FILE_HDR_SZ))
    if magic != MAGIC: die(f"to NIE jest sparse (magic {magic:#x})")
    print(f"sparse v{maj}.{mnr}, blok {blk} B, {total_blks} blokow ({total_blks*blk} B raw), {total_chunks} chunkow")
    counts = {}
    for _ in range(total_chunks):
        ch = f.read(max(chs, CHUNK_HDR_SZ))
        typ, _r, cblks, total_sz = struct.unpack('<HHII', ch[:CHUNK_HDR_SZ])
        f.seek(total_sz - chs if total_sz > chs else 0, 1)
        counts[typ] = counts.get(typ, 0) + 1
    for typ, n in counts.items():
        name = {CHUNK_RAW: 'RAW', CHUNK_FILL: 'FILL', CHUNK_DONT_CARE: 'DONT-CARE',
                CHUNK_CRC32: 'CRC32'}.get(typ, hex(typ))
        print(f"  {name}: {n} chunkow")

def selftest():
    import os, tempfile
    blk = 4096
    raw = (b'A' * blk + b'\x00' * (3 * blk) + b'B' * (2 * blk) +
           b'\x00' * blk + b'C' * blk)
    d = tempfile.mkdtemp()
    p_raw, p_sp, p_back = (os.path.join(d, x) for x in ('r.img', 's.img', 'b.img'))
    open(p_raw, 'wb').write(raw)
    img2simg(p_raw, p_sp, blk)
    simg2img(p_sp, p_back)
    assert open(p_back, 'rb').read() == raw, "round-trip NIE jest tozsamosciowy!"
    sp = open(p_sp, 'rb').read()
    magic, maj, mnr, fhs, chs, blksz, tb, tc, cs = struct.unpack('<IHHHHIIII', sp[:28])
    assert (magic, maj, mnr, fhs, chs, blksz, tb, tc) == (MAGIC, 1, 0, 28, 12, blk, 8, 5)
    off, types = 28, []
    raws = {0: b'A'*blk, 2: b'B'*2*blk, 4: b'C'*blk}
    for i in range(5):
        typ, _r, cblks, total_sz = struct.unpack('<HHII', sp[off:off+12])
        types.append(typ)
        if typ == CHUNK_RAW:
            assert sp[off+12:off+total_sz] == raws[i]
        else:
            assert typ == CHUNK_FILL and cblks == (3 if i == 1 else 1)
        off += total_sz
    assert types == [CHUNK_RAW, CHUNK_FILL, CHUNK_RAW, CHUNK_FILL, CHUNK_RAW]
    assert off == len(sp)
    print("SELFTEST: img2simg/simg2img OK")

if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if '--selftest' in sys.argv: selftest()
    elif len(args) == 3 and args[0] == 'img2simg': img2simg(args[1], args[2])
    elif len(args) == 3 and args[0] == 'simg2img': simg2img(args[1], args[2])
    elif len(args) == 2 and args[0] == 'info':     info(args[1])
    else:
        print(__doc__); sys.exit(2)
