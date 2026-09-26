#!/usr/bin/env bash
# Buduje wariant CLEAN: donorski system_ext minus 7 pakietow diagnostycznych/telemetrii,
# plus kompletny zestaw do flashowania (system/product/vbmeta z lekkiego - te same bajty).
# Odporny na restarty: kazdy krok sprawdza, czy juz nie jest zrobiony.
# NIE tnie na czesci, NIE wysyla na Dysk (user powiedzial: poczekac na sygnal).
set -uo pipefail
REPO=/home/user/Lenovo-Tab-P11-Gen-2-HyperOS-4-CN-HyperOS-4-from-Xiaomi-Pad-9-Pro-Max-
OUTDIR=$REPO/dist/clean-release/HyperOS4_P11Gen2-clean
SYSEXT=/tmp/system_ext_clean.img
DONOR=/tmp/system_ext_donor.img
UUID_EXT=a11ce5a1-0000-4000-8000-5c1e4b7e9a64

# --- df-guard (26 IX): ENOSPC ucina mkfs/cp bez bledu; najpierw miejsce, potem build ---
# FAIL-CLOSED (jak w make_release.sh): nieczytelny df = odmowa budowy.
AVAIL_KB=$(df -k --output=avail "$REPO" 2>/dev/null | awk 'END{print $1}')
case $AVAIL_KB in
  ''|*[!0-9]*)
    echo "FATAL: nie umiem odczytac wolnego miejsca (df --output=avail niezwrotny) - nie buduje na slepo." >&2
    exit 2;;
esac
if [ "$AVAIL_KB" -lt 3000000 ]; then
  echo "FATAL: $((AVAIL_KB/1024)) MB wolnego - wymagane >=3000 MB (ENOSPC ucina obrazy bez bledu, docs/08 26 IX)." >&2
  exit 2
fi

cd "$REPO"
step() { echo; echo "=== $* ==="; }

# LEKCJA 26 IX: 'git reset --hard origin/arena' w kroku 0 zabilo niezacommitowana
# prace (sekcje ZC suity) przy odpaleniu buildera w trakcie sesji. Od teraz reset
# TYLKO na jawne --force-git-restore; domyslnie builder ani nie fetchuje, nie resetuje.
step "0) stan gita (bez resetu; --force-git-restore aby wymusic)"
if [ "${1:-}" = "--force-git-restore" ]; then
  git fetch -q origin 'refs/heads/arena/01a0ca42-lenovo-tab-p11-gen-2-hyperos-4:refs/remotes/origin/arena' 2>/dev/null || true
  git reset --hard -q origin/arena 2>/dev/null || true
  echo "  UWAGA: wykonano git reset --hard origin/arena (jawna flaga)"
else
  if [ -n "$(git status --porcelain 2>/dev/null | head -1)" ]; then
    echo "  drzewo ma niezacommitowane zmiany - builder ich NIE rusza (bez flagi)"
  fi
fi
git log --oneline -1

step "1) toolchain"
if [ ! -x /tmp/erofs-c/mkfs.erofs ]; then
  tools/build_comp_libs.sh /tmp/comp-build >/dev/null 2>&1
  tools/build_erofs_local.sh /tmp/erofs-c >/dev/null 2>&1
fi
/tmp/erofs-c/mkfs.erofs --version | head -1

step "2) spool -> donorski system_ext"
if [ ! -f "$DONOR" ] || [ "$(stat -c%s "$DONOR")" != 632840192 ]; then
  mkdir -p /tmp/spool
  git fetch -q origin transfer-spool
  git archive FETCH_HEAD | tar -x -C /tmp/spool
  tools/assemble_raw_parts.py --parts /tmp/spool/transfer --out "$DONOR" \
    --expect-sha256 7340a8367d3da8e4bdcf56a0f53dd7b77d87f81389d08b2a7e9e449fc02a5385 | tail -1
fi
M=$(md5sum "$DONOR" | cut -d' ' -f1)
echo "md5 donora: $M"
[ "$M" = f879747f3f7ebb5eb026eddeb02f8d13 ] || { echo "FATAL: md5 != suma Google"; exit 1; }

step "3) drzewo product lekkiego (potrzebne do buildu systemu)"
if [ ! -d /tmp/tree-product/etc ]; then
  mkdir -p /tmp/prod-lekki-extract
  /tmp/erofs-c/fsck.erofs --extract=/tmp/prod-lekki-extract \
    dist/release/HyperOS4_P11Gen2/product_hyperos4_p11g2.img >/dev/null 2>&1
  rm -rf /tmp/tree-product && cp -a /tmp/prod-lekki-extract /tmp/tree-product
fi

step "3b) system.img lekkiego (jedyne zrodlo: receptura docs/08)"
LEK=dist/release/HyperOS4_P11Gen2/system_hyperos4_p11g2.img
if [ ! -f "$LEK" ]; then
  if [ -f /tmp/rebuild-lekki/system_hyperos4_p11g2.img ]; then
    cp /tmp/rebuild-lekki/system_hyperos4_p11g2.img "$LEK"
    echo "  system.img: kopia z /tmp/rebuild-lekki"
  fi
