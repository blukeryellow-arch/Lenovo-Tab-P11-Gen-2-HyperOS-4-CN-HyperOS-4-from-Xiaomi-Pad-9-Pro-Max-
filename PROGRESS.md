## Ostatni status

**25 IX wieczor:** wariant **CLEAN** (coherent minus 7 pakietow diagnostycznych/
telemetrii w system_ext; MSA/bloat w obrazach nie wystepuje z konstrukcji — product
donora nigdy nie wgrywany). Kit `dist/clean-release/HyperOS4_P11Gen2-clean/`:
system_ext 602 189 824 B (slot 744 968 192), verify 1:1, flash-all 5/5 na atrapie,
SHA256SUMS 10/10. Builder: `tools/build_clean_kit.sh` (idempotentny). Suite --real:
**161/0** (po odbudowie obrazow -full zniszczonych przez resety VM).
**26 IX rano: sekcja ZC (wariant CLEAN, 13 kontroli anty-zamienna/anty-nadpis/oneway)**
→ suita **166/0 (no-real) / 174/0 (--real)**; flake CI wyjasniony (tag-rerun zielony).
Upload na Dysk:
wstrzymany na sygnal usera („powiem ci kiedy"). Push gita: standardowy.

# Licznik przebiegu — HyperOS 4 na Lenovo Tab P11 Gen 2 (TB350FU)

Tryb: agent pracuje samodzielnie, bez pytań. Ten plik jest aktualizowany po kazdym
etapie; `run` = id biegu GitHub Actions, `sha256` = weryfikacja co do bajta.
Start bloku: 2026-09-23 ~16:55 (Europe/Warsaw), limit czasowy 3h.

**To jest HISTORIA bloku 3h z 23 IX — plik zamrożony po jego zamknięciu** (zdanie
o aktualizowaniu „po każdym etapie" dotyczy tamtego bloku). Wiersze „DO ZROBIENIA"
odnosiły się do jego chwili; większość zamknęły późniejsze etapy (`dist/rom-kit/`,
`dist/modules/`, przebiegi workflowów, suity). Bieżący stan i blokady: `docs/08-stan-i-blokady.md`;
umowy testów: `docs/07-jak-weryfikowac.md` (153 kontroli atrap / 161 z `--real`).

| # | etap | status | dowod / czas |
|--:|---|---|---|
| 1 | kanaal transferowy (runner + kawalki <=90 MB) | GOTOWE (poprz. tura) | bieg 17 `35823024969`, sha256 `afb1e37bc86b` |
| 2 | odzysk po resize sandboxa (praca z gałęzi) | GOTOWE | `images/system.assets.tar.gz` 716 MB, sha256 ZGODNY z MANIFESTem |
| 3 | tryb RAW (surowe czastki z zakresem) + jeziorny branch `transfer-spool` | GOTOWE | test lokalny: 2 zakresy -> sha256 oryginalu |
| 4 | transfer `vbmeta` + `boot` + `vendor_boot` (małe, Lenovo) | DO ZROBIENIA | — |
| 5 | transfer overlayow `product`+`odm`+`system_ext`+`vendor_mystical` | W TRAKCIE | jeden bieg, subset sciezek |
| 6 | transfer `odm` (HyperOS) | DO ZROBIENIA | — |
| 7 | transfer `product` (HyperOS, najwiekszy) | DO ZROBIENIA | — |
| 8a | AVB targetu + build.prop zrodla + VINTF | GOTOWE | sdk=37, A17, mat. 202604 (92 HAL), device.xml 144 |
| 8b | vintf_diff tool + porownanie z manifiesitem targetu | NARZEDZE GOTOWE | czeka na /vendor z adb |
| 9 | przebudowa lancucha AVB (hashtree + testkey) i vbmeta spójna | DO ZROBIENIA | out/vbmeta-hyperos4.img |
| 10 | flashkit (skrypt + obrazy + rollback) + wariant modulu | POL-DOZADNE | `dist/rom-kit/` (vbmeta+flash.sh+sumy) i `dist/modules/hyperos4_fonts_p11g2.zip`; brak: `system_hyperos4_p11g2.img` 1,38 GB poza git (limit bloba) oraz flash na sprzecie |

Uwaga o uprawnieniach: kazdy bieg wymaga wczasowo 'kazdy z linkiem' na plikach, ktore
sa pobierane, i `make_private` zaraz po nim. Kazdorazowo weryfikowane przez
`list_permissions` (ma zostac tylko 'owner').
etap 4/5: VINTF + budowa ROM-u gotowe i wpiete w workflow (rom_build: 1)
etap 5/5: pack_module.sh (walidacja zipa Magisk) - testy 3 tryby sciezek + 2 ujemne
etap 5/5: flash.sh z rozrozneniem bootloader/fastbootd (genereowany heredokiem, 79 linii, skladnia OK)
etap 5/5: ROM-kit zbiegu 35897100768 zweryfikowany offline (EROFS 1 376 899 072 B, macierzy w bajtach, vbmeta Flags: 3)
etap 5/5: modul fontow poprawiony pomiarom cmap (MiSansVF zamiast MiSansLatinVF, serif odrzucony: 14 kodow)
etap 5/5: uprawnienia Dysku zamkniete - 8/8 plikow ma tylko 'owner' (zweryfikowane list_permissions)
etap 5/5: autoryzacja GitHuba w sandboxie padla w trakcie fazy (gh api 401) - push wstrzymany, dane odzyskane z wiszacego commitu

## Start nastepnego biegu (gdy bedziesz chcial dociagnac reszte) — kolejnosc obowiazkowa

Ten krok CELWO nie zostal odpalony na koncu sesji: bieg CI otwiera na Dysku
'kazdy z linkiem' dla obrazow, ktore pobiera, a zamknac uprawnienia musi ktos, kto
jeszcze jest w sesji. Odpalenie i pozostawienie publicznego linku do wyciagnietego
firmware to nie jest stan, ktory chce sie komus zostawic.

    1) git add -A && git commit -m "[drive-probe] bieg 4: small-tary (system/odm) po fixie rm"
       git push origin HEAD:refs/heads/arena/01a0ca42-lenovo-tab-p11-gen-2-hyperos-4
       # workflow startuje od pusha (workflow_dispatch dawal 403); 'drive-probe.request'
       # ma juz rom_build: 1, do_unpack: 1, max_total: 1900000000
    2) poczekaz ~20 min:  gh run list --limit 3
    3) bash tools/ingest_run.sh          # fetch + skladanie + moduly + INGEST_STATUS.md
    4) ZAMKNIJC uprawnienia: make_private na 8 plikach i weryfikacja, ze zostal 'owner'
       (to samo, co bylo zrobione w tej sesji: 8/8 zamkniete)
    5) bash tools/pull_spool.sh wipe     # nie trzymac 1,5 GB na galazi transfer-spool

