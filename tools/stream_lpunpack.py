#!/usr/bin/env python3
"""stream_lpunpack.py - wypakowanie partycji ze strumienia RAW super.img.

Cel: bazowy zip lolinet zawiera super.img RAW 8,3G (deflate 45%) - za duzy na
dysk runera (avail 8-14G). Ten unpacker czyta super.img ze strumienia
(stdin lub plik) SEKWENCYJNIE i pisze tylko partycje _a do katalogu
wyjsciowego, bez materializacji super na dysku.

Format liblp (system/core/fs_mgr/liblp, metadata_format.h):
  - geometry @0 (magic 0x616C5379) + backup; metadata @4096 (magic 0x414C5030)
    w slotach co metadata_max_size
  - LpMetadataPartition: name[36]@0, attributes@36, first_extent_index@40,
    num_extents@44, group_index@48   (UWAGA: pierwotne lpinfo.py czytalo
    num_extents@40 - na super_empty obie wartosci 0 wiec bledu nie bylo widac)
  - LpMetadataExtent (packed): num_sectors u64@0 (sektory 512B),
    target_type u32@8 (0=LINEAR, 1=ZERO), target_data u64@12 (sektor na
    device dla LINEAR), target_source u32@20 (INDEX BLOCK DEVICE, nie partycji)
  - offset plikowy extentu = target_data * 512 (plik super == block device 0)

Uzycie:
  stream_lpunpack.py --out DIR (--stdin | --file super.raw) [--suffix _a]
  stdout: manifest "P <part> <rozmiar>" + "W <part> <zapisano> <oczek> <OK?>"

Test: lpmake mini-super -> lpunpack (AOSP) vs stream_lpunpack -> cmp.
"""
import os
import struct
import sys

LP_METADATA_GEOMETRY_MAGIC = 0x616C4467  # 'gDla' (receipt: lpmake mini @4096; 0x616C5379 bylo bledne -> fallback)
LP_METADATA_HEADER_MAGIC = 0x414C5030
SECTOR = 512
HEAD_HINT = 1_310_720  # 1.25 MB: geometry + 3 sloty metadanych (64K) z zapasem
CHUNK = 4 * 1024 * 1024


def u16(b, o): return struct.unpack_from("<H", b, o)[0]
def u32(b, o): return struct.unpack_from("<I", b, o)[0]
def u64(b, o): return struct.unpack_from("<Q", b, o)[0]


def parse_metadata(head):
    g = head.find(struct.pack("<I", LP_METADATA_GEOMETRY_MAGIC))
    if g < 0:
        raise SystemExit("BRAK GEOMETRY MAGIC (to nie raw super; simg2img najpierw?)")
    m = head.find(struct.pack("<I", LP_METADATA_HEADER_MAGIC))
    if m < 0:
        raise SystemExit("BRAK METADATA MAGIC w glowie (potrzeba >= 1,2 MB glowy)")
    geom = {
        "metadata_max_size": u32(head, g + 40),
        "metadata_slot_count": u32(head, g + 44),
        "logical_block_size": u32(head, g + 48),
    }
    major, minor = u16(head, m + 4), u16(head, m + 6)
    header_size = u32(head, m + 8)
    o = m + 80
    parts_tbl = (u32(head, o), u32(head, o + 4), u32(head, o + 8)); o += 12
    extents_tbl = (u32(head, o), u32(head, o + 4), u32(head, o + 8)); o += 12
    groups_tbl = (u32(head, o), u32(head, o + 4), u32(head, o + 8)); o += 12
    bdev_tbl = (u32(head, o), u32(head, o + 4), u32(head, o + 8))
    tbase = m + header_size

    def entries(spec):
        off, n, esz = spec
        p = tbase + off
        out = []
        for _ in range(n):
            out.append(head[p:p + esz])
            p += esz
        return out

    partitions = []
    for e in entries(parts_tbl):
        partitions.append({
            "name": e[0:36].split(b"\0", 1)[0].decode(),
            "attributes": u32(e, 36),
            "first_extent_index": u32(e, 40),
            "num_extents": u32(e, 44),
            "group_index": u32(e, 48),
        })
    groups = [{
        "name": e[0:36].split(b"\0", 1)[0].decode(),
        "maximum_size": u64(e, 40),
    } for e in entries(groups_tbl)]
    bdevs = [{
        "first_logical_block": u64(e, 0),
        "alignment": u64(e, 8),
        "size": u64(e, 16),
        "name": e[24:24 + 36].split(b"\0", 1)[0].decode(),
    } for e in entries(bdev_tbl)]
    extents = [{
        "num_sectors": u64(e, 0),
        "target_type": u32(e, 8),
        "target_data": u64(e, 12),
        "target_source": u32(e, 20),
    } for e in entries(extents_tbl)]
    return {"version": f"{major}.{minor}", "geometry": geom,
            "partitions": partitions, "groups": groups,
            "block_devices": bdevs, "extents": extents}


