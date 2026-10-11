#!/usr/bin/env python3
"""lpinfo.py - parser metadanych liblp (super.img) bez zaleznosci zewnetrznych.

Format: LpGeometryHeader @4096 (+backup @8192), LpMetadataHeader @12288
        (+ sloty co metadata_max_size). Structs packed, LE (system/core/fs_mgr/liblp).

Uzycie:
  lpinfo.py <super.img>            -> geometry + devices + grupy + partycje
  lpinfo.py --json <super.img>     -> to samo jako JSON
"""
import json
import struct
import sys

LP_METADATA_GEOMETRY_MAGIC = 0x616C4467  # 'gDla' (receipt: lpmake mini-super @4096; 0x616C5379 = zawsze fallback)
LP_METADATA_HEADER_MAGIC = 0x414C5030    # 'ALP0' LE
GEOMETRY_OFFSET = 4096
GEOMETRY_SIZE = 4096


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def u64(b, o):
    return struct.unpack_from("<Q", b, o)[0]


def u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def _find(data, magic):
    """Skan pliku za magic (LE) - odporne na rozne layouty (super pelny vs blob)."""
    needle = struct.pack("<I", magic)
    off = 0
    while True:
        i = data.find(needle, off)
        if i < 0 or i % 4 == 0:
            return i
        off = i + 1


def parse_geometry(data):
    g_off = _find(data, LP_METADATA_GEOMETRY_MAGIC)
    if g_off < 0:
        # Blob flashtoolowy (Lenovo): moze miec zdegenerowana geometrie (magic 'gDla',
        # pola zerowane). lpdumps czyta metadane bez niej - robimy to samo.
        return {"magic": "brak (blob flashtoolowy)", "struct_size": None,
                "metadata_max_size": 65536, "metadata_slot_count": 3,
                "logical_block_size": 4096, "note": "geometry fallback (standard VAB)"}
    g = data[g_off:g_off + GEOMETRY_SIZE]
    struct_size = u32(g, 4)
    # checksum[32] @8
    return {
        "magic": f"{LP_METADATA_GEOMETRY_MAGIC:#x}",
        "struct_size": struct_size,
        "metadata_max_size": u32(g, 40),
        "metadata_slot_count": u32(g, 44),
        "logical_block_size": u32(g, 48),
    }


