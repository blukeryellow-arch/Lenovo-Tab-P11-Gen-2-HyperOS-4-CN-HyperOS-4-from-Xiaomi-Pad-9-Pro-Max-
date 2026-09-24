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
# PADDLE = lista FAIL-i w pliku, nie tylko w strumieniu. Powod jest moj: 24 IX odpalilem
# suite jako '... | tail -3', zobaczylem '53 PASS / 1 FAIL' i commitnalem, a nazwy tej
# kontroli nigdy nie widzialem - bo byla dwa ekrany wyzej, wycieta przez mnie samego.
# Licznik nie wystarczy: podsumowanie musi samo wymusic, co padlo.
PADDLE=$WORK/PADDLE.txt; : > "$PADDLE"
trap '[ $KEEP -eq 1 ] || rm -rf "$WORK"' EXIT
MK="$EROFS_DIR/mkfs.erofs"; FS="$EROFS_DIR/fsck.erofs"; DUMP="$EROFS_DIR/dump.erofs"
pass=0; fail=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fail=$((fail+1)); printf '%s\n' "$*" >> "$PADDLE"; }
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
# --- resize super (RS1-RS3): polityka domyslna + swiadoma zgoda ------------------
# 'nawet na request' zostaje prawda dla sciezki domyslnej; RS2 sprawdza, ze sama prosba
# bez frazy zgody nie dotyka urzadzenia, a RS3 ze pelna zgoda robi dokladnie delete
# product_a/b + resize system_a/b i NIE flashuje product (docs/06 §6.34).
runfb "RS1: domyslnie zero resize (polityka 'nawet na request' zostaje)" 0 6 $sz_v $sz_pr $sz_sy
if grep -qE 'delete-logical-partition|resize-logical-partition' "$WORK/fb.log"; then
  bad "RS1: w logu atrapy jest resize, ktory nikt nie zamowil"
else ok "RS1: log bez delete/resize przy braku flag"; fi
runfb "RS2: RESIZE_SUPER=1 bez I_ACCEPT_DATA_LOSS -> odmowa, zero flashow" 1 0 $sz_v $sz_pr $sz_sy RESIZE_SUPER=1
if grep -qE 'delete-logical-partition|resize-logical-partition' "$WORK/fb.log"; then
  bad "RS2: odmowa, a atrapa i tak dostala polecenia resize"
else ok "RS2: odmowa nie dotknela urzadzenia"; fi
runfb "RS3: resize z pelna zgoda -> 4 flashy (bez product)" 0 4 $sz_v $sz_pr $sz_sy RESIZE_SUPER=1 I_ACCEPT_DATA_LOSS=yes
if grep -q 'delete-logical-partition product_a' "$WORK/fb.log" && grep -q 'delete-logical-partition product_b' "$WORK/fb.log" \
   && grep -q 'resize-logical-partition system_a' "$WORK/fb.log" && grep -q 'resize-logical-partition system_b' "$WORK/fb.log" \
   && ! grep -q 'flash product' "$WORK/fb.log"; then
  ok "RS3: kolejnosc delete product_a/b + resize system_a/b, product nie flashowany"
