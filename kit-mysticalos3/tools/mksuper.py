#!/usr/bin/env python3
"""Buduje super.img (format liblp / logical partitions) z JEDNA logiczna
partycja "system", ktora liniowo mapuje zawartosc podanego obrazu.
Bez lpmake - czysty python na podstawie metadata_format.h (AOSP liblp).

Uzycie: mksuper.py <system.img> <super.img> [nazwa_partycji]
Wyjscie: super.img = [geometry x2][metadata slot0 x2][zawartosc system.img]
"""
import hashlib
import struct
import sys

GEOMETRY_MAGIC = 0x616C4467
HEADER_MAGIC = 0x414C5030
SECTOR = 512
RESERVED = 4096          # LP_PARTITION_RESERVED_BYTES
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
    # magic, struct_size, checksum[32](=0), metadata_max_size,
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
    assert len(partitions) == SZ_PARTITION
    extents = struct.pack("<QIQI", num_sectors, 0, first_logical_sector, 0)
    assert len(extents) == SZ_EXTENT
    groups = struct.pack("<36sIQ", b"default", 0, 0)
    assert len(groups) == SZ_GROUP
    blockdev = struct.pack("<QIIQ36sI", first_logical_sector, ALIGNMENT, 0,
                           super_size, b"super", 0)
    assert len(blockdev) == SZ_BLOCKDEV
    tables = partitions + extents + groups + blockdev
    tables_size = len(tables)

    # ---- deskryptory (offsety wzgledem konca headera) ----
    d_part = struct.pack("<III", 0, 1, SZ_PARTITION)
    d_ext = struct.pack("<III", SZ_PARTITION, 1, SZ_EXTENT)
    d_grp = struct.pack("<III", SZ_PARTITION + SZ_EXTENT, 1, SZ_GROUP)
    d_bdv = struct.pack("<III", SZ_PARTITION + SZ_EXTENT + SZ_GROUP, 1, SZ_BLOCKDEV)

    # ---- header v1.0 (checksumi = 0 do policzenia) ----
    hdr = struct.pack("<IHHI32sI32s", HEADER_MAGIC, 1, 0, SZ_HEADER_V1_0,
                      b"\x00" * 32, tables_size, b"\x00" * 32)
    hdr += d_part + d_ext + d_grp + d_bdv
    assert len(hdr) == SZ_HEADER_V1_0, len(hdr)
    hdr_chk = sha256(hdr)
    tbl_chk = sha256(tables)
    hdr = hdr[:12] + hdr_chk + hdr[44:48] + tbl_chk + hdr[80:]
    # ^ wstaw: header_checksum @12..43, tables_checksum @48..79
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

    # pierwszy sektor ZA metadanymi: 2 bloki geometry + sloty (primary+backup)
    meta_bytes = RESERVED * 2 + METADATA_MAX_SIZE * METADATA_SLOT_COUNT * 2
    first_logical_sector = meta_bytes // SECTOR
    content_off = first_logical_sector * SECTOR

    super_size = content_off + img_size
    # wyrownanie rozmiaru super do 1 MiB (kosmetyka GPT)
    if super_size % ALIGNMENT:
        super_size += ALIGNMENT - (super_size % ALIGNMENT)

    geom = build_geometry()
    meta = build_metadata(super_size, num_sectors, first_logical_sector, part_name)

    with open(src, "rb") as r, open(dst, "wb") as w:
        w.write(geom + b"\x00" * (RESERVED - len(geom)))       # geometry
        w.write(geom + b"\x00" * (RESERVED - len(geom)))       # backup geometry
        blob = meta + b"\x00" * (METADATA_MAX_SIZE - len(meta))
        w.write(blob)                                          # slot 0 primary
        w.write(blob)                                          # slot 0 backup
        assert w.tell() == content_off
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            w.write(chunk)
        pad = super_size - w.tell()
        if pad > 0:
            w.write(b"\x00" * pad)
    print("super: %s (system: %d sektorow, zawartosc @ %d, partycja '%s')"
          % (dst, num_sectors, content_off, part_name))
    return 0


if __name__ == "__main__":
    sys.exit(main())
