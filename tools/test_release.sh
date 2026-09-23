#!/usr/bin/env bash
# Wracalny zestaw testow dla sciezki budowy wydania (tools/make_release.sh + towarzysze).
#
# Po co: przez dluzszy czas wiedza o tym, ze 'product.img jest dobry' istniala TYLKO jako
# historia polecen w mojej sesji. To sie nie przenosi na zadne inne urzadzenie ani na zadna
# pozniejsza zmiane. Ten skrypt odtwarza te same kontrole na drzewach syntetycznych (sekundy,
# zero zaleznosci od obrazow 1,4 GB) i doklada rzeczy, ktorych sam nie sprawdzilem:
#  - TEST C: czy weryfikator NAPRAWDE failuje, kiedy w obrazie czegoś brakuje (test negatywny;
#    bez niego 'wszystkie pliki OK' moze znaczyć 'nikt nie sprawdzil, ze check cokolwiek widzi')
#  - TEST D: czy symlinki sa w ogole objetoane weryfikacja (byly, ale dopiero po 409 linkach
#    w drzewie systemowym - patrz docs/06 §6.9)
#  - TESTY E-H: bramka rozmiaru partycji w generowanym flash-all.sh, na atrapie fastboot
#    (atrapa zlapala trzy moje bledy: stat na symlinku, '$(((' jako podstawienie, '*[!0-9]*'
#    odrzucajacy '0x' - patrz docs/06 §6.11)
#
# Uzycie: tools/test_release.sh [--erofs-dir KATALOG] [--keep]
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(dirname "$HERE")
EROFS_DIR=${EROFS_DIR:-}
KEEP=0; REAL=0
# Opcje moga byc w dowolnej kolejnosci i dowolna ilosc - pierwsza wersja czytala je tylko
# z $1, wiec './test_release.sh --erofs-dir X --real' cicho pomijala blok J (16 PASS, zero
# 'realnych'). To jest ten sam blad, co 'opcja po opcji' w kazdym skrypcie powloki.
while [ $# -gt 0 ]; do
  case $1 in
    --keep) KEEP=1; shift;;
    --real) REAL=1; shift;;
    --erofs-dir) EROFS_DIR=$2; shift 2;;
    *) echo "nieznana opcja: $1 (zna --keep, --real, --erofs-dir)" >&2; exit 3;;
  esac
done
WORK=$(mktemp -d /tmp/reltest.XXXXXX)
trap '[ $KEEP -eq 1 ] || rm -rf "$WORK"' EXIT
MK="$EROFS_DIR/mkfs.erofs"; FS="$EROFS_DIR/fsck.erofs"
pass=0; fail=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fail=$((fail+1)); }
note() { printf '        %s\n' "$*"; }
t() { # t <nazwa> <oczekiwane rc> <komenda...>
  local name=$1 want=$2; shift 2
  local out rc
  out=$("$@" 2>&1); rc=$?
  if [ "$rc" = "$want" ]; then ok "$name (rc=$rc)"; else bad "$name: rc=$rc, miało byc $want"; printf '%s\n' "$out" | tail -6 | sed 's/^/        |/'; fi
  LAST_OUT=$out
}
[ -x "$MK" ] && [ -x "$FS" ] || { echo "FATAL: brak $MK / $FS — zbuduj: tools/build_erofs_local.sh $EROFS_DIR"; exit 2; }
echo "=== narzedzia: $("$MK" --help 2>&1 | head -1) ==="
printf '  mkfs=%s fsck=%s  praca=%s\n' "$MK" "$FS" "$WORK"

# ---------------------------------------------------------------- drzewo testowe
say_tree="$WORK/tree"
mkdir -p "$say_tree/fonts" "$say_tree/etc/selinux" "$say_tree/overlay"
head -c 90000 /dev/zero | tr '\0' 'A' > "$say_tree/fonts/dlugi.ttf"
printf 'sans-serif\n' > "$say_tree/fonts/fonts.xml"
printf 'seapp\n' > "$say_tree/etc/selinux/product_seapp_contexts"
printf '<overlay/>\n' > "$say_tree/overlay/SomeRro.apk"
# symlinki: dzialajacy + wiszacy (ten drugi wywola bledy w naiwnych porownywarkach - patrz docs/06 §6.9)
ln -s fonts.xml "$say_tree/etc/link_do_okladki.xml"
ln -s ../nigynie_ma "$say_tree/etc/link_wiszacy"
mkdir -p "$say_tree/katalog_pusty"

