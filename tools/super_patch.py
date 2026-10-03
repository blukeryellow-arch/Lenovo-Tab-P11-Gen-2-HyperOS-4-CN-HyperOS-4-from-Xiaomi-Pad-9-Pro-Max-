#!/usr/bin/env python3
"""super_patch.py - buduje SPARSE super.img na stdout z localnych obrazow
partycji + metadanych bazowego super (z glowy), BEZ lpmake i BEZ posrednich
plikow na dysku.

Dlaczego: obrazy partycji _a bazowego super TB350FU to 8,18G (receipt runu
36617353135); lpmake wymaga wszystkich obrazow + pliku wyjsciowego naraz
(8,1G + 8,3G = 16,4G) - niewykonalne na runnerze (avail 8-14G). Ten patcher:
  - czyta TYLKO glowe bazowego super (1,25M: geometry + 3 sloty metadanych),
  - splicuje wlasne extenty (nowe rozmiary/offsety obrazow m3) i przelicza
    checksumy liblp (SHA256 header/tables),
  - emituje SPARSE (magic 0xED26FF3A) strumieniowo na stdout: RAW chunki
    czytane z obrazow (<=64M na chunk, nic w RAM), DONT-CARE na dziury,
  - po skonsumowaniu obrazu UNLINK go (progresywne zwalnianie dysku w trakcie
    zapisu czastek; wylaczane flaga --keep).

Semantyka formatu (system/core/libsparse/sparse_format.h + liblp):
  chunk_header: type u16, reserved u16, chunk_sz u32 (bloki), total_sz u32
  (RAZEM z naglowkiem 12B: RAW=12+data, FILL=12+4, DONT-CARE=12, CRC=12+4),
  LpMetadataHeader.header_checksum = SHA256(header[0:header_size] z oboma
  polami checksum wyzerowanymi), tables_checksum = SHA256(tables).

Uzycie:
  super_patch.py --head head.bin --device-size N --img part=plik [--img ...]
                 [--keep] [--block 4096] > super_sparse.img
  stderr: layout (linie "L part size off region") + manifest.
"""
import hashlib
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from stream_lpunpack import parse_metadata  # noqa: E402

SPARSE_MAGIC = 0xED26FF3A
CHUNK_RAW = 0xCAC1
CHUNK_DONT_CARE = 0xCAC3
RAW_CHUNK_MAX = 64 * 1024 * 1024
GEOM_MAGIC = 0x616C4467
META_MAGIC = 0x414C5030


def sha256(b):
    return hashlib.sha256(b).digest()


def patch_metadata_slot(slot_bytes, header_size, tables_size, extents_tbl, new_extents):
    """Splicuje nowe wpisy extentow (ext_index -> (num_sectors, target_sector))
    w bajtach slotu metadanych i przelicza checksumy liblp. Zwraca nowe bajty."""
    buf = bytearray(slot_bytes[:header_size + tables_size])
    tbase = header_size + extents_tbl[0]
    for idx, (num_sectors, target_sector) in new_extents.items():
        off = tbase + idx * 24
        struct.pack_into("<Q", buf, off, num_sectors)            # num_sectors
        struct.pack_into("<I", buf, off + 8, 0)                  # LINEAR
        struct.pack_into("<Q", buf, off + 12, target_sector)     # target_data
        struct.pack_into("<I", buf, off + 20, 0)                 # device 0
    # SEMANTYKA (wyprowadzona empirycznie z oryginalu lpmake, 29 IX):
    #   tables_checksum = SHA256(tables[0:tables_size])
    #   header_checksum = SHA256(header[0:header_size] z wyzerowanym WYLACZNIE
    #                             header_checksum @12..44; tables_checksum wchodzi
    #                             do hashu WARTOSCIA)
    tables = bytes(buf[header_size:header_size + tables_size])
    buf[48:80] = sha256(tables)                    # tables_checksum @48..80
    hdr = bytearray(buf[:header_size])
    hdr[12:44] = b"\0" * 32                        # tylko header_checksum zero
    buf[12:44] = sha256(bytes(hdr))                # header_checksum @12..44
    return bytes(buf)


