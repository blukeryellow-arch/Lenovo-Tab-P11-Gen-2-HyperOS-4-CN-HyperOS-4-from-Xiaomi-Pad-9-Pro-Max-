#!/usr/bin/env bash
# HyperOS 4 na Lenovo Tab P11 Gen 2 (TB350FU) — WARIANT COHERENT (noc 24/25 IX).
#
# Roznica wzgledem lekkiego wydania (HyperOS4_P11Gen2/): dokladamy donorski
# system_ext (Xiaomi Pad 9 Pro Max, HyperOS 4). Stockowy system_ext to LGSIU A14
# (sdk 34) — wymieszany z systemem A17 dalby gwarantowany chaos klas; donorski
# usuwa ta niespojnosc. Zostaje luka vendor A12 (VNDK 31) <-> system A17 —
# patrz docs/09-analiza-targetu.md, szczegolnie §5 (szanse i ograniczenia).
#
# BEZPIECZNIKI (te same co w lekkim wydaniu + jeden nowy):
#   1. bramka sumy sha256 przed kazdym flashem,
#   2. kopia vbmeta_stock_{a,b}.img PRZED pierwszym zapisem (to Twoj rollback AVB),
#   3. bramka rozmiaru partycji — ZAPYTANA, nie z dokumentu; abort przed flashem,
#   4. resize super TYLKO po RESIZE_SUPER=1 I_ACCEPT_DATA_LOSS=yes (jak w lekkim),
#   5. NOWE: system_ext bez slotow a/b (jednokierunkowy flash, brak rollbacku)
#      wymaga dodatkowo I_ACCEPT_SYSTEM_EXT_ONEWAY=yes.
# Nic nie kasuje danych bez Twojej wiedzy: erase userdata tylko po jawnym 't'.
set -uo pipefail
cd "$(dirname "$0")"

say() { printf '%s\n' "$*"; }
die() { printf 'PRZERWANE: %s\n' "$*" >&2; exit 1; }

command -v fastboot >/dev/null || die "brak fastboot w PATH"

IMG_SYS=system_hyperos4_p11g2.img
IMG_SEXT=system_ext_hyperos4_p11g2.img
IMG_PRD=product_hyperos4_p11g2.img
IMG_VB=vbmeta_hyperos4_p11g2.img

# ---------- krok 0: suma kontrolna kazdego pliku, ktory ma wejsc do urzadzenia
say "== 0. bramka sum (sha256sum)"
MISSING_BUILD=""
for f in "$IMG_SYS" "$IMG_SEXT" "$IMG_PRD" "$IMG_VB"; do
  if [ ! -f "$f" ]; then
    say "  BRAK $f"
    MISSING_BUILD="$MISSING_BUILD $f"
    continue
  fi
  want=$(awk -v F="$f" '$2==F {print $1}' SHA256SUMS.txt)
  got=$(sha256sum "$f" | awk '{print $1}')
  [ -n "$want" ] || die "SHA256SUMS.txt nie zna $f (wydanie niekompletne)"
  [ "$want" = "$got" ] || die "$f: suma $got != SHA256SUMS $want"
  say "  OK $f (${got:0:16}…)"
done
[ -z "$MISSING_BUILD" ] || die "brakujace obrazy:$MISSING_BUILD
  duze obrazy (>100 MB) nie zyja w gicie - odbuduj je receptura z docs/08
  (sekcja 'Odbudowa obrazow wydaj z transfer-spool') i doloz system_ext
  (kawalki na transfer-spool z nocy 24/25 IX, bieg drive-probe)."

# ---------- krok 1: identyfikacja urzadzenia
say "== 1. identyfikacja urzadzenia"
PROD=$(fastboot getvar product 2>&1 | tr -d $'\r' | sed -n 's/^product: *//p')
say "  product=${PROD:-nieznany}"
case "$PROD" in
  *TB350FU*|*p11*|*j7*) say "  OK, wyglada na Tab P11 Gen 2 (MT6789)";;
  "") say "  UWAGA: getvar nie zwrocil nic - upewnij sie, ze to wlasciwy tablet";;
  *) die "to NIE jest TB350FU ('$PROD') - ten zestaw jest tylko pod MT6789";;
esac

# ---------- krok 2: kopia zapasowa vbmeta (rollback AVB)
say "== 2. kopia vbmeta przed jakakolwiek zmiana"
for sfx in a b; do
  [ -f "vbmeta_stock_$sfx.img" ] && { say "  vbmeta_stock_$sfx.img juz jest (kopia z poprzedniego biegu)"; continue; }
  if fastboot fetch "vbmeta_$sfx" "vbmeta_stock_$sfx.img" 2>/dev/null; then
    say "  zapisano vbmeta_stock_$sfx.img"
  else
    say "  fetch vbmeta_$sfx nie udany - rollback = pliki Lenovo z Dysku (drive-inventory.tsv)"
  fi
done

# ---------- krok 3: bramka rozmiaru partycji (ZAPYTANA z urzadzenia)
say "== 3. bramka rozmiaru partycji"
FB_SZ() { fastboot getvar "partition-size:$1" 2>&1 | tr -d $'\r' | sed -n 's/^partition-size\['"$1"'\]: *//p' | sed 's/ .*//'; }
SZIMG() { stat -c%s "$1" 2>/dev/null || echo 0; }
GATE() { # GATE <partycja> <plik> — fail, gdy obraz nie miesci sie w slocie
  local part=$1 img=$2 sz isz
  sz=$(FB_SZ "$part")
  [ -n "$sz" ] || { say "  $part: rozmiar nieznany (fastboot nie zna partycji)"; return 2; }
  sz=$((sz)); isz=$(SZIMG "$img")
  if [ "$isz" -gt "$sz" ]; then
    say "  ZMALE: $img ($isz B) nie miesci sie w $part ($sz B, brakuje $((isz-sz)) B)"
    return 1
  fi
  say "  OK $part: $sz B >= $isz B"
  return 0
}