else bad "RS3: zla sekwencja resize (patrz $WORK/fb.log)"; fi
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
      # Drzewo ZALEZY OD WARIANTU takze dla system: -full to build 23 IX z drzewa, ktore
      # MIalo trzy macierze runnera (donor), a lekki jest z drzewa po ich usunieciu + jedna
      # wygenerowana. Porownywanie obu z jednego SYSTREE pokazywaloby w -full trzy macierze
      # jako 'DODATKOWE' - usterke testu, nie wydania (dokladnie klasa z 2026-09-23).
      # Dla -full podaj SYSTREE_FULL=<drzewo z macierzami runnera>.
      case "$b" in
        *-full) pt=${PRODTREE_FULL:-/tmp/tree-full}
                st=${SYSTREE_FULL:-${SYSTREE:-/tmp/sys-tree2/system_tree}};;
        *)      pt=${PRODTREE:-/tmp/tree-product}
                st=${SYSTREE:-/tmp/sys-tree2/system_tree};;
      esac
      case $img in
        product_hyperos4_p11g2.img) tree=$pt;;
        *)                          tree=$st;;
      esac
      if ! [ -d "$tree" ]; then note "$b/$img: brak drzewa $tree - pomijam (nie mam czego porownywac)"; continue; fi
      if [ "$img" = system_hyperos4_p11g2.img ]; then
        # Jezeli build-info mowi, ze builder DOLOZYL macierz (sciezka --vintf-level), to tego
        # pliku nie ma w drzewie uzytkownika - zostal z niego sprzatnety po weryfikacji. Bez
        # tego wykluczenia 'drzewo vs obraz' tlukloby na pliku, ktorego istnienie jest zamierzone
        # (24 IX, pierwszy '--real' na odzyskanych drzewach). Swiadomie slabsze: to samo
        # wykluczenie zaslepia rowniez macierze donorowe, wiec ich zgodnosci TU NIE dowodze -
        # dowodzi ich builder w trakcie budowy (wtedy plik JEST w drzewie) oraz S2 na obrazie.
        VEX=''
        grep -q 'vintf_macierz.*WYGENEROWANY' "$d/build-info.txt" 2>/dev/null && VEX='compatibility_matrix\.[0-9]+\.xml$'
        if [ -n "$VEX" ]; then
          t "$b/$img weryfikacja 1:1 (komentarze + dolozona macierz poza drzewem)" 0 bash "$HERE/verify_image.sh" --img "$d/$img" --tree "$tree" \
              --fsck "$FS" --exclude '\.komentarz\.txt$' --exclude "$VEX"
          note "$b/$img: macierz dolozona poza drzewem - donorowych etc/vintf TU nie porownuje"
        else
        t "$b/$img weryfikacja 1:1 (z wykluczeniami)" 0 bash "$HERE/verify_image.sh" --img "$d/$img" --tree "$tree" \
            --fsck "$FS" --exclude '\.komentarz\.txt$'
        fi
      else
        t "$b/$img weryfikacja 1:1" 0 bash "$HERE/verify_image.sh" --img "$d/$img" --tree "$tree" --fsck "$FS"
      fi
    done
    # Sumy kontrolne: sprawdzam TE pliki, ktore sa w katalogu. Dwa obrazy >100 MB nie moga lezec
    # w checkoutcie (limit GitHuba), a naiwne 'sha256sum -c' tluklo je jako blad - padal wiec
    # test, nie wydanie (24 IX). Nieobecnosc tlumaczona jest WYLACZNIE rozmiarem z kontraktu;
    # plik ponizej limitu, ktorego nie ma = wydanie niekompletne -> FAIL.
    if python3 - "$d" <<'PYS'
import os, re, subprocess, sys
d = sys.argv[1]
lim = 100 * 1024 * 1024
readme = open(os.path.join(d, 'README.md'), encoding='utf-8').read()
blk = re.search(r'<!--\s*ROZMIARY-KONTRAKT([^>]*)-->', readme)
roz = dict((m.group(1), int(m.group(2))) for m in re.finditer(r'([\w.-]+)=(\d+)', blk.group(1))) if blk else {}
zle = []; spraw = 0; pomin = []
for ln in open(os.path.join(d, 'SHA256SUMS.txt'), encoding='utf-8'):
    ln = ln.rstrip('\n')
    if not ln.strip():
        continue
    h, _, name = ln.partition('  '); name = name.strip()
    if not os.path.isfile(os.path.join(d, name)):
        pomin.append(name)
        if name in roz and roz[name] <= lim:
            zle.append(f"{name}: nieobecny, a kontrakt mowi {roz[name]} B (miesci sie w gicie)")
        continue
    r = subprocess.run(['sha256sum', '-c', '--status'], cwd=d, input=f'{h}  {name}\n',
                       capture_output=True, text=True)
    spraw += 1
    if r.returncode != 0:
        zle.append(f"{name}: suma NIE zgadza sie z SHA256SUMS.txt")
print(f"  sumy sprawdzone: {spraw}; nieobecne (powyzej limitu GitHuba): {len(pomin)}"
      + (f" [{', '.join(pomin)}]" if pomin else ""))
if not spraw:
    zle.append("zadnego pliku nie sprawdzono - kontrola sum jest martwa, nie zielona")
if zle:
    print('\n'.join('  ' + z for z in zle)); sys.exit(1)
sys.exit(0)
PYS
    then ok "$b: sumy zgadzaja sie dla wszystkich obecnych plikow"
    else bad "$b: SHA256SUMS.txt nie potwierdza sie na plikach"; fi
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
texts={}; sizes={}; d7seen=0; rows_done=0; rows_absent=0; absent=[]
for d in rel:
    dd=os.path.join(root,d)
    if not os.path.isdir(dd): bad.append(f"brak katalogu {d}"); continue
    for f in os.listdir(dd):
        # kontrakt obejmuje WSZYSTKO w katalogu poza dokumentacja, logami i samym plikiem sum
        # (SHA256SUMS.txt liczy sie PO bloku, wiec jego rozmiar bylby samoodwolaniem)
        if f.endswith(('.md','.log')) or f=='SHA256SUMS.txt': continue
        sizes[(d,f)]=os.path.getsize(os.path.join(dd,f))
    rp=os.path.join(dd,'README.md')
    if not os.path.isfile(rp): bad.append(f"brak {d}/README.md"); continue
    texts[d]=open(rp,encoding='utf-8').read()
