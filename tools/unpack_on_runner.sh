#!/usr/bin/env bash
# Rozpakowanie obrazow partycji NA RUNNERZE Actions i wypchanie ich jako kawalkow <= 90 MB.
#
# Kiedys to jest potrzebne: Google Drive NIE ma zadnego compute (konektor potrafi
# tylko kopiowac, przenosic, udostepniam i zapisac plik jako calosc), a sandbox agenta
# nie ma mount/debugfs/lpunpack. Runner ma pelny Ubuntu + sudo + loop devices, wiec
# rozpakowanie wykonuje sie tutaj, a do agenta ida tylko kawalki przez git.
#
# Wolne od kontenera i od LFS-a. Limit GitHuba 100 MB/plik obowiazuje przy pushu,
# stad split -b 90m i MANIFEST.tsv z blob SHA (agent sklada to tools/pull_via_git.sh).
#
# Uzycie na runnerze:   ./tools/unpack_on_runner.sh out transfer
#   $1 - katalog z pobranymi .img   $2 - katalog docelowy kawalkow (w repo)
#
# Skrypt NIE modyfikuje obrazow: mount tylko read-only, debugfs bez -w.
set -uo pipefail

SRC=${1:-out}
DST=${2:-transfer}
MAX=${MAX:-94371840}            # 90 MiB
mkdir -p "$DST"
[ "${KEEP_MANIFEST:-0}" = "1" ] || : > "$DST/MANIFEST.tsv"
[ "${KEEP_MANIFEST:-0}" = "1" ] || : > "$DST/UNPACK_REPORT.txt"

# To, co realnie potrzebne sciezce A (wyglad HyperOS), nie cale drzewo.
ALLOW=(
  system/fonts system/etc/fonts.xml system/etc/sysconfig system/framework/framework-res.apk
  product/overlay product/etc/permissions
  system_ext/overlay system_ext/framework odm/overlay odm/etc vendor_mystical/overlay
  vendor_mystical/etc/vintf
  vendor_mystical/etc/permissions
  odm/etc/vintf
  product/etc/vintf
  system_ext/etc/vintf
  product/etc/permissions
  system_ext/etc/permissions
  overlay
)

have() { command -v "$1" >/dev/null 2>&1; }
log() { echo "$@" | tee -a "$DST/UNPACK_REPORT.txt"; }

log "=== unpack_on_runner: $SRC -> $DST (limit kawalka $MAX B) ==="
log "narzedzia: mount=$(have mount && echo tak || echo NIE) debugfs=$(have debugfs && echo tak || echo NIE) fsck.erofs=$(have fsck.erofs && echo tak || echo NIE) simg2img=$(have simg2img && echo tak || echo NIE) tar=$(have tar && echo tak || echo NIE)"
df -h "$PWD" | tail -1 | sed 's/^/  /'

