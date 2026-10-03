#!/usr/bin/env bash
# flashowanie wydania HyperOS4->TB350FU. TYLKO odblokowany bootloader. Nazajeden.
# Uruchomione na 'atrapie fastboot' udajacej current-slot=b przechodzi sekwencje:
#   fetch vbmeta_a, fetch vbmeta_b, getvar is-userspace, flash <part>_<slot>, reboot
set -uo pipefail
cd "$(dirname "$0")"
command -v fastboot >/dev/null || { echo "brak fastboot w PATH"; exit 1; }
fb() { fastboot "$@"; }
DRY=${DRY:-0}
run() { if [ "$DRY" = 1 ]; then echo "DRY: fastboot $*"; else fastboot "$@"; fi; }

# --- resize super: domyslnie WYLACZONY i tak zostaje --------------------------------
# Powiekszanie super usuwa partycje i rusza /data - jest nieodwracalne, wiec domyslna
# polityka tego skryptu ('nawet na request') zostaje. Wlaczasz to tylko tak, ze swiadomie:
#     RESIZE_SUPER=1 I_ACCEPT_DATA_LOSS=yes ./flash-all.sh
# Wtedy leci dokladnie: delete-logical-partition product_a/b (tej samej sztuczki wymagaly
# GSI na tym sprzecie - patrz docs/05), resize-logical-partition system_a/b do rozmiaru
# obrazu + 64 MiB zapasu, i product NIE jest flashowany (partycji juz nie ma). Tracisz
# nakladki RRO z /product; fonty Xiaomi zostaja, bo sa w /system/fonts.
RESIZE_SUPER=${RESIZE_SUPER:-0}
SKIP_PRODUCT=0
IMG_VB=vbmeta_hyperos4_p11g2.img
IMG_PR=product_hyperos4_p11g2.img
IMG_SY=system_hyperos4_p11g2.img
[ -f "$IMG_VB" ] || { echo "brak $IMG_VB (zbuduj: tools/make_release.sh --avb ... --key ...)"; exit 1; }
[ -f "$IMG_PR" ] || { echo "brak $IMG_PR"; exit 1; }
if [ ! -f "$IMG_SY" ]; then
  echo "brak $IMG_SY - ten obraz ma ~1,38 GB i NIE lezy w gicie (limit 100 MB/blob)."
  echo "albo sciagnij z galezi transfer-spool (tools/pull_spool.sh all), albo odpal bieg"
  echo "CI z 'rom_build: 1' w drive-probe.request. Nie wgram partycji po omacku."
  exit 1
fi

echo "== 0. identyfikacja"
PROD=$(fb getvar product 2>&1 | tr -d $'\r' | sed -n 's/^product: *//p')
echo "  product=${PROD:-brak}"
case "$PROD" in *TB350FU*|*p11*|*j7*) :;; *) echo "  UWAGA: to nie TB350FU ('$PROD') - CTRL+C w ciagu 10 s"; sleep 10;; esac

echo "== 1. slot"
SLOT=$(fb getvar current-slot 2>&1 | tr -d $'\r' | sed -n 's/^current-slot: *//p')
SLOT=${SLOT:-a}; OTHER=$([ "$SLOT" = a ] && echo b || echo a)
echo "  current-slot=$SLOT (drugi: $OTHER)"

echo "== 2. kopie zapasowe vbmeta OBU slotow (to jest Twoj rollback AVB)"
for s in a b; do
  run fetch "vbmeta_$s" "vbmeta_stock_$s.img" 2>/dev/null \
    && echo "  zapisano vbmeta_stock_$s.img" \
    || echo "  fetch vbmeta_$s nie udany - rollback = obrazy Lenovo z Dysku (diagnostics/drive-inventory.tsv)"
done
if [ -f SHA256SUMS.txt ]; then
  echo "== 3. weryfikacja sum zanim cokolwiek wgre"
  if SUMS=$(sha256sum -c SHA256SUMS.txt 2>&1); then
    echo "  sumy OK ($(grep -c . SHA256SUMS.txt) pozycji)"
  else
    printf '%s\n' "$SUMS" | grep -E 'FAILED|WARNING' | head -8 | sed 's/^/    /'
    echo "  PRZERWANE. To albo brak pliku (zly katalog? nie skopiowano calego wydania),"
    echo "  albo obraz ma inne bajty niz w momencie budowy - nie wgram nie wiadomo czego."
    exit 1
  fi
