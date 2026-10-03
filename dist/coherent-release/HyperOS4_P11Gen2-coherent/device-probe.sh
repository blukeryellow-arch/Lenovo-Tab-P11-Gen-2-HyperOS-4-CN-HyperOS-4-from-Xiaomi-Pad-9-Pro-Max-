#!/usr/bin/env bash
# device-probe.sh - kontrola urzadzenia PRZED flashem (tylko odczyty).
# Kopia z repo: tools/device_probe.sh (ta partia, bez --adb do montowania).
#
# Po co: wydanie ma dwa warunki wstepne, ktorych nie da sie sprawdic z plikami na dysku —
# kernel musi montowac EROFS+lz4 (docs/06 §6.10, §6.17) i sloty musza pomiescic obrazy
# (docs/06 §6.11). Uruchomienie tego przed `flash-all.sh` jest tanie, a brak tego kroku
# jest tym, po czym ludzi zostaja z cegla.
#
# Skrypt swiadomie NIE flashuje, NIE mountuje, NIE remountuje i NIE pisze nic poza
# --out (domyślnie /dev/stdout). Wszystkie polecenia to `getvar` / `shell` / odczyt plikow.
#
# Użycie:
#   tools/device_probe.sh [--fastboot N] [--adb N] [--release KATALOG] [--out PLIK]
#                         [--assume-booted]   # gdy adb nie odpowiada, ale wiemy, ze ADB works
#   Środowisko testowe (uzywane przez tools/test_release.sh, sekcja P):
#     PROBE_ASSUME_BOOTED=1   - nie pytaj o tryb bootloadera
# Wersja z ograniczeniami: jezli `fastboot` nie zna `getvar partition-size`, to jest
# OSTRZEZENIE, nie odmowa — tak samo zachowuje sie bramka w `flash-all.sh`.
set -uo pipefail

FB=${FASTBOOT:-fastboot}; ADB=${ADB:-adb}; REL=${REL:-}
OUT=/dev/stdout; BOOTED=${PROBE_ASSUME_BOOTED:-0}
while [ $# -gt 0 ]; do
  case $1 in
    --fastboot) FB=$2; shift 2;;
    --adb) ADB=$2; shift 2;;
    --release) REL=$2; shift 2;;
    --out) OUT=$2; shift 2;;
    --assume-booted) BOOTED=1; shift;;
    *) echo "nieznana opcja: $1" >&2; exit 3;;
  esac
done
command -v "$FB" >/dev/null 2>&1 || { echo "brak $FB w PATH - nie mam czym zapytac urzadzenia" >&2; exit 2; }

GO=0; WARN=0; NOGO=0
say() { printf '%s\n' "$*" >> "$OUT"; }
go()   { say "  [OK ] $*"; GO=$((GO+1)); }   # GO MUST be counted here: bez tego werdykt
                                             # mowil 'kontrol OK: 0' przy 6 liniach [OK]
warn() { say "  [UW ] $*"; WARN=$((WARN+1)); }
no()   { say "  [NE ] $*"; NOGO=$((NOGO+1)); }

getvar() { # $1=klucz -> wartosc albo ''
  # '2>&1' jest OBOWIAZKOWE: fastboot pisze odpowiedzi getvar na stderr, nie na stdout
  # (atrapa w sekcji P testu te go dokladnie na tym przylapala - bez tego kazdy odczyt
  # wychodzil pusty, a skrypt grzeczenie zglaszal ostrzezenia zamiast blokad).
  local v
  # Filtr PO KLUCZU, nie 'cokolwiek przed dwukropkiem': fastboot dokleja 'OKAY [  0.001s]',
  # a 'sed s/^[^:]*: //' z tej linii zrobiloby wartosc '0.001s' - produktem bylo then
  # '[OK ] product=0.001s', czyli kontrola zielona i calkowicie wydmuszka (23 IX 2026,
  # przyloxyla to atrapa z sekcji P).
  v=$("$FB" getvar "$1" 2>&1 | tr -d '\r' | sed -n "s/^$1: *//p" | head -1)
  printf '%s' "$v"
}
toparse() { # '0x...' lub '12345' -> decymalnie; '' gdy nie do przeanalizowania
  local s=${1#0x}
  case $s in ''|*[!0-9a-fA-F]*) return 1;; esac
  printf '%d' "$((16#$s))"
}

say "== 1/4  tryb i sloty (fastboot)"
if [ "$BOOTED" != 1 ]; then
  if ! "$FB" devices 2>/dev/null | grep -q .; then
    say "  brak urzadzenia w trybie fastboot - uruchom: adb reboot bootloader"
    exit 1
  fi
