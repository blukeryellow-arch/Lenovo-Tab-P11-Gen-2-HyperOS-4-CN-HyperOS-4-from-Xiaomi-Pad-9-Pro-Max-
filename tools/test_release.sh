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
UUIDT=11111111-2222-3333-4444-555555555555
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
MK="$EROFS_DIR/mkfs.erofs"; FS="$EROFS_DIR/fsck.erofs"; DUMP="$EROFS_DIR/dump.erofs"
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
# BEZ 'tail -3': test szukal 'ZGODNE' w trzech ostatnich liniach, a gdy weryfikator
# dolozyl blok DAC (3 linie) tekst wypadl z okna i test failowal przy ZDROWYM obrazie.
# Asercja o tresci nie moze zalezec od liczby linii w cudzym wypisie.
bash "$HERE/verify_image.sh" --img "$WORK/b1.img" --tree "$say_tree" --fsck "$FS" > "$WORK/d.txt" 2>&1
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
# ---------------------------------------------------------------- K: higiena tekstu
echo "== K      pismo: zero znaków CJK/cyrylickich/emoji w tym, co trafia do wydania"
# Nie 'przy okazji', tylko jako test: trzy razy wplotlem obce znaki i trzy razy nikt
# tego nie widzial, bo skaner patrzyl po glob(), ktory omija .github/.
if python3 "$HERE/lint_pismo.py" --quiet; then
  ok "repo bez znakow obcego pisma (lint_pismo.py)"
else
  bad "lint_pismo.py znalazl obce znaki - patrz komunikat powyzej"
fi

# ---------------------------------------------------------------- L: try plikow
echo "== L/6  weryfikator pilnuje uprawniek (nie tylko tresci)"
TL=$WORK/L; mkdir -p "$TL/tree/etc" "$TL/fs"
printf 'system:x:1000:1000:system:/none:/bin/false\n' > "$TL/tree/etc/passwd"
chmod 644 "$TL/tree/etc/passwd"
"$MK" -T 0 -U "$UUIDT" --force-uid=0 --force-gid=0 "$TL/fs/product.img" "$TL/tree" >/dev/null 2>&1
t "L1: drzewo i obraz zgodne co do try" 0 bash "$HERE/verify_image.sh" --img "$TL/fs/product.img" --tree "$TL/tree" --fsck "$FS" --dump "$DUMP"
# podmieniam TRY w drzewie (tresc ta sama) - obraz NIE moze tego "przejsc"
chmod 600 "$TL/tree/etc/passwd"
out=$(bash "$HERE/verify_image.sh" --img "$TL/fs/product.img" --tree "$TL/tree" --fsck "$FS" --dump "$DUMP" 2>&1); rc=$?
if [ $rc -ne 0 ] && printf '%s' "$out" | grep -q 'roznia sie uprawnienia'; then
  ok "L2: zmiana try w drzewie wykryta (0o600 vs 0o644)"
else
  bad "L2: weryfikator przepuscil zmiane try! rc=$rc"
  printf '%s\n' "$out" | tail -3 | sed 's/^/      /'
fi
# i ta sama podmiana nie moze byc wykryta 'przez przypadek': przywracam try -> znow OK
chmod 644 "$TL/tree/etc/passwd"
t "L3: po przywroceniu try znow czysto" 0 bash "$HERE/verify_image.sh" --img "$TL/fs/product.img" --tree "$TL/tree" --fsck "$FS" --dump "$DUMP"

