#!/usr/bin/env bash
# powrot do stock: wgrywa vbmeta z kopii wykonanej przez flash-all.sh
set -uo pipefail
cd "$(dirname "$0")"
for s in a b; do
  [ -f "vbmeta_stock_$s.img" ] || { echo "brak vbmeta_stock_$s.img - kopie robil flash-all.sh (krok 2)"; continue; }
  fastboot flash "vbmeta_$s" "vbmeta_stock_$s.img" && echo "  przywrocone vbmeta_$s"
done
echo "Partycje product/system przywraca sie obrazami Lenovo/stock z Dysku (IDs in diagnostics/drive-inventory.tsv)."
