#!/usr/bin/env bash
# Dopelnia drzewo /product o pliki, ktorych REALNIE szuka system z HyperOS 4.
#
# Skad sie wziala ta lista. Zbudowalem /product minimalny (tylko fonts) i zmierzylem,
# co obraz system_hyperos4_p11g2.img wywoluje pod /product: 'grep -ao "/product/..." |
# sort | uniq -c' => 54x /product/etc, 18x /product/pangu/, 4x etc/fonts_customization.xml,
# 3x etc/selinux/product_*.contexts, 2x etc/aconfig_flags.pb, 2x etc/vintf/manifest.xml...
# (liczby w diagnostics/product-refs.tsv). Te pozycje sa w pelnym product.img (6,4 GB),
# ktorego nie da sie przeniesc kanalem 100 MB/blob, więc nie pakujemy calosci - wyciagamy
# TYLKO wskazane sciezki.
#
# Wymaga: fsck.erofs (tools/build_erofs_local.sh) albo 'debugfs' dla ext4. Obsluge EROFS
# robimy pierwszej, bo HyperOS 4 uzywa EROFS rowniez dla product.
#
# Uzycie:
#   tools/enrich_product.sh --src /sciezka/do/product.img --tree /tmp/tree-product [--fs auto]
set -uo pipefail
SRC=''; TREE=''; FST=auto; FSCK=${FSCK:-}
while [ $# -gt 0 ]; do
  case $1 in
    --src) SRC=$2; shift 2;;
    --tree) TREE=$2; shift 2;;
    --fs) FST=$2; shift 2;;
    *) echo "nieznana opcja: $1" >&2; exit 3;;
  esac
done
[ -n "$SRC" ] && [ -f "$SRC" ] || { echo "podaj --src <product.img>"; exit 3; }
[ -n "$TREE" ] || { echo "podaj --tree <katalog drzewa product>"; exit 3; }
HERE=$(cd "$(dirname "$0")" && pwd); [ -n "$FSCK" ] || FSCK="$HERE/vendor/erofs/fsck.erofs"
[ -x "$FSCK" ] || FSCK=$(command -v fsck.erofs || true)
[ -n "$FSCK" ] || { echo "brak fsck.erofs - zbuduj: tools/build_erofs_local.sh"; exit 2; }

# sciezki WZGLEDEM korzenia partycji; te, ktorych brak w drzewie, dolaczamy
NEED='etc/fonts_customization.xml etc/aconfig_flags.pb etc/selinux/product_seapp_contexts
etc/selinux/product_file_contexts etc/selinux/product_hwservice_contexts
etc/selinux/product_service_contexts etc/selinux/product_keystore2_key_contexts
etc/vintf/manifest.xml etc/vintf/compatibility_matrix.device.xml
etc/sysconfig media/audio/ui/camera_click.ogg'
# etc/permissions SWIADOMIE poza lista: 12 plikow, zero wpisow <library>, za to 467
# zezwoleń priv-app dla pakietow Xiaomi/GMS-CN, ktorych na Lenovo nie ma, plus dwie
# deklaracje <feature> (m.in. cn.google.services.xml). To bagaz z ryzykiem, nie
# wymagane przez init ani PMS (pomiar: 'grep -c <library>' = 0, patrz docs/02).

echo "== enrich_product: $SRC -> $TREE (odczyt: $FSCK)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
# Zmierzone na fsck.erofs 1.8.2 (test A/B/C, 2026-09-23):
#   --path=<PLIK>   + --extract=katalog  -> rc=1, NIC nie wyciaga (pierwsza wersja tego
#                     skryptu brala 'find' po katalogu i kopiowala sama sobie nazwe
#                     katalogu docelowego - pliki ladowaly jako 'etc/x')
#   --path=<KATALOG>                     -> wyciaga ZAWARTOSC katalogu SPLASZCZONA
#   bez --path                           -> caly FS z zachowanymi sciezkami (za drogie
#                     dla product.img 6,4 GB)
# Stad: wyciagamy KATALOG NADRZEDNY i kopiujemy sam listek.
nget=0; nmiss=0
for rel in $NEED; do
  [ -e "$TREE/$rel" ] && { echo "  juz jest: $rel"; continue; }
  parent=$(dirname "$rel"); leaf=$(basename "$rel")
  rm -rf "$TMP/out"; mkdir -p "$TMP/out"
  if [ "$parent" = "." ]; then parent=$leaf; leaf=$leaf; fi
  if timeout 900 "$FSCK" --extract="$TMP/out" --path="$parent" "$SRC" >/dev/null 2>&1 \
     && [ -e "$TMP/out/$leaf" ]; then
    mkdir -p "$TREE/$(dirname "$rel")"
    cp -a "$TMP/out/$leaf" "$TREE/$rel"
    echo "  dolaczone: $rel ($(stat -c%s "$TREE/$rel" 2>/dev/null || echo katalog))"; nget=$((nget+1))
  else
    echo "  NIE MA w zrodle: $rel"; nmiss=$((nmiss+1))
  fi
done
echo "== dolozonych plikow: $nget, nieobecnych w zrodle: $nmiss"
echo "   drzewo teraz: $(find "$TREE" -type f | wc -l) plikow, $(du -sh "$TREE" | cut -f1)"
[ $nget -gt 0 ] && echo "   nastepny krok: tools/make_release.sh --product-tree $TREE ..."
exit 0