# ---------------------------------------------------------------- A: selftest buildera
echo "== A/6  make_release --selftest"
t "selftest przechodzi" 0 bash "$HERE/make_release.sh" --selftest --erofs-dir "$EROFS_DIR" --out "$WORK/selftest"
grep -Eq 'round-trip: OK|weryfikacja product: OK' <<<"$LAST_OUT" && ok "selftest: obrot obrazu potwierdzony" || bad "selftest: brak linii o weryfikacji obrazu"
grep -q 'IDENTYCZNY sha256' <<<"$LAST_OUT" && ok "selftest: determinizm zgloszony" || bad "selftest: brak linie determinizmu"

# ---------------------------------------------------------------- B: determinizm na tym drzewie
echo "== B/6  determinizm (dwa budowania, ten sam plik)"
$MK -T 0 -U 11111111-1111-1111-1111-111111111111 -zlz4 "$WORK/b1.img" "$say_tree" >/dev/null 2>&1
$MK -T 0 -U 11111111-1111-1111-1111-111111111111 -zlz4 "$WORK/b2.img" "$say_tree" >/dev/null 2>&1
if cmp -s "$WORK/b1.img" "$WORK/b2.img"; then ok "dwa budowania identyczne co do bajta ($(stat -c%s "$WORK/b1.img") B)"; else bad "buildy roznia sie — nie da sie wydac przepisu 'odtworzy to samo'"; fi

# ---------------------------------------------------------------- C: weryfikator musi WIDZEC brak
echo "== C/6  verify_image.sh: test negatywny (czy check naprawde cos widzi)"
t "obraz poprawny przechodzi" 0 bash "$HERE/verify_image.sh" --img "$WORK/b1.img" --tree "$say_tree" --fsck "$FS"
# psuje: wyciagam plik z drzewa, obraz zostaje stary -> musi byc 'dodatkowy'; albo odwrotnie
printf 'dopisany_po_fakcie\n' > "$say_tree/etc/nowy_plik.txt"
t "drzewo ma wiecej niz obraz -> FAIL" 1 bash "$HERE/verify_image.sh" --img "$WORK/b1.img" --tree "$say_tree" --fsck "$FS"
grep -q 'BRAK W OBRAZIE' <<<"$LAST_OUT" && ok "wskazal brakujacy wpis po nazwie" || { note "$(printf '%s' "$LAST_OUT" | grep -m1 'BRAK\|ROZBIEZ' || echo '(brak wskazania)')"; bad "nie wskazal, ktorego wpisu brakuje"; }
rm "$say_tree/etc/nowy_plik.txt"

# ---------------------------------------------------------------- D: symlinki
echo "== D/6  symlinki w obszarze weryfikacji (docs/06 §6.9)"
nlinks=$(find "$say_tree" -type l | wc -l)
grep -qE "symlinki $nlinks" <<<"$LAST_OUT" || true
bash "$HERE/verify_image.sh" --img "$WORK/b1.img" --tree "$say_tree" --fsck "$FS" 2>&1 | tail -3 > "$WORK/d.txt"
printf '  (linkow w drzewie: %s)\n' "$nlinks"
if grep -q 'ZGODNE' "$WORK/d.txt"; then ok "drzewo z $nlinks symlinkami zweryfikowane"; else bad "weryfikacja drzewa z linkami padla"; cat "$WORK/d.txt" | sed 's/^/        |/'; fi
# negatyw: podmieniam cel linku w drzewie - obraz ma stary, weryfikator MUSI to zobaczyc
ln -sfn fonts.xml "$say_tree/etc/link_wiszacy"
if bash "$HERE/verify_image.sh" --img "$WORK/b1.img" --tree "$say_tree" --fsck "$FS" >/dev/null 2>&1; then
  bad "weryfikator NIE zobaczyl zmiany celu symlinka (pusty check!)"
else
  ok "zmiana celu symlinka zostala wykryta"
fi

# ---------------------------------------------------------------- E-H: flash-all.sh na atrapie
echo "== E-H/6  bramka rozmiaru i kolejnosc flashy (atrapa fastboot)"
REL="$WORK/rel"   # wydanie TESTOWE: --allow-no-vbmeta ponizej
bash "$HERE/make_release.sh" --product-tree "$say_tree" --erofs-dir "$EROFS_DIR" \
     --allow-no-vbmeta --out "$REL" > "$WORK/relbuild.log" 2>&1