# ---------------------------------------------------------------- M: normalizacja wlasciciela
echo "== M/6  wlasciciel: --force-uid dziala, a bez niego dostajemy uid hosta"
# To jest sekcja o defecte znalezionym 2026-09-23: mkfs.erofs bierze uid/gid z drzewa, a
# drzewa powstaly z ekstrakcji na koncie 1001 - wydane obrazy mialy 'Uid: 1001 Gid: 1001'
# (korzen /product i /system). Bez tej sekcji nic by nie pilnowalo, ze flaga wciaz dziala.
TM=$WORK/M; mkdir -p "$TM/tree/etc"
printf 'x\n' > "$TM/tree/etc/a.txt"; chmod 644 "$TM/tree/etc/a.txt"
uid_host=$(id -u)
"$MK" -T 0 -U "$UUIDT" --force-uid=0 --force-gid=0 "$TM/root.img" "$TM/tree" >/dev/null 2>&1
"$MK" -T 0 -U "$UUIDT"                      "$TM/host.img" "$TM/tree" >/dev/null 2>&1
r_uid() { local n; n=$("$DUMP" -s "$1" 2>/dev/null | awk -F': *' '/root nid/{print $2}')
          "$DUMP" --nid="$n" "$1" 2>/dev/null | sed -n 's/.*Uid: \([0-9]*\).*/\1/p'; }
a=$(r_uid "$TM/root.img"); b=$(r_uid "$TM/host.img")
[ "$a" = 0 ] && ok "M1: z --force-uid=0 korzen ma uid 0 (bylo: $a)" || bad "M1: --force-uid nie dziala (uid=$a)"
if [ "$uid_host" = 0 ]; then
  note "M2: pomijam - runner jest rootem, wiec 'bez flagi' i tak da 0 (nie ma co porownywac)"
else
  [ "$b" = "$uid_host" ] && ok "M2: bez flagi korzen dziedziczy uid hosta ($b) - dokladnie to, co psulo wydanie" \
    || bad "M2: oczekiwalem uid hosta $uid_host, dostalem $b - zmienilo sie cos w mkfs"
fi
# i weryfikator MUSI to zobaczyc, gdy mu kazemy
if bash "$HERE/verify_image.sh" --img "$TM/host.img" --tree "$TM/tree" --fsck "$FS" --dump "$DUMP" \
     --expect-owner 0:0 >/dev/null 2>&1; then
  bad "M3: weryfikator przepuscil obraz z uid $b mimo --expect-owner 0:0"
else
  ok "M3: --expect-owner 0:0 odrzuca obraz dziedziczacy uid hosta"
fi
t "M4: --expect-owner akceptuje obraz znormalizowany" 0 \
  bash "$HERE/verify_image.sh" --img "$TM/root.img" --tree "$TM/tree" --fsck "$FS" --dump "$DUMP" --expect-owner 0:0

# ---------------------------------------------------------------- N: sumy w dokumentach
# Kazda przebudowa wydania zmienia sha256 plikow, a README i docs/cyguja te sumy recznie.
# Ta kontrola pilnuje, ze ZADEN przytoczony prefiks nie jest duchem: musi byc prefiksem
# ktorejs pozycji w SHA256SUMS.txt ktoregos z dwoch wydano. (Bez tego trzy razy zostawialem
# w README 'stare' sumy po zmianie passwd/group i po korekcie DAC.)
echo "== N/6  dokumentacja cytuje sumy, ktore istnieja"
if python3 - "$ROOT" <<'PYN'
import glob,os,re,sys
root=sys.argv[1]
sums={}
for d in glob.glob(os.path.join(root,'dist/release/*')):
    p=os.path.join(d,'SHA256SUMS.txt')
    if os.path.isfile(p):
        sums[d]={l.split()[0] for l in open(p,encoding='utf-8') if len(l.split())==2}
ok=True
total_seen=0
for d,known in sums.items():
    rd=os.path.join(d,'README.md')
    if not os.path.isfile(rd): continue
    txt=open(rd,encoding='utf-8').read()
    # prefiks 8+ hex '…' albo w tabeli, plus wiersze 'sha256sum ... # <hex>'
    # Prefiksy liczymy TYLKO z linii, ktora mowi o pliku wydania. Bez tego kontrola
    # poslubi 'cdbb7717…', czyli sha1 KLUCZA AVB (avbtool info_image), za sume obrazu
    # i zglosi ducha, ktorego nie ma (2026-09-23, pierwsza wersja N).
    WANT=re.compile(r'product|system|vbmeta|flash-all|rollback|release-manifest|build-info')
    # 'ROZMIARY-KONTRAKT' to linia z ROZMIARAMI plikow (product=75198464 ...). Sama w sobie jest
    # poprawnym ciagiem hex (150560768 to osiem-cyfrowy 'prefiks sumy'!), wiec Nbralaby ja jako
    # duke sume i FAILowala. Za te linie odpowiada sekcja Q — kontrola rozmiarow, nie sum.
    SKIP=re.compile(r'sha1|klucz|key|cdbb7717|ROZMIARY-KONTRAKT', re.I)
    for line in txt.split('\n'):
        if not WANT.search(line) or SKIP.search(line): continue
        for pref in re.findall(r'[`#\s*]?([0-9a-f]{8,64})\u2026?', line):
            total_seen += 1
            if not any(h.startswith(pref) for k in sums.values() for h in k):
                print(f"  {os.path.relpath(rd,root)}: suma {pref}… NIE wystepuje w zadnym SHA256SUMS.txt ({line.strip()[:70]})")
                ok=False