fi

echo "== 4. tryb"
US=$(fb getvar is-userspace 2>&1 | tr -d $'\r' | sed -n 's/^is-userspace: *//p')
echo "  is-userspace=${US:-nieznany}"; [ "$US" = yes ] || { echo "  potrzebny fastbootd: adb reboot fastboot (albo fb reboot fastboot)"; exit 1; }

if [ "$RESIZE_SUPER" = 1 ]; then
  if [ "${I_ACCEPT_DATA_LOSS:-}" != yes ]; then
    echo "== 4b. ODMOWA: RESIZE_SUPER=1 bez I_ACCEPT_DATA_LOSS=yes"
    echo "  To usuwa product_a/b i powieksza system w super: dane z /data ida w piach,"
    echo "  bez odwrotu. Jesli naprawde chcesz: I_ACCEPT_DATA_LOSS=yes ./flash-all.sh"
    exit 1
  fi
  echo "== 4b. resize super (SWIADOMA ZGODA przyjeta; NIEODWRACALNE)"
  SYS=$(stat -Lc%s "$IMG_SY")
  # 4 MiB w gore (blok EROFS) + 64 MiB zapasu
  NEW=$(( ((SYS + 4194303) / 4194304) * 4194304 + 67108864 ))
  echo "  system.img $SYS B -> slot po resize $NEW B"
  run delete-logical-partition product_a
  run delete-logical-partition product_b
  run resize-logical-partition system_a "$NEW"
  run resize-logical-partition system_b "$NEW"
  SKIP_PRODUCT=1
  echo "  (product_a/b usuniety - w kroku 6 nie bedzie flashowany)"
fi

echo "== 5. czy obrazy mieszcza sie w partycjach"
# Rozmiar SLOTU logicznego zna tylko urzadzenie. W fabrycznej vbmeta Lenovo sa rozmiary
# ZRODLOWYCH obrazow (product 2 748 350 464 B, system_ext 744 968 192 B) - to NIE jest
# limit slotu w super, a ten build ma system 1 376 899 072 B, czyli wiecej niz source
# (937 791 488 B). stad ta bron: przerwac PRZED pierwszym flaszem, nie po trzecim.
FIT=1
for p in vbmeta product system; do
  case $p in
    vbmeta) img=$IMG_VB;;
    product) img=$IMG_PR;;
    system) img=$IMG_SY;;
  esac
  # -L (dereference): bez tego 'stat' na symlinku zwraca dlugosc sciezki, nie rozmiar
  # pliku - bramka widziala need=0 i przepuszczala nawet 1,4 GB na partycje 768 MB
  # (test B/D, 2026-09-23 20:0x). Wydobycie tego bylo wlasnie po to te atrapy.
  if [ "$p" = product ] && [ "$SKIP_PRODUCT" = 1 ]; then
    echo "  product: pomijam (partycje usuniete przez resize)"
    continue
  fi
  need=$(stat -Lc%s "$img" 2>/dev/null || echo 0)
  [ "$need" = 0 ] && { echo "  ${p}: brak obrazu, pomijam"; continue; }
  for s in a b; do
    raw=$(fb getvar partition-size:${p}_$s 2>&1 | tr -d $'\r' | sed -n 's/^partition-size\['"${p}_${s}"'\]: *//p' | sed 's/ .*//')
    if [ -z "$raw" ]; then
      echo "  ${p}_$s: fastboot nie zwrocil partition-size -> nie moge grac rozmiarem (kontynuuje)"
      continue
    fi
    # Parsowanie: NIE wolno po prostu sprawdzic '*[!0-9]*', bo '0x...' ma w sobie 'x' i
    # taka bramka odrzucalaby KAZDY hex (wlanie to zepsulem w pierwszej poprawce, test A
    # 2026-09-23: 'nieparsowany rozmiar 0x1000000'). Najpierw odejmij prefiks, potem
    # sprawdzaj cyfry. A-F tolerowane: nie kazdy fastboot pisze malymi literami.
    body=$raw
    case $raw in 0[xX]*) body=${raw#0[xX]};; esac
    if [ -z "$body" ]; then
      echo "  ${p}_$s: pusty rozmiar po 0x - odpuszczam bron"; continue
    fi
    case $body in *[!0-9a-fA-F]*) echo "  ${p}_$s: nieparsowany rozmiar '$raw' - odpuszczam bron"; continue;; esac
    have=$((raw))
    if [ "$need" -gt "$have" ]; then
      # spacja po '((' jest MUSI: '$(((need-have)+x)/y)' bash czyta jako podstawienie
      # polecenia '$(' + arytmentacja i w efekcie 'brakuje  MB' (pusto) - zmierzone 2026-09-23.
      echo "  ZMALE: ${p}_$s = $((have/1048576)) MB, obraz = $((need/1048576)) MB, brakuje $(( (need-have+1048575)/1048576 )) MB"
      FIT=0
    else
      echo "  ok ${p}_$s: $((have/1048576)) MB mieSci $((need/1048576)) MB (zapas $(((have-need)/1048576)) MB)"
    fi
  done
