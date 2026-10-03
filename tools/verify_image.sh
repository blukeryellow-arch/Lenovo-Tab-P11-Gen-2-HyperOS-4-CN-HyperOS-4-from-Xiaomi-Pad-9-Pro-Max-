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
IMG=''; TREE=''; HERE=$(cd "$(dirname "$0")" && pwd); FS=${FSCK:-}; EXCL=''; EXPECT_OWNER=''; DUMP=${DUMP:-}
while [ $# -gt 0 ]; do
  case $1 in
    --img) IMG=$2; shift 2;; --tree) TREE=$2; shift 2;; --fsck) FS=$2; shift 2;;
    --exclude) EXCL="$EXCL|$2"; shift 2;;
    --expect-owner) EXPECT_OWNER=$2; shift 2;;
    --dump) DUMP=$2; shift 2;;
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
echo "== 1/4 fsck.erofs $IMG"
if timeout 900 "$FS" "$IMG" > "$OUT/fsck.txt" 2>&1; then
  echo "   czysto ($(grep -c . "$OUT/fsck.txt") linii raportu)"
else
  echo "   fsck zgłosił błędy (rc=$?):"; head -6 "$OUT/fsck.txt" | sed 's/^/     /'; exit 1
fi
echo "== 2/4 ekstrakcja z obrazu"
timeout 1800 "$FS" --extract="$OUT/x" "$IMG" >/dev/null 2>&1 || { echo "   ekstrakcja nieudana"; exit 1; }
echo "== 3/4 porownanie z $TREE"
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
                d[k]='F:'+h.hexdigest()+':'+oct(os.stat(p).st_mode & 0o7777)+((':'+str(os.stat(p).st_uid)+':'+str(os.stat(p).st_gid)) if ROOT else '')
            elif os.path.isdir(p): d[k]='D:'+oct(os.stat(p).st_mode & 0o7777)+((':'+str(os.stat(p).st_uid)+':'+str(os.stat(p).st_gid)) if ROOT else '')
    return d
ROOT = (os.geteuid()==0)   # uid/gid da sie odczytac z ekstrakcji TYLKO jako root:
# fsck.erofs jako zwykly uzytkownik nie wykona chown i dostaniemy uid ekstrakcji, nie obrazu.
A=walk(src); B=walk(dst)
miss=sorted(set(A)-set(B)); extra=sorted(set(B)-set(A))
diff=sorted(k for k in set(A)&set(B) if A[k]!=B[k])
nf=sum(1 for v in A.values() if v.startswith('F:'))
nl=sum(1 for v in A.values() if v.startswith('L:'))
nd=sum(1 for v in A.values() if v.startswith('D:'))   # 'D' NIGDY nie trafia: wartosc to
#   'D:0o755' (+ uid/gid jako root), wiec stary warunek 'v==D' dawal zero katalogow w
#   wyswietle przy 264 katalogach w drzewie (23 IX 2026). Sama weryfikacja byla poprawna -
#   porownanie liczy pelne wartosci - ale komunikat klamal, a komunikatem podejmuje decyzje.
print(f"  wykluczenia: {pats if pats else 'brak'}")
print(f"  zrodlo: {len(A)} wpisów (pliki {nf}, symlinki {nl}, katalogi {nd})")
print(f"  z obrazu: {len(B)} wpisów (pliki {sum(1 for v in B.values() if v.startswith('F:'))}, symlinki {sum(1 for v in B.values() if v.startswith('L:'))}, katalogi {sum(1 for v in B.values() if v.startswith('D:'))})")
if nf+nl+nd != len(A):
    print(f"  BLAD KONTROLNY: podzial {nf}+{nl}+{nd} != {len(A)} wpisow - licznik w tym skrypcie")
    print("     jest martwy, nie ufaj wyswietlenym kategoriom (patrz docs/06 §6.20).")
    sys.exit(4)
print(f"  ZGODNE: {len(set(A)&set(B))-len(diff)}   rozbiezne: {len(diff)}   brak z obrazu: {len(miss)}   dodatkowe: {len(extra)}")
def tail(x, n=24): return x[-n:] if len(x) > n else x
for k in diff[:8]:
    ax, bx = A[k], B[k]
    if ax[:40] == bx[:40]:   # sha taki sam -> roznicy jest try albo wlasciciel
        print("   ROZBIEZNOSC:", k, "| treSC IDENTYCZNA, roznia sie uprawnienia:", tail(ax, 22), "vs", tail(bx, 22))
    else:
        print("   ROZBIEZNOSC:", k, "|", tail(ax, 22), "vs", tail(bx, 22))
for k in miss[:8]: print("   BRAK W OBRAZIE:", k)
for k in extra[:8]: print("   DODATKOWY:", k)
sys.exit(0 if not (diff or miss or extra) else 1)
PY
rc=$?
[ $rc -eq 0 ] && echo "WERYFIKACJA OK: obraz oddaje drzewo 1:1 (pliki+symlinki+katalogi)" \
              || echo "WERYFIKACJA NIE PRZESZLA (rc=$rc)"

echo "== 4/4 wlasciciel obrazu (DAC)"
if [ -n "$EXPECT_OWNER" ]; then
  [ -x "$DUMP" ] || DUMP=$(command -v dump.erofs || true)
  if [ -z "$DUMP" ]; then
    echo "  NIE SPRAWDZONE: brak dump.erofs, a bez niego nie odczytam uid/gid z obrazu"
    echo "  (ekstrakcja jako zwykly uzytkownik NIE oddaje wlasciciela - nie udaje, ze sprawdzilem)"
    rc=1
  else
    NID=$("$DUMP" -s "$IMG" 2>/dev/null | awk -F': *' '/root nid/{print $2}')
    LINE=$("$DUMP" --nid="$NID" "$IMG" 2>/dev/null | grep -E 'Uid:' | tr -s ' ')
    WANT_UID=${EXPECT_OWNER%%:*}; WANT_GID=${EXPECT_OWNER##*:}
    got=$(printf '%s' "$LINE" | sed -n 's/.*Uid: \([0-9]*\).*Gid: \([0-9]*\).*/\1:\2/p')
    printf '  korzen obrazu (nid %s): %s   oczekiwano %s\n' "$NID" "${got:-?}" "$EXPECT_OWNER"
    if [ "$got" = "$WANT_UID:$WANT_GID" ]; then
      echo "  OK: wlasciciel zgodny z AOSP (korzen); try plikow porownane wyzej 1:1"
    else
      echo "  ROZBIEŻNOŚĆ: obraz ma wlasciciela $got, a wydanie musi miec $EXPECT_OWNER"
      echo "  (uid 1001 = 'radio' - to jest ten blad, ktory wykryto 2026-09-23: mkfs bral uid z drzewa)"
      rc=1
    fi
  fi
else
  echo "  (pominiem - nie podano --expect-owner; try byly porownywane)"
fi
exit $rc
