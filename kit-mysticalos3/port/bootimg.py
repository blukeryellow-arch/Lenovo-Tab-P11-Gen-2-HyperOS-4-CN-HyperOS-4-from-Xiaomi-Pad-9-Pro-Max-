#!/usr/bin/env python3
"""Android boot image unpack/patch/repack (pure python; v0-v4).
Uzycie (patch BOOTCLASSPATH w init.rc ramdiska):
    bootimg.py patch <in.img> <out.img> <jar1> <jar2> ...
Wypisuje raport (naglowek, kompresja, lista plikow ramdiska, linia przed/po).
- Kernel/DTB/sekcje nienaruszone (1:1 bajt po bajcie).
- Ramdisk: dekompresja -> cpio newc -> edycja init.rc -> cpio newc -> ta sama
  kompresja. Naglowek v4: podpis (boot signature) zostaje usuniety (nieprawidlowy
  po edycji; weryfikacja AVB i tak wylaczona flagami 3).
"""
import gzip
import io
import lzma
import struct
import sys
import zlib

MAGIC = b"ANDROID!"
NEWC_HDR = 110


# ---------------- cpio newc ----------------
def cpio_parse(data):
    files = {}
    pos = 0
    while pos < len(data):
        if data[pos:pos + 6] not in (b"070701", b"070702"):
            raise ValueError(f"cpio: zly magic @ {pos}")
        f = lambda o: int(data[pos + 6 + o * 8: pos + 6 + (o + 1) * 8], 16)
        (ino, mode, uid, gid, nlink, mtime, fsz, devmaj, devmin,
         rmaj, rmin, nsz, chk) = (f(i) for i in range(13))
        name_off = pos + NEWC_HDR
        name = data[name_off:name_off + nsz - 1].decode()
        data_off = (name_off + nsz + 3) & ~3
        fdata = data[data_off:data_off + fsz]
        if name == "TRAILER!!!":
            break
        files[name] = (mode, uid, gid, fdata)
        pos = (data_off + fsz + 3) & ~3
    return files


def cpio_build(files):
    out = io.BytesIO()

    def hdr(mode, uid, gid, fsz, nsz):
        h = b"070701" + b"".join(
            f"{v:08X}".encode() for v in
            (0, mode, uid, gid, 1, 0, fsz, 0, 0, 0, 0, nsz, 0))
        assert len(h) == NEWC_HDR
        return h
    for name in sorted(files):
        mode, uid, gid, fdata = files[name]
        nb = name.encode() + b"\x00"
        out.write(hdr(mode, uid, gid, len(fdata), len(nb)))
        out.write(nb)
        # wyrownanie do 4 liczac od poczatku archiwum (naglowek=110, start wpisu
        # jest 4-aligned, wiek pad = (-(110+len(nb))) % 4)
        out.write(b"\x00" * ((-(NEWC_HDR + len(nb))) % 4))
        out.write(fdata)
        if len(fdata) % 4:
            out.write(b"\x00" * (4 - len(fdata) % 4))
    out.write(hdr(0, 0, 0, 0, 11) + b"TRAILER!!!\x00")
    out.write(b"\x00" * (4 - (out.tell() % 4) if out.tell() % 4 else 0))
    return out.getvalue()


# ---------------- kompresja ramdiska ----------------
def detect_comp(data):
    if data[:2] == b"\x1f\x8b":
        return "gzip"
    if data[:4] in (b"\x02\x21\x4c\x18", b"\x03\x21\x4c\x18"):
        return "lz4_legacy"
    if data[:4] == b"\x04\x22\x4d\x18":
        return "lz4"
    if data[:6] == b"\xfd7zXZ\x00":
        return "xz"
    if data[:6] == b"070701":
        return "none"
    raise ValueError(f"nieznana kompresja ramdiska: {data[:8].hex()}")


def decompress(data, comp):
    if comp == "gzip":
        return gzip.decompress(data)
    if comp == "xz":
        return lzma.decompress(data)
    if comp == "none":
        return data
    raise ValueError(f"kompresja {comp} wymaga narzedzia zewnetrznego (lz4)")


def compress(data, comp):
    if comp == "gzip":
        return gzip.compress(data, 6)
    if comp == "xz":
        return lzma.compress(data)
    if comp == "none":
        return data
    raise ValueError(f"kompresja {comp} niedostepna w czystym pythonie")


