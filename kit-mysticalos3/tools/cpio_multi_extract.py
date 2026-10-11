#!/usr/bin/env python3
"""Wyciaga WSZYSTKIE sklejone archiwa cpio (newc) z jednego pliku.
GNU cpio -i czyta tylko pierwsze archiwum do TRAILER!!! - Android ramdisk.img
czesto zawiera kilka sklejonych archywow (boot + vendor/dtbo etc).
Uzycie: cpio_multi_extract.py <in.cpio> <outdir>
"""
import os, sys, stat

def run(data, outdir):
    pos, n = 0, 0
    magic = (b"070701", b"070702")
    while pos < len(data) - 6:
        if data[pos:pos+6] not in magic:
            pos += 1
            continue
        try:
            f = [int(data[pos+6+i*8:pos+14+i*8], 16) for i in range(13)]
        except ValueError:
            pos += 1
            continue
        mode, filesize, namesize = f[1], f[6], f[11]
        if namesize <= 0 or namesize > 4096 or filesize > len(data):
            pos += 1
            continue
        name = data[pos+110:pos+110+namesize-1].decode("utf-8", "replace")
        hdr_end = pos + 110 + namesize
        hdr_end = (hdr_end + 3) & ~3
        if hdr_end + filesize > len(data):
            pos += 1
            continue
        fstart = hdr_end
        fend = (fstart + filesize + 3) & ~3
        if name == "TRAILER!!!":
            pos = fend
            continue
        path = os.path.join(outdir, name)
        ft = mode & 0o170000
        try:
            if ft == 0o040000:
                os.makedirs(path, exist_ok=True)
            elif ft == 0o120000:
                os.makedirs(os.path.dirname(path) or outdir, exist_ok=True)
                try:
                    os.symlink(data[fstart:fstart+filesize].decode("utf-8","replace"), path)
                except FileExistsError:
                    pass
            elif ft == 0o100000:
                os.makedirs(os.path.dirname(path) or outdir, exist_ok=True)
                with open(path, "wb") as w:
                    w.write(data[fstart:fstart+filesize])
                os.chmod(path, mode & 0o7777)
        except (OSError, ValueError) as e:
            print("skip %s: %s" % (name, e), file=sys.stderr)
        n += 1
        pos = fend
    return n

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__); sys.exit(2)
    data = open(sys.argv[1], "rb").read()
    os.makedirs(sys.argv[2], exist_ok=True)
    print("plikow wyciagnietych:", run(data, sys.argv[2]))
