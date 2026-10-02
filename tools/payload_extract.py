#!/usr/bin/env python3
"""payload_extract.py - wyciaga JEDNA partycje z payload.bin OTA A/B (format CrAU)
bez pobierania calosci na dysk (dysk runera: product.img ~6,4G zamiast 12,6G tgz /
10,3G zipa; Drive dlawi pelne transfery, ale_ranges + rownoleglosc przechodza).

Zrodla wejsciowe (jedno z):
  --payload PLIK                 lokalny payload.bin
  --zip-url URL --entry NAZWA    wpis w ZIPie (OTA Recovery ROM); wpis MUSI byc
                                 STORED (compress_type=0) - HTTP Range nie
                                 ogarnia deflate; OTA Xiaomi: payload.bin stored
                                 (weryfikowane przed praca)

Dzialanie:
  1. naglowek CrAU: magic(4) + version(u32BE) + manifest_size(u64BE)
     [+ metadata_signature_size(u32BE) gdy version>=2]
  2. manifest = protobuf wire-format (MINIMALNY parser, bez zaleznosci):
       DeltaArchiveManifest { block_size=2; partitions=13 }
       PartitionUpdate      { partition_name=1; new_partition_info=7; operations=268 }
       PartitionInfo        { size=1; hash=2 }
       InstallOperation     { type=1; data_offset=2; data_length=3;
                              dst_extents=6; dst_length=7; data_sha256_hash=8 }
       Extent               { start_block=1; num_blocks=2 }
  3. operacje partycji: bloby pobierane ROWNOLEGLE (HTTP Range, --jobs N,
     prefetch glebokosci 2x jobs), dekompresja REPLACE/REPLACE_BZ/REPLACE_XZ/
     REPLACE_LZ4 (modul lz4), ZERO/DISCARD bez danych, zapis na dst extents.
  4. weryfikacje: data_sha256_hash per-op (gdy obecne), dlugosc po dekompresji
     vs dst extents, rozmiar wyjscia vs new_partition_info.size,
     opcjonalnie --erofs-check (magic e2e1f5e0 @ offset 1024 - patrz
     extract-miui-apps.sh v1.1).

Uzycie:
  payload_extract.py --zip-url URL --entry payload.bin --partition product \
      --out product.img [--jobs 6] [--erofs-check] [--dump-structure]
  payload_extract.py --payload payload.bin --partition product --out product.img
"""
import argparse
import bz2
import hashlib
import io
import json
import lzma
import os
import socket
import struct
import sys
import threading
import time
import urllib.request
import zipfile
from concurrent.futures import ThreadPoolExecutor

# --- typy operacji (system/update_engine/update_metadata.proto) ---
OP_NAMES = {
    0: "REPLACE", 1: "REPLACE_BZ", 2: "MOVE", 3: "BSDIFF", 4: "SOURCE_COPY",
    5: "SOURCE_BSDIFF", 6: "ZERO", 7: "DISCARD", 8: "REPLACE_XZ",
    9: "LZ4AA(deprecated)", 10: "LZ4HC(deprecated)", 11: "REPLACE_LZ4",
}
REPLACE, REPLACE_BZ, MOVE, BSDIFF = 0, 1, 2, 3
SOURCE_COPY, SOURCE_BSDIFF, ZERO, DISCARD = 4, 5, 6, 7
REPLACE_XZ, REPLACE_LZ4 = 8, 11


# ----------------------------------------------------------------------------
# protobuf wire format - minimalny parser
# ----------------------------------------------------------------------------
def read_varint(buf, pos):
    """varint -> (value, new_pos)."""
    result = 0
    shift = 0
    while True:
        if pos >= len(buf):
            raise ValueError("varint poza buforem")
        b = buf[pos]
        pos += 1
        result |= (b & 0x7F) << shift
        if not (b & 0x80):
            return result, pos
        shift += 7
        if shift > 63:
            raise ValueError("varint za dlugi")