# Zakres: TYLKO README wydania. 'docs/*.md' celowo POZA tym - dokumentacja modulu RRO
# cytuje sumy .apk i .zip, ktorych z definicji nie ma w SHA256SUMS.txt partycji (pierwsza
# wersja kontrolki N wywalila 'duchy' na docs/02:c9009d01…/62b688a8… i to kontrolka
# byla zla, nie dokumenty: invariant 'suma w README wydania' nie dotyczy modutu).
# Chcialbym 'kazda suma w kazdym dokumencie' - to wymaga indeksu artifactow, ktorego nie mam,
# wole wiec waski, ale dzialajacy test niz szeroki, ktory trzeba wylaczac.
if total_seen == 0:
    # TO jest najwazniejsza linia tej kontrolki. Bez niej 'PASS' znaczyloby 'nic nie
    # przeanalizowalem' - i tak wlasnie sie stalo: regex dopuszczal 8-16 znakow hex,
    # a README cytuje 20, wiec zero linii sie zalapalo i test byl zielony przy
    # nieaktualnych sumach (2026-09-23). Kontrola musi mowic, ile razy cos zobaczyla.
    print("  BRACK: zadna suma nie zostala przeanalizowana - kontrola jest martwa, nie zielona")
    ok=False
else:
    print(f"  (przeanalizowane sumy w dokumentach wydania: {total_seen})")
sys.exit(0 if ok else 1)
PYN
then ok "dokumenty cytuja istniejace sumy"
else bad "dokumentacja cytuje sume, ktorej nie ma w SHA256SUMS.txt"; fi

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

# --------------------------------------------------------------- P: device_probe
echo "== P      device_probe.sh: werdykt PRZED flashem (atrapa fastboot/adb)"
# Atrapa uderza w punkt, ktory sam sie nie widzi: 'getvar X' to DRUGI argument, a
# odpowiedz fastboota leci na STDERR w formie 'klucz: wartosc' plus linie OKAY. Kazde
# uproszczenie ktore tu wczesniej zrobilem (odpowiedz na stdout; zapytanie
# 'partition-size:systema' bez podkreślenia; parser 'cokolwiek przed dwukropkiem')
# dawalo zielony werdykt przy zerowej liczbie odczytanych parametrow. Dlatego test
# liczy scenariusze i pilnuje, by NO-GO bylo UZASADNIONE liczba, nie tylko kodem.
PROBE=$ROOT/tools/device_probe.sh
if [ ! -f "$PROBE" ]; then
  bad "brak tools/device_probe.sh"
else
  PP=$WORK/probe; mkdir -p $PP/fb $PP/adb $PP/rel
  cat > $PP/fb/fastboot <<'SHF'
#!/usr/bin/env bash
k=${2:-}
o() { printf '%s\n' "$1" >&2; }
case $k in
  devices) exit 0;;
  product) o "product: misty3g";;
  current-slot) o "current-slot: a";;
  is-userspace) o "is-userspace: ${FB_USR:-yes}";;
  partition-size:product_a) o "partition-size:product_a: ${FB_SIZE_PRODUCT_A:-0x4c000000}";;
  partition-size:product_b) o "partition-size:product_b: ${FB_SIZE_PRODUCT_B:-0x4c000000}";;
  partition-size:system_a) o "partition-size:system_a: ${FB_SIZE_SYSTEM_A:-0x3d000000}";;
  partition-size:system_b) o "partition-size:system_b: ${FB_SIZE_SYSTEM_B:-0x3d000000}";;
  *) o "OKAY [  0.001s]"; o "finished. total time: 0.001s";;