for d,txt in texts.items():
    m=re.search(r'<!--\s*ROZMIARY-KONTRAKT([^\n]*)-->', txt)
    if not m:
        bad.append(f"{d}/README.md: brak bloku ROZMIARY-KONTRAKT (make_release go nie wstrzyknal?)"); continue
    for name,val in re.findall(r'([\w.-]+\.(?:img|sh|tsv|txt))=(\d+)', m.group(1)):
        seen+=1
        real=sizes.get((d,name))
        if real is None:
            # GitHub nie pomiesci pliku >100 MB, wiec na swiezym checkoutcie CI 'system.img' nie ma.
            # To NIE moze byc FAIL (bylo nim przez dwie przebudowy i CI je polknelo brakiem pipefail),
            # ale nie moze byc tez ciche - raportuje sie ile ich bylo i tylko powyzej limitu.
            if int(val)>100*1024*1024: absent.append(f"{d}/{name} ({val} B - ponad limit GitHuba)")
            else: bad.append(f"{d}: {name} z kontraktu nie istnieje w katalogu (a miesci sie w gicie)")
            continue
        if real!=int(val): bad.append(f"{d}: {name} kontrakt mowi {val} B, plik ma {real} B")
        pretty=f"{int(val):,}".replace(',',' ')
        # TA SAM proza, nie 'ktorakolwiek': pierwszy wersji pozwolila, by -full README
        # ratowal lekki (ten przywoluje jego rozmiar przy porownaniu wariantow) i test
        # negatywny 'sklam proze w lekkim' przeszedl na zielono. Kontrola, ktora tak
        # wybacza, nie istnieje (23 IX 2026).
        prose=re.sub(r'<!--.*?-->','',txt,flags=re.S)
        # W prozie ma byc nazwa I liczba (granice cyfr: "591" w numerze commita aaa5919 to
        # nie liczba 591). Nie tylko zgodnosc, ale OBECNOSC - bo obietnica z bloku kontraktu
        # mowi 'znika z prozy -> FAIL', a pierwsza wersja lapala tylko klamstwo, nie wyciecie
        # calego wiersza (24 IX 2026).
        if not (name in prose and re.search(r"(?<!\d)"+re.escape(pretty)+r"(?!\d)", prose)):
            bad.append(f"{d}: {name} = {val} B musi byc w prozie tego README z liczba "
                       f"{pretty} - brak nazwy albo liczby (wiersz wyciety albo tekst z "
                       f"poprzednia liczba)")
    # ten sam rozmiar i ta sama suma musza byc w docs/07 (tabelka 'stan wydania') - tam blok
    # README nie siega, a to wlasnie ten dokument czyta ktos, kto liczy, czy sie miesci.
    # docs/07: tabelka 'stan wydania' — WIERSZAMI, nie 'czy gdziekolwiek w pliku'. Rozroznienie
    # po 'gdziekolwiek' udowodnilo sie jako bezwartosciowe: podmienilem sume producta w wierszu
    # na DEADBEEF, a kontrola byla zielona, bo ten sam prefiks zostal w akapicie ponizej (23 IX
    # 2026). Tolerancja = 'wiersz, ktorego nie umiem sklasyfikowac, pomijam', ale liczbe
    # przejranych wierszy asertuje ponizej — zeby 'puste przejscie' nie udawalo PASS-a.
    d7=os.path.join(root,'docs/07-jak-weryfikowac.md')
    if os.path.isfile(d7) and rows_done==0:      # skan raz na przebieg (docs/07 jest jeden)
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
            ok=False; istnieje=False
            for suffix in dirs:
                dd=os.path.join(root,'dist/release/HyperOS4_P11Gen2'+(suffix or ''))
                fp=os.path.join(dd,art)
                if not os.path.isfile(fp): continue
                istnieje=True
                if os.path.getsize(fp)!=size: continue
                sl=[l for l in open(os.path.join(dd,'SHA256SUMS.txt'),encoding='utf-8') if art in l]
                if sl and sl[0].split()[0].startswith(pref): ok=True; break
            if not ok:
                # pliku nie ma NIGDZIE i jest wiekszy niz limit GitHuba -> na swiezym checkoutcie CI
                # nie moze byc ani obrazu, ani jego sumy do porownania. To nie dowod, ze dokument klamie,
                # wiec nie FAIL - ale musi byc POLICZONE, zeby 'zero zweryfikowanych wierszy' nie udalo sukcesu.
                if not istnieje and size>100*1024*1024: rows_absent+=1; continue
                msg=f"docs/07: wiersz '{cells[0]}' obiecuje {size} B + {pref[:12]}…"
                if not istnieje: msg+=" — pliku nie ma w zadnym katalogu wydania (miesci sie w gicie, wiec powinien)"
                else: msg+=" — plik jest, ale para rozmiar/suma sie nie zgadza"
                if msg not in bad: bad.append(msg)
        if rows_done<4: bad.append(f"docs/07: przejrzalem tylko {rows_done} wierszy tabelki (oczekuje >=4) — kontrola sie nie wykonala")
    if os.path.isfile(d7):
        t7=open(d7,encoding='utf-8').read(); d7seen+=1
        for name,val in re.findall(r'([\w.-]+\.(?:img|sh|tsv|txt))=(\d+)', m.group(1)):
            pretty=f"{int(val):,}".replace(',',' ')          # '920 047 616' — jak w tabelce
            if not name.endswith('.img'): continue     # docs/07 opisuje ladunek, nie metadane
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
# spojnosc tabel markdown — 23 IX 2026 moja podmiana rozmiarow w 'Sklad wydania' zwrocila
# piec wierszy z czterema kolumnami zamiast trzech ('| |'); markdown przesuwa wtedy kolumny i
# nikt by nie powiedzial 'dokument jest zly', tylko 'brzydko sie renderuje'
for d,txt in texts.items():
    L=txt.splitlines(); i=0
    while i<len(L):
        if L[i].lstrip().startswith('|') and i+1<len(L) and re.match(r'^\s*\|[\s:|-]+\|\s*$', L[i+1]):
            ncol=L[i].count('|'); j=i+2
            while j<len(L) and L[j].lstrip().startswith('|'):
                if L[j].count('|')!=ncol:
                    msg=f"{d}/README.md:{j+1}: wiersz tabeli ma {L[j].count('|')-1} kol., naglowek {ncol-1}"
                    if msg not in bad: bad.append(msg)
                j+=1
            i=j
        else: i+=1
