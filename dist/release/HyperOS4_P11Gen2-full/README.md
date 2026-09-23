# Wariant `-full`: /product z fontami **i 67 nakladkami RRO** HyperOS

Ten katalog rożni się od `../HyperOS4_P11Gen2` **jedynie plikiem `product_hyperos4_p11g2.img`**
(153 391 104 B zamiast 77 619 200 B): dokładam 67 nakladek RRO (m.in. `AospFrameworkResOverlay`,
`SettingsRroCommonOverlay` 42 MB, `DevicesOverlay` 12 MB, `MiuiSecurityCoreOverlay` 13 MB) plus
drzewo katalogow z `staging/product/overlay`, bo to one daja „HyperOS Look", a nie same fonty.

`system_hyperos4_p11g2.img` (967 503 872 B) i `vbmeta_hyperos4_p11g2.img` (4 096 B) sa **tymi
samymi bajtami** co w wariancie lekkim — te same sha256, ten sam UUID, ta sama budowa:

```
product  b4bb8064d722dccb…   (153 391 104 B, 147/147 wpisow 1:1)
system   5cf58995174c7dc3…   (967 503 872 B, 4 565/4 565 wpisow 1:1; 967 507 968 to rozmiar SPRZED wykluczen)
vbmeta   9cf2e7e4e165687a…   (Flags: 3, rollback_index 0)
```

Instrukcja, wymagania kernela (`CONFIG_EROFS_FS_LZ4`), bramka rozmiaru partycji i przepis
odtworzenia bit w bit: **`../HyperOS4_P11Gen2/README.md`**.

## Wlasciciel plikow w partii

`Uid: 0 Gid: 0 Access: 0755` dla korzenia `/product` (normowane `--force-uid/--force-gid`,
patrz `../HyperOS4_P11Gen2/README.md` i docs/06 §6.19). Rozmiary po tej korekcie zostaly te same,
sha sie zmienily.

## Kiedy wybrac ten wariant, a kiedy nie

- **Wybierz**, jeśli chcesz, żeby framework HyperOS dostał swoje nakładki zasobów — bez nich
  tablet ma zasoby stockowe Lenovo (fonty i tak zadziałają, bo one sa w `system/fonts` +
  `/product/fonts`).
- **Nie wybieraj**, jeśli testujesz bootalnosc: te nakladki moga nadpisac `config_*` frameworku
  (np. wyciecie ekranu, gesty i dolny pasek nawigacji), a ich sygnatura Xiaomi nie znaczy niczyjej
  zgody na Lenovo — wtedy awarie trudno przypisac. Wariant lekki zaweza podejrzenia.

Stan wariantu (po przebudowie z 2026-09-23): 132 pliki, w tym `etc/passwd` i `etc/group`
oraz `etc/vintf/` **swiadomie bez** `manifest.xml` — patrz docs/06 §6.15. Weryfikacja
obrazu 1:1: **147/147** wpisów, `product.img` = 153 391 104 B, sha256 `b4bb8064d722dccb…`.

Czego **nie** ma tu, a ma pełny `product.img` Xiaomi (6,4 GB): `pangu/`, `bin/`,
`etc/aconfig_flags.pb`, `etc/fonts_customization.xml`,
`etc/selinux/product_*.contexts`, `etc/vintf/manifest.xml`, `overlay/partition_order.xml`.
Liczby odwołań do nich w obrazie `system`: `diagnostics/product-refs.tsv`. Dopięcie ich z
wlasnego product.img: `tools/enrich_product.sh --src product.img --tree <drzewo>`.
