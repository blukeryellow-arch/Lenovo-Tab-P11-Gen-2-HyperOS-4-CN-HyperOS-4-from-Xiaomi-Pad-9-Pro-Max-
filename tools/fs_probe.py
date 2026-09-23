#!/usr/bin/env python3
"""Geometria obrazow partycji - to, czego potrzebuje arytmetyka dopasowania do super.

Czysty Python, zero zaleznosci, WYLACZNIE odczyt. Dziala w sandboxie agenta (bez
e2fsprogs) i na runnerze Actions.

Uczone na bledzie: naglowek obrazu boot (ANDROID!) ma kilka układow pol (v0 vs v3/v4
vs wlasnosciowy MTK) i zgadywanie ich dawalo liczby typu "ramdisk 384 MB". Dlatego
boot/vendor_boot DUMP-UJEMY SUROWO, bez interpretacji - a interpretujemy tylko te
struktury, ktore sa norma i ktore umiemy sprawdzic: ext4, EROFS, Android sparse.

Uzycie:
  ./fs_probe.py obraz.img [...]     odczyt
  ./fs_probe.py --selftest          walidacja parserow na superblockach generowanych w tym pliku
"""
import os
import struct
import sys

SPARSE_MAGIC = b'\x3b\xff\x26\xed'
EROFS_MAGIC = b'\xe2\xe1\xf5\xe0'


def human(n):
    n = float(n)
    for unit in ('B', 'KiB', 'MiB', 'GiB', 'TiB'):
        if abs(n) < 1024 or unit == 'TiB':
            return f"{n:.0f} {unit}" if unit == 'B' else f"{n:.2f} {unit}"
        n /= 1024.0


def probe_raw_boot(fh, size):
    """Bez interpretacji: surowe slowa. Interpretacja boot naglowka wymaga
    mkbootimg/avbtool - nie tej funkcji."""
    fh.seek(0)
    head = fh.read(8)
    if head in (b'ANDROID!', b'VNDRBOOT', b'RECOVRYX'):
        kind = {b'ANDROID!': 'boot', b'VNDRBOOT': 'vendor_boot', b'RECOVRYX': 'recovery'}[head]
        fh.seek(8)
        words = struct.unpack('<12I', fh.read(48))
        print(f"  {kind} (magic {head.decode()}) - SUROWE pola @8..:")
        labels = ('f0', 'f1', 'f2', 'f3', 'f4', 'f5', 'f6', 'f7', 'page?', 'hdrver?', 'osver?', 'f11')
        for lab, w in zip(labels, words):
            print(f"    {lab:8s} = {w:>12}  (0x{w:08x})")
        print("    Nie wnioskuje z tego rozmiarow: uklad pol rozni sie miedzy v0, v3/v4")
        print("    i buildami MTK. Do odczytu: avbtool (blok AVB) albo mkbootimg --print_images.")
        return {'kind': kind, 'raw': words}
    if head[:4] == b'AVB0':
        auth, aux = struct.unpack('>2Q', _readat(fh, 8, 16))
        print(f"  blok vbmeta: auth={auth} B aux={aux} B (raz {256 + auth + aux} B)")
        return {'kind': 'vbmeta', 'block_bytes': 256 + auth + aux}
    if head[:2] == b'\x1f\x8b':
        print("  surowy gzip")
        return {'kind': 'gzip'}
    return None


def _readat(fh, off, n):
    fh.seek(off)
    return fh.read(n)


def probe_ext4(fh, size):
    sb = _readat(fh, 1024, 256)
    if len(sb) < 256 or sb[56:58] != b'\x53\xef':
        return None
    blocks, rblocks, free, inodes = struct.unpack_from('<4I', sb, 4)
    log_bs, mkblock, inodes_per_grp, magic, state = struct.unpack_from('<5H', sb, 24)[:5]
    log_bs = struct.unpack_from('<I', sb, 24)[0]
    bs = 1024 << log_bs
    feat = struct.unpack_from('<I', sb, 96)[0]
    names = [nm for bit, nm in ((0, 'sparse_super'), (1, 'large_file'), (5, 'flex_bg'),
                                (10, '64bit'), (12, 'dir_nlink'), (13, 'extra_isize'),
                                (17, 'metadata_csum'), (18, 'largedir'), (22, 'orphan_file'))
             if feat >> bit & 1]
    if feat >> 10 & 1:  # 64bit: gorne 32 bity liczby blokow
        blocks |= struct.unpack('<I', _readat(fh, 1024 + 0x150, 4))[0] << 32
    used = max(0, blocks - free)
    print(f"  ext2/3/4: {blocks} blokow x {bs} B = {human(blocks * bs)}")
    print(f"    zajete {human(used * bs)} | wolne {human(free * bs)} | rezerwa roota {human(rblocks * bs)}")
    print(f"    inodes {inodes} | stan {state} | incompat: {', '.join(names) or '-'}")
    print(f"    -> TYLE musi zmiescic partycja docelowa: {human(used * bs)} "
          f"(nie {human(size)} - reszta pliku to padding)")
    return {'kind': 'ext4', 'used_bytes': used * bs, 'image_bytes': blocks * bs,
            'file_bytes': size, 'block_size': bs, 'blocks': blocks, 'free': free,
            'inodes': inodes}


