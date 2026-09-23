# Wariant `-full`: /product z fontami **i 67 nakladkami RRO** HyperOS

Ten katalog rożni się od `../HyperOS4_P11Gen2` **jedynie plikiem `product_hyperos4_p11g2.img`**
(150 560 768 B zamiast 75 198 464 B): dokładam 67 nakladek RRO (m.in. `AospFrameworkResOverlay`,
`SettingsRroCommonOverlay` 42 MB, `DevicesOverlay` 12 MB, `MiuiSecurityCoreOverlay` 13 MB) plus
drzewo katalogow z `staging/product/overlay`, bo to one daja „HyperOS Look", a nie same fonty.

`system_hyperos4_p11g2.img` (920 047 616 B) i `vbmeta_hyperos4_p11g2.img` (4 096 B) sa **tymi
samymi bajtami** co w wariancie lekkim — te same sha256, ten sam UUID, ta sama budowa:

```
product  da17ffcd20c0ab4e…   (150 560 768 B, 147/147 wpisow 1:1)
system   cf0b889d45a6bb4f…   (920 047 616 B, 4 565/4 565 wpisow 1:1)
vbmeta   9cf2e7e4e165687a…   (Flags: 3, rollback_index 0)
```

Instrukcja (w tym **krok 0**: `bash device-probe.sh --release .`, ktory mowi GO/NO-GO na
podstawie odczytan z tabletu), wymagania kernela (`CONFIG_EROFS_FS_LZ4`), bramka rozmiaru
partycji i przepis odtworzenia bit w bit: **`../HyperOS4_P11Gen2/README.md`**. Ten katalog tez
zawiera `device-probe.sh` i ma 8 pozycji w `SHA256SUMS.txt` (`sha256sum -c` = 8/8 OK).

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

Ciekawostka zmierzona 23 IX 2026: przy `lz4hc,9` wykluczenie trzech plikow `.komentarz.txt`
z drzewa `system` (1 205 B) **nie zmienilo rozmiaru obrazu w ogole** — miescily sie w blokach
juz zajetych — podczas gdy przy `lz4` zdejmowaly dokladnie jeden blok (4 096 B). Nie znaczy to
„po co flaga": pliki-notatki nie maja byc na partycji niezaleznie od ich wagi, a `--exclude-regex`
wciiaz jest w `make_release`. Znaczy to tylko, ze rozmiaru obrazu nie przewidywac z liczby
bajtow wykluczanych plikow.

Stan wariantu (po przebudowie z 2026-09-23): 132 pliki, w tym `etc/passwd` i `etc/group`
oraz `etc/vintf/` **swiadomie bez** `manifest.xml` — patrz docs/06 §6.15. Weryfikacja
obrazu 1:1: **147/147** wpisów, `product.img` = 150 560 768 B, sha256 `da17ffcd20c0ab4e…`.

Czego **nie** ma tu, a ma pełny `product.img` Xiaomi (6,4 GB): `pangu/`, `bin/`,
`etc/aconfig_flags.pb`, `etc/fonts_customization.xml`,
`etc/selinux/product_*.contexts`, `etc/vintf/manifest.xml`, `overlay/partition_order.xml`.
Liczby odwołań do nich w obrazie `system`: `diagnostics/product-refs.tsv`. Dopięcie ich z
wlasnego product.img: `tools/enrich_product.sh --src product.img --tree <drzewo>`.
<!-- ROZMIARY-KONTRAKT product_hyperos4_p11g2.img=150560768 system_hyperos4_p11g2.img=920047616 vbmeta_hyperos4_p11g2.img=4096 -->
<!-- Utrzymuje go tools/make_release.sh, sprawdza tools/test_release.sh (sekcja Q).
     Jezli ktora kolwiek z tych liczb nie zgadza sie z plikiem albo znika z prozy
     tego README, test wydania FAILuje. To nie jest komentarz do recznego pilnowania. -->