# asercja 'ile przejrzalem' — te trzy linie zniknely raz przy rozbudowie Q (23 IX) i Q zostalo
# kontrola bez zadnego progu: zero pozycji dawaloby PASS. Nie powtarzac.
if seen<16: bad.append(f"przeanalizowano tylko {seen} pozycji kontraktu (dwa README x 8 plikow) - kontrola martwa")
if rows_done<4: bad.append(f"przejrzalem {rows_done} wierszy tabeli docs/07 (oczekuje >=4) - kontrola martwa")
if bad: print("\n".join("  "+b for b in bad)); sys.exit(1)
print(f"  przeanalizowane pozycje kontraktu: {seen}, z czego pominietych (za duze na GitHuba): {len(absent)}")
print(f"  wiersze docs/07: zweryfikowane {rows_done-rows_absent}, pominiete (obraz poza limitem GitHuba) {rows_absent}")
for a_ in absent: print("     absent-skip: "+a_)
PYQ
then ok "rozmiary w README = rozmiary plikow (kontrakt Q)"; else bad "kontrakt rozmirow nie przechodzi"; fi

echo "== R      pliki workflow: YAML parsowalny, zadnego 'run:' rozsypanego wcieceniem"
# 24 IX 2026: moja podmiana dwóch linii w build.yml zgubila wciecie, 'bash tools/...' wyladowalo
# w kolumnie 0, YAML uznal to za koniec bloku scalarowego i CALY workflow zostal odrzucony
# ('workflow file issue', zero jobow) - GitHub nie uruchomil nawet testow. Heurystyka ponizej
# łapie to lokalnie, bez czekania na czerwony bieg.
if python3 - "$ROOT" <<'PYR'
import os, re, sys

root = sys.argv[1]
wd = os.path.join(root, '.github', 'workflows')
bad = []
files = []
blocks = 0
if os.path.isdir(wd):
    files = [f for f in sorted(os.listdir(wd)) if f.endswith(('.yml', '.yaml'))]
if len(files) < 2:
    bad.append(f"w .github/workflows jest {len(files)} plik(ow) yaml, oczekuje >=2 - kontrola nie ma czego pilnowac")
try:
    import yaml
    have = True
except Exception:
    have = False
for fn in files:
    path = os.path.join(wd, fn)
    txt = open(path, encoding='utf-8').read()
    L = txt.split('\n')
    if have:
        try:
            d = yaml.safe_load(txt)
            if not isinstance(d, dict) or 'jobs' not in d:
                bad.append(f"{fn}: YAML czyta sie, ale nie ma klucza 'jobs:'")
            elif not d['jobs']:
                bad.append(f"{fn}: 'jobs:' puste")
        except Exception as e:
            bad.append(f"{fn}: BLAD parsowania YAML -> {str(e).splitlines()[0][:200]}")
    for i, l in enumerate(L):
        m = re.match(r'^(\s*)run:\s*[|>][-+]?\s*$', l)
        if not m:
            continue
        blocks += 1
        k = len(m.group(1))
        j = i + 1
        base = None
        while j < len(L):
            cur = L[j]
            if cur.strip() == '':
                j += 1
                continue
            ind = len(cur) - len(cur.lstrip(' '))
            if ind <= k:
                break
            if base is None:
                base = ind
            elif ind < base:
                bad.append(f"{fn}:{j+1}: wciecenie {ind} < {base} wewnatrz bloku 'run:' - YAML domknie blok w polowie")
            j += 1
        for j, cur in enumerate(L):
            if re.match(r'^(bash |rc=|if |fi$|done$|for |echo |set |exit |mkdir |sudo |\[ |export )', cur):
                msg=f"{fn}:{j+1}: polecenie powloki w kolumnie 0 ({cur[:48]}...)"
                if msg not in bad: bad.append(msg)
                break
