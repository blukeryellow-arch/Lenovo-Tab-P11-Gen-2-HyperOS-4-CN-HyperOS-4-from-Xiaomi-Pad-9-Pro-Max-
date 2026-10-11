#!/usr/bin/env bash
# Pakowanie i wysylka obrazow partycji przez GitHub (kanal, ktory DZIALA z sandboxa agenta).
#
# Kontekst (zmierzone 2026-09-22, nie zelu):
#   - Google Drive konektor agenta: twardy limit 104 857 600 B na plik, bez zakresow
#   - egress agenta: github.com + api.github.com = 200; reszta (Google, LFS media,
#     objects.githubusercontent.com) = 000
#   - GitHub zwykly commit: ostrzezenie 50 MB, ODRZUCENIE powyzej 100 MB
#   - Git LFS: 2 GB/plik, ALE agent nie ma git-lfs i nie widzi media.githubusercontent.com
#     => LFS i Release assets (2 GB) sluza TYLKO runnerowi Actions, nie agentowi
# Stad: najpierw ROZPAKOWUJEMY i filtrowamy (to zwykle redukuje 11.9 GB do setek MB albo
# mniej), a to co zostaje jedzie jako kawalki <= 90 MB z MANIFEST.tsv.
#
# Uzycie (na Twoim komputerze, w katalogu z obrazami; potrzebuje git + repo klonu):
#   TOOLS=1 ./ship_to_github.sh /sciezka/do/obrazow /sciezka/do/klonu/repo
#
# Zmienne srodowiska:
#   PARTS=system,product,system_ext,odm,vendor   ktore obrazy pakowac
#   ONLY_ASSETS=1   tylko subset zasobow (fonty/tapety/dzwieki/overlaye/apk-i frameworku)
#                   zamiast pelnego drzewa - DOMYSLNIE wlaczone, bo o to chodzi w sciezce A
#   KEEP_IMG=1      wysylac takze surowe obrazy (rozepchnie repo; limit GitHub 100 MB/plik)
#   BRANCH=rom-blobs
#
# Skrypt NIE modyfikuje zadnego obrazu. Czyta i kopiuje.
set -uo pipefail

SRC=${1:-.}
DST=${2:-.}
BRANCH=${BRANCH:-rom-blobs}
PARTS=${PARTS:-system,product,system_ext,odm,vendor}
ONLY_ASSETS=${ONLY_ASSETS:-1}
MAX=94371840   # 90 MiB, z zapasem pod 100 MB GitHuba
[ -d "$SRC" ] || { echo "'$SRC' nie jest katalogiem z obrazami" >&2; exit 2; }
cd "$DST" || { echo "'$DST' nie jest katalogiem" >&2; exit 2; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "'$DST' to nie repo git" >&2; exit 2; }

STAGE=$PWD/.ship-stage
OUT=$PWD/transfer
rm -rf "$STAGE"; mkdir -p "$STAGE" "$OUT"
: > "$OUT/MANIFEST.tsv"
printf '# MANIFEST\tname\tsha256\tparts-bajt\n' > "$OUT/README.md"
echo "katalog zrodlowy: $SRC"
echo "stage:            $STAGE"

have() { command -v "$1" >/dev/null 2>&1; }
echo "narzedzia: $(have mount && echo mount || echo 'mount BRAK') $(have debugfs && echo debugfs || echo 'debugfs BRAK') $(have lpunpack && echo lpunpack || echo 'lpunpack BRAK') $(have 7z && echo 7z || echo '7z BRAK')"
echo

# --- 1) Rozpakowanie jednego obrazu do drzewa (tylko odczyt) ------------------------
unpack_one() {  # $1 = sciezka do .img
  local img=$1 tag=$1
  local dir="$STAGE/$tag"
  mkdir -p "$dir"
  # sparse -> raw, jesli trzeba
  local work="$img"
  if [ "$(head -c4 "$img" | od -An -tx1 | tr -d ' \n')" = "3bff26ed" ]; then
    if have simg2img; then
      simg2img "$img" "$dir/.raw" && work="$dir/.raw" && echo "    sparse -> raw OK"
    else
      echo "    sparse, a brak simg2img - pomijam ten obraz" >&2; return 1
    fi
  fi
  if have lpunpack && [ "$(head -c4 "$work" | od -An -tx1 | tr -d ' \n')" = "67446c61" ]; then
    echo "    to super.img (geometryja LP) -> lpunpack"
    lpunpack "$work" "$dir" && return 0
  fi
  # ext4/erofs: najpierw debugfs (bez roota, bez mountu), pozniej mount -o ro
  if have debugfs && debugfs -R "stat /" "$work" >/dev/null 2>&1; then
    echo "    ext4 -> debugfs dump"
    ( echo "rdump / $dir"; echo "quit" ) | debugfs -f /dev/stdin "$work" >/dev/null 2>&1 && return 0
    echo "    debugfs zwrucil blad - proba mount -o ro,loop" >&2
  fi
  if have fsck.erofs && fsck.erofs --extract="$dir" "$work" >/dev/null 2>&1; then
    echo "    EROFS -> fsck.erofs --extract OK"; return 0
  fi
  if mount -o ro,loop "$work" "$dir" 2>/dev/null; then
    echo "    zamontowane read-only pod $dir"; MOUNTED=1; return 0
  fi
  echo "    NIE UDALO SIE ROZPAKOWAC $img (brak debugfs/fsck.erofs/mountu)" >&2
  return 1
}

