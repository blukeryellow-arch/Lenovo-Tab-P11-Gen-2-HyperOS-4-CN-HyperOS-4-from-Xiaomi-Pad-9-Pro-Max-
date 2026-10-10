#!/usr/bin/env python3
"""Buduje super.img (format liblp / logical partitions) z JEDNA logiczna
partycja "system", ktora liniowo mapuje zawartosc podanego obrazu.
Bez lpmake - czysty python na podstawie liblp (AOSP fs_mgr/liblp).

Layout zgodny z fs_mgr/liblp/utility.cpp:
  [0 .. 4095]    LP_PARTITION_RESERVED_BYTES (zera)
  [4096 .. 8191] geometry primary   (GetPrimaryGeometryOffset = 4096)
  [8192 ..12287] geometry backup
  [12288..16383] metadata slot 0 primary  (4096 + 2*4096)
  [16384..20479] metadata slot 0 backup   (+ metadata_max_size)
  [20480..]      zawartosc (first_logical_sector = 20480/512 = 40)

Wersja metadanych: major=10 (LP_METADATA_MAJOR_VERSION), minor=0,
header v1.0 (header_size=128, minor < VERSION_FOR_EXPANDED_HEADER).

Uzycie:
  mksuper.py <super.img> <nazwa1>=<obraz1> [<nazwa2>=<obraz2> ...]   (multi)
  mksuper.py <system.img> <super.img> [nazwa]                        (stary, 1 partycja)
"""
import hashlib
import struct
import sys

GEOMETRY_MAGIC = 0x616C4467
HEADER_MAGIC = 0x414C5030
MAJOR_VERSION = 10     # LP_METADATA_MAJOR_VERSION
MINOR_VERSION = 0      # musi byc <= LP_METADATA_MINOR_VERSION_MAX (2)
SECTOR = 512
RESERVED = 4096          # LP_PARTITION_RESERVED_BYTES
GEOM_SIZE = 4096         # LP_METADATA_GEOMETRY_SIZE
METADATA_MAX_SIZE = 4096
METADATA_SLOT_COUNT = 1
LOGICAL_BLOCK_SIZE = 4096
ALIGNMENT = 1048576

# rozmiary struktur (packed)
SZ_GEOMETRY = 52
SZ_HEADER_V1_0 = 128
SZ_PARTITION = 52
SZ_EXTENT = 24
SZ_GROUP = 48
SZ_BLOCKDEV = 64


def sha256(b):
    return hashlib.sha256(b).digest()


def build_geometry():
    # magic, struct_size, checksum[32](=0 przy liczeniu), metadata_max_size,
    # metadata_slot_count, logical_block_size
    g = struct.pack("<II32sIII", GEOMETRY_MAGIC, SZ_GEOMETRY, b"\x00" * 32,
                    METADATA_MAX_SIZE, METADATA_SLOT_COUNT, LOGICAL_BLOCK_SIZE)
    assert len(g) == SZ_GEOMETRY
    chk = sha256(g)
    return struct.pack("<II32sIII", GEOMETRY_MAGIC, SZ_GEOMETRY, chk,
                       METADATA_MAX_SIZE, METADATA_SLOT_COUNT, LOGICAL_BLOCK_SIZE)