# ---------------- boot image ----------------
def parse_boot(path):
    d = open(path, "rb").read()
    if d[:8] != MAGIC:
        raise ValueError("to nie jest boot image (brak ANDROID!)")
    ver = struct.unpack_from("<I", d, 40)[0]
    if ver >= 3:
        (k_size, r_size, os_ver, h_size) = struct.unpack_from("<4I", d, 8)
        reserved = struct.unpack_from("<4I", d, 24)
        cmdline = d[44:44 + 1536].split(b"\x00")[0].decode()
        page = 4096
        k_off = 4096
        r_off = (k_off + k_size + page - 1) & ~(page - 1)
        sig_size = 0
        if ver == 4:
            sig_size = struct.unpack_from("<I", d, 44 + 1536)[0]
        return dict(ver=ver, page=page, k_size=k_size, r_size=r_size,
                    os_ver=os_ver, h_size=h_size, cmdline=cmdline,
                    kernel=d[k_off:k_off + k_size],
                    ramdisk=d[r_off:r_off + r_size], sig_size=sig_size, raw=d)
    # v0-v2 (page-based)
    (k_size, k_addr, r_size, r_addr, s_size, s_addr, t_size, t_addr,
     page, hdr_ver, os_ver) = struct.unpack_from("<11I", d, 8)
    name = d[48:64].split(b"\x00")[0].decode()
    cmdline = (d[64:576] + d[608:608 + 1024]).split(b"\x00")[0].decode()
    off = lambda o: (o + page - 1) & ~(page - 1)
    k_off = off(1648) if hdr_ver == 0 else off(1664 if hdr_ver == 1 else 1672)
    r_off = off(k_off + k_size)
    sec_off = off(r_off + r_size)
    sections = {"second": (s_size, sec_off), "tags": (t_size, off(sec_off + s_size))}
    if hdr_version_ge(hdr_ver, 1):
        rd_size = struct.unpack_from("<I", d, 1632)[0]
        sections["recovery_dtbo"] = (rd_size, off(sec_off + s_size + t_size))
    if hdr_version_ge(hdr_ver, 2):
        dtb_size = struct.unpack_from("<I", d, 1648)[0]
        base = off(sec_off + s_size + t_size + sections.get("recovery_dtbo", (0, 0))[0])
        sections["dtb"] = (dtb_size, base)
    return dict(ver=hdr_ver, page=page, k_size=k_size, r_size=r_size,
                os_ver=os_ver, cmdline=cmdline, name=name,
                kernel=d[k_off:k_off + k_size],
                ramdisk=d[r_off:r_off + r_size],
                sections={n: d[o:o + s] for n, (s, o) in sections.items()}, raw=d)


def hdr_version_ge(v, ref):
    return v >= ref


def build_boot(b):
    page = b["page"]
    if b["ver"] >= 3:
        hdr = bytearray(4096)
        hdr[:8] = MAGIC
        struct.pack_into("<4I", hdr, 8, len(b["kernel"]), len(b["ramdisk"]),
                         b["os_ver"], b["h_size"])
        # reserved + version + cmdline
        struct.pack_into("<4I", hdr, 24, 0, 0, 0, 0)
        struct.pack_into("<I", hdr, 40, b["ver"])
        hdr[44:44 + len(b["cmdline"].encode())] = b["cmdline"].encode()
        out = bytes(hdr) + b["kernel"]
        out += b"\x00" * ((-(len(out))) % page)
        out += b["ramdisk"]
        return out
    raise ValueError("rebuild v0-v2: nie wspierany (urządzenie używa v3/v4)")


def patch_bootclasspath(in_path, out_path, extra_jars):
    b = parse_boot(in_path)
    comp = detect_comp(b["ramdisk"])
    cpio = decompress(b["ramdisk"], comp)
    files = cpio_parse(cpio)
    rc_names = [n for n in files if n == "init.rc" or n.endswith("/init.rc")]
    if not rc_names:
        raise ValueError("init.rc nie znaleziony w ramdisku!")
    rc_name = rc_names[0]
    mode, uid, gid, data = files[rc_name]
    text = data.decode()
    lines = text.split("\n")
    patched = 0
    for i, ln in enumerate(lines):
        if ln.strip().startswith("export BOOTCLASSPATH"):
            before = ln.strip()
            add = ":".join(j for j in extra_jars if j not in ln)
            lines[i] = ln.rstrip() + ":" + add
            print("PRZED:", before[:120] + ("..." if len(before) > 120 else ""))
            print("PO   :", lines[i][:120] + ("..." if len(lines[i]) > 120 else ""))
            patched += 1
            break
    if not patched:
        raise ValueError("brak 'export BOOTCLASSPATH' w init.rc!")
    files[rc_name] = (mode, uid, gid, "\n".join(lines).encode())
    new_cpio = cpio_build(files)
    new_rd = compress(new_cpio, comp if comp != "lz4_legacy" else "gzip")
    if comp == "lz4_legacy":
        print(f"UWAGA: lz4_legacy -> przepakowano na gzip (kernel obsluguje)")
    b["ramdisk"] = new_rd
    open(out_path, "wb").write(build_boot(b))
    print(f"boot: v{b['ver']}, kernel {len(b['kernel'])} B, "
          f"ramdisk {b['r_size']} -> {len(new_rd)} B ({comp}), "
          f"plikow w ramdisk: {len(files)}")
    print(f"bootimg OK: {out_path}")


if __name__ == "__main__":
    if sys.argv[1] == "patch":
        patch_bootclasspath(sys.argv[2], sys.argv[3], sys.argv[4:])
    elif sys.argv[1] == "info":
        b = parse_boot(sys.argv[2])
        comp = detect_comp(b["ramdisk"])
        print(f"ver={b['ver']} kernel={b['k_size']}B ramdisk={b['r_size']}B comp={comp}")
        print("cmdline:", b["cmdline"][:200])
        files = cpio_parse(decompress(b["ramdisk"], comp))
        print(f"plikow w ramdisk: {len(files)}; init.rc: "
              f"{[n for n in files if n.endswith('init.rc')]}")
    else:
        print(__doc__)