def parse_metadata(data, geom):
    m_off = _find(data, LP_METADATA_HEADER_MAGIC)
    if m_off < 0:
        raise SystemExit("BRAK METADATA MAGIC (0x414c5030) w pliku")
    base = m_off
    hdr = data[base:base + 256]
    magic = u32(hdr, 0)
    if magic != LP_METADATA_HEADER_MAGIC:
        raise SystemExit(f"BAD METADATA MAGIC: {magic:#x} @ {base}")
    major, minor = u16(hdr, 4), u16(hdr, 6)
    header_size = u32(hdr, 8)
    # checksum[32] @12; tables_size @44; tables_checksum[32] @48
    tables_size = u32(hdr, 44)
    # KOLEJNOSC tabel w LpMetadataHeader (metadata_format.h):
    # v1.0+: partitions, [extents v1.1+], groups, block_devices
    # v10.0+ (VABC): + namespaces na koncu
    o = 80
    parts_tbl = (u32(hdr, o), u32(hdr, o + 4), u32(hdr, o + 8)); o += 12
    extents_tbl = (u32(hdr, o), u32(hdr, o + 4), u32(hdr, o + 8)); o += 12
    groups_tbl = (u32(hdr, o), u32(hdr, o + 4), u32(hdr, o + 8)); o += 12
    bdev_tbl = (u32(hdr, o), u32(hdr, o + 4), u32(hdr, o + 8)); o += 12
    namespaces_tbl = None
    if major >= 10:
        namespaces_tbl = (u32(hdr, o), u32(hdr, o + 4), u32(hdr, o + 8))

    tbase = base + header_size

    def table(spec, parse_entry):
        off, n, esz = spec
        out = []
        p = tbase + off
        for i in range(n):
            out.append(parse_entry(data, p))
            p += esz
        return out

    def parse_part(b, p):
        # v10.x (VABC): name[36]@0, attributes u32@36, first_extent_index u32@40,
        # num_extents u32@44, group_index u32@48 (receipt: lpmake mini + lpunpack;
        # wczesniej num_extents czytane @40 - na super_empty obie = 0, niewidoczne)
        name = b[p:p + 36].split(b"\0", 1)[0].decode()
        attrs = u32(b, p + 36)
        first_ext = u32(b, p + 40)
        num_extents = u32(b, p + 44)
        group_idx = u32(b, p + 48)
        return {"name": name, "attributes": attrs, "group_index": group_idx,
                "first_extent_index": first_ext, "num_extents": num_extents}

    def parse_group(b, p):
        name = b[p:p + 36].split(b"\0", 1)[0].decode()
        flags = u32(b, p + 36)
        return {"name": name, "flags": flags, "maximum_size": u64(b, p + 40)}

    def parse_bdev(b, p):
        # v10.x (VABC): first_logical_block u64, alignment u64, size u64,
        # name[36] @24, flags u32 @60 - receipt: super_empty TB350FU ('super', 9 GiB)
        first, = struct.unpack_from("<Q", b, p)
        align, = struct.unpack_from("<Q", b, p + 8)
        size, = struct.unpack_from("<Q", b, p + 16)
        name = b[p + 24:p + 24 + 36].split(b"\0", 1)[0].decode()
        flags = u32(b, p + 60) if p + 64 <= len(b) else 0
        return {"name": name, "first_logical_block": first, "alignment": align,
                "alignment_offset": 0, "size": size, "flags": flags}

    def parse_extent(b, p):
        num_sectors = u64(b, p)
        target_type = u32(b, p + 8)
        target_data = u64(b, p + 12)
        target_source = u32(b, p + 20)
        return {"num_sectors": num_sectors, "target_type": target_type,
                "target_data": target_data, "target_source": target_source}

    return {
        "version": f"{major}.{minor}",
        "header_size": header_size,
        "tables_size": tables_size,
        "partitions": table(parts_tbl, parse_part),
        "groups": table(groups_tbl, parse_group),
        "block_devices": table(bdev_tbl, parse_bdev),
        "extents": table(extents_tbl, parse_extent),
    }


def main():
    as_json = "--json" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        raise SystemExit(__doc__)
    with open(args[0], "rb") as f:
        data = f.read()
    geom = parse_geometry(data)
    meta = parse_metadata(data, geom)
    if as_json:
        print(json.dumps({"geometry": geom, "metadata": meta}, indent=2))
        return
    print("== GEOMETRY ==")
    for k, v in geom.items():
        print(f"  {k}: {v}")
    print("== BLOCK DEVICES ==")
    for d in meta["block_devices"]:
        print(f"  {d['name']}: size={d['size']} ({d['size'] / 1e9:.3f} GB) "
              f"align={d['alignment']} flags={d['flags']:#x}")
    print("== GROUPS ==")
    for g in meta["groups"]:
        print(f"  {g['name']}: max_size={g['maximum_size']} ({g['maximum_size'] / 1e9:.3f} GB) flags={g['flags']:#x}")
    print("== PARTITIONS ==")
    for p in meta["partitions"]:
        print(f"  {p['name']}: group={meta['groups'][p['group_index']]['name'] if p['group_index'] < len(meta['groups']) else '?'} "
              f"attrs={p['attributes']:#x} extents={p['num_extents']}")
    # Suma extents na urzadzenie (realne zajecie)
    if meta["extents"]:
        print("== EXTENTS (sumy sektorow na partycje) ==")
        by_src = {}
        for p in meta["partitions"]:
            i0, n = p["first_extent_index"], p["num_extents"]
            s = sum(e["num_sectors"] for e in meta["extents"][i0:i0 + n]
                    if e["target_type"] == 0)
            by_src[p["name"]] = s * 512
        for k, v in by_src.items():
            print(f"  {k}: {v} B ({v / 1e9:.3f} GB)")


if __name__ == "__main__":
    main()
