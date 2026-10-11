import sys, struct
try:
    data = open('/tmp/tail1m.bin','rb').read()
    eocd = data.rfind(b'PK\x05\x06')
    print("EOCD w tailu:", eocd, "rozmiar tailu:", len(data))
    if eocd >= 0:
        cd_size, cd_off = struct.unpack('<II', data[eocd+12:eocd+20])
        print(f"central dir: size={cd_size} off={cd_off} (plik {sys.argv[1]} B)")
except Exception as e:
    print("tail parse:", e)