def probe_erofs(fh, size):
    """erofs_super_block: magic@0, features@4, blkszbits@8, sb_packbits@9,
    ondisk_size@10, bb_size@24, meta_ino@56, vol_name@60[32].
    Pola pewne interpretujemy; reszta - nie, bo layout bywal przerabiany."""
    d = _readat(fh, 1024, 128)
    if len(d) < 128 or d[:4] != EROFS_MAGIC:
        return None
    magic, features = struct.unpack_from('<2I', d, 0)
    blkszbits = d[8]
    sb_packbits = d[9]
    ondisk = struct.unpack_from('<H', d, 10)[0]
    bb_size = struct.unpack_from('<I', d, 24)[0]
    vol = d[60:92].split(b'\0')[0].decode('utf-8', 'replace')
    bs = 1 << blkszbits if 8 < blkszbits < 20 else 0
    print(f"  EROFS: bb_size={bb_size} blokow, blkszbits={blkszbits}"
          f" -> blok {bs or '?'} B, ondisk_size={ondisk}, packbits={sb_packbits}")
    if vol:
        print(f"    nazwa woluminu: {vol!r}")
    if bs:
        print(f"    zajetosc FS: {human(bb_size * bs)} z {human(size)} pliku"
              f" (roznica = padding partycji)")
    print("    features: " + ", ".join(nm for bit, nm in
          ((0, 'INCOMPAT_XXXX'), (1, 'COMPRESS_LZ4'), (4, 'EXTRA_DEVICE'),
           (6, 'DEDUPE'), (7, 'FRAGMENTS'), (8, 'COMPRESSION_BIT'),
           (17, 'COMPRESS_LZ4HC'), (18, 'COMPRESS_ZSTD'), (19, 'LARGE_SLOTS'))
          if features >> bit & 1) or "-")
    print("    -> pojedyncze pliki (build.prop) wyciaga dump.erofs/fsck.erofs, nie ten skrypt")
    return {'kind': 'erofs', 'bb_size': bb_size, 'block_size': bs,
            'used_bytes': bb_size * bs if bs else None, 'file_bytes': size}


def probe_sparse(fh, size):
    """sparse_header: magic@0, major@4, minor@6, file_hdr_size@8, chunk_size@12,
    blk_sz@16, blk_cnt@20, total_chunks@24."""
    buf = _readat(fh, 0, 28)
    if buf[:4] != SPARSE_MAGIC:
        return None
    vmaj, vmin, hdrsz, chunksz, blksz, nb, totchk = struct.unpack_from('<HH5I', buf, 4)
    print(f"  Android SPARSE v{vmaj}.{vmin}: file_hdr_size={hdrsz} chunk={chunksz} B "
          f"blk_sz={blksz} B blk_cnt={nb} total_chunks={totchk}")
    print(f"    po konwersji (simg2img) raw = {human(nb * blksz)}; plik zajety = {human(size)}")
    print("    -> obraz w srodku to wlasciwy FS: najpierw simg2img, pozniej ten skrypt")
    return {'kind': 'sparse', 'raw_bytes': nb * blksz, 'file_bytes': size,
            'blk_sz': blksz, 'blk_cnt': nb}


def probe(path):
    """Pojedynczy obraz -> typ + geometria. Nigdy nie rzuca wyjatkami na zewnatrz."""
    size = os.path.getsize(path)
    print(f"### {os.path.basename(path)}  {human(size)}")
    with open(path, 'rb') as fh:
        r = probe_raw_boot(fh, size)
        if r is None and size >= 4096:
            r = (probe_sparse(fh, size) or probe_ext4(fh, size)
                 or probe_erofs(fh, size))
        if r is None:
            print(f"  naglowek nierozpoznany: {_readat(fh, 0, 8).hex()}")
            r = {'kind': 'unknown'}
    print()
    return r