def iter_fields(buf):
    """Generator pol: (field_number, wire_type, value). value: int (wt 0/1) lub
    (start, koniec) dla len-delim (wt 2) - bez kopiowania."""
    pos = 0
    n = len(buf)
    while pos < n:
        tag, pos = read_varint(buf, pos)
        field, wt = tag >> 3, tag & 7
        if wt == 0:
            val, pos = read_varint(buf, pos)
        elif wt == 1:
            if pos + 8 > n:
                raise ValueError("skrotowy fixed64")
            val = struct.unpack_from("<Q", buf, pos)[0]
            pos += 8
        elif wt == 5:
            if pos + 4 > n:
                raise ValueError("skrotowy fixed32")
            val = struct.unpack_from("<I", buf, pos)[0]
            pos += 4
        elif wt == 2:
            ln, pos = read_varint(buf, pos)
            if pos + ln > n:
                raise ValueError("len-delim poza buforem")
            val = (pos, pos + ln)
            pos += ln
        else:
            raise ValueError("wire_type %d nieobslugiwany" % wt)
        yield field, wt, val


class Extent:
    __slots__ = ("start_block", "num_blocks")

    def __init__(self, start_block=0, num_blocks=0):
        self.start_block, self.num_blocks = start_block, num_blocks

    @property
    def byte_len(self):
        return self.num_blocks  # x block_size - liczone przez wywolawce


class Op:
    __slots__ = ("type", "data_offset", "data_length", "dst_extents", "dst_length",
                 "data_sha256")

    def __init__(self):
        self.type = None
        self.data_offset = 0
        self.data_length = 0
        self.dst_extents = []
        self.dst_length = 0
        self.data_sha256 = None


class Partition:
    __slots__ = ("name", "new_size", "new_hash", "ops", "raw_fields",
                 "raw", "ops_field")

    def __init__(self):
        self.name = None
        self.new_size = 0
        self.new_hash = None
        self.ops = []
        self.raw_fields = {}
        self.raw = None
        self.ops_field = None


def parse_extent(buf):
    e = Extent()
    for f, wt, v in iter_fields(buf):
        if f == 1 and wt == 0:
            e.start_block = v
        elif f == 2 and wt == 0:
            e.num_blocks = v
    return e


def parse_op(buf):
    op = Op()
    for f, wt, v in iter_fields(buf):
        if f == 1 and wt == 0:
            op.type = v
        elif f == 2 and wt == 0:
            op.data_offset = v
        elif f == 3 and wt == 0:
            op.data_length = v
        elif f == 4 and wt == 2:
            op.src_extents = None  # nieuzywane dla full OTA
        elif f == 6 and wt == 2:
            op.dst_extents.append(parse_extent(buf[v[0]:v[1]]))
        elif f == 7 and wt == 0:
            op.dst_length = v
        elif f == 8 and wt == 2:
            op.data_sha256 = buf[v[0]:v[1]]
    return op


def looks_like_op(sub):
    """Heurystyka: sub-wiadomosc wyglada jak InstallOperation?"""
    has_type = has_off = has_len = has_ext = False
    try:
        for f, wt, v in iter_fields(sub):
            if f == 1 and wt == 0 and v < 32:
                has_type = True
            elif f == 2 and wt == 0:
                has_off = True
            elif f == 3 and wt == 0:
                has_len = True
            elif f == 6 and wt == 2:
                has_ext = True
            elif f == 8 and wt == 2:
                pass  # sha256
            elif wt == 2 and f in (4,):
                has_ext = has_ext or True
    except ValueError:
        return False
    return has_type and (has_off or has_len or has_ext)