[ -f "$REL/flash-all.sh" ] && ok "make_release wypluil flash-all.sh" || { bad "brak flash-all.sh"; tail -5 "$WORK/relbuild.log" | sed 's/^/        |/'; }
mkdir -p "$WORK/stub/bin"
if [ ! -x "$WORK/stub/bin/fastboot" ]; then
  cat > "$WORK/stub/bin/fastboot" <<'STUB'
#!/usr/bin/env bash
# Atrapa fastboot (te sama jak w docs/06 §6.11; tu dokladana przez test).
# FB_SLOT, FB_USERSPACE, FB_SIZE_<PART>_<SLOT> steruja odpowiedziami.
echo "FASTBOOT: $*" >> "${FB_LOG:-/dev/null}"
case "$1 $2" in
  "getvar product")      echo "product: TB350FU"; exit 0;;
  "getvar current-slot") echo "current-slot: ${FB_SLOT:-b}"; exit 0;;
  "getvar is-userspace") echo "is-userspace: ${FB_USERSPACE:-yes}"; exit 0;;
  fetch)                 echo "OKAY"; exit 0;;
esac
if [ "$1" = getvar ]; then
  k=${2#partition-size:}
  if [ "$k" != "$2" ]; then
    ev=FB_SIZE_$(printf '%s' "$k" | tr 'a-z' 'A-Z'); v=${!ev:-}
    if [ -n "$v" ]; then eval "n=$v"; echo "partition-size[$k]: $v ($(( n / 1048576 )) MB)"; exit 0; fi
    echo "FAILED (partition-size unknown: $k)" >&2; exit 1
  fi
fi
echo "OKAY"; exit 0
STUB
  chmod +x "$WORK/stub/bin/fastboot"
fi
runfb() { # runfb <nazwa> <oczek_rc> <oczek_flashy> [ZMIENNE...]
  local name=$1 want=$2 flashes=$3; shift 3
  local envs=(); local i
  for kv in "$@"; do envs+=("$kv"); done
  : > "$WORK/fb.log"
  local out rc
  out=$(cd "$REL" && env PATH="$WORK/stub/bin:$PATH" FB_LOG="$WORK/fb.log" "${envs[@]}" bash flash-all.sh 2>&1); rc=$?
  local got; got=$(grep -c '^FASTBOOT: flash ' "$WORK/fb.log")
  if [ "$rc" = "$want" ] && [ "$got" = "$flashes" ]; then
    ok "$name (rc=$rc, flashby=$got)"
  else
    bad "$name: rc=$rc flashby=$got, oczekiwano rc=$want flashby=$flashes"
    printf '%s\n' "$out" | grep -E 'ZMALE|PRZERWANE|ok |nie zwrocil' | head -4 | sed 's/^/        |/;s/^/      /'
  fi
}
sz_v="FB_SIZE_VBMETA_A=0x1000000 FB_SIZE_VBMETA_B=0x1000000"
sz_pr="FB_SIZE_PRODUCT_A=0x100000000 FB_SIZE_PRODUCT_B=0x100000000"
sz_sy="FB_SIZE_SYSTEM_A=0x1000000000 FB_SIZE_SYSTEM_B=0x1000000000"
# wydanie bez --system-img: flash-all MUSI przerwac (nie ma co wgrac)
t "brak system.img -> abort, zero flashow" 1 bash -c "cd '$REL' && env PATH='$WORK/stub/bin:$PATH' FB_LOG='$WORK/fb.log' bash flash-all.sh >/dev/null 2>&1"
# Dokladam brakujace obrazy. vbmeta NULOWY jest celowy: bramka traktuje need=0 jako
# 'brak obrazu, pomijam' (nie udaje, ze 0 B miesci sie na slocie 8 MB - patrz §6.11).
# System to plik rzedowy 900 MB (truncate nie zapisuje dysku, sekunda), zeby F mial z czym
# porownywac slot 768 MB. Poprzednia wersja tego testu kasowala go 'cp /dev/null' POMIEDZY
# E i F - stad F przepuszczal, choc powinien przerwac (2026-09-23).
: > "$REL/vbmeta_hyperos4_p11g2.img"
truncate -s 900M "$REL/system_hyperos4_p11g2.img" 2>/dev/null \
  || dd if=/dev/zero of="$REL/system_hyperos4_p11g2.img" bs=1M count=900 conv=notrunc status=none
runfb "E: sloty obszerne (product 4 GB, system 64 GB)" 0 6 $sz_v $sz_pr $sz_sy
runfb "F: system 900 MB na slocie 768 MB -> abort" 1 0 $sz_v $sz_pr FB_SIZE_SYSTEM_A=0x30000000 FB_SIZE_SYSTEM_B=0x30000000

runfb "G: product 4 KB przy obrazie product" 1 0 FB_SIZE_VBMETA_A=0x1000000 FB_SIZE_VBMETA_B=0x1000000 FB_SIZE_PRODUCT_A=0x1000 FB_SIZE_PRODUCT_B=0x1000 $sz_sy
runfb "H: fastboot nie zna partition-size -> ostrzezenie + kontynuacja" 0 6 FB_USERSPACE=yes
runfb "I: brak fastbootd (is-userspace:no) -> zero flashow" 1 0 $sz_v $sz_pr $sz_sy FB_USERSPACE=no
# ---------------------------------------------------------------- J: release realny
if [ $REAL -eq 1 ]; then
  echo "== J    wydanie realne (dist/release) — nie tylko syntetyki"
  for d in "$ROOT"/dist/release/HyperOS4_P11Gen2*; do
    [ -d "$d" ] || continue
    b=$(basename "$d")
    for img in product_hyperos4_p11g2.img system_hyperos4_p11g2.img; do
      [ -f "$d/$img" ] || { note "$b: brak $img (oczekiwane - nie jest w gicie)"; continue; }
      # drzewo ZALEZY OD WARIANTU - 'product' w -full ma overlay, lekkie drzewo nie;
      # pierwsza wersja testu podstawiala /tmp/tree-product do obu i 'DODATKOWE' wpisy
      # z -full wygladaly jak usterka wydania, a byly usterka testu (2026-09-23)
      case "$b" in
        *-full) pt=${PRODTREE_FULL:-/tmp/tree-full};;
        *)      pt=${PRODTREE:-/tmp/tree-product};;
      esac
      case $img in
        product_hyperos4_p11g2.img) tree=$pt;;
        *)                          tree=${SYSTREE:-/tmp/sys-tree2/system_tree};;
      esac
      if ! [ -d "$tree" ]; then note "$b/$img: brak drzewa $tree - pomijam (nie mam czego porownywac)"; continue; fi
      if [ "$img" = system_hyperos4_p11g2.img ]; then
        t "$b/$img weryfikacja 1:1 (z wykluczeniami)" 0 bash "$HERE/verify_image.sh" --img "$d/$img" --tree "$tree" \
            --fsck "$FS" --exclude '\.komentarz\.txt$'
      else
        t "$b/$img weryfikacja 1:1" 0 bash "$HERE/verify_image.sh" --img "$d/$img" --tree "$tree" --fsck "$FS"
      fi
    done
    # suma kontrolna wydania musi sie zgadzac co do pliku (brak system.img = innny test, patrz wyzej)
    t "$b: sha256sum -c SHA256SUMS.txt" 0 bash -c "cd '$d' && sha256sum -c SHA256SUMS.txt >/dev/null 2>&1"
    # manifest musi mowic te same rozmiary, co pliki na dysku (w Pythonie, nie w gniazdkach awk)
    if python3 - "$d" <<'PYPY'
import os,sys
d=sys.argv[1]
bad=[]
for ln in open(os.path.join(d,'release-manifest.tsv'),encoding='utf-8') :
    p=ln.rstrip('\n').split('\t')
    if len(p)>=2 and p[0].endswith('.img') and os.path.exists(os.path.join(d,p[0])):
        real=os.path.getsize(os.path.join(d,p[0]))
        if str(real)!=p[1]: bad.append(f"{p[0]}: manifest {p[1]} vs plik {real}")
if bad: print('\n'.join(bad)); sys.exit(1)
PYPY
    then ok "$b: rozmiary w manifeście = rozmiary plików"; else bad "$b: manifest nie zgadza się z plikami"; fi
  done
fi

echo; echo "=== podsumowanie: $pass PASS, $fail FAIL ==="
[ $fail -eq 0 ] || echo "UWAGA: ktorys test padl — nie wydawaj zmiany w tools/, ktora to wywolala."
exit $([ $fail -eq 0 ] && echo 0 || echo 1)