done
if [ "$FIT" != 1 ]; then
  echo "  PRZERWANE, ZADEN flash nie poszedl. Co mozna:"
  # Bez liczb: one sie zmieniaja z kompresja, a glupie '88 MB' przy 74 MB w obrazie
  # bylaby gorsze niz milczenie. Rozmiary sa w release-manifest.tsv tego katalogu.
  echo "   - product: jest wariant lekki (tylko fonty, bez 67 nakladek RRO) - patrz"
  echo "     dist/release/HyperOS4_P11Gen2 vs -full; rozmiary w release-manifest.tsv;"
echo "   - system: drabinka kompresji (zmierzone na tym samym drzewie 1 376 899 072 B):"
      echo "       --compress lz4hc,9 -> 920 047 616 B  (to jest DOMYSLNE w tym wydaniu)"
      echo "       --compress lz4     -> 967 503 872 B  (+45,3 MiB, mkfs 2,3x szybciej)"
      echo "       --compress none    -> 1 376 899 072 B (wymaga tylko EROFS, bez lz4)"
      echo "     lz4hc NIE podnosi poprzeczki dla kernela: na dysku ten sam identyfikator"
      echo "     Z_EROFS_COMPRESSION_LZ4, wiec jezeli '-zlz4' wstanie, lz4hc tez wstanie."
      echo "     Bez kompresji obraz jest wiekszy niz source HyperOS, bo source jest EROFS+lz4;"
      echo "   - powiekszanie super usuwa product i rusza /data (nieodwracalne). Ten skrypt"
      echo "     robi to wylacznie na swiadoma prosbe: RESIZE_SUPER=1 I_ACCEPT_DATA_LOSS=yes"
      echo "     ./flash-all.sh - wtedy delete-logical-partition product_a/b +"
      echo "     resize-logical-partition system_a/b, a product nie jest flashowany."
  exit 1
fi

echo "== 6. flash"
run flash vbmeta_a "$IMG_VB"; run flash vbmeta_b "$IMG_VB"
if [ "$SKIP_PRODUCT" = 1 ]; then
  echo "  product: pominiety (partycji nie ma po resize)"
else
  run flash product_a "$IMG_PR"; run flash product_b "$IMG_PR"
fi
run flash system_a "$IMG_SY";  run flash system_b "$IMG_SY"
echo "  (product i system ida na OBA sloty: flashowanie tylko biezacego daje 'flash OK, boot stop',"
echo "   bo weryfikacja i init patrza na slot startowy - patrz dist/rom-kit/README.sumy.md)"

echo "== 7. reboot (bez wipe /data: decyzja nalezy do Ciebie)"
echo "  framework Inny niz stockowy -> czesto potrzebny 'fastboot erase userdata'."
echo "  Nie robie tego za Ciebie: utrata danych jest nieodwracalna."
run reboot