def main():
    argv = sys.argv[1:]
    head_path = argv[argv.index("--head") + 1]
    device_size = int(argv[argv.index("--device-size") + 1])
    block = int(argv[argv.index("--block") + 1]) if "--block" in argv else 4096
    keep = "--keep" in argv
    out_dir = argv[argv.index("--out-dir") + 1] if "--out-dir" in argv else None
    n_parts = int(argv[argv.index("--parts") + 1]) if "--parts" in argv else None
    prefix = argv[argv.index("--prefix") + 1] if "--prefix" in argv else "super_mystical3.part."
    images = {}
    i = 0
    while i < len(argv):
        if argv[i] == "--img":
            k, v = argv[i + 1].split("=", 1)
            images[k] = v
            i += 2
        else:
            i += 1
    if out_dir and not n_parts:
        raise SystemExit("--out-dir wymaga --parts")

    head = open(head_path, "rb").read()
    meta = parse_metadata(head)

    g_off = head.find(struct.pack("<I", GEOM_MAGIC))
    if g_off < 0:
        raise SystemExit("BRAK GEOMETRY w head")
    m0 = g_off + 2 * 4096
    mmax = meta["geometry"]["metadata_max_size"]
    slots = meta["geometry"]["metadata_slot_count"]
    if head.find(struct.pack("<I", META_MAGIC), m0) != m0:
        raise SystemExit(f"metadata slot0 nie @ {m0}")
    header_size = struct.unpack_from("<I", head, m0 + 8)[0]
    tables_size = struct.unpack_from("<I", head, m0 + 44)[0]
    o = m0 + 80
    _parts_tbl = struct.unpack_from("<III", head, o)
    extents_tbl = struct.unpack_from("<III", head, o + 12)
    slot_len = header_size + tables_size
    if slot_len > mmax:
        raise SystemExit(f"slot ({slot_len}) > metadata_max_size ({mmax})")

    # partycje z danymi w kolejnosci offsetow bazowych
    data_parts = []
    for p in meta["partitions"]:
        if p["num_extents"] == 0 or not p["name"].endswith("_a"):
            continue
        base = p["name"][:-2]
        if base not in images:
            raise SystemExit(f"brak --img dla partycji z danymi: {base}")
        data_parts.append((p, base, images[base]))
    data_parts.sort(key=lambda t: meta["extents"][t[0]["first_extent_index"]]["target_data"])
    missing = set(images) - {b for _, b, _ in data_parts}
    if missing:
        raise SystemExit(f"--img bez partycji w super: {sorted(missing)}")

    # nowy layout: pierwszy @1M, kolejne wyrownane do bloku
    total_blks = device_size // block
    if device_size % block:
        raise SystemExit("device_size niepodzielne przez blok")
    cur = 1048576
    layout = []
    new_extents = {}
    for p, base, path in data_parts:
        sz = os.path.getsize(path)
        region = (sz + block - 1) // block * block
        off = (cur + block - 1) // block * block
        new_extents[p["first_extent_index"]] = (region // 512, off // 512)
        layout.append((base, path, sz, off, region))
        cur = off + region

    main_a = next((g["maximum_size"] for g in meta["groups"] if g["name"] == "main_a"), None)
    used = sum(l[4] for l in layout)
    if main_a is not None and used > main_a:
        raise SystemExit(f"obrazy ({used} B) > budzet main_a ({main_a} B)")

    # sloty metadanych: patch + oryginalne paddingi, spacing co mmax
    meta_area = bytearray()
    for s_i in range(slots):
        off = m0 + s_i * mmax
        raw = head[off:off + slot_len]
        if len(raw) < slot_len:
            raise SystemExit(f"slot {s_i} niepelny w head")
        meta_area += patch_metadata_slot(raw, header_size, tables_size,
                                         extents_tbl, new_extents)
        meta_area += head[off + slot_len:off + mmax]   # padding oryginalny
    meta_area = bytes(meta_area)
    meta_end = m0 + slots * mmax
    if len(meta_area) != meta_end - m0:
        raise SystemExit("meta_area size mismatch")

    # ---- PLAN chunkow (bez danych w RAM): (type, nblocks, source) ----
    # source: None (dont-care) | (b'bytes', data) | (b'file', path, len)
    plan = []
    def add_gap(a, b):
        if b > a:
            plan.append((CHUNK_DONT_CARE, (b - a) // block, None))
    add_gap(0, g_off)
    plan.append((CHUNK_RAW, (2 * 4096) // block, (b"bytes", head[g_off:g_off + 2 * 4096])))
    plan.append((CHUNK_RAW, len(meta_area) // block, (b"bytes", meta_area)))
    pos = meta_end
    for base, path, sz, off, region in layout:
        add_gap(pos, off)
        remaining = region
        while remaining > 0:
            take = min(remaining, RAW_CHUNK_MAX)
            plan.append((CHUNK_RAW, take // block, (b"file", path, take)))
            remaining -= take
        pos = off + region
    add_gap(pos, device_size)
    if (device_size - sum(nb for _, nb, _ in plan) * block) != 0:
        raise SystemExit("plan chunkow nie pokrywa calego device")
    # calkowity rozmiar sparse (deterministyczny z planu) -> part_size pod N czastek
    sparse_total = 28 + sum(12 + (len(src[1]) if src is not None and src[0] == b"bytes" else 0)
                            + ((src[2]) if src is not None and src[0] == b"file" else 0)
                            for _, _, src in plan)
    part_size = None
    part_paths = []
    part_hashes = []
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
        part_size = (sparse_total + n_parts - 1) // n_parts
        part_size = (part_size + 1048575) // 1048576 * 1048576   # wyrownanie do 1M

    # ---- zapis strumieniowy (stdout albo czastki w --out-dir) ----
    import hashlib as _hl
    part_idx = -1
    part_fh = None
    part_len = 0
    part_sha = None

    def next_part():
        nonlocal part_idx, part_fh, part_len, part_sha
        if part_fh is not None:
            part_fh.close()
            part_hashes.append((part_paths[-1], part_sha.hexdigest()))
        part_idx += 1
        path = os.path.join(out_dir, f"{prefix}{part_idx:02d}")
        part_paths.append(path)
        part_fh = open(path, "wb")
        part_len = 0
        part_sha = _hl.sha256()

    def wout(b):
        # zapis do stdout lub aktualnej czastki (rotacja na granicach chunkow)
        nonlocal part_len
        if part_fh is None:
            sys.stdout.buffer.write(b)
            sys.stdout.buffer.flush()
        else:
            part_fh.write(b)
            part_sha.update(b)
            part_len += len(b)

    if out_dir:
        next_part()
    out = type("W", (), {"write": staticmethod(lambda b: wout(b)),
                         "flush": staticmethod(lambda: None)})()
    # file_hdr (28B): magic u32, major u16, minor u16, file_hdr_sz u16(28),
    # chunk_hdr_sz u16(12), blk_sz u32, total_blks u32, total_chunks u32,
    # image_checksum u32 (0 - nieobowiazkowe)
    out.write(struct.pack("<IHHHHIIII", SPARSE_MAGIC, 1, 0, 28, 12,
                          block, total_blks, len(plan), 0))
    # ile chunkow plikowych pozostalo per sciezka (do progresywnego unlink)
    remaining_chunks = {}
    for _, _, src in plan:
        if src is not None and src[0] == b"file":
            remaining_chunks[src[1]] = remaining_chunks.get(src[1], 0) + 1
    for ct, nb, src in plan:
        if part_fh is not None and part_len >= part_size:
            next_part()
        if src is None:
            out.write(struct.pack("<HHII", ct, 0, nb, 12))
        elif src[0] == b"bytes":
            data = src[1]
            out.write(struct.pack("<HHII", ct, 0, nb, 12 + len(data)))
            out.write(data)
        else:
            path, take = src[1], src[2]
            out.write(struct.pack("<HHII", ct, 0, nb, 12 + take))
            with open(path, "rb") as f:
                written = 0
                while written < take:
                    buf = f.read(min(4 * 1024 * 1024, take - written))
                    if not buf:
                        # obraz krotszy niz region -> dopelnij zerami
                        buf = b"\0" * min(4 * 1024 * 1024, take - written)
                    out.write(buf)
                    written += len(buf)
            out.flush()
            remaining_chunks[path] -= 1
            if not keep and remaining_chunks[path] == 0:
                try:
                    os.unlink(path)
                    print(f"# unlink {path} (zwolniono dysk)", file=sys.stderr)
                except OSError as e:
                    print(f"# unlink {path}: {e}", file=sys.stderr)
        out.flush()

    if part_fh is not None:
        part_fh.close()
        part_hashes.append((part_paths[-1], part_sha.hexdigest()))
        for path, digest in part_hashes:
            print(f"S\t{os.path.basename(path)}\t{digest}\t{os.path.getsize(path)}",
                  file=sys.stderr)
        print(f"# sparse_total={sparse_total} czastek={len(part_paths)} "
              f"part_size={part_size}", file=sys.stderr)
    print(f"# device={device_size} blokow={total_blks} chunkow={len(plan)} "
          f"main_a_used={used}/{main_a}", file=sys.stderr)
    for base, path, sz, off, region in layout:
        print(f"L\t{base}\t{sz}\t{off}\t{region}", file=sys.stderr)


if __name__ == "__main__":
    main()
