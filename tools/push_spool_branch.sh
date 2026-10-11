#!/usr/bin/env bash
# Wypychanje kawalkow na GALEZ JEZORNA (transfer-spool), nie na galaz sesji.
#
# Po co: GitHub liczy rozmiar repo od objectow DOSTEPNYCH po referencjach.
# bieg po biegu dokladalibysmy 1,8 GB do historii `arena/...`, repo osiagneloby
# miekki limit ~5 GB (mail od GitHuba, a potem bol przy kazdym clone). Jezorzy
# branch jest nadpisywany (--force), a agent kasuje go po zlozeniu ("git push
# origin :transfer-spool") - wowczas bloba i tak zgarnia gc, a historia pracy
# (tylko raporty + kod) pozostaje lekka.
#
# Uzycie (na runnerze, w katalogu pracy repo):
#   tools/push_spool_branch.sh <katalog-z-kawalkami> [nazwa-galezi]
set -uo pipefail

DST=${1:?podaj katalog z kawalkami}
SPOOL=${2:-transfer-spool}
REPO_URL=${SPOOL_REPO_URL:-$(git remote get-url origin)}
# W Actions checkout siedzi na ODLOZONYM HEAD, wiec 'git rev-parse --abbrev-ref HEAD'
# zwraca "HEAD" i wczesniejszy powrot 'git checkout "$BRANCH_FROM_HEAD"' byl no-op -
# runner zostawal na orphan-branchu, a kolejny krok ('git push HEAD:arena/...')
# dostawal non-fast-forward: raport nie docie (bieg 35892866524). Trzymamy SHA.
ORIG_SHA=$(git rev-parse HEAD)
BRANCH_FROM_HEAD="$ORIG_SHA"

[ -d "$DST" ] || { echo "BRAK KATALOGU: $DST" >&2; exit 2; }
n=$(find "$DST" -type f | wc -l)
[ "$n" -gt 0 ] || { echo "katalog pusty - nie ma czego pchac" >&2; exit 3; }
echo "  wypycham $n plik(6) z $DST na $SPOOL ($(du -sh "$DST" | cut -f1))"

git checkout -q --orphan "$SPOOL" 2>/dev/null || { git checkout -q -B "$SPOOL"; }
git rm -r -q --cached . 2>/dev/null || true
# Dolaczenie brakowalo ktoregos ogniwa: nadpisanie jeziory (force) wywalaloby czastki z poprzedniego
# biegu, a 'product.img' potrzebuje czterech biegow (2 GB/push). Wystawiamy drzewo
# POPRZEDNIEGO spoolu obok nowych plikow - 'tar --skip-old-files' nie rusza tego, co
# wlasnie zapisal ten bieg, a 'git archive' nie prowdzi konfliktow z checkoutem.
SPOOL_REMOTE=${SPOOL_REPO_URL:-origin}
# FIX (noc 24/25 IX, bieg 36030150849): checkout w Actions jest PLYTKI (depth=1), wiec
# SHA poprzedniego spoola z ls-remote nie istnieje lokalnie i 'git archive $prev' padal
# po cichu (|| true) - jezioro bylo nadpisywane BEZ scalania i czastki z poprzednich
# biegow ginely. Fetchujemy ten jeden commit, zanim zaczniemy cokolwiek archiwizowac.
git fetch -q --depth=1 "$SPOOL_REMOTE" "$SPOOL" 2>/dev/null || true
prev=$(git rev-parse FETCH_HEAD 2>/dev/null || git ls-remote "$SPOOL_REMOTE" "$SPOOL" 2>/dev/null | cut -f1)
if [ -n "$prev" ]; then
  n0=$(find "$DST" -type f | wc -l)
  git archive "$prev" "$DST" 2>/dev/null | tar -x --skip-old-files -C . 2>/dev/null || true
  echo "  dolaczone czastki z poprzedniego biegu: $n0 -> $(find "$DST" -type f | wc -l) plik(6)"
fi
git add -f "$DST" 2>/dev/null || true
if git diff --cached --quiet 2>/dev/null; then echo "nic w indeksie - pomijam"; git checkout -q "$ORIG_SHA" 2>/dev/null; exit 0; fi
git -c user.name=drive-probe -c user.email=drive-probe@users.noreply.github.com \
  commit -q -m "kawalki do sciagniecia (run ${GITHUB_RUN_ID:-local})"

# 'git push' na obca galaz wymaga pelnego URL-a jeseli origin jest scoped-token
if [ -n "${GITHUB_SERVER_URL:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ]; then
  REPO_URL="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY.git"
fi
git push -q --force "$REPO_URL" "HEAD:$SPOOL" && echo "  OK na $SPOOL" || { echo "  PUSH NA SPOOL PADL" >&2; git checkout -q "$BRANCH_FROM_HEAD" 2>/dev/null; exit 1; }
git checkout -q "$ORIG_SHA" 2>/dev/null || git checkout -q "$GITHUB_SHA" 2>/dev/null || true
git branch -q -D "$SPOOL" 2>/dev/null || true
echo "  wrocone do $(git rev-parse --short HEAD)"