W tej sesji zrobione i wgitane: dist/modules/hyperos4_fonts_p11g2.zip (29 015 567 B),
dist/rom-kit/ (vbmeta Flags:3 + flash.sh 84 linie + sumy runnera i gita), naprawy
unpack_on_runner/assemble_raw_parts/build_rom_on_runner, fontgen po cmap, rro_targets
z krzyzowka 67 apk. NIE zrobione: flash na urzadzeniu (brak sprzetu tu) i jakakolwiek
przerobka vendora pod mt6789.

## Maraton 26 IX (04:24-13:00 UTC): ciagla wiarygodnosc wydania

- Dysk COMPLETE (2b406b1): folder clean 40/40, md5 serwera=lokalne 1:1, sprzatanie,
  inwentarz diagnostics/drive-clean-kit.tsv, fix buildera krok 7.
- Flake CI wyjasniony przez tag ci-repro-b69ff4c (zielony 1m27s, ten sam commit);
  logi/artefakty z sandboxa niepobieralne - patrz docs/08 "Noc 25/26 IX".
- Sekcja ZC (13 kontroli CLEAN) -> 166 PASS no-real / 174 --real (9689c7a, CI zielone);
  oba negatywy sprawdzone: anty-zamienna (sumy 53dd7dfb vs donorska) i anty-nadpis
  (flash-all coherent -> 3x FAIL, przywrocono -> 166/0).
- zloz.sh end-to-end (7b6a3d3): skrypt z Dysku + czesci = 4/4 obrazy IDENTYCZNE z dist,
  idempotentny; zloz.bat review OK; uprawnienia folderu clean: owner-only.
- README main: sekcja Wydania (4 warianty, szanse, CLEAN/Dysk/zloz, 166/174).
- Trzecia odsłona ENOSPC: replay przy 6,4 GB wolnego urwal cp i CICHO nadpisal
  system.img w 3 wariantach dist; naprawa przez odbudowe (8/8, 8/8, 9/9, 10/10)
  + utwardzenia: set -e w recepturze, rm -rf przed cp drzewa product, df-guard
  (<3000 MB = FATAL) w make_release i build_clean_kit. Suite po wszystkim: 166/174.
- Sekcja AA suity (df-guard): test izolacyjny ze stubem df wykazal, ze tr -dc '0-9'
  na calej linii zbiera cyfry z wszystkich kolumn (fail-open!) - fix: awk END{print $1}
  + case *[!0-9]* (fail-closed). 4 kontrole anty-regresyjne. Suite: 170/178.
- Przeglad adwersarza skryptow wydania: LATENTNY BUG device_probe.sh NEED_S - regex
  '^system_' lapanl tez 'system_ext' i w coherent porownywal slot systemu z 602 MB
  zamiast 920 MB (falszywe GO na 633-919 MB). Fix: jawne nazwy plikow; sumy/kontrakty
  odswiezone; 4 pliki kitu podmienione na Dysku (update_file_content znieksztalca
  UTF-8! -> delete+upload_file, md5 4/4 po pobraniu; 40/40, owner-only).
