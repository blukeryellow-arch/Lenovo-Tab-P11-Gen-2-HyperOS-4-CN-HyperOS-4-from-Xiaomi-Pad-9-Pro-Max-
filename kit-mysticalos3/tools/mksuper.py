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

Uzycie: mksuper.py <system.img> <super.img> [nazwa_partycji]
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


def build_metadata(super_size, num_sectors, first_logical_sector, part_name):
    # ---- tabele ----
    partitions = struct.pack("<36sIIII", part_name.encode(), 0, 0, 1, 0)
    extents = struct.pack("<QIQI", num_sectors, 0, first_logical_sector, 0)
    groups = struct.pack("<36sIQ", b"default", 0, 0)
    blockdev = struct.pack("<QIIQ36sI", first_logical_sector, ALIGNMENT, 0,
                           super_size, b"super", 0)
    tables = partitions + extents + groups + blockdev
    tables_size = len(tables)
    for blob, sz in ((partitions, SZ_PARTITION), (extents, SZ_EXTENT),
                     (groups, SZ_GROUP), (blockdev, SZ_BLOCKDEV)):
        assert len(blob) == sz

    # ---- deskryptory (offsety wzgledem KONCA headera) ----
    d_part = struct.pack("<III", 0, 1, SZ_PARTITION)
    d_ext = struct.pack("<III", SZ_PARTITION, 1, SZ_EXTENT)
    d_grp = struct.pack("<III", SZ_PARTITION + SZ_EXTENT, 1, SZ_GROUP)
    d_bdv = struct.pack("<III", SZ_PARTITION + SZ_EXTENT + SZ_GROUP, 1, SZ_BLOCKDEV)

    # ---- header v1.0 (checksumi = 0 do policzenia) ----
    hdr = struct.pack("<IHHI32sI32s", HEADER_MAGIC, MAJOR_VERSION, MINOR_VERSION,
                      SZ_HEADER_V1_0, b"\x00" * 32, tables_size, b"\x00" * 32)
    hdr += d_part + d_ext + d_grp + d_bdv
    assert len(hdr) == SZ_HEADER_V1_0, len(hdr)
    hdr_chk = sha256(hdr)
    tbl_chk = sha256(tables)
    hdr = hdr[:12] + hdr_chk + hdr[44:48] + tbl_chk + hdr[80:]
    assert len(hdr) == SZ_HEADER_V1_0
    return hdr + tables


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    part_name = sys.argv[3] if len(sys.argv) > 3 else "system"

    import os
    img_size = os.path.getsize(src)
    assert img_size % SECTOR == 0, "obraz systemu musi byc wielokrotnoscia 512"
    num_sectors = img_size // SECTOR

    # layout: reserved + geometry x2 + sloty (primary+backup)
    meta_start = RESERVED + GEOM_SIZE * 2                 # 12288
    content_off = meta_start + METADATA_MAX_SIZE * METADATA_SLOT_COUNT * 2  # 20480
    first_logical_sector = content_off // SECTOR          # 40

    super_size = content_off + img_size
    if super_size % ALIGNMENT:
        super_size += ALIGNMENT - (super_size % ALIGNMENT)

    geom = build_geometry()
    meta = build_metadata(super_size, num_sectors, first_logical_sector, part_name)

    with open(src, "rb") as r, open(dst, "wb") as w:
        w.write(b"\x00" * RESERVED)                            # reserved
        w.write(geom + b"\x00" * (GEOM_SIZE - len(geom)))      # geometry primary
        w.write(geom + b"\x00" * (GEOM_SIZE - len(geom)))      # geometry backup
        blob = meta + b"\x00" * (METADATA_MAX_SIZE - len(meta))
        w.write(blob)                                          # slot 0 primary
        w.write(blob)                                          # slot 0 backup
        assert w.tell() == content_off, w.tell()
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            w.write(chunk)
        pad = super_size - w.tell()
        if pad > 0:
            w.write(b"\x00" * pad)
    print("super: %s (system: %d sektorow, zawartosc @ %d, partycja '%s', "
          "metadata v%d.%d)" % (dst, num_sectors, content_off, part_name,
                                MAJOR_VERSION, MINOR_VERSION))
    return 0


if __name__ == "__main__":
    sys.exit(main())
