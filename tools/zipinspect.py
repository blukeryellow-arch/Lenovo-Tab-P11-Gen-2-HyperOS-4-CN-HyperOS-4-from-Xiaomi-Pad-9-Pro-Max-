import zipfile, struct
z = zipfile.ZipFile('/tmp/base.zip')
names = [n for n in z.namelist() if n.endswith('.img')]
print("pliki .img:", len(names))
for n in sorted(names):
    i = z.getinfo(n)
    print(f"  {n.split('/')[-1]}: comp={i.compress_size} uncomp={i.file_size} method={i.compress_type}")
sup = [n for n in names if n.endswith('super.img')]
for n in sup:
    with z.open(n) as f:
        h = f.read(28)
        m = struct.unpack('<I', h[:4])[0]
        print(f"super.img glowa: magic={m:#x} bytes={h[:4].hex()}")
        if m == 0xED26FF3A:
            print("  -> SPARSE (simg2img przed lpunpack)")
        elif h[:4] == b'gDla':
            print("  -> liblp geometry RAW super (lpunpack wprost)")
        else:
            print("  -> nieznany format?!")
print("metody kompresji:", sorted(set(z.getinfo(n).compress_type for n in z.namelist() if not n.endswith('/'))))