fi
if [ ! -f "$LEK" ]; then
  if [ ! -d /tmp/romkit/system_tree ]; then
    tools/assemble_raw_parts.py --parts /tmp/spool/transfer --out /tmp/rom-kit.tar.gz \
      --expect-sha256 537eb4ea0c98f4b87bd1ccdb2e0ab502745dfd0820ef1deefb9d42e2a5b0923b | tail -1
    mkdir -p /tmp/romkit && tar -xzf /tmp/rom-kit.tar.gz -C /tmp/romkit
  fi
  mkdir -p /tmp/tree2 && cp -al /tmp/romkit/system_tree /tmp/tree2/ 2>/dev/null || true
  rm -f /tmp/tree2/system_tree/system/etc/vintf/compatibility_matrix.{4,5,6}.{xml,komentarz.txt}
  mkdir -p /tmp/rebuild-lekki
  tools/make_release.sh --product-tree /tmp/tree-product --system-tree /tmp/tree2/system_tree \
    --vintf-level 5 --vintf-optional-missing --out /tmp/rebuild-lekki \
    --erofs-dir /tmp/erofs-c --exclude-regex '\.komentarz\.txt$' --allow-no-vbmeta >/dev/null 2>&1 \
    || { echo "FATAL: build lekkiego sie wywrocil"; exit 1; }
  cp /tmp/rebuild-lekki/system_hyperos4_p11g2.img "$LEK"
fi

S=$(sha256sum dist/release/HyperOS4_P11Gen2/system_hyperos4_p11g2.img | cut -d' ' -f1)
echo "system.img sha256: $S"
[ "${S:0:8}" = 4836dcd4 ] || { echo "FATAL: system.img != 4836dcd4... (receptura zglasza niezgodnosc)"; exit 1; }
echo "system.img: ZGODNY z wydaniem lekkim"

step "4) ekstrakcja + czyszczenie system_ext"
if [ ! -d /tmp/ext-clean/app ]; then
  rm -rf /tmp/ext-orig
  /tmp/erofs-c/fsck.erofs --extract=/tmp/ext-orig "$DONOR" >/dev/null 2>&1
  cp -al /tmp/ext-orig /tmp/ext-clean
  for p in app/EngineerMode app/DebugLoggerUI app/MiSightService app/VsimCore app/CameraMind app/PowerInsight priv-app/RtMiCloudSDK; do
    rm -rf "/tmp/ext-clean/$p" && echo "  USUNIETO: $p"
  done
fi
echo "wpisow oryginal: $(find /tmp/ext-orig | wc -l), po czyszczeniu: $(find /tmp/ext-clean | wc -l)"

step "5) mkfs system_ext CLEAN"
if [ ! -f "$SYSEXT" ] || [ "$(stat -c%s "$SYSEXT")" -gt 744968192 ]; then
  ( cd /tmp && /tmp/erofs-c/mkfs.erofs -T 0 -U "$UUID_EXT" -zlz4hc,9 \
      --force-uid=0 --force-gid=0 "$SYSEXT" ext-clean > /tmp/mkfs-ext.log 2>&1 ) \
    || { tail -5 /tmp/mkfs-ext.log; exit 1; }
fi
SZ=$(stat -c%s "$SYSEXT")
echo "rozmiar: $SZ B (slot: 744968192, donorski: 632840192)"
[ "$SZ" -le 744968192 ] || { echo "FATAL: NIE MIESCI SIE W SLOCIE"; exit 1; }

step "6) weryfikacja 1:1 (verify_image.sh: pliki po sha256, symlinki po readlink)"
tools/verify_image.sh --img "$SYSEXT" --tree /tmp/ext-clean --fsck /tmp/erofs-c/fsck.erofs \
  || { echo "FATAL: weryfikacja obrazu CLEAN nie przeszla"; exit 1; }
echo "sha256 CLEAN: $(sha256sum "$SYSEXT" | cut -d' ' -f1)"

step "7) skladanie zestawu CLEAN"
mkdir -p "$OUTDIR"
cp -f "$SYSEXT" "$OUTDIR/system_ext_hyperos4_p11g2.img"
cp -f dist/release/HyperOS4_P11Gen2/system_hyperos4_p11g2.img "$OUTDIR/"
cp -f dist/release/HyperOS4_P11Gen2/product_hyperos4_p11g2.img "$OUTDIR/"
cp -f dist/release/HyperOS4_P11Gen2/vbmeta_hyperos4_p11g2.img "$OUTDIR/"
# device-probe/flash-all/rollback cleana sa w gicie (krok 0 je przywraca) - NIE wolno
# ich nadpisywac wersja coherent: clean ma wlasny naglowek flash-all (8177 B vs 7662 B).
# Bug znaleziony 25 IX wieczorem po porownaniu md5 z Dyskiem (c40d7486 vs d669a070).
cp -f dist/release/HyperOS4_P11Gen2/device-probe.sh "$OUTDIR/"
[ -f "$OUTDIR/flash-all.sh" ] || cp -f dist/coherent-release/HyperOS4_P11Gen2-coherent/flash-all.sh "$OUTDIR/"
[ -f "$OUTDIR/rollback.sh" ] || cp -f dist/coherent-release/HyperOS4_P11Gen2-coherent/rollback.sh "$OUTDIR/"
echo "--- $OUTDIR:"
stat -c "%s %n" "$OUTDIR"/* | sort -k2

step "GOTOWE (bez ciecia, bez uploadu)"
