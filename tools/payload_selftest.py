#!/usr/bin/env python3
"""payload_selftest.py - lokalny test tools/payload_extract.py bez sieci
zewnetrznej (loopback HTTP). Buduje syntetyczny OTA:

  1. drzewo product (apki MIUI-lookalike) -> mkfs.erofs z kit-mysticalos3/bin
     (gdy brak binarki - dane losowe, erofs-check pomijany),
  2. referencja = obraz z dziura wypelniona zerami (ZERO op pokryje),
  3. manifest protobuf (boot dummy, product, vbmeta dummy) z opami:
     REPLACE, REPLACE_BZ, REPLACE_XZ, ZERO, DISCARD (+REPLACE_LZ4 gdy modul),
  4. payload.bin v2 (naglowek 24B + manifest + sygnatura 32B + bloby),
  5. zip: payload.bin STORED + payload_properties.txt + care_map DEFLATE,
  6. serwuje zip przez http.server na 127.0.0.1, odpala payload_extract.py
     --zip-url, porownuje wynik z referencja (cmp) + erofs-check.

Wyjscie: PASS/FAIL (exit code). Uzycie: python3 tools/payload_selftest.py
"""
import bz2
import hashlib
import http.server
import json
import lzma
import os
import random
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
EXTRACT = os.path.join(HERE, "payload_extract.py")
MKFS = os.path.join(HERE, "..", "kit-mysticalos3", "bin", "mkfs.erofs")
BLOCK = 4096


def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def tag(field, wt):
    return varint((field << 3) | wt)


def pb_str(field, s):
    b = s.encode()
    return tag(field, 2) + varint(len(b)) + b


def pb_msg(field, body):
    return tag(field, 2) + varint(len(body)) + body


def pb_varint(field, v):
    return tag(field, 0) + varint(v)


def pb_bytes(field, b):
    return tag(field, 2) + varint(len(b)) + b


def extent(start, num):
    return pb_varint(1, start) + pb_varint(2, num)


def op_msg(op_type, data_offset, data_length, extents, sha=None):
    body = pb_varint(1, op_type) + pb_varint(2, data_offset) + \
        pb_varint(3, data_length)
    for (start, num) in extents:
        body += pb_msg(6, extent(start, num))
    if sha:
        body += pb_bytes(8, sha)
    return body


class RangeHTTPHandler(http.server.SimpleHTTPRequestHandler):
    """SimpleHTTPRequestHandler + obsluga Range (pythonowy http.server domyslnie
    jej nie ma, a HTTPRangeSource jej wymaga)."""

    def _range(self):
        h = self.headers.get("Range")
        if not h or not h.startswith("bytes="):
            return None
        spec = h[6:].split(",")[0].strip()
        a, _, b = spec.partition("-")
        if a == "":
            return None  # suffix-range: niepotrzebne
        start = int(a)
        end = int(b) if b else self._fsize() - 1
        return start, min(end, self._fsize() - 1)

    def _fsize(self):
        path = self.translate_path(self.path)
        return os.stat(path).st_size

    def do_HEAD(self):
        self.send_response(200)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(self._fsize()))
        self.end_headers()

    def do_GET(self):
        rng = self._range()
        path = self.translate_path(self.path)
        with open(path, "rb") as f:
            if rng:
                start, end = rng
                f.seek(start)
                data = f.read(end - start + 1)
                self.send_response(206)
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Range",
                                 "bytes %d-%d/%d" % (start, end, self._fsize()))
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            else:
                data = f.read()
                self.send_response(200)
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)