if blocks < 8:
    bad.append(f"znalazlem {blocks} blokow 'run:', powinno byc >=8 - petla blokow nie zadzialala")
print(f"  pliki: {', '.join(files) if files else 'BRAK'}; bloki run: {blocks}; " +
      ("pyyaml: wlaczony" if have else "pyyaml: NIEDOSTEPNY (tylko heurystyka wciecen)"))
if bad:
    print("\n".join("  " + b for b in bad))
    sys.exit(1)
PYR
then ok "workflowy parsowalne, bloki run spojne (sekcja R)"; else bad "pliki workflow sa uszkodzone - patrz R"; fi

echo "== S      bramka VINTF w budowie: --vintf-level doklada plik do OBRAZU i sprzata z drzewa"
# Bez tej sekcji 'dokladamy macierz' pozostaloby zdaniem, ktoremu nikt nie ufa. 24 IX 2026 wyszlo,
# ze generator nadpisuje ATRYBUT level, a init czyta ELEMENT <level> - plik o nazwie
# compatibility_matrix.5.xml mial w srodku '<level>6</level>'. Taki blad przezywa rc=0 i 'plik
# istnieje'; zabija go dopiero porownanie z tym, co NAPRAWDZE lezy w rozpakowanym obrazie.
TS=$WORK/S; mkdir -p "$TS/tree/etc/vintf" "$TS/tree/product" "$TS/tree/vendor" "$TS/tree/system_ext" "$TS/tree/odm" "$TS/tree/fonts"
printf 'x\n' > "$TS/tree/fonts/a.ttf"
cat > "$TS/tree/etc/vintf/compatibility_matrix.202404.xml" <<'XMLS'
<compatibility-matrix version="7.0" type="framework">
  <level>6</level>
  <hal format="aidl" optional="false"><name>audio.core</name><version>2</version><max-level>7</max-level></hal>
  <hal format="aidl" optional="true"><name>thermal</name><version>2</version><max-level>8</max-level></hal>
  <hal format="aidl" optional="false"><name>gatekeeper</name><version>1</version><max-level>8</max-level></hal>
  <hal format="aidl" optional="false"><name>stylelater</name><min-level>7</min-level></hal>
</compatibility-matrix>
XMLS
t "S1  budowa z --vintf-level 5" 0 bash "$HERE/make_release.sh" --product-tree "$TS/tree" --system-tree "$TS/tree" --vintf-level 5 --erofs-dir "$EROFS_DIR" --allow-no-vbmeta --out "$TS/out"
mkdir -p "$TS/x"; timeout 300 "$FS" --extract="$TS/x" "$TS/out/system_hyperos4_p11g2.img" >/dev/null 2>&1
M5="$TS/x/etc/vintf/compatibility_matrix.5.xml"
if [ -f "$M5" ]; then
  ok "S2  w rozpakowanym system.img jest etc/vintf/compatibility_matrix.5.xml"
  # poziom MUSI byc zgodny w OBU formach: mlodszy libvintf (/system) czyta element <level>,
  # starszy (/vendor, A12) czyta atrybut level=. Ktos, kto sprawdzi tylko jedno, przeoczy polowe.
  if grep -q '<level>5</level>' "$M5" && grep -qE '<compatibility-matrix[^>]*level="5"' "$M5"; then
    ok "S3  plik deklaruje poziom 5 w elemencie I w atrybucie (nie odziedziczone po zrodle 6)"
  elif ! grep -q '<level>5</level>' "$M5"; then
    bad "S3  element <level> w dokladanym pliku nie rowna sie zadanemu poziomowi - to zasloni bramke init"
  else
    bad "S3  atrybut level= na <compatibility-matrix> nie mowi 5 - A12-owy libvintf patrzy wlasnie w niego"
  fi
  if grep -qE '<name>thermal</name>' "$M5" && grep -qE '<name>audio.core</name>' "$M5"; then ok "S4  HAL-e z max-level 7/8 zostaly (obnizamy poziom vendora, nie uslugi)"
  else bad "S4  wygenerowana macierz zgubila HAL-e, ktore powinny w niej zostac"; fi
  # i drugi koniec: gdyby generator byl po prostu 'cp', ten HAL by zostal - a nie powinien
  if grep -qE '<name>stylelater</name>' "$M5"; then bad "S4b generator NIE odcial HAL-a z min-level 7 (plik jest kopia zrodla, nie macierzy level 5)"
  else ok "S4b  HAL z min-level 7 odciety (ciałem faktycznie filtruje, nie kopiuje)"; fi
