# Licznik przebiegu — HyperOS 4 na Lenovo Tab P11 Gen 2 (TB350FU)

Tryb: agent pracuje samodzielnie, bez pytań. Ten plik jest aktualizowany po kazdym
etapie; `run` = id biegu GitHub Actions, `sha256` = weryfikacja co do bajta.
Start bloku: 2026-09-23 ~16:55 (Europe/Warsaw), limit czasowy 3h.

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
| 10 | flashkit (skrypt + obrazy + rollback) + wariant modulu | DO ZROBIENIA | scripts/make_flash_kit.sh |

Uwaga o uprawnieniach: kazdy bieg wymaga wczasowo 'kazdy z linkiem' na plikach, ktore
sa pobierane, i `make_private` zaraz po nim. Kazdorazowo weryfikowane przez
`list_permissions` (ma zostac tylko 'owner').
etap 4/5: VINTF + budowa ROM-u gotowe i wpiete w workflow (rom_build: 1)
etap 5/5: pack_module.sh (walidacja zipa Magisk) - testy 3 tryby sciezek + 2 ujemne
etap 5/5: flash.sh z rozrozneniem bootloader/fastbootd (genereowany heredokiem, 79 linii, skladnia OK)