def parse_partition(buf, ops_field=None):
    p = Partition()
    p.raw = buf
    for f, wt, v in iter_fields(buf):
        if f == 1 and wt == 2:
            p.name = buf[v[0]:v[1]].decode("utf-8", "replace")
        elif f == 7 and wt == 2:  # new_partition_info
            for f2, wt2, v2 in iter_fields(buf[v[0]:v[1]]):
                if f2 == 1 and wt2 == 0:
                    p.new_size = v2
                elif f2 == 2 and wt2 == 2:
                    p.new_hash = buf[v2[0]:v2[1]]
        elif wt == 2:
            p.raw_fields.setdefault(f, 0)
            p.raw_fields[f] += 1
    # operations: najpierw kanoniczne 268; gdy 0 -> auto-detekcja pola
    # (receipt 37007764992: Xiaomi OTA HyperOS 4.0.13 ma ops pod innym
    # numerem; auto-skan repeated len-delim z wygladem InstallOperation)
    for cand in [268] + sorted([f for f in p.raw_fields
                                if f != 268 and f not in (1, 6, 7)]):
        msgs = []
        for f, wt, v in iter_fields(buf):
            if f == cand and wt == 2:
                msgs.append(buf[v[0]:v[1]])
        if not msgs:
            continue
        if all(looks_like_op(m) for m in msgs[:5]) and len(msgs) >= 1:
            p.ops = [parse_op(m) for m in msgs]
            p.ops_field = cand
            break
    return p


def parse_manifest(buf):
    """-> (block_size, [Partition])"""
    block_size = 4096
    partitions = []
    for f, wt, v in iter_fields(buf):
        if f == 2 and wt == 0:
            block_size = v
        elif f == 13 and wt == 2:
            partitions.append(parse_partition(buf[v[0]:v[1]]))
    return block_size, partitions


def dump_structure(block_size, partitions, out=sys.stderr):
    print("# manifest: block_size=%d, partycji=%d" % (block_size, len(partitions)),
          file=out)
    for p in partitions:
        hashes = sum(1 for o in p.ops if o.data_sha256)
        print("#   partycja %-14s new_size=%-12d ops=%-5d (pole %s, sha256 na %d)"
              % (p.name, p.new_size, len(p.ops),
                 p.ops_field if p.ops_field else "-", hashes), file=out)
        if p.raw_fields and p.name in ("product", "system", "vendor"):
            top = sorted(((f, n) for f, n in p.raw_fields.items()),
                         key=lambda kv: -kv[1])[:6]
            print("#     pola len-delim w %s: %s" % (p.name, top), file=out)


# ----------------------------------------------------------------------------
# warstwa bajtowa: lokalny plik lub HTTP Range
# ----------------------------------------------------------------------------
class LocalFile(io.RawIOBase):
    def __init__(self, path):
        self.f = open(path, "rb")
        self.f.seek(0, 2)
        self.size = self.f.tell()
        self.requests = 0

    def read_at(self, off, ln):
        self.f.seek(off)
        self.requests += 1
        return self.f.read(ln)


class HTTPRangeSource:
    """Zrodlo bajtow przez HTTP Range (jedna domena, rownolegle watki)."""

    def __init__(self, url):
        self.url = url
        self.size = 0
        self.requests = 0
        self.lock = threading.Lock()
        self.bytes_downloaded = 0
        self._probe()

    def _probe(self):
        last = None
        for attempt in range(4):
            try:
                req = urllib.request.Request(self.url, method="HEAD")
                with urllib.request.urlopen(req, timeout=60) as r:
                    self.size = int(r.headers.get("Content-Length", "0"))
                    self.accepts = r.headers.get("Accept-Ranges", "none")
                    return
            except Exception as e:
                last = e
                time.sleep(2 * (attempt + 1))
        # fallback: GET z Range 0-0 (niektore serwery, w tym drive.usercontent,
        # nie odpowiadaja na HEAD); 206 + Content-Range dowodzi obslugi range
        for attempt in range(4):
            try:
                req = urllib.request.Request(self.url,
                                             headers={"Range": "bytes=0-0"})
                with urllib.request.urlopen(req, timeout=60) as r:
                    if r.status in (200, 206):
                        cr = r.headers.get("Content-Range", "")
                        if r.status == 206 and "/" in cr:
                            self.size = int(cr.rsplit("/", 1)[1])
                            self.accepts = "bytes"
                            return
                        self.size = int(r.headers.get("Content-Length", "0"))
                        self.accepts = r.headers.get("Accept-Ranges", "none")
                        return
            except Exception as e:
                last = e
                time.sleep(2 * (attempt + 1))
        raise SystemExit("HEAD/GET-probe nie wyszly po 4 probach: %r" % last)

    def read_at(self, off, ln, timeout=600):
        if ln <= 0:
            return b""
        end = off + ln - 1
        last_err = None
        for attempt in range(6):
            try:
                req = urllib.request.Request(
                    self.url, headers={"Range": "bytes=%d-%d" % (off, end)})
                with urllib.request.urlopen(req, timeout=timeout) as r:
                    data = r.read()
                if len(data) == ln:
                    with self.lock:
                        self.requests += 1
                        self.bytes_downloaded += ln
                    return data
                last_err = "krotki range: chciano %d, dostano %d" % (ln, len(data))
            except Exception as e:
                last_err = "%s: %s" % (type(e).__name__, e)
            sys.stderr.write("# range %d-%d retry %d/6: %s\n"
                             % (off, end, attempt + 1, last_err))
            time.sleep(3 * (attempt + 1))
        raise SystemExit("range %d-%d padl po 6 probach: %s" % (off, end, last_err))


