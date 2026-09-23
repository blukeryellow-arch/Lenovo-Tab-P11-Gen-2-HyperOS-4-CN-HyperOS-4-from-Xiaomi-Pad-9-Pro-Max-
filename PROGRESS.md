# Licznik przebiegu — HyperOS 4 na Lenovo Tab P11 Gen 2 (TB350FU)

Tryb: agent pracuje samodzielnie, bez pytań. Ten plik jest aktualizowany po kazdym
etapie; `run` = id biegu GitHub Actions, `sha256` = weryfikacja co do bajta.
Start bloku: 2026-09-23 ~16:55 (Europe/Warsaw), limit czasowy 3h.

| # | etap | status | dowod / czas |
|--:|---|---|---|
| 1 | kanaal transferowy (runner + kawalki <=90 MB) | GOTOWE (poprz. tura) | bieg 17 `35823024969`, sha256 `afb1e37bc86b` |
| 2 | odzysk po resize sandboxa (praca z gałęzi) | GOTOWE | `images/system.assets.tar.gz` 716 MB, sha256 ZGODNY z MANIFESTem |
| 3 | unpack: allowlist `./`, ONLY_DIRS, budzet 2 GB na push | W TRAKCIE | — |
| 4 | transfer `vbmeta` + `boot` + `vendor_boot` (małe, Lenovo) | DO ZROBIENIA | — |
| 5 | transfer `vendor_mystical` + `system_ext` (HyperOS) | DO ZROBIENIA | — |
| 6 | transfer `odm` (HyperOS) | DO ZROBIENIA | — |
| 7 | transfer `product` (HyperOS, najwiekszy) | DO ZROBIENIA | — |
| 8 | analiza: AVB/fingerprinty/VINTF na prawidzwych bajtach | DO ZROBIENIA | docs/05 |
| 9 | przebudowa lancucha AVB (hashtree + testkey) i vbmeta spójna | DO ZROBIENIA | out/vbmeta-hyperos4.img |
| 10 | flashkit (skrypt + obrazy + rollback) + wariant modulu | DO ZROBIENIA | scripts/make_flash_kit.sh |

Uwaga o uprawnieniach: kazdy bieg wymaga wczasowo 'kazdy z linkiem' na plikach, ktore
sa pobierane, i `make_private` zaraz po nim. Kazdorazowo weryfikowane przez
`list_permissions` (ma zostac tylko 'owner').