# --------------------------------------------------------------------------
def _mk_ext4_sb(blocks=1_000_000, free=250_000, reserved=50_000, inodes=65_536,
                log_bs=2, feat=0, blocks_hi=None):
    sb = bytearray(1024)  # superblock ext4 ma 1024 B
    if blocks_hi is not None:
        struct.pack_into('<I', sb, 0x150, blocks_hi)
    struct.pack_into('<4I', sb, 4, blocks, reserved, free, inodes)
    struct.pack_into('<I', sb, 24, log_bs)
    struct.pack_into('<H', sb, 56, 0xEF53)
    struct.pack_into('<I', sb, 96, feat)
    return bytes(sb)


def _mk_erofs_sb(bb_size=4096, blkszbits=12, features=1 << 1):
    d = bytearray(128)
    struct.pack_into('<2I', d, 0, 0xE0F5E1E2, features)
    d[8] = blkszbits
    struct.pack_into('<H', d, 10, 128)
    struct.pack_into('<I', d, 24, bb_size)
    d[60:68] = b'testvol\0'
    return bytes(d)


def selftest():
    import io
    ok = True
    # ext4: 1 000 000 x 4096 = 4,10 GB, wolne 250 000 -> zajete 750 000 blokow
    img = bytearray(1024) + bytearray(_mk_ext4_sb()) + bytearray(4096)
    r = probe_ext4(io.BytesIO(bytes(img)), len(img))
    exp = {'kind': 'ext4', 'used_bytes': 750_000 * 4096, 'image_bytes': 1_000_000 * 4096,
           'block_size': 4096, 'blocks': 1_000_000, 'free': 250_000, 'inodes': 65_536}
    for k, v in exp.items():
        if r.get(k) != v:
            print(f"  BLAD ext4: {k} = {r.get(k)}, oczekiwano {v}")
            ok = False
    # ext4 z 64bit
    sb = bytearray(_mk_ext4_sb(blocks=0xFFFFFFFF, free=0xFFFF_FFFF, feat=1 << 10,
                               blocks_hi=3))
    img = bytearray(1024) + sb + bytearray(4096)
    r = probe_ext4(io.BytesIO(bytes(img)), len(img))
    if r['blocks'] != 0xFFFFFFFF | (3 << 32):
        print(f"  BLAD ext4 64bit: blocks={r['blocks']}")
        ok = False
    # EROFS
    img = bytearray(1024) + bytearray(_mk_erofs_sb(bb_size=4096, blkszbits=12)) + bytearray(4096)
    r = probe_erofs(io.BytesIO(bytes(img)), len(img))
    if r['used_bytes'] != 4096 * 4096:
        print(f"  BLAD erofs: used={r['used_bytes']} (ma byc bb_size x blok = 4096*4096)")
        ok = False
    if r.get('bb_size') != 4096 or r.get('block_size') != 4096:
        print("  BLAD erofs: bb_size/block_size")
        ok = False
    # sparse
    d = bytearray(28)
    struct.pack_into('<4sHH5I', d, 0, SPARSE_MAGIC, 1, 0, 28, 4096, 4096, 100, 3)
    img = bytes(d) + bytes(4096)
    r = probe_sparse(io.BytesIO(img), len(img))
    if r['raw_bytes'] != 100 * 4096 or r['blk_cnt'] != 100:
        print(f"  BLAD sparse: raw={r['raw_bytes']} blk_cnt={r['blk_cnt']} (ma byc 100 x 4096)")
        ok = False
    print("SELFTEST:", "WSZYSTKIE PARSERY OK" if ok else "ROZJEZIE - nie ufac liczbom z tego pliku")
    return 0 if ok else 1


if __name__ == '__main__':
    args = sys.argv[1:]
    if args == ['--selftest']:
        sys.exit(selftest())
    if not args:
        print(__doc__)
        sys.exit(2)
    rc = 0
    for p in args:
        if not os.path.exists(p):
            print(f"### {p}: NIE ISTNIEJE\n")
            rc = 1
            continue
        try:
            probe(p)
        except Exception as e:
            print(f"  BLAD: {type(e).__name__}: {e}\n")
            rc = 1
    sys.exit(rc)
