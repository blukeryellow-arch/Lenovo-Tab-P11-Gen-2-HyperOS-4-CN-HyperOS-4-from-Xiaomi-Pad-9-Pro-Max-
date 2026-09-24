# Wariant `-full`: /product z fontami **i 67 nakladkami RRO** HyperOS

> **Stan 24 IX — przeczytaj, zanim wyciągniesz fastboot.** Oba obrazy tego katalogu są
> **odtworzone 24 IX bajt w bajt** (hash-orakul: sumy poniżej zgadzają się z wydanymi co do
> bajta), ale `system_hyperos4_p11g2.img` 920 047 616 B pozostaje buildem z 23 IX, w którym
> drzewo nosiło trzy pliki `etc/vintf/compatibility_matrix.{4,5,6}.xml` (każdy cięty od
> poprzedniego, a `optional` zapisany jako element, którego libvintf nie czyta). Skutek mierzony
> na rozpakowanym obrazie: 84 pozycje i **84 obowiązkowe** — czyli bramka `init` pozostaje
> zamknięta. Poprawiony obraz (84 pozycje, **0 obowiązkowych**, 19 197 B w jednym pliku, sha256
> `4836dcd4c8d5f6c0…`, 920 039 424 B) jest w `../HyperOS4_P11Gen2/` — do bootowania wybierz ten.
> Zestaw plików `product` rozstrzygnięty, nie zgadnięty: kuracja ze `staging/product/overlay` to
> 63 fonty + 67 RRO + `etc/passwd` + `etc/group` (147 wpisów), bez reszty `etc` z tara assetów.
> Dowody i liczby: `docs/06 §6.32`, `§6.33`.

Różnica wobec `../HyperOS4_P11Gen2` to plik `product_hyperos4_p11g2.img`
(150 560 768 B zamiast 75 198 464 B): dokładam 67 nakladek RRO (m.in. `AospFrameworkResOverlay`,
`SettingsRroCommonOverlay` 42 MB, `DevicesOverlay` 12 MB, `MiuiSecurityCoreOverlay` 13 MB) plus
drzewo katalogow z `staging/product/overlay`, bo to one daja „HyperOS Look", a nie same fonty.
Drugi plik inny niż u sąsiada to `system_hyperos4_p11g2.img` (tu kaskada z 23 IX, u sąsiada
poprawiony build 24 IX), a `flash-all.sh` (6 749 B) pochodzi z chwili wydania tej partii i
**nie ma** ścieżki `RESIZE_SUPER` — do flashowania służy wariant lekki.

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
zawiera `device-probe.sh` (6 533 B) i ma 8 pozycji w `SHA256SUMS.txt` (`sha256sum -c` = 8/8 OK).

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

Stan wariantu (odtworzenie z 2026-09-24, skład rozstrzygnięty hash-orakulem): 132 pliki —
63 fonty, 67 RRO, `etc/passwd` i `etc/group`; katalogu `etc/vintf/` tu **nie ma**, a
`etc/vintf/manifest.xml` pominięty świadomie — patrz docs/06 §6.15. Weryfikacja
obrazu 1:1: **147/147** wpisów, `product.img` = 150 560 768 B, sha256 `da17ffcd20c0ab4e…`.

Czego **nie** ma tu, a ma pełny `product.img` Xiaomi (6,4 GB): `pangu/`, `bin/`,
`etc/aconfig_flags.pb`, `etc/fonts_customization.xml`,
`etc/selinux/product_*.contexts`, `etc/vintf/manifest.xml`, `overlay/partition_order.xml`.
Liczby odwołań do nich w obrazie `system`: `diagnostics/product-refs.tsv`. Dopięcie ich z
wlasnego product.img: `tools/enrich_product.sh --src product.img --tree <drzewo>`.
<!-- ROZMIARY-KONTRAKT build-info.txt=385 device-probe.sh=6533 flash-all.sh=6749 product_hyperos4_p11g2.img=150560768 release-manifest.tsv=672 rollback.sh=1152 system_hyperos4_p11g2.img=920047616 vbmeta_hyperos4_p11g2.img=4096 -->
<!-- Utrzymuje go tools/make_release.sh, sprawdza tools/test_release.sh (sekcja Q).
     Jezli ktora kolwiek z tych liczb nie zgadza sie z plikiem albo znika z prozy
     tego README, test wydania FAILuje. To nie jest komentarz do recznego pilnowania. -->
