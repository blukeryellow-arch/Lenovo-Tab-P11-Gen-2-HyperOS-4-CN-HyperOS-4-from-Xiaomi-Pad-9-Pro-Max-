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
  product/media product/overlay product/etc/permissions product/app product/priv-app
  system_ext/overlay system_ext/framework odm/overlay odm/etc vendor_mystical/overlay
)

have() { command -v "$1" >/dev/null 2>&1; }
log() { echo "$@" | tee -a "$DST/UNPACK_REPORT.txt"; }

log "=== unpack_on_runner: $SRC -> $DST (limit kawalka $MAX B) ==="
log "narzedzia: mount=$(have mount && echo tak || echo NIE) debugfs=$(have debugfs && echo tak || echo NIE) fsck.erofs=$(have fsck.erofs && echo tak || echo NIE) simg2img=$(have simg2img && echo tak || echo NIE) tar=$(have tar && echo tak || echo NIE)"
df -h "$PWD" | tail -1 | sed 's/^/  /'

total_pkgs=0
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

  tree=$(mktemp -d /tmp/tree.XXXXXX)
  method=""
  # 1) mount read-only - najdokladniejsze, dziala na ext4 i EROFS, wymaga sudo (runner ma)
  if have mount; then
    if sudo -n mount -o ro,loop "$work" "$tree" 2>/dev/null; then
      method="mount-ro"; log "    zamontowane read-only"
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
  [ "$method" = "mount-ro" ] && sudo -n umount "$tree" 2>/dev/null

  # paczka: tylko allowliste, sciezki wzgledne; to, czego nie ma, odpada bez bledu
  include=()
  for d in "${ALLOW[@]}"; do
    [ -e "$tree/$d" ] && include+=("$d")
  done
  if [ "${#include[@]}" -eq 0 ]; then
    # brak znanych katalogow - bierzemy calosc, ale to sygnal do korekty allowlisty
    log "    (!) zaden katalog z allowlisty nie istniejal - pakujac calosc"
    include=(".")
  fi
  pkg="$DST/$base-assets.tar.gz"
  if [ "$method" = "mount-ro" ] && have mount; then
    sudo -n mount -o ro,loop "$work" "$tree" 2>/dev/null && {
      sudo -n tar -I "gzip -1" -cf "$pkg" -C "$tree" "${include[@]}" 2>>"$DST/UNPACK_REPORT.txt" || {
        sudo -n umount "$tree"; tree_packed=0; }
      sudo -n umount "$tree" 2>/dev/null
    }
  fi
  [ -s "$pkg" ] || tar -I "gzip -1" -cf "$pkg" -C "$tree" "${include[@]}" 2>>"$DST/UNPACK_REPORT.txt" || true
  rm -rf "$tree"

  if [ ! -s "$pkg" ]; then
    log "    paczka pusta - nic nie wyciagnieto"
    continue
  fi
  psz=$(stat -c%s "$pkg"); psha=$(sha256sum "$pkg" | cut -d' ' -f1)
  log "    paczka: $(basename "$pkg") $psz B sha256=${psha:0:16}..."

  n=0
  if [ "$psz" -gt "$MAX" ]; then
    rm -f "$pkg".part.*   # koscie po poprzednim biegu, zeby nie doaczyc starych czesci
    split -b "$MAX" -d -a 3 "$pkg" "$pkg.part."
    n=$(ls "$pkg".part.* 2>/dev/null | wc -l)
    log "    podzial na $n czastek (limit GitHuba 100 MB/plik)"
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
  rm -f "$pkg"

  total_pkgs=$((total_pkgs+1))

  # sprzatanie duzych plikow miedzy iteracjami - runner ma ~14 GB, nie mniej
  rm -f "$img" "$SRC/$base.raw"
  df -h "$PWD" | tail -1 | sed 's/^/    wolne teraz: /' | tee -a "$DST/UNPACK_REPORT.txt" >/dev/null
done

log
log "=== podsumowanie: $total_pkgs paczek ==="
cat "$DST/MANIFEST.tsv" >> "$DST/UNPACK_REPORT.txt"
cat "$DST/MANIFEST.tsv"
echo
echo "Jezeli ten plik jest w repo, agent sciagnie go przez:"
echo "  tools/pull_via_git.sh <repo-url> <galaz> ./incoming"
exit 0