else bad "S2  w obrazie NIE MA dokladanej macierzy, a builder ją zapowiedzial w logu"; fi
if [ ! -e "$TS/tree/etc/vintf/compatibility_matrix.5.xml" ]; then ok "S5  drzewo wejsciowe posprzatane (plik tylko w obrazie)"
else bad "S5  builder zostawil wygenerowany plik w drzewie uzytkownika"; fi
if grep -q 'vintf_macierz.*WYGENEROWANY' "$TS/out/build-info.txt"; then ok "S6  build-info.txt opisuje dokladanie (stan da sie poznac po fakcie)"
else bad "S6  build-info.txt milczy o macierzy - kto to dostarczy, nie wiedzial, co bylo w srodku"; fi
t "S7  budowa BEZ --vintf-level" 0 bash "$HERE/make_release.sh" --product-tree "$TS/tree" --system-tree "$TS/tree" --erofs-dir "$EROFS_DIR" --allow-no-vbmeta --out "$TS/out2"
mkdir -p "$TS/x2"; timeout 300 "$FS" --extract="$TS/x2" "$TS/out2/system_hyperos4_p11g2.img" >/dev/null 2>&1
if [ ! -e "$TS/x2/etc/vintf/compatibility_matrix.5.xml" ]; then ok "S8  bez flagi nic nie dokladamy (brak domyslnej 'poprawki' cudzego obrazu)"
else bad "S8  dokladamy plik mimo braku flagi - build przestaje byc odtwarzalny z podanych argumentow"; fi
if grep -q 'vintf_macierz.*BRAK' "$TS/out2/build-info.txt"; then ok "S9  build-info nazywa to BRAKIEM bramki, nie 'pominietym'"
else bad "S9  build-info nie ostrzega o braku macierzy - ktos to wgra i dostanie bootloop bez wskazowki"; fi
# --- wariant miekki bramki (S13/S14) -------------------------------------------
# 24 IX wyszlo, ze '--optional-missing' dopisywal ELEMENT <optional>true</optional>, ktorego
# libvintf nie zna (on czyta ATRYBUT <hal optional="..."> - parse_xml.cpp:528, a nieznane dzieci
# <hal> sa ignorowane). Plik po takiej 'poprawce' wyglądał na zmiękczony i nie otwierał niczego.
# Dlatego te dwie kontrole czytaja plik wyciągnięty z rozpakowanego obrazu i porównują atrybuty.
mkdir -p "$TS/vvendor"
cat > "$TS/vvendor/manifest.xml" <<'XMLV'
<manifest version="1.0" type="device">
  <hal format="aidl">
    <name>audio.core</name>
    <version>2</version>
    <interface><name>IModule</name><instance>default</instance></interface>
  </hal>
</manifest>
XMLV
t "S13a budowa w wariancie miękkim NA SZEROKO" 0 bash "$HERE/make_release.sh" --product-tree "$TS/tree" --system-tree "$TS/tree" --vintf-level 5 --vintf-optional-missing --erofs-dir "$EROFS_DIR" --allow-no-vbmeta --out "$TS/out4"
mkdir -p "$TS/x4"; timeout 300 "$FS" --extract="$TS/x4" "$TS/out4/system_hyperos4_p11g2.img" >/dev/null 2>&1
if python3 - "$TS/x4/etc/vintf/compatibility_matrix.5.xml" <<'PYT'
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot(); h = r.findall('hal')
if len(h) < 2:
    print(f"    w pliku tylko {len(h)} HAL-i - fixture sie rozjechal, kontrola nie ma sensu"); sys.exit(1)
brak = [x.findtext('name') for x in h if x.get('optional') != 'true']
dzieci = [x.findtext('name') for x in h if x.find('optional') is not None]
if brak or dzieci:
    print(f"    optional='true' brak dla: {brak}; child-element (ignorowany przez init): {dzieci}")
    sys.exit(1)
print(f"    wszystkie {len(h)} pozycji: atrybut optional=\"true\", zadnego dziecka <optional>")
PYT
then ok "S13 miękki wariant realnie zmiękcza plik w OBRAZIE (atrybut, nie element)"
else bad "S13 'optional' nie jest atrybutem w rozpakowanym obrazie - init tego nie zobaczy i bramka zostaje zamknięta"; fi
if grep -q 'wariant: miękki NA SZEROKO' "$TS/out4/build-info.txt"; then ok "S13b build-info nazywa wariant po imieniu (NA SZEROKO)"
else bad "S13b build-info nie mówi, że optional oznaczono bez danych z urzadzenia - ktoś to weźmie za stan faktyczny"; fi