class ZipEntrySource:
    """Dostep do bajtow WPISU w zipie (payload.bin STORED) przez zrodlo
    bajtowe (lokalne lub HTTPRange). Zwraca read_at wzgledem poczatku danych
    wpisu + offset bazowy."""

    def __init__(self, src, entry_name):
        # zipfile potrzebuje file-like z seek/read od konca (komentarz/EOCD) -
        # najprosciej: male okienko na EOCD przez pelny strumien robimy sami:
        # czytamy ostatnie 256KB, szukamy EOCD, parsujemy central directory.
        tail_len = min(1024 * 1024, src.size)
        tail = src.read_at(src.size - tail_len, tail_len)
        eocd = tail.rfind(b"PK\x05\x06")
        if eocd < 0:
            raise SystemExit("brak EOCD w zipie")
        eocd_abs = src.size - tail_len + eocd
        cd_size = struct.unpack_from("<I", tail, eocd + 12)[0]
        cd_off = struct.unpack_from("<I", tail, eocd + 16)[0]
        if cd_off == 0xFFFFFFFF or cd_size == 0xFFFFFFFF:
            # ZIP64: lokalizator PK\x06\x07 tuż przed EOCD -> PK\x06\x06
            loc = tail.rfind(b"PK\x06\x07", 0, eocd)
            if loc < 0:
                raise SystemExit("zip64: brak lokalizatora PK\x06\x07")
            z64_off, = struct.unpack_from("<Q", tail, loc + 8)
            z64 = src.read_at(z64_off, 56)
            if z64[:4] != b"PK\x06\x06":
                raise SystemExit("zip64: zly magic PK\x06\x06")
            cd_size, = struct.unpack_from("<Q", z64, 40)
            cd_off, = struct.unpack_from("<Q", z64, 48)
            print("  zip64: cd_off=%d cd_size=%d" % (cd_off, cd_size))
        cd = src.read_at(cd_off, cd_size)
        pos, found = 0, []
        while pos < len(cd) and cd[pos:pos + 4] == b"PK\x01\x02":
            (nlen, elen, clen) = struct.unpack_from("<HHH", cd, pos + 28)
            method = struct.unpack_from("<H", cd, pos + 10)[0]
            csize, usize = struct.unpack_from("<II", cd, pos + 20)
            name = cd[pos + 46:pos + 46 + nlen].decode("utf-8", "replace")
            header_off = struct.unpack_from("<I", cd, pos + 42)[0]
            if header_off == 0xFFFFFFFF or csize == 0xFFFFFFFF or \
                    usize == 0xFFFFFFFF:
                # zip64 extra (id 0x0001): 8B wartosci w kolejnosci dla tych
                # pol, ktore maja wartosc 0xFFFFFFFF w naglowku
                ex = cd[pos + 46 + nlen:pos + 46 + nlen + elen]
                epos = 0
                while epos + 4 <= len(ex):
                    eid, esz = struct.unpack_from("<HH", ex, epos)
                    if eid == 0x0001:
                        dpos, remaining = epos + 4, esz
                        for which in (usize, csize, header_off):
                            if which == 0xFFFFFFFF and remaining >= 8:
                                v, = struct.unpack_from("<Q", ex, dpos)
                                if which is usize:
                                    usize = v
                                elif which is csize:
                                    csize = v
                                else:
                                    header_off = v
                                dpos += 8
                                remaining -= 8
                        break
                    epos += 4 + esz
            if name == entry_name or name.endswith("/" + entry_name):
                found.append((name, method, csize, usize, header_off))
            pos += 46 + nlen + elen + clen
        if not found:
            all_names = []
            pos2 = 0
            while pos2 < len(cd) and cd[pos2:pos2 + 4] == b"PK\x01\x02":
                n2, e2, c2 = struct.unpack_from("<HHH", cd, pos2 + 28)
                all_names.append(cd[pos2 + 46:pos2 + 46 + n2]
                                 .decode("utf-8", "replace"))
                pos2 += 46 + n2 + e2 + c2
            raise SystemExit("brak wpisu '%s' w zipie; wpisy: %s"
                             % (entry_name, all_names[:20]))
        if len(found) > 1:
            raise SystemExit("wpis '%s' niejednoznaczny: %r"
                             % (entry_name, [f[0] for f in found]))
        name, method, csize, usize, header_off = found[0]
        if method != zipfile.ZIP_STORED:
            raise SystemExit("wpis '%s' NIE jest STORED (method=%d) - "
                             "range-extraction niemozliwa; potrzebny plan B"
                             % (name, method))
        if csize != usize:
            raise SystemExit("wpis '%s': csize != usize (%d vs %d)"
                             % (name, csize, usize))
        # lokalny naglowek -> poczatek danych
        lh = src.read_at(header_off, 30)
        if lh[:4] != b"PK\x03\x04":
            raise SystemExit("zly lokalny naglowek @ %d" % header_off)
        lnlen, elen = struct.unpack_from("<HH", lh, 26)
        data_off = header_off + 30 + lnlen + elen
        self.name, self.size, self.data_off = name, usize, data_off
        self.src = src

    @property
    def requests(self):
        return getattr(self.src, "requests", "?")

    def read_at(self, off, ln, **kw):
        if off + ln > self.size:
            raise SystemExit("odczyt poza payload.bin (%d+%d > %d)"
                             % (off, ln, self.size))
        return self.src.read_at(self.data_off + off, ln, **kw)