# system_ext: najpierw sprobuj slotow a/b, potem partycji bez przyrostka
SEXT_MODE=none
GATE system_ext_a "$IMG_SEXT" && SEXT_MODE=ab
if [ "$SEXT_MODE" = none ]; then
  if GATE system_ext_b "$IMG_SEXT" 2>/dev/null; then SEXT_MODE=ab; fi
fi
if [ "$SEXT_MODE" = none ]; then
  if GATE system_ext "$IMG_SEXT" 2>/dev/null; then SEXT_MODE=oneway; fi
fi
if [ "$SEXT_MODE" = ab ]; then
  say "  system_ext ma sloty a/b - zwykly flash obu"
elif [ "$SEXT_MODE" = oneway ]; then
  say "  UWAGA: system_ext BEZ slotow a/b - flash JEDNOKIERUNKOWY (brak rollbacku tej partycji)."
  if [ "${I_ACCEPT_SYSTEM_EXT_ONEWAY:-}" != "yes" ]; then
    die "jednokierunkowy system_ext wymaga I_ACCEPT_SYSTEM_EXT_ONEWAY=yes (albo uzyj lekkiego wydania bez system_ext)"
  fi
  say "  zgoda na jednokierunkowy system_ext: przyjeta"
else
  die "urzadzenie nie zna partycji system_ext (ani _a/_b, ani bez przyrostka).
  Wariant coherent jej wymaga - uzyj wydanienia lekkiego (HyperOS4_P11Gen2/)."
fi

# reszta bramki: vbmeta, product, system (system moze wymagac resize)
VB_OK=1; GATE vbmeta_a "$IMG_VB" || VB_OK=0
PR_FIT=1;  GATE product_a "$IMG_PRD" || PR_FIT=0
SY_FIT=1;  GATE system_a "$IMG_SYS" || SY_FIT=0

RESIZE=0
if [ "$SY_FIT" = 0 ]; then
  if [ "${RESIZE_SUPER:-}" = "1" ] && [ "${I_ACCEPT_DATA_LOSS:-}" = "yes" ]; then
    RESIZE=1
    say "  resize super: SWIADOMA ZGODA obecna - product_a/b zostana usuniete, system_a/b poszerzone"
  else
    die "system nie miesci sie, a zgoda RESIZE_SUPER=1 I_ACCEPT_DATA_LOSS=yes nie zostala podana
  (resize kasuje product w super - to nieodwracalne; szczegoly: README, docs/06 6.34)"
  fi
fi

# ---------- krok 4: flash
say "== 4. flash (kolejnosc: vbmeta, system, system_ext, product)"
if [ "$RESIZE" = 1 ]; then
  fastboot delete-logical-partition product_a || die "delete product_a nie wyszedl"
  fastboot delete-logical-partition product_b || die "delete product_b nie wyszedl"
  NEWSZ=$(( ($(SZIMG "$IMG_SYS") + 4194303) / 4194304 * 4194304 + 67108864 ))
  fastboot resize-logical-partition system_a "$NEWSZ" || die "resize system_a nie wyszedl"
  fastboot resize-logical-partition system_b "$NEWSZ" || die "resize system_b nie wyszedl"
  say "  product_a/b usuniete; system_a/b -> $NEWSZ B"
fi
for s in a b; do
  fastboot flash "vbmeta_$s" "$IMG_VB" || die "vbmeta_$s"
  fastboot flash "system_$s" "$IMG_SYS" || die "system_$s"
done
if [ "$SEXT_MODE" = ab ]; then
  fastboot flash system_ext_a "$IMG_SEXT" || die "system_ext_a"
  fastboot flash system_ext_b "$IMG_SEXT" || die "system_ext_b"
else
  fastboot flash system_ext "$IMG_SEXT" || die "system_ext (jednokierunkowy)"
fi
if [ "$RESIZE" = 0 ]; then
  for s in a b; do
    fastboot flash "product_$s" "$IMG_PRD" || die "product_$s"
  done
else
  say "  product POMINIETY (partycje usuniete w resize)"
fi

# ---------- krok 5: dane (framework A17 nad A12 - wipe zdecydowanie zalecany)
say "== 5. dane"
say "  zmiana frameworku (LGSIU A14 -> HyperOS 4 A17): bez czystego /data pulpit moze nie wstac."
read -r -p "  Usunac /data (usuwa wszystko z tableta)? [t/N] " a </dev/tty 2>/dev/null || a=n
case "$a" in
  t|T|tak|TAK) fastboot erase userdata && say "  userdata wykasowane" || say "  erase nie wyszedl - zrob recznie: fastboot erase userdata";;
  *) say "  bez wipe - jesli boot wejdzie w petle, wroc tu i wykonaj erase";;
esac

# ---------- krok 6: reboot
say "== 6. reboot"
fastboot reboot || true
say ""
say "Gotowe. Jezeli pulpit nie wstanie w 5-10 min:"
say "  adb wait-for-device; adb logcat -b all > /tmp/logcat.txt"
say "  bash tools/postflash_triage.sh /tmp/logcat.txt   # powie DOKLADNIE co stanelo"
say "Rollback AVB: ./rollback.sh (vbmeta z kopii). Uwaga: system_ext bez slotow"
say "nie ma rollbacku - powrot = flash stockowego system_ext z paczki Lenovo."
