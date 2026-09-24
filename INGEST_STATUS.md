# Stan dowiezienia danych (INGEST)

Ostatnia faza: bieg CI `35897100768` (marker `fcf056d`), kanał Google Drive → GitHub → gałąź
`transfer-spool`. Data: 2026-09-23, godz. ~18:10 UTC.

Uwaga z 24 IX: katalogu `images/` już nie ma (reset sandboxa) — bajty da się odzyskać
z `origin/transfer-spool` przez `tools/assemble_raw_parts.py`, opis w `docs/08` §8.6.

## Co realnie leży w workspace

| paczka | bajty | sha256 (runner) | weryfikacja |
|---|---|---|---|
| `images/drive-1IjQeu…-assets.tar.gz` (`product`) | 134 808 062 | `a53ff508…` | **ZGODNY** z zapisem runnera i z sumą Dysku (łańcuch md5→sha256 w `tools/assemble_raw_parts.py`) |
| `images/rom-kit.tar.gz` | 1 425 601 570 | `537eb4ea…` | **ZGODNY**; `sha256sum -c` w środku: `system_hyperos4_p11g2.img: OK`, `vbmeta_hyperos4_p11g2.img: OK`, `flash.sh: OK`, `MISMATCH.md: OK` |
| `images/rom-docs.tar.gz` | 30 452 | `848d0fe5…` | **ZGODNY** |
| `images/drive-13e-…-assets.tar.gz` (`system_ext`) | 495 557 978 | `c110a454…` | ze starszego biegu, zweryfikowane wcześniej |
| `images/drive-1WQM…-assets.tar.gz` (`vendor_mystical`) | 537 396 421 | `639b76e8…` | j.w. |
| `images/system.assets.tar.gz` | 749 834 731 | — | j.w. (`/system/fonts` 206 fontów, `etc/vintf`, `framework-res.apk`) |

## Czego NIE ma i dlaczego (bez zatajania)

- `transfer/drive-1Pu6RU…-assets.tar.gz` (`system`, 72 809 115 B) i `drive-1rrK7z…` (`odm`, 6317 B):
  **usunięte na runnerze, na spool nigdy nie trafiły**. `tools/unpack_on_runner.sh` robi `rm -f "$pkg"`
  po wystawieniu manifestu, a przy paczkach ≤ 90 MB nie ma części `.part.NNN`, więc po usunięciu
  rodzica nie ma czego zbierać. `tools/assemble_raw_parts.py` teraz to wykrywa i mówi
  „NIEKOMPLETNE" zamiast milczeć; wina leży po stronie `unpack_on_runner.sh` (poprawione w tym
  samym commicie: usuwa rodzica tylko gdy powstały części).
  **Skutek praktyczny: zerowy** — zawartość `system` mam z wcześniejszego `system.assets.tar.gz`
  (749 MB, te same ścieżki), a 6 KB `odm` to `etc/build.prop` + `permissions`.
- Fonty i overlaye **były** szukane w `system_ext` i `vendor_mystical` — tam ich nie ma (0 plików
  `./fonts/`). Są w `product` (patrz wyżej) i to jest właściwe miejsce.

## Awaria, która zdarzyła się w trakcie (nie ukrywać)

O ~17:56 UTC autoryzacja GitHub w sandboxie przestała działać: `git fetch` →
`could not read Username for 'https://github.com'`, `gh api` → `401 Bad credentials`
(`GH_TOKEN` miał długość, ale odrzucony). `tools/ingest_run.sh` padł na kroku 1/6.
**Odzysk bez sieci:** commit spoolu `066fb208` został w bazie obiektów jako wiszący
(fetch bez refspeca nie ruszył refa), więc `git fsck --dangling` →
`git update-ref refs/spool/run3 066fb2085562d2ebc9713af7ec5f977e2ed33b3e` →
`git archive refs/spool/run3 transfer`. 22 pliki, 1,5 GB wyciągnięte lokalnie.
Ref jest lokalny, nic nie poszło na GitHub poza dotychczasowymi pushami.

## Bramki, których ten stan NIE otwiera

Ścieżka B (swap obrazów) wymaga `vbmeta --flags 3` — wygenerowana i sprawdzona (`Flags: 3`,
klucz `cdbb7717…`), ale **flash na urządzeniu nie był wykonany**. Ścieżka A (nakładka) ma
gotowy moduł fontów; nadpisanie `framework-res.apk` przez RRO pozostaje zablokowane podpisem.