# ----------------------------------------------------------------------------
# ekstrakcja
# ----------------------------------------------------------------------------
def decode_op(op_type, blob):
    if op_type == REPLACE:
        return blob
    if op_type == REPLACE_BZ:
        return bz2.decompress(blob)
    if op_type == REPLACE_XZ:
        return lzma.decompress(blob)
    if op_type == REPLACE_LZ4:
        try:
            import lz4.frame  # noqa
        except ImportError:
            raise SystemExit("REPLACE_LZ4 wymaga modulu lz4 "
                             "(pip install lz4) - nie zainstalowany")
        import lz4.frame
        return lz4.frame.decompress(blob)
    if op_type == LZ4HC or op_type == 9:
        raise SystemExit("LZ4AA/LZ4HC deprecated - brak obslugi")
    raise SystemExit("typ op %d (%s) bez danych nie powinien miec bloba"
                     % (op_type, OP_NAMES.get(op_type, "?")))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--payload")
    ap.add_argument("--zip-url")
    ap.add_argument("--entry", default="payload.bin")
    ap.add_argument("--partition", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--jobs", type=int, default=12,
                    help="watki pobierania chunkow")
    ap.add_argument("--chunk", type=int, default=16 * 1024 * 1024,
                    help="rozmiar chunku range (B)")
    ap.add_argument("--prefetch-ops", type=int, default=3)
    ap.add_argument("--erofs-check", action="store_true")
    ap.add_argument("--dump-structure", action="store_true")
    ap.add_argument("--progress-every", type=int, default=10)
    args = ap.parse_args()

    if bool(args.payload) == bool(args.zip_url):
        raise SystemExit("podaj dokladnie jedno z --payload / --zip-url")

    t0 = time.time()
    if args.payload:
        src = LocalFile(args.payload)
        pl = src
        print("zrodlo: lokalny plik %s (%d B)" % (args.payload, src.size))
    else:
        base = HTTPRangeSource(args.zip_url)
        print("zrodlo: HTTP %s\n  size=%d accept-ranges=%s"
              % (args.zip_url, base.size, getattr(base, "accepts", "?")))
        if "bytes" not in getattr(base, "accepts", ""):
            raise SystemExit("serwer nie wspiera Range - plan B")
        pl = ZipEntrySource(base, args.entry)
        print("  wpis %s: STORED, %d B @+%d" % (pl.name, pl.size, pl.data_off))
        src = pl

    # --- naglowek CrAU (update_engine/payload_consumer.cc: PayloadHeader) ---
    #   magic[4] "CrAU" + version u64BE + manifest_size u64BE  = 20B (v1)
    #   v2+: + metadata_signature_size u32BE                    = 24B
    # Receipt runu 37007276549 (bajty z zywego OTA Xiaomi): version u64BE@+4
    # (u32@+4 czyta 0, u64@+8 czyta 0x200000000 = wlasnie u64 version=2).
    hdr = src.read_at(0, 32)
    print("naglowek payload (hex, 32B): %s" % hdr.hex())
    if hdr[:4] != b"CrAU":
        raise SystemExit("zly magic payload.bin: %r" % hdr[:4])
    version, = struct.unpack_from(">Q", hdr, 4)
    manifest_size, = struct.unpack_from(">Q", hdr, 12)
    if version >= 2:
        meta_sig_size, = struct.unpack_from(">I", hdr, 20)
        manifest_off = 24
    else:
        meta_sig_size = 0
        manifest_off = 20
    blobs_base = manifest_off + manifest_size + meta_sig_size
    print("payload: version=%d manifest=%dB meta_sig=%dB, bloby od %d"
          % (version, manifest_size, meta_sig_size, blobs_base))

    manifest = src.read_at(manifest_off, manifest_size)
    block_size, partitions = parse_manifest(manifest)
    if args.dump_structure or True:  # struktura ZAWSZE do logu (evidence)
        dump_structure(block_size, partitions)
    part = None
    for p in partitions:
        if p.name == args.partition:
            part = p
    if part is None:
        raise SystemExit("brak partycji '%s' (sa: %s)"
                         % (args.partition, [p.name for p in partitions]))
    if not part.ops:
        raise SystemExit("partycja '%s' bez operacji" % args.partition)

    # --- plan transferu ---
    total_dl = sum(o.data_length for o in part.ops if o.type not in (ZERO, DISCARD))
    by_type = {}
    for o in part.ops:
        by_type[OP_NAMES.get(o.type, str(o.type))] = \
            by_type.get(OP_NAMES.get(o.type, str(o.type)), 0) + 1
    print("partycja %s: %d op (%s), do pobrania %d B (%.2f GiB), new_size=%d"
          % (part.name, len(part.ops), ", ".join("%s x%d" % kv
             for kv in sorted(by_type.items())), total_dl, total_dl / 2**30,
             part.new_size))

    # walidacja extents
    for i, o in enumerate(part.ops):
        if o.type in (MOVE, BSDIFF, SOURCE_COPY, SOURCE_BSDIFF):
            raise SystemExit("op %d typu %s - to nie full OTA (delta?) - brak "
                             "obsługi" % (i, OP_NAMES.get(o.type)))
        if o.type in (ZERO, DISCARD):
            continue
        if not o.dst_extents:
            raise SystemExit("op %d bez dst_extents" % i)

    out_size = part.new_size
    if not out_size:
        end_max = 0
        for o in part.ops:
            for e in o.dst_extents:
                end_max = max(end_max, (e.start_block + e.num_blocks) * block_size)
        out_size = end_max
        print("new_size nieznany -> z extents: %d" % out_size)

    # --- rownolegly chunk-prefetch + sekwencyjny zapis ---
    # Blob kazdego opu dzielony na --chunk B kawalki pobierane przez pule
    # watkow (--jobs) - lamiemy per-connection throttling Drive. Zapis
    # sekwencyjny w kolejnosci opow, prefetch --prefetch-ops opow naprzod.
    fout = open(args.out, "wb")
    fout.truncate(out_size)
    progress_t0 = time.time()
    last_report = [0.0]
    written = [0]

    def needs_data(op):
        return op.type not in (ZERO, DISCARD) and op.data_length > 0

    def submit_op_chunks(op):
        futs = []
        off = 0
        while off < op.data_length:
            ln = min(args.chunk, op.data_length - off)
            futs.append(pool.submit(src.read_at,
                                    blobs_base + op.data_offset + off, ln))
            off += ln
        return futs

    def report(force=False):
        now = time.time()
        if not force and now - last_report[0] < 30:
            return
        last_report[0] = now
        dl = getattr(src, "bytes_downloaded", None)
        if dl is None:
            dl = getattr(getattr(src, "src", None), "bytes_downloaded", 0)
        dt = now - progress_t0
        spd = dl / max(0.001, dt)
        print("  [%5.1f%%] op %d/%d, %.0f MiB / %.0f MiB, %.2f MB/s, ETA %.1f min"
              % (min(100.0, 100.0 * dl / max(1, total_dl)), written[0], len(part.ops),
                 dl / 2**20, total_dl / 2**20, spd / 2**20,
                 (total_dl - dl) / max(1.0, spd) / 60.0), flush=True)

    pending = {}

    def ensure_submitted(idx):
        if idx < len(part.ops) and idx not in pending:
            op = part.ops[idx]
            pending[idx] = submit_op_chunks(op) if needs_data(op) else []

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for i, op in enumerate(part.ops):
            for j in range(i, min(len(part.ops), i + args.prefetch_ops)):
                ensure_submitted(j)
            futs = pending.pop(i, [])
            blob = b"".join(f.result() for f in futs)
            if op.data_sha256 and blob:
                got_hash = hashlib.sha256(blob).digest()
                if got_hash != op.data_sha256:
                    raise SystemExit("sha256 bloba op %d nie zgadza sie "
                                     "(oczek. %s, jest %s)"
                                     % (i, op.data_sha256.hex()[:16],
                                        got_hash.hex()[:16]))
            apply_op(fout, op, blob, block_size, part.name)
            written[0] += 1
            report()
    fout.close()
    report(force=True)

    got = os.path.getsize(args.out)
    print("gotowe: %s = %d B (oczek. %d) w %.1f min; requestow HTTP: %s"
          % (args.out, got, out_size, (time.time() - t0) / 60.0,
             getattr(src, "requests", "?")))
    if out_size and got != out_size:
        raise SystemExit("rozmiar wyjscia != new_size")
    if part.new_hash:
        print("new_partition_info.hash (do weryfikacji zewnetrznej): %s"
              % part.new_hash.hex())

    if args.erofs_check:
        with open(args.out, "rb") as f:
            f.seek(1024)
            magic = f.read(4)
        if magic == bytes.fromhex("e2e1f5e0"):
            print("erofs-check: magic e2e1f5e0 @1024 OK")
        else:
            raise SystemExit("erofs-check: zly magic @1024: %s" % magic.hex())


def apply_op(fout, op, blob, block_size, part_name):
    if op.type in (ZERO, DISCARD):
        return
    data = decode_op(op.type, blob)
    want = sum(e.num_blocks for e in op.dst_extents) * block_size
    if len(data) != want:
        raise SystemExit("op %s partycji %s: po dekompresji %d B != dst extents %d B"
                         % (OP_NAMES.get(op.type), part_name, len(data), want))
    pos = 0
    for e in op.dst_extents:
        chunk = data[pos:pos + e.num_blocks * block_size]
        fout.seek(e.start_block * block_size)
        fout.write(chunk)
        pos += len(chunk)


if __name__ == "__main__":
    main()
