#!/usr/bin/env bash
# Sortowanie sterty pomieszanych obrazow po odciskach kluczy AVB - nie po nazwach plikow.
#
# Nazwe pliku przepisac sie da w trzy sekundy; odcisku klucza nie. Kazdy obraz
# partycji z AVB ma wbudowany blok vbmeta (1-2 KB) zakonczony stopeka AVBf. Ten blok
# zawiera klucz podpisujacy, rollback index location, flags i property descriptors
# z fingerprintiem buildu - to wystarczy, zeby opisac obraz bez sciagania go w calosci.
#
# Target (Lenovo Tab P11 Gen 2, vbmeta.img) przypinal:
#   boot           9d808b0995768d0677fccb1efcddb7cf9e153d99
#   vbmeta_system  fa41159a5d696abdef93176a07d0b0d001263f01
#   vbmeta_vendor  9577bc6c0772975ecce93c4d8a178662c728dadf
#   (siebie podpisal AOSP testkey_rsa2048  cdbb77177f731920bbe0a0f94f84d9038ae0617d)
#
# UZYCIE:  ./identify_images.sh <katalog z obrazami>
# WYNIK:   <katalog>/_avb_frags/  - fragmenty po ~2-64 KB; kazdy ponizej limitu
#          100 MB transferu przez Google Drive. Calych obrazow przesylac nie trzeba.
#
# Tylko czyta. Nic nie zmienia, nie wymaga roota.
set -uo pipefail

DIR=${1:-.}
[ -d "$DIR" ] || { echo "katalog '$DIR' nie istnieje" >&2; exit 2; }
command -v python3 >/dev/null || { echo "BRAK python3" >&2; exit 1; }
OUT="$DIR/_avb_frags"
mkdir -p "$OUT"
: > "$OUT/MANIFEST.txt"

python3 - "$DIR" "$OUT" <<'PY'
import os, struct, sys, glob

DIR, OUT = sys.argv[1], sys.argv[2]
AVB0 = b'AVB0'
files = sorted(glob.glob(os.path.join(DIR, '*.img')) + glob.glob(os.path.join(DIR, '*.IMG')))
if not files:
    print(f"Brak plikow .img w {DIR}", file=sys.stderr)
    raise SystemExit(1)

def block_size(hdr):
    """Rozmiar bloku vbmeta z jego naglowka. Pola (authentication_data_block_size,
    auxiliary_data_block_size) ida parami; u roznych generacji avbtool przesuniete o
    4 bajty. Akceptujemy tylko pary dace sensowny rozmiar (<64 KB bloku)."""
    for shift in (8, 12):
        try:
            auth = struct.unpack_from('>Q', hdr, shift)[0]
            aux  = struct.unpack_from('>Q', hdr, shift + 8)[0]
        except struct.error:
            continue
        if 0 <= auth <= 4096 and 64 <= aux <= 64 * 1024 and 256 + auth + aux <= 65536:
            return shift, auth, aux
    return None

for img in files:
    name = os.path.basename(img)
    size = os.path.getsize(img)
    rep = [f"### {name}  {size} B"]
    try:
        with open(img, 'rb') as f:
            head = f.read(min(8, size))
            sig = {b'ANDROID!': 'android boot image', b'VNDRBOOT': 'vendor_boot',
                   b'\x3b\xff\x26\xed': 'Android sparse'}.get(head)
            if head[:4] == AVB0:
                sig = 'vbmeta (partycja vbmeta)'
            rep.append(f"sygnatura naglowka: {sig or head.hex() or 'plik pusty'}")

            # ostatni AVB0 w pliku = blok vbmeta tego obrazu; padding partycji to zera,
            # wiec rfind jest stabilniejszy niż liczenie offsetow ze stopki
            voff, tail = None, None
            CHUNK = 8 * 1024 * 1024
            pos = size
            while pos > 0 and voff is None:
                lo = max(0, pos - CHUNK)
                f.seek(lo); buf = f.read(pos - lo)
                i = buf.rfind(AVB0)
                if i >= 0:
                    voff = lo + i
                pos = lo
            if voff is None:
                rep.append("AVB: nie znaleziono bloku vbmeta (partycja surowa albo inny build)")
            else:
                f.seek(voff); hdr = f.read(256)
                got = block_size(hdr)
                if not got:
                    rep.append(f"AVB0 znaleziony @{voff}, ale naglowek nieprawidlowy - brak fragmentu")
                else:
                    shift, auth, aux = got
                    total = 256 + auth + aux
                    f.seek(voff); blob = f.read(total)
                    frag = os.path.join(OUT, name + '.vbmeta')
                    with open(frag, 'wb') as w:
                        w.write(blob)
                    # Celowo NIE odczytuje stad flags/rollback_index_location: layout
                    # rozni sie miedzy format_version 1.0 i 1.1, latwo podac bledna
                    # liczbe. Autorytatywnie robi to avbtool ponizej.
                    ALG = {0: 'NONE', 1: 'SHA256_RSA2048', 2: 'SHA256_RSA4096',
                           5: 'SHA256_RSA8192', 7: 'SHA512_RSA8192'}
                    a = struct.unpack_from('>I', hdr, 28)[0]
                    rep.append(f"AVB: blok @{voff} ({total} B) algorytm={ALG.get(a, a)}")
                    rep.append(f"     zapisano: {name}.vbmeta ({len(blob)} B)")
            f.seek(0)
            with open(os.path.join(OUT, name + '.page0'), 'wb') as w:
                w.write(f.read(4096))
    except Exception as e:
        rep.append(f"BLAD odczytu: {type(e).__name__}: {e}")
    with open(os.path.join(OUT, 'MANIFEST.txt'), 'a') as w:
        w.write("\n".join(rep) + "\n")
    print("\n".join("   " + l for l in rep))
    print()
PY

AVB=""
for c in avbtool "$HOME/romtools/avb/avbtool.py" "$HOME/avb/avbtool.py"; do
  if command -v "$c" >/dev/null 2>&1 || [ -f "$c" ]; then AVB=$c; break; fi
done
if [ -n "$AVB" ]; then
  echo "=== odciski kluczy i lancuchy (avbtool na fragmentach) ==="
  for fr in "$OUT"/*.vbmeta; do
    [ -e "$fr" ] || continue
    echo "--- $(basename "$fr")"
    python3 "$AVB" info_image --image "$fr" 2>&1 |
      grep -E 'Algorithm:|Public key|Rollback|Flags:|Partition Name|Chain Partition|Hash descriptor|HASHTREE|Prop: com.android.build.(product|system|vendor|vendor_boot|odm)' |
      sed 's/^/    /' | head -30
    python3 "$AVB" info_image --image "$fr" 2>&1 |
      awk -v f="$(basename "$fr")" '/Public key \(sha1\)/{print "KLEJE\t"f"\t"$NF}' >> "$OUT/MANIFEST.txt"
  done
else
  echo "(avbtool nieznaleziony - fragmenty zapisane, odczytam je po swojej stronie)"
fi

echo
echo "=== GOTOWE: $OUT ==="
ls -l "$OUT" | tail -n +2 | awk '{printf "  %-44s %9s B\n", $9, $5}'
echo
echo "Wrzu CALA zawartosc _avb_frags na Google Drive."