esac
SHF
  cat > $PP/adb/adb <<'SHA'
#!/usr/bin/env bash
[ "${FAKE_ADB_DOWN:-0}" = 1 ] && exit 1
{ [ "${FAKE_EROFS:-1}" = 1 ] && echo "CONFIG_EROFS_FS=y"
  [ "${FAKE_LZ4:-1}" = 1 ] && echo "CONFIG_EROFS_FS_LZ4=y"
  echo "Enforcing"; } 2>/dev/null
SHA
  chmod +x $PP/fb/fastboot $PP/adb/adb
  printf 'product_hyperos4_p11g2.img\t77619200\tx\tproduct_a\nsystem_hyperos4_p11g2.img\t967503872\tx\tsystem_a\n' \
    > $PP/rel/release-manifest.tsv
  pj() { # pj <nazwa> <oczekiwane rc> [ZMIENNE=SRODOWISKA...]
    local name=$1 want=$2; shift 2; local rc=0
    env FASTBOOT=$PP/fb/fastboot ADB=$PP/adb/adb "$@" \
      bash "$PROBE" --release $PP/rel --assume-booted > $PP/log 2>&1 || rc=$?
    seen=$((seen+1))
    if [ "$rc" = "$want" ]; then ok "$name (rc=$rc)"; else
      bad "$name: rc=$rc zamiast $want; wypis: $(grep -E '^ +\[(NE|UW)' $PP/log | head -2 | tr '\n' ' ')"
    fi
  }
  seen=0
  pj "urzadzenie zgodne -> GO"                                   0
  pj "brak CONFIG_EROFS_FS_LZ4 -> NO-GO"                         2 FAKE_LZ4=0
  pj "brak EROFS w kernelu (w ogole) -> NO-GO"                   2 FAKE_EROFS=0
  pj "slot system_a mniejszy niz obraz -> NO-GO"                 2 FB_SIZE_SYSTEM_A=0x10000000
  pj "slot rowny obrazowi co do bajta -> GO (granica '<')"       0 FB_SIZE_SYSTEM_A=$(printf '0x%x' 967503872)
  pj "slot o bajt mniejszy -> NO-GO"                             2 FB_SIZE_SYSTEM_A=$(printf '0x%x' 967503871)
  pj "bootloader zamiast fastbootd -> NO-GO"                     2 FB_USR=no
  pj "adb nie odpowiada -> GO z zastrzezeniem (nie klamstwo)"    0 FAKE_ADB_DOWN=1
  if [ $seen -ge 8 ]; then ok "przeanalizowanych scenariuszy urzadzenia: $seen"; else
    bad "tylko $seen/8 scenariuszy przebieglo - petla padla w polowie"
  fi
  # NO-GO musi mowic, DLACZEGO i CO Z ROBI (nie byc samotnym kodem wyjścia):
  env FASTBOOT=$PP/fb/fastboot ADB=$PP/adb/adb FAKE_LZ4=0 \
    bash "$PROBE" --release $PP/rel --assume-booted > $PP/log 2>&1
  if grep -q 'EROFS_FS_LZ4' $PP/log && grep -q 'compress none' $PP/log; then
    ok "odmowa bez lz4 wskazuje rozwiazanie (--compress none)"
  else bad "odmowa bez lz4 nie podaje zadnego wyjscia"; fi
  env FASTBOOT=$PP/fb/fastboot ADB=$PP/adb/adb FB_SIZE_SYSTEM_A=0x10000000 \
    bash "$PROBE" --release $PP/rel --assume-booted > $PP/log 2>&1
  if grep '\[NE \]' $PP/log | grep -q 'system_a' && grep '\[NE \]' $PP/log | grep -q '268435456'; then
    ok "odmowa rozmiaru cytuje slot i liczbe bajtow"
  else bad "odmowa rozmiaru nie pokazuje liczb (samo 'NO-GO')"; fi