fi
PROD=$(getvar product); SLOT=$(getvar current-slot); USR=$(getvar is-userspace)
[ -n "$PROD" ] && go "product=$PROD" || warn "fastboot nie odpowiedzial na 'getvar product'"
[ -n "$SLOT" ] && go "current-slot=$SLOT" || warn "brak current-slot (slot 'a' i 'b' beda liczone osobno)"
if [ -n "$USR" ]; then
  case $USR in
    *yes*|*true*|1) go "is-userspace=$USR (fastbootd - partycje logiczne zapisywalne)";;
    *) no "is-userspace=$USR - to NIE jest fastbootd; /product i /system sa w grupie logicznej i flash w bootloaderze padnie (albo zle zapisze)";;
  esac
else
  warn "brak odpowiedzi na is-userspace - nie moglem potwierdzic fastbootd; flash-all.sh i tak to wymusza"
fi

say "== 2/4  rozmiary slotow vs obrazy wydania"
NEED_P=""; NEED_S=""
if [ -n "$REL" ] && [ -f "$REL/release-manifest.tsv" ]; then
  # 26 IX, przegląd adwersarza: prefiks '^system_' łapał TEŻ 'system_ext_...' i brał
  # PIERWSZY wiersz manifestu. W coherent system_ext był pierwszy, więc probe
  # porównywał slot systemu z 632 MB (system_ext) zamiast 920 MB (system) -
  # fałszywe GO na slotach 633-919 MB. Jawne nazwy plików zamiast prefiksów.
  NEED_P=$(awk -F'\t' '$1 == "product_hyperos4_p11g2.img" {print $2; exit}' "$REL/release-manifest.tsv")
  NEED_S=$(awk -F'\t' '$1 == "system_hyperos4_p11g2.img"  {print $2; exit}' "$REL/release-manifest.tsv")
  say "  wydanie: product=${NEED_P:-?} B  system=${NEED_S:-?} B  (z $REL/release-manifest.tsv)"
else
  warn "nie podano --release - nie mam z czym porownac rozmiarow (bramka pozostaje w flash-all.sh)"
fi
for slot in a b; do
  for part in product system; do
    have=$(getvar "partition-size:${part}_${slot}"); hdec=$(toparse "${have:-}") || hdec=''
    need=$([ "$part" = product ] && printf '%s' "$NEED_P" || printf '%s' "$NEED_S")
    if [ -z "$hdec" ]; then
      warn "partition-size:${part}_${slot} = '${have:-brak}' - niezmierzone; flash-all.sh sprawi to samodzielnie"
      continue
    fi
    if [ -n "$need" ]; then
      if [ "$hdec" -lt "$need" ]; then
        no "${part}_${slot}: slot $hdec B < obraz $need B - to jest ten przypadek, ktory cegluje"
      else
        go "$(printf '%s_%s: %s B >= %s B (zapas %s%%)' "$part" "$slot" "$hdec" "$need" \
             "$(( (hdec - need) * 100 / (need>0?need:1) ))")"
      fi
    else
      go "${part}_${slot}: $hdec B (brak obrazu w wydaniu do porownania - pomijam)"
    fi
  done
done

say "== 3/4  kernel urzadzenia: EROFS i lz4 (przez adb, jezeli device zyje)"
SH=$("$ADB" shell 'zcat /proc/config.gz 2>/dev/null | grep -E "^CONFIG_EROFS" ; getenforce' 2>/dev/null | tr -d '\r')
if [ -n "$SH" ]; then
  if printf '%s' "$SH" | grep -q 'CONFIG_EROFS_FS=y'; then go "CONFIG_EROFS_FS=y"; else no "brak CONFIG_EROFS_FS=y w /proc/config.gz - kernel nie zmontuje zadnego obrazu EROFS"; fi
  if printf '%s' "$SH" | grep -q 'CONFIG_EROFS_FS_LZ4=y'; then
    go "CONFIG_EROFS_FS_LZ4=y (nasz obraz ma 'incompatible features: lz4_0padding', patrz docs/06 §6.17)"
  else
    no "brak CONFIG_EROFS_FS_LZ4=y - z ta vbmeta i tym system.img MONTAZ ODMOWI. Rozwiazanie: zbuduj z --compress none (tools/make_release.sh), albo nie flashuj"
  fi
  case $SH in *Enforcing*) go "SELinux: Enforcing (prawidłowo)";; *Permissive*) warn "SELinux: Permissive";; *) warn "SELinux: nie odczytane";; esac
else
  warn "adb nie odpowiada (urzadzenie w fastboot?) - pominiem sondy kernela; to jest WARUNEK WSTEPNY wydania, wiec zrob ja pozniej albo przed rebootem"
fi

say "== 4/4  werdykt"
say "  kontrol OK: $GO   ostrzezen: $WARN   blokad: $NOGO"
if [ $NOGO -gt 0 ]; then
  say "  WERDYKT: NO-GO - nie flashuj tego wydania na tym urzadzeniu, dopuki ponizsze linie nie znikna"
  rc=2
elif [ $WARN -gt 0 ]; then
  say "  WERDYKT: GO Z ZASTRZEZENIAMI - mozna flashowac, ale przeczytaj linie [UW]"
  rc=0
else
  say "  WERDYKT: GO"
  rc=0
fi
exit $rc