t "S14a budowa miękka z manifestem vendora" 0 bash "$HERE/make_release.sh" --product-tree "$TS/tree" --system-tree "$TS/tree" --vintf-level 5 --vintf-optional-missing --vintf-vendor-manifest "$TS/vvendor" --erofs-dir "$EROFS_DIR" --allow-no-vbmeta --out "$TS/out5"
mkdir -p "$TS/x5"; timeout 300 "$FS" --extract="$TS/x5" "$TS/out5/system_hyperos4_p11g2.img" >/dev/null 2>&1
if python3 - "$TS/x5/etc/vintf/compatibility_matrix.5.xml" <<'PYV'
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
m = {(x.findtext('name') or '').strip(): (x.get('optional') or 'BRAK') for x in r.findall('hal')}
zle = []
# audio.core jest w manifescie vendora -> NIE wolno go zwalniac z wymagania
if m.get('audio.core') != 'false': zle.append(f"audio.core={m.get('audio.core')} (powinno zostać 'false')")
# gatekeepera vendor nie ma -> ma byc zwolniony
if m.get('gatekeeper') != 'true':  zle.append(f"gatekeeper={m.get('gatekeeper')} (powinno być 'true')")
if zle: print("    " + "; ".join(zle)); sys.exit(1)
print(f"    odczytane optional: {m}")
PYV
then ok "S14 z manifestem vendora zwalnia TYLKO brakujace pozycje (audio.core zostaje wymagany)"
else bad "S14 markowanie na podstawie manifestu vendora nie dziala - zmiękczanie bez potrzeby lub wymagania bez sensu"; fi
if grep -q 'podstawa: manifest vendora' "$TS/out5/build-info.txt"; then ok "S14b build-info podaje podstawę zmiękczenia (manifest vendora)"
else bad "S14b build-info nie mowi, na jakiej podstawie oznaczono optional"; fi
if [ ! -e "$TS/tree/etc/vintf/compatibility_matrix.5.xml" ]; then ok "S15 drzewo posprzątane również po dwóch miękkich wariantach"
else bad "S15 po mieszkich wariantach zostal plik w drzewie uzytkownika"; fi

cp "$M5" "$TS/tree/etc/vintf/compatibility_matrix.5.xml" 2>/dev/null
printf '<!-- znacznik: ten plik jest moj, nie buildera -->\n' >> "$TS/tree/etc/vintf/compatibility_matrix.5.xml"
SZP=$(sha256sum "$TS/tree/etc/vintf/compatibility_matrix.5.xml" | cut -c1-16)
t "S10 budowa z drzewem, ktore MA wlasna macierz" 0 bash "$HERE/make_release.sh" --product-tree "$TS/tree" --system-tree "$TS/tree" --vintf-level 5 --erofs-dir "$EROFS_DIR" --allow-no-vbmeta --out "$TS/out3"
SZO=$(sha256sum "$TS/tree/etc/vintf/compatibility_matrix.5.xml" | cut -c1-16)
if [ "$SZP" = "$SZO" ]; then ok "S11 istniejacy plik w drzewie nienaruszony (sha $SZP przed i po)"
else bad "S11 builder NADPISAL plik uzytkownika, mimo ze ten mial level"; fi
if grep -q 'vintf_macierz.*JEST w drzewie' "$TS/out3/build-info.txt"; then ok "S12 build-info mowi 'JEST w drzewie', nie 'WYGENEROWANY'"
else bad "S12 build-info opisuje stan, ktorego nie bylo"; fi

# --- format z prawdziwego donora (S16-S18) ------------------------------------
# 24 IX: dziewiec plikow FCM z drzewa donora nosi poziom WYLACZNIE w atrybucie
# (compatibility_matrix.202404.xml: <compatibility-matrix version="9.0" type="framework"
# level="202404">). Zrodlo <level>6</level> powyzej bylo moim fixturem, nie formatem AOSP -
# stad dwie kontrole ponizej, zeby fikcja nie wrocila jako 'dowod'.
mkdir -p "$TS/f2"
cat > "$TS/f2/compatibility_matrix.202404.xml" <<'XMLF'
<compatibility-matrix version="9.0" type="framework" level="202404">
  <hal format="aidl" optional="false"><name>audio.core</name><version>2</version><max-level>7</max-level></hal>
  <hal format="aidl" optional="false"><name>gatekeeper</name><version>1</version><max-level>8</max-level></hal>
</compatibility-matrix>
XMLF
t "S16 generator na zrodle w formacie donora (atrybut, bez elementu)" 0 python3 "$HERE/make_level_matrix.py" --from-dir "$TS/f2" --level 5 --out "$TS/f2/compatibility_matrix.5.xml"
if python3 - "$TS/f2/compatibility_matrix.5.xml" <<'PYF'
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
att = (r.get('level') or '').strip()
el = r.find('level')
if att != '5':
    print(f"    atrybut level={att!r}, a powinno '5'"); sys.exit(1)
if el is not None:
    print("    SKRYPT WYMYSLIL element <level>, ktorego zrodlo donora nie mialo - konstrukt spoza formatu")
    sys.exit(1)