fi

# --------------------------------------------------- Q: kontrakt rozmirow w README
echo "== Q      rozmiary w dokumentach wydania musza zgadzac sie z plikami (kontrakt)"
# Sekcja N pilnuje, ze dokumenty cytują ISTNIEJACE sumy. To za malo: 23 IX 2026 automat
# odswiezajacy dokumentacje zmienil sumy, a ROZMIARY zostawil sprzed przebudowy — i zadna
# kontrola nie krzyknela, bo liczba '967 503 872' byla poprawna w dniu, w ktory ja wpisano.
# Leczenie: blok '<!-- ROZMIARY-KONTRAKT nazwa=bajty ... -->' w README, liczony przez
# make_release'i, plus drugi czlony: ta sama liczba musi wystepowac w PROZE ktoregos README
# (inaczej blok jest swiezy, a akapit klamie — dokladnie klasa bledu, ktora zrobilem).
if python3 - "$ROOT" <<'PYQ'
import os,re,sys
root=sys.argv[1]; rel=[d for d in ('dist/release/HyperOS4_P11Gen2','dist/release/HyperOS4_P11Gen2-full')]
seen=0; bad=[]
texts={}; sizes={}; d7seen=0
for d in rel:
    dd=os.path.join(root,d)
    if not os.path.isdir(dd): bad.append(f"brak katalogu {d}"); continue
    for f in os.listdir(dd):
        if f.endswith('.img'): sizes[(d,f)]=os.path.getsize(os.path.join(dd,f))
    rp=os.path.join(dd,'README.md')
    if not os.path.isfile(rp): bad.append(f"brak {d}/README.md"); continue
    texts[d]=open(rp,encoding='utf-8').read()