total_pkgs=0
RUN_TAG="${RUN_TAG:-${GITHUB_RUN_ID:-local}}"
MAX_TOTAL="${MAX_TOTAL:-1900000000}"
budget_left="$MAX_TOTAL"
SKIP_IDS=""
for img in "$SRC"/*.img "$SRC"/*.raw; do
  [ -e "$img" ] || continue
  base=$(basename "$img"); base=${base%.img}; base=${base%.raw}
  isz=$(stat -c%s "$img")
  log
  log "--- $base ($isz B)"

  work="$img"
  if have simg2img && [ "$(head -c4 "$img" | od -An -tx1 | tr -d ' \n')" = "3bff26ed" ]; then
    if simg2img "$img" "$SRC/$base.raw" 2>>"$DST/UNPACK_REPORT.txt"; then
      work="$SRC/$base.raw"; log "    sparse -> raw: $(stat -c%s "$work") B"
    else
      log "    simg2img nie udalo sie (sprobam czytac jako surowy)"
    fi
  fi

  # Runner Azure ma ~13 GB wolnego CALEGOOS - przy 6,45 GB obrazie 'pakuj calosc'
  # to byl strzal w kolano. Wymagam zapasu przed startem i mowie o tym w raporcie.
  need=$(( isz + (isz/8) + 4194304 ))
  avail=$(df --output=avail -k "$PWD" 2>/dev/null | tail -1 | tr -d ' ')
  if [ -n "$avail" ] && [ $((avail*1024)) -lt "$need" ]; then
    log "    SKIP: potrzeba ~$need B wolnego, jest $((avail*1024)) B - nie dotykam (mniejsze = nastepny bieg)"
    rm -f "$img"; continue
  fi
  tree=$(mktemp -d /tmp/tree.XXXXXX)
  method=""
  # 1) mount read-only - najdokladniejsze, dziala na ext4 i EROFS, wymaga sudo (runner ma)
  if have mount; then
    if sudo -n mount -o ro,loop "$work" "$tree" 2>/dev/null; then
      method="mount-ro"; mounted=1; log "    zamontowane read-only"
    fi
  fi
  # 2) debugfs - ext4 bez montowania (odczyt)
  if [ -z "$method" ] && have debugfs && debugfs -R "stat /" "$work" >/dev/null 2>&1; then
    method="debugfs"
    cmds=""
    for d in "${ALLOW[@]}"; do cmds+="rdump $d $tree"$'\n'; done
    printf '%s\nquit\n' "$cmds" | debugfs -f /dev/stdin "$work" >/dev/null 2>&1
    log "    debugfs rdump (sciezki ktore istnieja trafia do paczki)"
  fi
  # 3) EROFS przez fsck.erofs --extract (cala zawartosc - ostatnia deska ratunku)
  if [ -z "$method" ] && have fsck.erofs; then
    if fsck.erofs --extract="$tree" "$work" >/"$DST/UNPACK_REPORT.txt" 2>&1; then
      method="fsck.erofs"; log "    fsck.erofs --extract"
    fi
  fi
  if [ -z "$method" ]; then
    log "    BRAK SKUTECZNEJ METODY rozpakowania (brak mount/debugfs/fsck.erofs albo nieznany FS)"
    [ -d "$tree" ] && rmdir "$tree" 2>/dev/null
    continue
  fi
  umount_tree() { [ "${mounted:-0}" = "1" ] && sudo -n umount "$tree" 2>/dev/null; mounted=0; }

  # Paczka = TYLKO to, czego sciezka A potrzebuje. Dobre praktyki, ktore tu siedza:
  #  - obraz EROFS/ext4 punktuje sie w ITS ROOT, czyli 'product/overlay' NIE ISTNIEJE
  #    w montowanym drzewie (jest 'overlay'). Wczesniejsza wersja szukala z prefiksem
  #    nazwy partycji -> nie trafiaa w nic -> wpadala w 'pakuj calosc' -> przy product
  #    6,45 GB to ENOSPC na runnerze (13 GB wolnego) i ucieta paczka wmanewrowana w
  #    MANIFEST (bieg 35894152349, 2026-09-23). Dlatego teraz wzorce sa po OGONIE.
  include=()
  if [ -n "${ONLY_DIRS:-}" ]; then
    for d in $ONLY_DIRS; do
      for cand in "$d" "./$d" "${d#./}"; do
        [ -e "$tree/$cand" ] && { include+=("$cand"); break; }
      done
    done
    [ "${#include[@]}" -gt 0 ] || { log "    (!) ONLY_DIRS nie trafil w nic - odpuszczam paczke"; continue; }
  else
    # wzorce po OGONIE sciezki, bo po zamontowaniu nie ma prefiksu partycji.
    # Bez line-continuation: poprzednia lotka gubila '\', przez co '-not -path'
    # stawal sie osobnym poleceniem, a filtr znikal (test 2026-09-23).
    dirs=$(cd "$tree" && find . -xdev -maxdepth 4 -type d -name overlay -not -path './lost+found*' 2>/dev/null)
    dirs="$dirs
$(cd "$tree" && find . -xdev -maxdepth 3 -type d -name vintf 2>/dev/null)"
    dirs="$dirs
$(cd "$tree" && find . -xdev -maxdepth 3 -type d -name permissions 2>/dev/null)"
    dirs="$dirs
$(cd "$tree" && find . -xdev -maxdepth 3 -type d -name sysconfig 2>/dev/null)"
    dirs="$dirs
$(cd "$tree" && find . -xdev -maxdepth 3 -type d -name fonts 2>/dev/null)"
    files=$(cd "$tree" && find . -xdev -maxdepth 2 -type f -name build.prop 2>/dev/null)
    files="$files
$(cd "$tree" && find . -xdev -maxdepth 4 -type f -name 'compatibility_matrix*.xml' 2>/dev/null)"
    files="$files
$(cd "$tree" && find . -xdev -maxdepth 4 -type f -name manifest.xml 2>/dev/null)"
    files="$files
$(cd "$tree" && find . -xdev -maxdepth 4 -type f -name framework-res.apk 2>/dev/null)"
    files="$files
$(cd "$tree" && find . -xdev -maxdepth 4 -type f -name fonts.xml 2>/dev/null)"
    files="$files
$(cd "$tree" && find . -xdev -maxdepth 4 -type f -name 'public.libraries.txt' 2>/dev/null)"
    # katalog + plik w nim to w tarze dwojakie wpisy - zostawiam katalog, wyrzucam dzieci
    all_list=$(printf '%s\n' "$dirs" "$files" | grep -v '^\.$' | sort -u)
    for rel in $all_list; do
      keep=1
      for d in $all_list; do
        [ "$d" = "$rel" ] && continue
        case "$rel" in "$d"/*) keep=0; break;; esac
      done
      [ "$keep" = "1" ] && include+=("$rel")
    done
    [ "${#include[@]}" -gt 0 ] || { log "    (!) allowlista nie trafil w NIC w tym obrazie - NIE pakujemy calosci (patrz komentarz wyzej)"; umount_tree; continue; }
    log "    trafil: ${#include[@]} pozycji: $(printf '%s ' "${include[@]}" | cut -c1-200)"
  fi
  # (sciezki dobrane wyzej; brak 'pakuj calosc' - to bylo zrodlo ENOSPC)
  pkg="$DST/$base-assets.tar.gz"
  # 'sudo' potrzebne, bo na zamontowanym ro drzewie nie zawsze da sie czytac bez roota;
  # tar dostaje liste 'include' wzgledem '$tree' - te same sciezki, ktore wlasnie dobralem.
  if [ "${mounted:-0}" = "1" ]; then
    sudo -n tar -I "gzip -1" -cf "$pkg" -C "$tree" "${include[@]}" 2>>"$DST/UNPACK_REPORT.txt" || \
      log "    (sudo tar rc=$? - probuje bez sudo)"
    umount_tree
  fi
  [ -s "$pkg" ] || tar -I "gzip -1" -cf "$pkg" -C "$tree" "${include[@]}" 2>>"$DST/UNPACK_REPORT.txt" || true
  rm -rf "$tree"

  if [ ! -s "$pkg" ]; then
    log "    paczka pusta - nic nie wyciagnieto"
    umount_tree 2>/dev/null || true
    continue
  fi
  # BRAMKA 1: paczka, ktorej tar nie domknal (ENOSPC!), nie moje miec wstepu do
  # manifestu - 'tar -tzf' czyta calosc i wywala sie na ucietym strumieniu gzipa.
  if ! tar -tzf "$pkg" >/dev/null 2>&1; then
    log "    SKIP: paczka USZKODZONA/UCIETA (tar -tzf padl; pewnie brak miejsca) - wyrzucam"
    rm -f "$pkg"; continue
  fi
  psz=$(stat -c%s "$pkg"); psha=$(sha256sum "$pkg" | cut -d' ' -f1)
  # budzet na bieg: 'git push' GitHuba twardo lata >2 GB (a 100 MB/plik to dopiero
  # pocdatek), wiec zamiast wywracac bieg - przerzucamy reszte na nastepny i mowimy o tym
  if [ $(( budget_left - psz )) -lt 0 ]; then
    log "    SKIP: paczka $psz B przekracza budzet biegu (zostal $budget_left B) - wpisz ten obraz do drive-probe.request jeszcze raz"
    SKIP_IDS="$SKIP_IDS $(basename "$base")"
    rm -f "$pkg"; continue
  fi
  budget_left=$(( budget_left - psz ))
  log "    budzet po tej paczce: $budget_left B"
  log "    paczka: $(basename "$pkg") $psz B sha256=${psha:0:16}..."

  n=0
  if [ "$psz" -gt "$MAX" ]; then
    rm -f "$pkg".part.*   # koscie po poprzednim biegu, zeby nie doaczyc starych czesci
    split -b "$MAX" -d -a 3 "$pkg" "$pkg.part."
    n=$(ls "$pkg".part.* 2>/dev/null | wc -l)
    log "    podzial na $n czastek (limit GitHuba 100 MB/plik)"
    # BRAMKA 2: sum(a) musi dawac ojcowski sha256 - przy ENOSPC split pisal 131 KB
    # i 'n=1' wpadlo do manifestu jako pelna paczka (zmierzone 2026-09-23).
    jsha=$(cat "$pkg".part.* | sha256sum | cut -d' ' -f1)
    if [ "$jsha" != "$psha" ]; then
      log "    SKIP: zlozone czastki daja $jsha != $psha - nie ufam tej paczce, kasuje"
      rm -f "$pkg".part.*; rm -f "$pkg"; continue
    fi
    log "    spr: zlozone czastki = paczka rodzic OK"
  fi

  {
    printf '%s\t%s\t%s\t%s\n' "$(basename "$pkg")" "$psha" "$psz" "$((n>0 ? n : 1))"
    if [ "$n" -gt 0 ]; then
      for f in "$pkg".part.*; do printf 'transfer/%s\t%s\n' "$(basename "$f")" "$(git hash-object -t blob "$f")"; done
    else
      printf 'transfer/%s\t%s\n' "$(basename "$pkg")" "$(git hash-object -t blob "$pkg")"
    fi
  } >> "$DST/MANIFEST.tsv"
  # limit GitHuba to 100 MB NA BLOB (zmierzone 2026-09-22): tarball rodzic musial
  # zniknac PRZED 'git add -f transfer/', ale po splicie i po MANIFESCIE - wczesniejsza
  # ata kasowala go przed splitem, przez co 'split' nie miel czego dzielic (0 czesci).
  # Usuwac rodzica WYLACZNIE gdy powstaly czesci. Przy paczce <= MAX nie ma .part.*,
  # a MANIFEST wskazuj wlasnie na rodzica - wczesniejsze bezwarunkowe rm kasowalo plik
  # przed "git add", wiec small-tary (system 72 MB, odm 6 KB) nigdy nie trafiy na spool
  # i skadanie dawalo „brakuje 1 z 1 czastek" (zmierzone 2026-09-23, bieg 35897100768).
  if [ "$n" -gt 0 ]; then rm -f "$pkg"; else log "    rodzic zostaje w transfer/ (n=0, <= MAX)"; fi

  # ten sam manifest co w trybie 'raw:' - dzieki temu tools/assemble_raw_parts.py sklada
  # obie sciezki (rozpakowana paczke i surowy obraz) jednym kodem, bez drugiego parsera
  {
    printf '# RAW v1\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(basename "$pkg")" "$psz" "$psha" "$((n>0 ? n : 1))" 0 "$((n>0 ? n-1 : 0))"
    if [ "$n" -gt 0 ]; then
      for f in "$pkg".part.*; do
        printf 'part\t%s\t%s\t%s\n' "$(basename "$f")" "$(stat -c%s "$f")" "$(sha256sum "$f" | cut -d' ' -f1)"
      done
    else
      printf 'part\t%s\t%s\t%s\n' "$(basename "$pkg")" "$psz" "$psha"
    fi
  } >> "$DST/RAW_MANIFEST-${RUN_TAG:-local}.tsv"

  total_pkgs=$((total_pkgs+1))

  # sprzatanie duzych plikow miedzy iteracjami - runner ma ~14 GB, nie mniej
  rm -f "$img" "$SRC/$base.raw"
  df -h "$PWD" | tail -1 | sed 's/^/    wolne teraz: /' | tee -a "$DST/UNPACK_REPORT.txt" >/dev/null
done

log
log "=== podsumowanie: $total_pkgs paczek, pominietych:${SKIP_IDS:-brak} ==="
cat "$DST/MANIFEST.tsv" >> "$DST/UNPACK_REPORT.txt"
cat "$DST/MANIFEST.tsv"
echo
echo "Jezeli ten plik jest w repo, agent sciagnie go przez:"
echo "  tools/pull_via_git.sh <repo-url> <galaz> ./incoming"
exit 0