def build_segments(meta, suffix="_a"):
    """Segmenty (file_start, file_end, base, part_off) posortowane po starcie
    w pliku super. Wyłącznie LINEAR na device 0; ZERO traktowane jako dziura
    (w fabrycznych super nie występują - jeżeli są, fail głośno)."""
    segs = []
    files = {}
    for p in meta["partitions"]:
        if not p["name"].endswith(suffix) or p["num_extents"] == 0:
            continue
        base = p["name"][: -len(suffix)]
        pos = 0
        for i in range(p["first_extent_index"],
                       p["first_extent_index"] + p["num_extents"]):
            e = meta["extents"][i]
            nbytes = e["num_sectors"] * SECTOR
            if e["target_type"] != 0:
                raise SystemExit(f"{base}: extent typu {e['target_type']} (ZERO) - nieobslugiwane")
            if e["target_source"] != 0:
                raise SystemExit(f"{base}: extent na device {e['target_source']} != 0")
            segs.append((e["target_data"] * SECTOR,
                         e["target_data"] * SECTOR + nbytes, base, pos))
            pos += nbytes
        files[base] = pos
    segs.sort(key=lambda s: s[0])
    for a, b in zip(segs, segs[1:]):
        if a[1] > b[0]:
            raise SystemExit(f"NAKLADAJACE sie segmenty: {a} vs {b}")
    return segs, files


def main():
    argv = sys.argv[1:]
    out_dir = argv[argv.index("--out") + 1]
    use_stdin = "--stdin" in argv
    file_path = argv[argv.index("--file") + 1] if "--file" in argv else None
    suffix = argv[argv.index("--suffix") + 1] if "--suffix" in argv else "_a"
    head_out = argv[argv.index("--head") + 1] if "--head" in argv else None
    if bool(use_stdin) == bool(file_path):
        raise SystemExit("podaj dokladnie jedno zrodlo: --stdin albo --file")

    src = sys.stdin.buffer if use_stdin else open(file_path, "rb")

    def read_exact(n):
        buf = b""
        while len(buf) < n:
            part = src.read(n - len(buf))
            if not part:
                break
            buf += part
        return buf

    # glowa: bufor poczatkowy; strumien po jej odczytaniu jest na pozycji
    # len(head). Uwaga: pierwszy segment danych moze zaczynac sie WEWNATRZ
    # glowy (np. @1M przy glowie 1,25M) - te bajty serwujemy z bufora.
    head = read_exact(HEAD_HINT)
    if len(head) < 512 * 1024:
        raise SystemExit(f"glowa za krotka: {len(head)} (strumien urwany?)")
    meta = parse_metadata(head)
    segs, files = build_segments(meta, suffix)
    os.makedirs(out_dir, exist_ok=True)
    if head_out:
        with open(head_out, "wb") as f:
            f.write(head)
    bd = meta["block_devices"][0] if meta["block_devices"] else {}
    print(f"# liblp v{meta['version']}; slots={meta['geometry']['metadata_slot_count']}; "
          f"bdev={bd.get('name', '?')} ({bd.get('size', 0)} B); "
          f"grupy={[g['name'] for g in meta['groups']]}")
    print(f"# glowy={len(head)} B; segmenty: {[(s[2], s[0], s[1]) for s in segs]}")
    for base in sorted(files):
        print(f"P\t{base}\t{files[base]}")

    outs = {base: open(os.path.join(out_dir, base + ".img"), "wb") for base in files}
    written = dict.fromkeys(files, 0)
    pos = 0  # logiczna pozycja od POCZATKU super

    def skip_to(target):
        nonlocal pos
        while pos < target:
            if pos < len(head):
                pos = min(target, len(head))
            else:
                n = min(target - pos, CHUNK)
                buf = read_exact(n)
                if len(buf) < n:
                    raise SystemExit(f"strumien za krotki przy skip do {target}")
                pos += len(buf)

    for fs, fe, base, part_off in segs:
        if fs < pos:
            raise SystemExit(f"segment {base} zaczyna sie {fs} < pozycji {pos} (niespojny strumien)")
        skip_to(fs)
        fpart = outs[base]
        fpart.seek(part_off)
        need = fe - fs
        while need > 0:
            if pos < len(head):
                take = min(need, len(head) - pos)
                fpart.write(head[pos:pos + take])
                pos += take
                need -= take
                written[base] += take
            else:
                buf = read_exact(min(need, CHUNK))
                if not buf:
                    raise SystemExit(f"strumien za krotki w {base} (brakuje {need})")
                fpart.write(buf)
                pos += len(buf)
                need -= len(buf)
                written[base] += len(buf)
    for f in outs.values():
        f.close()
    if not use_stdin:
        src.close()
    ok_all = True
    for base in sorted(files):
        ok = written[base] == files[base] and \
            os.path.getsize(os.path.join(out_dir, base + ".img")) == files[base]
        ok_all = ok_all and ok
        print(f"W\t{base}\t{written[base]}\t{files[base]}\t{'OK' if ok else 'NIEPELNY'}")
    sys.exit(0 if ok_all else 1)


if __name__ == "__main__":
    main()
