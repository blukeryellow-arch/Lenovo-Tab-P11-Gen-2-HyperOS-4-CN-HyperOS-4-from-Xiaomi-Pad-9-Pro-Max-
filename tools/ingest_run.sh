#!/usr/bin/env bash
# Koncowka biegu drive-probe: sciagnac -> zloz -> zweryfikowac -> zbudowac to, co sie da.
#
# Robi dokladnie te rzeczy, ktore robilem recznie w dwoch poprzednich biegach, ale
# w kolejnosci, ktora NIE pozwala przemycic polowicznych danych:
#   1) pull spoolu do parts/            (tools/pull_spool.sh pull)
#   2) skladanie + weryfikacja sha256/md5 (assemble_raw_parts.py; rc != 0 = odpadam)
#   3) assety 'product' (fonts/overlay) -> staging/   <- bez tego NIE MA MiSansa
#   4) modul fontow + ZIP                (make_font_module.sh, pack_module.sh)
#   5) rom-docs.tar.gz (jezeli jest) -> rom/ i wypisanie MISMATCH.md
#   6) podsumowanie: co zweryfikowane, czego brak (bez udawania)
#
# Uzycie: bash tools/ingest_run.sh [--skip-pull] [--fonts-tylko]
set -uo pipefail
cd "$(dirname "$0")/.."
SKIP_PULL=0; FONTS_ONLY=0
for a in "$@"; do case "$a" in --skip-pull) SKIP_PULL=1;; --fonts-tylko) FONTS_ONLY=1;; esac; done

echo "=== 1/6  sciaganie kawalkow ze spoolu ==="
if [ "$SKIP_PULL" = "0" ]; then
  bash tools/pull_spool.sh pull || { echo "FATAL: pull padl (galaz transfer-spool pusta?)"; exit 1; }
else
  echo "  (pominiete --skip-pull; parts/ ma $(find parts -type f 2>/dev/null | wc -l) plikow)"
fi

echo "=== 2/6  skladanie i weryfikacja sum ==="
# assembler weryfikuje sha256 runnera ORAZ md5 serwera Google (z inwentarza) - jeseli
# ktoraokolwiek sie nie zgadza, NIE wolno niczej budowac na tym pliku
if bash tools/pull_spool.sh assemble; then ASM=1; else ASM=0; echo "  (assemble rc!=0 - patrz komunikaty wyzej; niektore obrazy moga byc niekompletne)"; fi

echo "=== 3/6  assety z product (fonty, overlaye) ==="
rm -rf staging/product; mkdir -p staging/product
PTAR=$(ls -1 images/*assets.tar.gz parts/*assets.tar.gz 2>/dev/null | head -100 | while read -r t; do
         tar tzf "$t" >/dev/null 2>&1 || continue
         tar tzf "$t" 2>/dev/null | grep -qE '^\./(product/)?fonts/' && echo "$t"
       done | head -1)
if [ -n "${PTAR:-}" ]; then
  echo "  paczka z fontami: $PTAR"
  timeout 1200 tar xzf "$PTAR" -C staging/product --wildcards './fonts/*' './product/fonts/*' './overlay/*' './product/overlay/*' './etc/permissions/*' 2>/dev/null
  find staging/product -type f | wc -l | sed 's/^/  plikow: /'
  du -sh staging/product 2>/dev/null | sed 's/^/  rozmiar: /'
  FDIR=$(find staging/product -maxdepth 3 -type d -name fonts | head -1)
else
  echo "  BRAK paczki z '/fonts/' - 'product' pewnie nie zostal dociagnety (ENOSPC/budzet)"
  FDIR=""
fi

if [ "$FONTS_ONLY" = "0" ]; then
  echo "=== 4/6  modul fontow ==="
  if [ -n "${FDIR:-}" ] && [ -n "$(find "$FDIR" -type f 2>/dev/null | head -1)" ]; then
    if bash tools/make_font_module.sh --fonts "$FDIR" --out modules-build/hyperos4_fonts_p11g2 --family MiSans; then
      if bash tools/pack_module.sh modules-build/hyperos4_fonts_p11g2 hyperos4_fonts_p11g2.zip; then
        sha256sum hyperos4_fonts_p11g2.zip | sed 's/^/  /'
        echo "  MODUL GOTOWY (zip w korzeniu repo); zrodlo: $(basename "$PTAR")"
      else
        echo "  FATAL: pakowanie padlo - katalog modulu jest, ZIP-u nie ma" >&2
      fi
    else
      echo "  FATAL: generator modulu padl - nie pakujemy" >&2
    fi
  else
    echo "  POMINIETE: nie ma z czego budowac (brak /product/fonts w sciagnietych paczkach)."
    echo "  Nie buduje modulu 'na zamiennikach' - patrz komunikat w kroku 3."
  fi
fi

echo "=== 5/6  dokumentacja ROM-u (rom-docs) ==="
RD=$(ls -1 parts/rom-docs.tar.gz images/rom-docs.tar.gz 2>/dev/null | head -1)
if [ -n "${RD:-}" ]; then
  rm -rf rom && mkdir -p rom && tar xzf "$RD" -C rom 2>/dev/null
  echo "  plikow w rom/: $(find rom -type f | wc -l)"
  [ -f rom/MISMATCH.md ] && { echo "  --- MISMATCH.md ---"; sed -n '1,14p' rom/MISMATCH.md; }
else
  echo "  BRAK rom-docs.tar.gz na spoolu (bieg ROM nie skonczyl siepacjalnie?)"
fi

echo "=== 6/6  podsumowanie ==="
{
  echo "# ingest_run - stan po biegu $(date -u +%FT%TZ)"
  echo
  echo "| element | stan |"
  echo "|---|---|"
  echo "| skladanie parts/ | $([ "$ASM" = 1 ] && echo 'ZWERYFIKOWANE (sha256 runnera)' || echo 'NIE PEWNE - rc!=0') |"
  echo "| paczka z fontami | $([ -n "${FDIR:-}" ] && echo "jest: $FDIR (zrodlo: $(basename "${PTAR:-brak})")" || echo 'BRAK (product nie doszedl)') |"
  echo "| ZIP modulu | $([ -f hyperos4_fonts_p11g2.zip ] && echo "jest ($(stat -c%s hyperos4_fonts_p11g2.zip) B)" || echo 'BRAK') |"
  echo "| rom-docs | $([ -n "${RD:-}" ] && echo jest || echo BRAK) |"
  echo
  echo "Obrazy w images/: $(ls -1 images/*.tar.gz 2>/dev/null | wc -l) paczek assetow, $(ls -1 images/*.img 2>/dev/null | wc -l) obrazow."
  echo "Uprawnienia Drive: DO ZAMKNIECIA po zebraniu danych (make_private + list_permissions)."
} | tee INGEST_STATUS.md