print("    atrybut level='5', elementu nie wymyslono (zgodne z formatem donora)")
PYF
then ok "S16 generator lustrza format zrodla: atrybut tak, wymyslony element nie"
else bad "S16 generator dopisal element <level> przy zrodle bez elementu - to jest ten sam blad co z optional"; fi

SZ1=$(sha256sum "$TS/f2/compatibility_matrix.5.xml" | cut -d' ' -f1)
O2=$(python3 "$HERE/make_level_matrix.py" --from-dir "$TS/f2" --level 5 --out "$TS/f2/compatibility_matrix.5.xml" 2>&1)
SZ2=$(sha256sum "$TS/f2/compatibility_matrix.5.xml" | cut -d' ' -f1)
if echo "$O2" | grep -q 'pominietych plikow.*1'; then ok "S17 drugi przebieg rozpoznaje wlasny plik i go omija (brak kaskady jak 23 IX)"
else bad "S17 generator nie rozpoznal wlasnego wyjscia - przy petli 'for lv in 4 5 6' zrodlem staje sie plik z poprzedniego przebiegu"; fi
if [ "$SZ1" = "$SZ2" ]; then ok "S18 powtorzenie tego samego wyjscia daje te same bajty ($SZ1)"
else bad "S18 generator nie jest odtwarzalny: $SZ1 vs $SZ2"; fi


# -------------------------------------------------- T: twierdzenia README vs build-info
# Wymusila to zycie: README lekkiego wydania przez dwa dni obiekiwal „dobudowane macierze
# VINTF 4/5/6", a build-info.txt tego buildu nie mial nawet klucza `vintf_macierz` (obrazy
# powstaly przed aaa5919). Zdanie w dokumencie nie ma zadnej sily dowodowej, jezeli nic nie
# pila do pliku, ktro ten stan opisuje. Kontrolka jest dwukierunkowa: claim bez dowodu FAILuje
# i dowod bez claimu FAILuje (zeby nie zamienic klamstwa w milczenie).
echo "== T      README wydania nie moze obiecywac macierzy, ktorych build-info nie potwierdza"
TC=0; TF=0
for d in "$ROOT"/dist/release/HyperOS4_P11Gen2*; do
  [ -d "$d" ] || continue
  b=$(basename "$d"); TC=$((TC+1))
  rd="$d/README.md"; bi="$d/build-info.txt"
  [ -f "$rd" ] && [ -f "$bi" ] || { note "$b: brak README lub build-info - nic nie sprawdzam"; continue; }
  if python3 - "$rd" "$bi" "$b" <<'PYT'
import re, sys
rd, bi, b = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(rd, encoding='utf-8').read()
info = open(bi, encoding='utf-8').read()
m = re.search(r'^vintf_macierz[^\n]*$', info, re.M)
dowod = bool(m) and ('BRAK' not in m.group(0))
# claim = zdanie, ktore MOWI, ze macierz JEST w obrazie (a nie ze jej nie ma)
claim = False
for zd in re.split(r'(?<=[.!?])\s+', txt):
    if re.search(r'macierz|vintf', zd, re.I) and re.search(r'dobudowan|zawiera|trafi[łl]|wpi[ęe]t', zd, re.I) \
       and not re.search(r'nie (zawiera|ma)|bez |sprzed flagi|NIE zawiera'
                         r'|wcze[sś]niejsz|poprzedni|by[łl]o przepisane|nieaktualn|przesta[łl]', zd, re.I):
        claim = True; print(f"    claim: {zd.strip()[:96]}")
if claim and not dowod:
    print(f"  {b}: README twierdzi, ze macierz jest w obrazie, a build-info nie ma 'vintf_macierz' z dowodem")
    sys.exit(1)
if dowod and not claim:
    print(f"  {b}: build-info mowi, ze macierz byla dokladana, a README tego nie opisuje (milczenie = stary tekst?)")
    sys.exit(1)
print(f"  {b}: claim={claim} dowod={dowod} - zgodne")
sys.exit(0)
PYT
  then ok "$b: twierdzenia o VINTF zgodne z build-info"
  else bad "$b: README i build-info opisuja dwa rozne swiaty"; TF=$((TF+1)); fi
done
if [ "$TC" -eq 0 ]; then bad "zaden katalog wydania nie zostal przeanalizowany - kontrolka jest martwa"; TF=$((TF+1)); fi
[ "$TF" -eq 0 ] && ok "sekcja T: przeanalizowane katalogi: $TC"

echo; echo "=== podsumowanie: $pass PASS, $fail FAIL ==="
if [ -s "$PADDLE" ]; then
  echo "--- co padlo (te same linie, ktorych nie utnie zadne tail) ---"
  sed 's/^/  /' "$PADDLE"
fi
[ $fail -eq 0 ] || echo "UWAGA: ktorys test padl — nie wydawaj zmiany w tools/, ktora to wywolala."
exit $([ $fail -eq 0 ] && echo 0 || echo 1)
