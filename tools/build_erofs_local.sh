#!/usr/bin/env bash
# Buduje erofs-utils (mkfs.erofs / fsck.erofs / dump.erofs) BEZ autoconfu, apt i roota.
#
# Po co ten skrypt. Sandbox agentowy mial gcc, make i git, ale NIE mial autoconf/
# automake/libtool ani naglowow -dev (lz4.h, zlib.h, uuid/uuid.h), a mirror kernel.org
# byl odciety (TLS). Bez mkfs.erofs nie da sie ZBUDOWAC obrazu EROFS lokalnie - da sie
# tylko opisac. Tymczasem github.com i codeload.github.com dzialaja bez kredensow, wiec
# src jest; brakuje tylko 'configure'. Rozwiazanie: osondzie wymagane cechy samym gcc i
# napisz config.h rece (to jedyna rzecz, ktorej autoconf dostarcza).
#
# Zmierzone tutaj (2026-09-23): trzy kolejne 'mkfs.erofs -T 0 -U <uuid>' na tym samym
# drzewie daly IDENTYCZNY sha256 obrazu => obraz jest deterministyczny, wiec 'przepis'
# da sie zweryfikowac tak samo dobrze jak 'plik'.
#
# Uzycie: tools/build_erofs_local.sh [katalog-docelowy]      (domyslnie ./tools/vendor/erofs)
set -uo pipefail
# Sciezka docelowa MUSI byc absolutna. Kompilacja robi 'cd $SRC', a wczesniejszy
# wzorzec '$OLDPWD/$DST' dla argumentu '/tmp/x' sklecal '/tmp/erofs-src/tmp/x/...'
# - budowanie konczylo sie 'OK', a selfcheck nie znalaz pliku (zmierzone 2026-09-23).
DST_IN=${1:-./tools/vendor/erofs}
case $DST_IN in
  /*) DST=$DST_IN;;
  *)  DST="$PWD/$DST_IN";;
esac
mkdir -p "$DST" || exit 2
SRC=/tmp/erofs-src
VER=${EROFS_VER:-master}

say() { printf '%s\n' "$*"; }
die() { printf 'FATAL: %s\n' "$*" >&2; exit 2; }

need() { command -v "$1" >/dev/null 2>&1 || die "brak programu: $1"; }
need gcc; need git; need make || true

[ -x "$DST/mkfs.erofs" ] && { say " juz zbudowane: $DST/mkfs.erofs"; exit 0; }

say "== 1/4  zrodla =="
if [ ! -d "$SRC/lib" ]; then
  rm -rf "$SRC"; mkdir -p "$SRC"
  # gitee/kernel.org sa odiete; codeload githuba dziala bez uwierzytelnienia
  timeout 300 curl -sSL "https://codeload.github.com/erofs/erofs-utils/tar.gz/refs/heads/$VER" -o /tmp/erofs.tgz \
    || die "nie sciagnalem zrodel (codeload github.com)"
  tar xzf /tmp/erofs.tgz -C "$SRC" --strip-components=1 || die "rozpakowanie nie wyszlo"
fi
[ -f "$SRC/lib/erofs_fs.h" ] || [ -f "$SRC/include/erofs/internal.h" ] || die "zrodla niepelne"
say "  plikow .c: $(find "$SRC" -name '*.c' | wc -l)"

say "== 2/4  mini-configure (sondy gcc zamiast autoconfu) =="
cd "$SRC" || die "brak $SRC"
: > config.h
probe() {   # $1=makra $2=nazwa funkcji $3=naglowek, w ktorym ma byc deklaracja
  # (void)f - WITHOUT the cast gcc widzi 'f;' jako uzycie niezadeklarowanego
  # identyfikatora i sonda padala na wszystkich 13 funkcjach (memrchr -> blad
  # 'static declaration follows non-static', bo config.h nie mial HAVE_MEMRCHR).
  printf '#define _GNU_SOURCE 1\n#include <%s>\nint main(){(void)%s;return 0;}\n' "$3" "$2" > /tmp/ep.c
  if gcc -c -o /tmp/ep.o /tmp/ep.c >/dev/null 2>&1; then
    echo "#define $1 1" >> config.h; say "  + $1"
  else say "  - $1"; fi
}
hdr() { printf '#include <%s>\nint main(){return 0;}\n' "$2" > /tmp/ep.c
        gcc -c -o /tmp/ep.o /tmp/ep.c >/dev/null 2>&1 && { echo "#define $1 1" >> config.h; say "  + $1 ($2)"; } || say "  - $1 ($2)"; }
hdr HAVE_PTHREAD_H pthread.h; hdr HAVE_UNISTD_H unistd.h; hdr HAVE_STDINT_H stdint.h
hdr HAVE_SYS_STATFS_H sys/statfs.h; hdr HAVE_SYS_STATVFS_H sys/statvfs.h
hdr HAVE_SYS_SYSMACROS_H sys/sysmacros.h; hdr HAVE_SYS_SENDFILE_H sys/sendfile.h
hdr HAVE_SYS_RESOURCE_H sys/resource.h; hdr HAVE_SYS_RANDOM_H sys/random.h
hdr HAVE_SYS_MMAN_H sys/mman.h; hdr HAVE_SYS_IOCTL_H sys/ioctl.h
hdr HAVE_SYS_XATTR_H sys/xattr.h; hdr HAVE_SYS_UIO_H sys/uio.h
hdr HAVE_LINUX_FALLOC_H linux/falloc.h
# HAVE_LINUX_TYPES_H MUSI byc zdefiniowane, jesli <linux/falloc.h> ma byc czytany:
# bez niego erofs defs.h typedefuje __u64 jako 'unsigned long', a glibc przez
# asm/int-ll64.h daje 'unsigned long long' -> 'conflicting types for __u64'
# (dokladnie ten blad, ktory wywalil pierwsze trzy proby budowy).
echo "#define HAVE_LINUX_TYPES_H 1" >> config.h; say "  + HAVE_LINUX_TYPES_H (wymuszone)"
probe HAVE_PREAD64 'pread64' unistd.h; probe HAVE_PWRITE64 'pwrite64' unistd.h
probe HAVE_FSTATFS 'fstatfs' sys/statfs.h; probe HAVE_STATVFS 'statvfs' sys/statvfs.h
probe HAVE_COPY_FILE_RANGE 'copy_file_range' unistd.h; probe HAVE_GETRANDOM 'getrandom' sys/random.h
probe HAVE_FGETXATTR 'fgetxattr' sys/xattr.h; probe HAVE_MEMRCHR 'memrchr' string.h
probe HAVE_FDATASYNC 'fdatasync' unistd.h; probe HAVE_STRNLEN 'strnlen' string.h
probe HAVE_ASPRINTF 'asprintf' stdio.h; probe HAVE_STRCHRNUL 'strchrnul' string.h
probe HAVE_EXPLICIT_BZERO 'explicit_bzero' stdio.h
{ echo '#define PACKAGE "erofs-utils"'; echo '#define PACKAGE_NAME "erofs-utils"'
  echo '#define PACKAGE_TARNAME "erofs-utils"'; echo '#define PACKAGE_STRING "erofs-utils local"'
  echo '#define PACKAGE_BUGREPORT ""'; echo '#define PACKAGE_URL ""'
  echo '#define PACKAGE_VERSION "1.8.2-local"'; echo '#define VERSION "1.8.2-local"'
  echo '#define EROFS_PACKAGED_VERSION "1.8.2-local"'; echo '#define HAVE_BYTESWAP_H 1'
  echo '#define STDC_HEADERS 1'; } >> config.h
say "  config.h: $(grep -c define config.h) definicji"

say "== 3/4  kompilacja (bez kompresji: brak lz4.h/zlib.h - swiadome) =="
# Kompresji NIE ma i to nie ubytek: CI dla tego obrazu Tez wyszlo na wariant bez
# kompresji (sonda flag odrzucila '-O fragment...' w mkfs.erofs 1.9.4), a obraz
# bez kompresji DA SIĘ weryfikowac i przeszukiwac bez biblitek rozpatrujacych.
EXCL='compressor_lib(lzma|zstd|deflate)|compressor_lz4|compressor_lz4hc|compress_qpl|liberofs_sha256'
LIB=$(find lib -maxdepth 1 -name '*.c' | grep -vE "$EXCL" | tr '\n' ' ')
CFLAGS="-O2 -DHAVE_CONFIG_H -D_GNU_SOURCE -I. -Iinclude -Ilib"
fail=0
for tool in mkfs fsck dump; do
  srcs=$(find "$tool" -maxdepth 1 -name '*.c' 2>/dev/null | tr '\n' ' ')
  [ -n "$srcs" ] || { say "  ! $tool: brak zrodel, pomijam"; continue; }
  # shellcheck disable=SC2086
  if gcc $CFLAGS -o "$DST/$tool.erofs" $LIB $srcs -lpthread 2>/tmp/egcc.log; then
    say "  OK $tool.erofs"
  else
    say "  BLAD $tool.erofs (pierwsze 3 bledy):"; grep -m3 'error' /tmp/egcc.log | sed 's/^/     /'; fail=1
  fi
done
[ $fail -eq 0 ] || die "kompilacja nie przeszla"

say "== 4/4  selfcheck =="
for b in mkfs.erofs fsck.erofs; do
  [ -x "$DST/$b" ] || die "brak $DST/$b"
done
"$DST/mkfs.erofs" --help >/dev/null 2>&1 || die "mkfs.erofs nie uruchamia sie"
say "  gotowe: $DST/{mkfs,fsck,dump}.erofs"
say "  uwaga: 'mkfs.erofs -T 0 -U <uuid>' jest deterministyczne (3/3 identyczne obrazy)"
