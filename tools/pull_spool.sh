#!/usr/bin/env bash
# Strona agenta: sciagnij kawalki z jeziornego brancha i złoz je.
#
#  tools/pull_spool.sh pull        # fetch + export transfer/ -> parts/
#  tools/pull_spool.sh assemble    # skladanka + weryfikacja (sha256 run + md5 Google)
#  tools/pull_spool.sh wipe        # usun galaz transfer-spool (zwolni kwote w repo usera)
#  tools/pull_spool.sh all         # pull + assemble
#
#parts/ NIE jest w gicie (obrazy >100 MB) - po 'sandbox reset' zostaje nam galaz,
# wiec 'pull' odtwarza wszystko bez ponownego biegu (sprawdzone: 716 MB paczka
# odzykana z historii z identycznym sha256).
set -uo pipefail
B=${SPOOL_BRANCH:-transfer-spool}
REPO=$(git remote get-url origin)
P=${PARTS_DIR:-parts}
case "${1:-all}" in
  pull)
    git fetch -q --force "$REPO" "+refs/heads/$B:refs/remotes/origin/$B" || { echo "brak galazi $B (bieg jeszcze nie skonczyl?)" >&2; exit 1; }
    mkdir -p "$P"
    git archive "origin/$B" transfer 2>/dev/null | tar -x -C "$P" --strip-components=1 || { echo "na $B nie ma transfer/" >&2; exit 1; }
    echo "  wyciagniete do $P: $(find "$P" -type f | wc -l) plik(6), $(du -sh "$P" | cut -f1)"
    ;;
  assemble)
    python3 tools/assemble_raw_parts.py --parts "$P" --inventory diagnostics/drive-inventory.tsv
    ;;
  wipe)
    git push -q "$REPO" ":$B" && echo "  galaz $B usunieta (bloby zgarnie gc)" || echo "  nie udalo sie usunac $B"
    ;;
  all)
    "$0" pull && "$0" assemble
    ;;
  *) echo "uzycie: $0 pull|assemble|wipe|all" >&2; exit 2;;
esac