def build_metadata(super_size, first_logical_sector, parts):
    """parts = [(name, num_sectors, extent_start_sector), ...] (po kolei)"""
    # ---- tabele (partycje i extents po jednej na partycje) ----
    part_tbl = b""
    ext_tbl = b""
    for i, (name, nsec, ext_start) in enumerate(parts):
        part_tbl += struct.pack("<36sIIII", name.encode(), 0, i, 1, 0)
        ext_tbl += struct.pack("<QIQI", nsec, 0, ext_start, 0)
    groups = struct.pack("<36sIQ", b"default", 0, 0)
    blockdev = struct.pack("<QIIQ36sI", first_logical_sector, ALIGNMENT, 0,
                           super_size, b"super", 0)
    tables = part_tbl + ext_tbl + groups + blockdev
    tables_size = len(tables)
    for blob, sz in ((part_tbl, SZ_PARTITION * len(parts)),
                     (ext_tbl, SZ_EXTENT * len(parts)),
                     (groups, SZ_GROUP), (blockdev, SZ_BLOCKDEV)):
        assert len(blob) == sz

    # ---- deskryptory (offsety wzgledem KONCA headera) ----
    n = len(parts)
    d_part = struct.pack("<III", 0, n, SZ_PARTITION)
    d_ext = struct.pack("<III", SZ_PARTITION * n, n, SZ_EXTENT)
    d_grp = struct.pack("<III", SZ_PARTITION * n + SZ_EXTENT * n, 1, SZ_GROUP)
    d_bdv = struct.pack("<III", SZ_PARTITION * n + SZ_EXTENT * n + SZ_GROUP,
                        1, SZ_BLOCKDEV)

    # ---- header v1.0 ----
    # KOLEJNOSC WAZNA (reader.cpp ReadMetadataHeader):
    #  - tables_checksum = SHA256(tables)
    #  - header_checksum = SHA256(header z WYLOOROWYM TYLKO header_checksum;
    #    tables_checksum musi byc JUZ wpisany!)
    hdr = struct.pack("<IHHI32sI32s", HEADER_MAGIC, MAJOR_VERSION, MINOR_VERSION,
                      SZ_HEADER_V1_0, b"\x00" * 32, tables_size, b"\x00" * 32)
    hdr += d_part + d_ext + d_grp + d_bdv
    assert len(hdr) == SZ_HEADER_V1_0, len(hdr)
    tbl_chk = sha256(tables)
    hdr = hdr[:48] + tbl_chk + hdr[80:]          # wpisz tables_checksum @48
    hdr_chk = sha256(hdr)                        # header_checksum nadal = 0
    hdr = hdr[:12] + hdr_chk + hdr[44:]          # wpisz header_checksum @12
    assert len(hdr) == SZ_HEADER_V1_0
    return hdr + tables


def main():
    import os
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    # format: mksuper.py <super.img> name=path [name=path ...]
    # (stary: mksuper.py <system.img> <super.img> [name] - zostawiony)
    if len(args) >= 2 and "=" in args[1]:
        dst = args[0]
        parts = []
        for spec in args[1:]:
            name, path = spec.split("=", 1)
            parts.append((name, path))
    else:
        src, dst = args[0], args[1]
        part_name = args[2] if len(args) > 2 else "system"
        parts = [(part_name, src)]

    # rozmiary i walidacja
    infos = []
    for name, path in parts:
        sz = os.path.getsize(path)
        assert sz % SECTOR == 0, "%s nie jest wielokrotnoscia 512" % path
        assert 0 < len(name) <= 36, "zla nazwa partycji: %s" % name
        infos.append((name, path, sz, sz // SECTOR))

    # layout: reserved + geometry x2 + sloty (primary+backup)
    meta_start = RESERVED + GEOM_SIZE * 2                 # 12288
    content_off = meta_start + METADATA_MAX_SIZE * METADATA_SLOT_COUNT * 2  # 20480
    first_logical_sector = content_off // SECTOR          # 40

    # extenty liniowo, wyrownane do 1 MiB (sektorowo)
    ext_start = first_logical_sector
    layout = []
    for name, path, sz, nsec in infos:
        layout.append((name, path, nsec, ext_start))
        ext_start += nsec
        if ext_start % (ALIGNMENT // SECTOR):
            ext_start += (ALIGNMENT // SECTOR) - (ext_start % (ALIGNMENT // SECTOR))

    super_size = ext_start * SECTOR
    if super_size % ALIGNMENT:
        super_size += ALIGNMENT - (super_size % ALIGNMENT)

    geom = build_geometry()
    meta = build_metadata(super_size, first_logical_sector,
                          [(n, ns, es) for (n, p, ns, es) in layout])

    with open(dst, "wb") as w:
        w.write(b"\x00" * RESERVED)                            # reserved
        w.write(geom + b"\x00" * (GEOM_SIZE - len(geom)))      # geometry primary
        w.write(geom + b"\x00" * (GEOM_SIZE - len(geom)))      # geometry backup
        blob = meta + b"\x00" * (METADATA_MAX_SIZE - len(meta))
        w.write(blob)                                          # slot 0 primary
        w.write(blob)                                          # slot 0 backup
        assert w.tell() == content_off, w.tell()
        for name, path, nsec, es in layout:
            w.seek(es * SECTOR)
            with open(path, "rb") as r:
                while True:
                    chunk = r.read(1 << 20)
                    if not chunk:
                        break
                    w.write(chunk)
        w.seek(super_size - 1)
        w.write(b"\x00")
    print("super: %s (partycje: %s; zawartosc @ %d, metadata v%d.%d)"
          % (dst, ", ".join("%s=%d s" % (n, ns) for (n, p, ns, e) in layout),
             content_off, MAJOR_VERSION, MINOR_VERSION))
    return 0


if __name__ == "__main__":
    sys.exit(main())