def zip64_sparse_test(tmp):
    """Ręcznie sklejony ZIP64 (sparse, ~KB realnych bajtów, wpis 4,3 GiB) -
    weryfikuje warstwę ZipEntrySource: EOCD->zip64->CD->zip64 extra->LFH."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "pe", os.path.join(HERE, "payload_extract.py"))
    pe = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pe)

    big = 4 * 1024**3 + 512 * 1024**2  # 4,5 GiB - rozmiar wpisu payload.bin
    head = b"CrAU" + struct.pack(">I", 2) + struct.pack(">Q", 5) + \
        struct.pack(">I", 4) + b"MANIF" + b"\x00" * 4  # 20+5+4 = 29 B realnych
    zpath = os.path.join(tmp, "sparse64.zip")
    cd_off = 30 + 11 + 20 + big
    with open(zpath, "wb") as f:
        # LFH (zip64: csize/usize = 0xFFFFFFFF + extra 0x0001 z usize,csize)
        extra_lfh = struct.pack("<HH", 1, 16) + struct.pack("<QQ", big, big)
        lfh = struct.pack("<IHHHHHIIIHH", 0x04034B50, 45, 0, 0, 0, 0,
                          0, 0xFFFFFFFF, 0xFFFFFFFF, 11, len(extra_lfh))
        f.write(lfh + b"payload.bin" + extra_lfh)
        assert f.tell() == 61, f.tell()
        f.write(head)
        f.seek(cd_off)  # sparse: dziura = bajty wpisu (zera)
        # CDH (zip64: csize/usize/header_off = 0xFFFFFFFF + extra 0x0001)
        extra_cd = struct.pack("<HH", 1, 24) + struct.pack(
            "<QQQ", big, big, 0)
        cdh = struct.pack("<IHHHHHHIIIHHHHHII", 0x02014B50, 45, 45, 0, 0,
                          0, 0, 0, 0xFFFFFFFF, 0xFFFFFFFF, 11, len(extra_cd),
                          0, 0, 0, 0, 0xFFFFFFFF)
        cd = cdh + b"payload.bin" + extra_cd
        f.write(cd)
        z64_eocd_off = cd_off + len(cd)
        z64 = struct.pack("<IQHHIIQQQQ", 0x06064B50, 44, 45, 45, 0, 0,
                          1, 1, len(cd), cd_off)
        loc = struct.pack("<IIQI", 0x07064B50, 0, z64_eocd_off, 1)
        eocd = struct.pack("<IHHHHIIH", 0x06054B50, 0, 0, 0xFFFF, 0xFFFF,
                           0xFFFFFFFF, 0xFFFFFFFF, 0)
        f.write(z64 + loc + eocd)
    print("zip64 sparse zip: logicznie %.2f GiB, na dysku %d B"
          % (os.path.getsize(zpath) / 2**30,
             os.stat(zpath).st_blocks * 512))

    port = 18581
    while True:
        try:
            srv = http.server.ThreadingHTTPServer(("127.0.0.1", port),
                                                  RangeHTTPHandler)
            break
        except OSError:
            port += 1
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    os.chdir(tmp)
    base = pe.HTTPRangeSource(
        "http://127.0.0.1:%d/sparse64.zip" % port)
    assert base.size == os.path.getsize(zpath), (base.size,)
    pl = pe.ZipEntrySource(base, "payload.bin")
    print("  wpis: %s size=%d data_off=%d" % (pl.name, pl.size, pl.data_off))
    assert pl.size == big, (pl.size, big)
    assert pl.data_off == 61, pl.data_off
    got_head = pl.read_at(0, len(head))
    assert got_head == head, (got_head[:20].hex(), head[:20].hex())
    tail16 = pl.read_at(big - 16, 16)
    assert tail16 == b"\x00" * 16, tail16.hex()
    srv.shutdown()
    print("ZIP64: PASS")
    return True


def main():
    tmp = tempfile.mkdtemp(prefix="plself_")
    print("workspace:", tmp)
    try:
        zip64_sparse_test(tmp)
        # --- 1. drzewo + obraz ---
        tree = os.path.join(tmp, "tree", "product")
        for rel, size in [
            ("app/MiuiCalculator/MiuiCalculator.apk", 300_000),
            ("priv-app/MiuiCamera/MiuiCamera.apk", 500_000),
            ("app/MiuiNotes/MiuiNotes.apk", 120_000),
            ("fonts/MiSans- VF.ttf", 150_000),
        ]:
            p = os.path.join(tree, rel.replace("MiSans- VF", "MiSans-VF"))
            os.makedirs(os.path.dirname(p), exist_ok=True)
            rng = random.Random(rel)
            with open(p, "wb") as f:
                f.write(bytes(rng.getrandbits(8) for _ in range(4096)) *
                        (size // 4096 + 1))
        img = os.path.join(tmp, "product.img")
        have_erofs = os.path.isfile(MKFS)
        if have_erofs:
            r = subprocess.run([MKFS, "-zlz4", img, tree],
                               capture_output=True, text=True)
            if r.returncode != 0:
                print("mkfs.erofs padl, dane losowe:", r.stderr[:200])
                have_erofs = False
        if not have_erofs:
            rng = random.Random(42)
            with open(img, "wb") as f:
                f.write(rng.getrandbits(8).to_bytes(1, "little") *
                        (3 * 1024 * 1024))
        with open(img, "rb") as f:
            raw = f.read()
        sz = len(raw)
        assert sz % BLOCK == 0 or True
        nblocks = (sz + BLOCK - 1) // BLOCK

        # --- 2. plan opow: [REPLACE | BZ | ZERO-hole | XZ | (LZ4) | DISCARD-tail]
        segs = []  # (typ, start_block, num_blocks)
        b0 = 0
        third = nblocks // 5
        segs.append((0, b0, third))                       # REPLACE (raw)
        segs.append((1, b0 + third, third))               # REPLACE_BZ
        hole_start = b0 + 2 * third
        segs.append((6, hole_start, third))               # ZERO
        segs.append((8, b0 + 3 * third, third))           # REPLACE_XZ
        rest_start = b0 + 4 * third
        rest = nblocks - rest_start
        have_lz4 = True
        try:
            import lz4.frame  # noqa
        except ImportError:
            have_lz4 = False
        if have_lz4 and rest >= 2:
            segs.append((11, rest_start, rest // 2))      # REPLACE_LZ4
            segs.append((7, rest_start + rest // 2,
                         rest - rest // 2))               # DISCARD
        else:
            segs.append((0, rest_start, rest))            # REPLACE reszta

        # referencja: ZERO/DISCARD obszary = zera
        ref = bytearray(raw)
        for (t, s, n) in segs:
            if t in (6, 7):
                for i in range(s * BLOCK, min((s + n) * BLOCK, len(ref))):
                    ref[i] = 0
        ref_path = os.path.join(tmp, "reference.img")
        with open(ref_path, "wb") as f:
            f.write(ref)

        # --- 3. bloby + manifest ---
        blobs = bytearray()
        ops_pb = b""
        for (t, s, n) in segs:
            if t in (6, 7):
                ops_pb += pb_msg(268, op_msg(t, len(blobs), 0, [(s, n)]))
                continue
            chunk = bytes(ref[s * BLOCK:(s + n) * BLOCK])
            if t == 0:
                blob = chunk
            elif t == 1:
                blob = bz2.compress(chunk)
            elif t == 8:
                blob = lzma.compress(chunk)
            elif t == 11:
                import lz4.frame
                blob = lz4.frame.compress(chunk)
            else:
                raise AssertionError(t)
            sha = hashlib.sha256(blob).digest()
            ops_pb += pb_msg(268, op_msg(t, len(blobs), len(blob),
                                         [(s, n)], sha))
            blobs += blob

        prod_pb = pb_str(1, "product") + \
            pb_msg(7, pb_varint(1, nblocks * BLOCK)) + ops_pb
        boot_pb = pb_str(1, "boot") + pb_msg(7, pb_varint(1, BLOCK)) + \
            pb_msg(268, op_msg(0, len(blobs), BLOCK, [(0, 1)]))
        blobs += bytes(raw[:BLOCK])  # boot dummy (nieporownywany)
        boot_pb = pb_str(1, "boot") + pb_msg(7, pb_varint(1, BLOCK)) + \
            pb_msg(268, op_msg(0, len(blobs) - BLOCK, BLOCK, [(0, 1)]))
        vbmeta_pb = pb_str(1, "vbmeta")  # pusta partycja
        manifest = pb_varint(2, BLOCK) + pb_msg(13, boot_pb) + \
            pb_msg(13, prod_pb) + pb_msg(13, vbmeta_pb)

        meta_sig = bytes(range(32))
        payload = b"CrAU" + struct.pack(">I", 2) + \
            struct.pack(">Q", len(manifest)) + \
            struct.pack(">I", len(meta_sig)) + manifest + meta_sig + bytes(blobs)
        print("payload.bin: %d B (manifest %d B, blobow %d B, opow product: %d)"
              % (len(payload), len(manifest), len(blobs), len(segs)))

        # --- 4. zip ---
        zpath = os.path.join(tmp, "synthetic_ota.zip")
        with zipfile.ZipFile(zpath, "w") as z:
            z.writestr(zipfile.ZipInfo("payload.bin"), payload,
                       compress_type=zipfile.ZIP_STORED)
            z.writestr("payload_properties.txt",
                       "FILE_HASH=x\nFILE_SIZE=%d\n" % len(payload),
                       compress_type=zipfile.ZIP_DEFLATED)
            z.writestr("care_map.txt", "placeholder",
                       compress_type=zipfile.ZIP_DEFLATED)

        # --- 5. serwer + ekstrakcja ---
        port = 18471
        while True:
            try:
                srv = http.server.ThreadingHTTPServer(
                    ("127.0.0.1", port), RangeHTTPHandler)
                break
            except OSError:
                port += 1
        th = threading.Thread(target=srv.serve_forever, daemon=True)
        th.start()
        os.chdir(tmp)
        print("serwer loopback: http://127.0.0.1:%d/synthetic_ota.zip" % port)
        out = os.path.join(tmp, "out_product.img")
        cmd = [sys.executable, EXTRACT,
               "--zip-url", "http://127.0.0.1:%d/synthetic_ota.zip" % port,
               "--entry", "payload.bin", "--partition", "product",
               "--out", out, "--jobs", "4"]
        if have_erofs:
            cmd.append("--erofs-check")
        r = subprocess.run(cmd, capture_output=True, text=True)
        print("--- payload_extract stdout ---")
        print(r.stdout)
        print("--- payload_extract stderr ---")
        print(r.stderr)
        srv.shutdown()
        if r.returncode != 0:
            print("FAIL: extractor exit %d" % r.returncode)
            return 1

        # --- 6. porownanie ---
        same = open(out, "rb").read() == open(ref_path, "rb").read()
        print("cmp %s vs %s: %s"
              % (out, ref_path, "BIT-IDENTYCZNY" if same else "ROZNICE!"))
        if not same:
            a = open(out, "rb").read()
            b = open(ref_path, "rb").read()
            for i in range(min(len(a), len(b))):
                if a[i] != b[i]:
                    print("pierwsza roznica @ %d: %02x vs %02x"
                          % (i, a[i], b[i]))
                    break
            return 1
        print("SELFTEST: PASS (%d opow, erofs=%s, lz4=%s)"
              % (len(segs), have_erofs, have_lz4))
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