for d,txt in texts.items():
    m=re.search(r'<!--\s*ROZMIARY-KONTRAKT([^\n]*)-->', txt)
    if not m:
        bad.append(f"{d}/README.md: brak bloku ROZMIARY-KONTRAKT (make_release go nie wstrzyknal?)"); continue
    for name,val in re.findall(r'([\w.]+\.img)=(\d+)', m.group(1)):
        seen+=1
        real=sizes.get((d,name))
        if real is None: bad.append(f"{d}: {name} z kontraktu nie istnieje w katalogu"); continue
        if real!=int(val): bad.append(f"{d}: {name} kontrakt mowi {val} B, plik ma {real} B")
        pretty=f"{int(val):,}".replace(',',' ')
        # TA SAM proza, nie 'ktorakolwiek': pierwszy wersji pozwolila, by -full README
        # ratowal lekki (ten przywoluje jego rozmiar przy porownaniu wariantow) i test
        # negatywny 'sklam proze w lekkim' przeszedl na zielono. Kontrola, ktora tak
        # wybacza, nie istnieje (23 IX 2026).
        prose=re.sub(r'<!--.*?-->','',txt,flags=re.S)
        if pretty not in prose:
            bad.append(f"{d}: {name} = {val} B jest w kontrakcie, ale nie ma tej liczby w PROZIE"
                       f" tego README — akapity zostaly z poprzednia liczba (blok swiezy, tekst klamie)")
    # ten sam rozmiar i ta sama suma musza byc w docs/07 (tabelka 'stan wydania') - tam blok
    # README nie siega, a to wlasnie ten dokument czyta ktos, kto liczy, czy sie miesci.
    # docs/07: tabelka 'stan wydania' — WIERSZAMI, nie 'czy gdziekolwiek w pliku'. Rozroznienie
    # po 'gdziekolwiek' udowodnilo sie jako bezwartosciowe: podmienilem sume producta w wierszu
    # na DEADBEEF, a kontrola byla zielona, bo ten sam prefiks zostal w akapicie ponizej (23 IX
    # 2026). Tolerancja = 'wiersz, ktorego nie umiem sklasyfikowac, pomijam', ale liczbe
    # przejranych wierszy asertuje ponizej — zeby 'puste przejscie' nie udawalo PASS-a.
    d7=os.path.join(root,'docs/07-jak-weryfikowac.md')
    if os.path.isfile(d7) and 'rows_done' not in globals():
        globals()['rows_done']=0
        for line in open(d7,encoding='utf-8'):
            if not line.lstrip().startswith('|') or '---' in line: continue
            low=line.lower()
            art=None
            for key,f in [('system','system_hyperos4_p11g2.img'),('vbmeta','vbmeta_hyperos4_p11g2.img'),('product','product_hyperos4_p11g2.img')]:
                if key in low: art=f; break
            if art is None: continue
            want_dir='-full' if 'full' in low else None
            cells=[c.strip() for c in line.strip().strip('|').split('|')]
            if len(cells)<3: continue
            nums=[c for c in cells if re.fullmatch(r'[0-9][0-9 ]{3,15}[0-9]', c)]
            shas=[c for c in cells if re.search(r'[0-9a-f]{8,64}', c)]
            if not nums or not shas: continue
            rows_done+=1
            size=int(nums[0].replace(' ',''))
            pref=re.search(r'[0-9a-f]{8,64}', shas[0]).group(0)
            dirs=[want_dir] if want_dir else [None,'-full']
            ok=False
            for suffix in dirs:
                dd=os.path.join(root,'dist/release/HyperOS4_P11Gen2'+(suffix or ''))
                fp=os.path.join(dd,art)
                if not os.path.isfile(fp): continue
                if os.path.getsize(fp)!=size: continue
                sl=[l for l in open(os.path.join(dd,'SHA256SUMS.txt'),encoding='utf-8') if art in l]
                if sl and sl[0].split()[0].startswith(pref): ok=True; break
            if not ok:
                msg=f"docs/07: wiersz '{cells[0]}' obiecuje {size} B + {pref[:12]}… — zaden katalog wydania nie ma takiego pliku z taka para"
                if msg not in bad: bad.append(msg)
        if rows_done<4: bad.append(f"docs/07: przejrzalem tylko {rows_done} wierszy tabelki (oczekuje >=4) — kontrola sie nie wykonala")
    if os.path.isfile(d7):
        t7=open(d7,encoding='utf-8').read(); d7seen+=1
        for name,val in re.findall(r'([\w.]+\.img)=(\d+)', m.group(1)):
            pretty=f"{int(val):,}".replace(',',' ')          # '920 047 616' — jak w tabelce
            msg=f"docs/07 nie ma rozmiaru {name} = {pretty} B (przedawniona tabelka)"
            if pretty not in t7 and msg not in bad:
                bad.append(msg)
            sl=[l for l in open(os.path.join(dd,'SHA256SUMS.txt'),encoding='utf-8') if name in l]
            if sl:
                full=sl[0].split()[0]
                # dokument moze skrocic sume dowolnie (8..64); sprawdzam, ktoryzkolwiek prefiks
                # tej DLUZOSCI wystepuje - sztywny wymog '16 albo 20' wywalilby FAIL na
                # poprawnym '9cf2e7e4…' w tabeli vbmeta (23 IX 2026, wlasnie tak sie stalo)
                msg2=f"docs/07 nie cytuje zadnego prefiksu sumy {name} (np. {full[:16]}…)"
                if not any(full[:L] in t7 for L in range(8, len(full)+1)) and msg2 not in bad:
                    bad.append(msg2)
if d7seen<1: bad.append("docs/07 nie zostalo przejrzone (brak pliku lub brak blokow) - kontrola nie zadzialala")
if bad: print("\n".join("  "+b for b in bad)); sys.exit(1)
print(f"  przeanalizowane pozycje kontraktu: {seen}")
PYQ
then ok "rozmiary w README = rozmiary plikow (kontrakt Q)"; else bad "kontrakt rozmirow nie przechodzi"; fi

echo; echo "=== podsumowanie: $pass PASS, $fail FAIL ==="
[ $fail -eq 0 ] || echo "UWAGA: ktorys test padl — nie wydawaj zmiany w tools/, ktora to wywolala."
exit $([ $fail -eq 0 ] && echo 0 || echo 1)