# --- 2) Filtrowanie do tego, co ma sens w sciezce A ---------------------------------
ASSET_GLOBS=(
  'system/fonts/*' 'system/etc/fonts.xml' 'system/etc/sysconfig/*'
  'product/media/*' 'product/app/*' 'product/overlay/*' 'product/media/audio/*'
  'product/etc/permissions/*' 'system/framework/framework-res.apk'
  'system_ext/overlay/*' 'system_ext/framework/*' 'odm/overlay/*'
  'product/priv-app/HyperOS*' 'product/app/HyperOS*' 'system/app/*'
)
filter_assets() {  # $1 = drzewo
  local tree=$1 dst="$2" n=0
  mkdir -p "$dst"
  for g in "${ASSET_GLOBS[@]}"; do
    while IFS= read -r f; do
      [ -e "$f" ] || continue
      rel=${f#"$tree"/}
      mkdir -p "$dst/$(dirname "$rel")"
      cp -a "$f" "$dst/$rel" && n=$((n+1))
    done < <(cd "$tree" && shopt -s nullglob globstar && ls -d $g 2>/dev/null; find . -path "./${g%/*}/*" -maxdepth 8 2>/dev/null | head -400)
  done
  echo "    dopasowanych wpissow: $n"
}

# --- 3) glowna petla: kazdy part -> paczka -> kawalki -> manifest --------------------
MOUNTED=0
IFS=',' read -ra LIST <<< "$PARTS"
for p in "${LIST[@]}"; do
  img="$SRC/${p}.img"
  [ -f "$img" ] || { echo "== $p.img: nie ma takiego pliku (pomijam)"; continue; }
  sz=$(stat -c%s "$img" 2>/dev/null || stat -f%z "$img")
  echo "== $p.img  ($sz B)"

  payload_dir="$STAGE/payload-$p"; mkdir -p "$payload_dir"
  if [ "$ONLY_ASSETS" = "1" ]; then
    tree="$STAGE/tree-$p"
    if unpack_one "$img"; then
      [ -d "$STAGE/$p" ] && mv "$STAGE/$p" "$tree" 2>/dev/null || tree="$STAGE"
      filter_assets "$tree" "$payload_dir"
    else
      echo "   ROZPAKOWANIE NIEUDANE - wysylam surowy obraz (split + manifest)"
      cp "$img" "$payload_dir/${p}.img"
    fi
  else
    unpack_one "$img" || cp "$img" "$payload_dir/${p}.img"
  fi

  tar -czf "$OUT/$p.tar.gz" -C "$payload_dir" . 2>/dev/null
  tsz=$(stat -c%s "$OUT/$p.tar.gz" 2>/dev/null || echo 0)
  echo "   spakowane: $tsz B ( $(python3 -c "print(f'{$tsz/1e6:.1f}')") MB )"
  if [ "$tsz" -gt 0 ] && [ "$((tsz/1024/1024))" -lt 1 ]; then
    echo "   (!) paczka mniejsza niz 1 MB - filtry mogly nic nie trafic; zobacz ls -R $payload_dir"
  fi

  # kawalkowanie tylko gdy trzeba
  n=0
  if [ "$tsz" -gt "$MAX" ]; then
    rm -f "$OUT"/$p.tar.gz.part.*
    split -b "$MAX" -d -a 3 "$OUT/$p.tar.gz" "$OUT/$p.tar.gz.part."
    n=$(ls "$OUT"/$p.tar.gz.part.* 2>/dev/null | wc -l)
    echo "   podzial na $n czastek <= 90 MB (limit GitHuba 100 MB/plik)"
  else
    echo "   caly plik ponizej 100 MB - bez podzialu"
  fi

  sha=$(sha256sum "$OUT/$p.tar.gz" | cut -d' ' -f1)
  {
    printf '%s\t%s\t%s\t%s\n' "$p.tar.gz" "$sha" "$tsz" "$((n>0 ? n : 1))"
    parts_list() {
      local f
      for f in "$@"; do
        printf 'transfer/%s\t%s\n' "$(basename "$f")" "$(git hash-object -t blob "$f")"
      done
    }
    if [ "$n" -gt 0 ]; then
      parts_list "$OUT"/$p.tar.gz.part.*
    else
      parts_list "$OUT/$p.tar.gz"
    fi
  } >> "$OUT/MANIFEST.tsv"
done

[ "$MOUNTED" = "1" ] && find "$STAGE" -maxdepth 1 -type d -exec umount {} \; 2>/dev/null

echo
echo "=== rozmiar tego, co leci ==="
du -sh "$OUT" | sed 's/^/  /'
ls -l "$OUT" | tail -n +2 | awk '{printf "  %-40s %12s B\n", $9, $5}'
echo
echo "=== MANIFEST.tsv ==="
cat "$OUT/MANIFEST.tsv"
echo
git add -f "$OUT" 2>/dev/null
git commit -q -m "rom-blobs: paczki do analizy agenta ($(date -u +%Y-%m-%dT%H:%M)Z)" 2>/dev/null || echo "(brak zmian do commitu)"
echo
if git rev-parse --verify -q "$BRANCH" >/dev/null; then REF=$BRANCH; else REF=$(git rev-parse --abbrev-ref HEAD); fi
echo "Wysylam na galaz: $REF"
git push -q origin "HEAD:$BRANCH" 2>&1 | tail -3 || {
  echo "push sie nie udal - sprobowac recznie: git push origin HEAD:$BRANCH"
}
echo
echo "Po stronie agenta: tools/pull_from_github.py --repo <OWNER>/<REPO> --branch $BRANCH --manifest transfer/MANIFEST.tsv"
echo "Uwaga: NIE commituj tego na galaz glowna projektu - to dane, nie kod."
