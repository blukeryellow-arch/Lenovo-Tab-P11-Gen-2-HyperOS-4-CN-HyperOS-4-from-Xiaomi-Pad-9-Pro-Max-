#!/usr/bin/env bash
# Niezależna weryfikacja obrazu EROFS: wyciagam go fsck.erofs i porównuj KAŻDY wpis
# z drzewem zrodlowym - pliki po sha256, symlink po readlink, katalogi po istnieniu.
#
# Po co kolejny skrypt, skoro make_release.sh ma krok 4/6? Bo make_release patrzy tylko
# na pliki ('find -type f'), a pierwszy pelny przejazd na drzewie systemowym wywolil
# FileNotFoundError na /adb_keys: to wiszący symlink, ktorego os.walk nie odrzuca.
# Obraz EROFS trzyma symlinki wśród inode'ow, wiec 'same pliki' to NIE jest rowne
# 'same drzewo' - miałbym zielone światło przy utraconych linkach.
#
# Uzycie: tools/verify_image.sh --img <obraz> --tree <drzewo> [--fsck <fsck.erofs>]
#         tools/verify_image.sh --img rom/system_hyperos4_p11g2.img --tree /tmp/sys-tree2/system_tree
set -uo pipefail
IMG=''; TREE=''; HERE=$(cd "$(dirname "$0")" && pwd); FS=${FSCK:-}; EXCL=''
while [ $# -gt 0 ]; do
  case $1 in
    --img) IMG=$2; shift 2;; --tree) TREE=$2; shift 2;; --fsck) FS=$2; shift 2;;
    --exclude) EXCL="$EXCL|$2"; shift 2;;
    *) echo "nieznana opcja: $1" >&2; exit 3;;
  esac
done
[ -f "$IMG" ] || { echo "podaj --img <obraz>"; exit 3; }
[ -d "$TREE" ] || { echo "podaj --tree <katalog>"; exit 3; }
[ -n "$FS" ] || FS="$HERE/vendor/erofs/fsck.erofs"
[ -x "$FS" ] || FS=$(command -v fsck.erofs || true)
[ -n "$FS" ] || { echo "brak fsck.erofs (tools/build_erofs_local.sh)"; exit 2; }
case $TREE in /*) :;; *) TREE=$PWD/$TREE;; esac

OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
echo "== 1/3 fsck.erofs $IMG"
if timeout 900 "$FS" "$IMG" > "$OUT/fsck.txt" 2>&1; then
  echo "   czysto ($(grep -c . "$OUT/fsck.txt") linii raportu)"
else
  echo "   fsck zgłosił błędy (rc=$?):"; head -6 "$OUT/fsck.txt" | sed 's/^/     /'; exit 1
fi
echo "== 2/3 ekstrakcja z obrazu"
timeout 1800 "$FS" --extract="$OUT/x" "$IMG" >/dev/null 2>&1 || { echo "   ekstrakcja nieudana"; exit 1; }
echo "== 3/3 porownanie z $TREE"
python3 - "$TREE" "$OUT/x" "${EXCL#|}" <<'PY'
import os,sys,hashlib,re
src,dst=sys.argv[1],sys.argv[2]
pats=[p for p in (sys.argv[3].split('|') if len(sys.argv)>3 and sys.argv[3] else []) if p]
def skip(rel):
    return any(re.search(p, rel) for p in pats)
def walk(root):
    d={}
    for r,ds,fs in os.walk(root, followlinks=False):
        for name in ds+fs:
            p=os.path.join(r,name); k=os.path.relpath(p,root)
            if skip(k): continue
            if os.path.islink(p): d[k]='L:'+os.readlink(p)
            elif os.path.isfile(p):
                h=hashlib.sha256()
                with open(p,'rb') as f:
                    for b in iter(lambda:f.read(1<<20),b''): h.update(b)
                d[k]='F:'+h.hexdigest()
            elif os.path.isdir(p): d[k]='D'
    return d
A=walk(src); B=walk(dst)
miss=sorted(set(A)-set(B)); extra=sorted(set(B)-set(A))
diff=sorted(k for k in set(A)&set(B) if A[k]!=B[k])
nf=sum(1 for v in A.values() if v.startswith('F:'))
nl=sum(1 for v in A.values() if v.startswith('L:'))
nd=sum(1 for v in A.values() if v=='D')
print(f"  wykluczenia: {pats if pats else 'brak'}")
print(f"  zrodlo: {len(A)} wpisów (pliki {nf}, symlinki {nl}, katalogi {nd})")
print(f"  z obrazu: {len(B)} wpisów")
print(f"  ZGODNE: {len(set(A)&set(B))-len(diff)}   rozbiezne: {len(diff)}   brak z obrazu: {len(miss)}   dodatkowe: {len(extra)}")
for k in diff[:8]: print("   ROZBIEZNOSC:", k, "|", A[k][:24], "vs", B[k][:24])
for k in miss[:8]: print("   BRAK W OBRAZIE:", k)
for k in extra[:8]: print("   DODATKOWY:", k)
sys.exit(0 if not (diff or miss or extra) else 1)
PY
rc=$?
[ $rc -eq 0 ] && echo "WERYFIKACJA OK: obraz oddaje drzewo 1:1 (pliki+symlinki+katalogi)" \
              || echo "WERYFIKACJA NIE PRZESZLA (rc=$rc)"
exit $rc
