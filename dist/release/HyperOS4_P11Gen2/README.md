# HyperOS 4 dla Lenovo Tab P11 Gen 2 (TB350FU) — zestaw do flashowania

Zbudowany i zweryfikowany **lokalnie** (bez chmury buildowej), narzędziami zbudowanymi
w tym samym sandboksie. Historia decyzji i wszystkie pomiary: `docs/06-budowa-lokalna.md`.

**Format obrazów: EROFS + `lz4`.** To nie kosmetyka — bez kompresji `system` miał
1 376 899 072 B, a źródłowy obraz HyperOS ma 937 791 488 B, bo HyperOS pakuje lz4.
Mój `lz4` daje 920 047 616 B (+3,2 % wobec źródła, −29,7 % wobec wersji bez kompresji).

## Warianty

| | co w `/product` | rozmiar `product.img` | dla kogo |
|---|---|---|---|
| `HyperOS4_P11G2` (ten katalog) | `fonts/` (28 plików MiSans VF w 13 wariantach, Arimo, SourceHanSansCN) | **75 198 464 B** | domyślny: minimalny surface zmiany |
| `HyperOS4_P11G2-full` | fonty **+ 67 nakładek RRO** (HyperOS-owy wygląd; `SettingsRroCommonOverlay` itd.) — jedyne miejsce, gdzie te RRO sie powoduja | **150 560 768 B** | jeśli ma być „HyperOS Look", nie tylko fonty |

`system` i `vbmeta` są w obu wariantach **tym samym plikiem** (identyczne sha256 — budowane
z tego samego drzewa i tego samego UUID).

## Skład wydania

| plik | bajty | co to |
|---|---|---|
| `product_hyperos4_p11g2.img` | 75 198 464 | `/product` (EROFS+lz4): `fonts/` + `etc/passwd` + `etc/group`; zweryfikowany **67/67** wpisów 1:1 |
| `system_hyperos4_p11g2.img` | 920 047 616 | `/system` z HyperOS 4 (framework, `system/fonts` z MiSans, `system/etc/permissions` 27 plików, wygenerowane macierze VINTF 4/5/6). Nakładek RRO **tu nie ma** — `system/product` w tym obrazie nie istnieje (zmierzone: `fsck.erofs --path=system/product` → rc 1), więc `/product` z tego wydania niczego nie przykrywa, tylko dokłada, zweryfikowany **4 565/4 565** wpisów 1:1. **Nie ma go w gicie** (limit 100 MB/blob) — patrz przepis niżej |
| `vbmeta_hyperos4_p11g2.img` | 4 096 | `Flags: 3` (weryfikacja + verity wyłączone), `rollback_index 0`, SHA256_RSA2048, key `cdbb7717…` |
| `flash-all.sh` | 6 631 | bramka sum → `getvar` → kopia vbmeta → **bramka rozmiaru partycji** → oba sloty → reboot |
| `device-probe.sh` | 6533 | **krok 0 przed flashem**: czyta `fastboot getvar` + `adb shell` i drukuje GO / GO z zastrzeżeniami / NO-GO (fastbootd, rozmiary slotów, `CONFIG_EROFS_FS{,_LZ4}`). Tylko odczyty — nic nie zapisuje, nic nie mountuje |
| `rollback.sh` | 1 152 | przywraca vbmeta z kopii wykonanej przed flashem |
| `release-manifest.tsv` | ~0,6 kB | `plik ⇥ bajty ⇥ sha256 ⇥ uwaga` |
| `SHA256SUMS.txt` | — | liczony na końcu; `sha256sum -c` = 8/8 OK. **`*.md` jest poza sumami** — README to dokumentacja, nie ładunek: inaczej redakcja zdania „unieważnia" wydanie (złapane przez `tools/test_release.sh`) |
| `build-info.txt` | — | kompresja, UUID, wersja `mkfs.erofs`, ścieżki drzew |
| `mkfs.log`, `fsck.log`, `system-verify.log` | — | surowe logi budowy i obu sprawdzeń |

## Jak sprawdzic, ze to, co masz, to to, co zbudowalem

```
tools/test_release.sh --real --erofs-dir <katalog z mkfs.erofs/fsck.erofs>
```

Ten skrypt robi wszystko, czego nie da sie zrobic patrzeniem na plik: buduje obrazy na
drzewie syntetycznym, sprawdza determinizm (dwa budowania = ten sam bajt), **psuje** obraz i
sprawdza, czy weryfikator to widzi (test negatywny — bez niego „wszystkie pliki OK" może
znaczyć „nikt nie sprawdził, czy check cokolwiek sprawdza"), podmienia cel symlinka, odpala
`flash-all.sh` na atrapie `fastboot` w pięciu scenariuszach (za mały slot → zero flashów)
i na końcu weryfikuje 1:1 **ten** katalog. 24 kontrole (z `--real`: 32), zero wymagań sieciowych.

## Poziomy dowodu — co sprawdza który test

Od najtańszego do jedynego, które dowodzi uruchomienia: **A** sumy → **B** zawartość 1:1 →
**C** determinizm → **D** instalator na atrapie `fastboot` → **E** format narzędziem z zewnątrz
(`release-selftest` w CI) → **F** vbmeta → **G** urządzenie. Każdy poziom ma w `docs/07-jak-weryfikowac.md`
polecenie, oczekiwane wyjście i — to jest rzecz, której zwykle brakuje — **jedno zdanie o tym,
czego ten test NIE dowodzi**. Np. `fsck.erofs` bez `--extract` zwraca 0 nawet na obrazie, którego
nie umie rozpakować, a `vbmeta` ma klucz testowy, więc obraz jest *samo-spójny*, nie *zaufany*.

## Jak to wgrać

```
bash device-probe.sh --release .   # KROK 0: tylko odczyty
sha256sum -c SHA256SUMS.txt      # musi byc OK dla kazdej pozycji (system zobaczysz dopiero po ściągnięciu)
bash flash-all.sh                # bootloader odblokowany; tablet w fastbootd (adb reboot fastboot)
```

`flash-all.sh` sam robi rzeczy, których zwykle się nie robi:
- nie rusza niczego, jeśli sumy nie zgadzają się **albo** tablet nie jest w fastbootd;
- pyta `getvar partition-size:{vbmeta,product,system}_{a,b}` i **przerywa przed pierwszym
  flaszem**, gdy obraz się nie mieści (testowo: `system` 768 MB vs obraz 922 MB →
  „ZMALE … brakuje 155 MB", zero flashów);
- flashuje **oba sloty** — tylko bieżący daje „flash OK, boot stop";
- kopiuje `vbmeta_stock_{a,b}.img` zanim cokolwiek nadpisze (to jest Twój rollback AVB);
- **nie** robi `erase userdata` za Ciebie — utrata danych jest nieodwracalna.

## Dlaczego `lz4hc,9`, a nie zwykłe `lz4`

Oba dają ten sam format na dysku (identyfikator `Z_EROFS_COMPRESSION_LZ4`, te same bity
`sb_csum mtime` / `lz4_0padding`), więc kernel nie ma żadnego nowego zadania. Różnica jest
wyłącznie w tym, jak mocno napina się kompresor przy budowie — i ile miejsca zostaje na
partycji: 920 047 616 B zamiast 967 503 872 B, czyli **45,3 MiB zapasu** za 14 sekund extra.
Przy wąskiej partycji `system` to jest dokładnie ten bufor, którego brak zabił próbę z GSIm.
Pełne porównanie trzech wariantów: docs/06 §6.23.

## Wymóg kernela (to jedyne, co może Cię zaskoczyć)

Obraz `system`/`product` z `lz4` wymaga, żeby **kernel Lenovo** miał `CONFIG_EROFS_FS_LZ4=y`:

```
adb shell 'zcat /proc/config.gz | grep EROFS'
```

`device-probe.sh` (krok 0) robi to zdanie za Ciebie i zatrzymuje flash, jezeli `LZ4` nie ma.
Nie ma? Wtedy flashuj wariant bez kompresji: `tools/make_release.sh … --compress none`
(pliki ~1,5× większe — `system` 1 376 759 808 B (bez wykluczen: 1 376 899 072 B z CI), `product` 87 973 888 B), albo zrezygnuj.
Format lz4 nie jest tu moim widzimisię: źródłowy `system.img` HyperOS-u jest lz4-owy.

## Odtworzenie bit w bajt — przepis sprawdzony na nowo skompilowanym narzędziu

`mkfs.erofs` zbudowany od zera (inna kompilacja, ten sam kod) odtwarza `product.img` wydania
**co do bajta** (`cmp` bez różnicy, sha256 `a961bec46085883d…`):

```
mkfs.erofs -T 0 -U 67b7eb22-3ebb-4c21-8b01-8ff545f10d8d -zlz4hc,9 \
           --force-uid=0 --force-gid=0 --exclude-regex '\.komentarz\.txt$' \
           out.img <drzewo-product>
```

Trzy flagi, bez których się nie uda: `-T 0` (zeruje timestamps, bez tego każdy bieg ma inne
bajty), `--force-uid/gid=0` (bez tego właściciel wchodzi z drzewa — patrz sekcja DAC wyżej)
i `--exclude-regex` (pliki-notatki generatora). To jest też powód, dla którego `make_release.sh`
ma je wpisane, a nie zostawia do recznego pilnowania.

## Odtworzyenie bit w bit (bez CI, z plików na Dysku)

Kanał git nie pomieści 967 MB, więc `system_hyperos4_p11g2.img` jest do zbudowania.
Potrzebujesz tylko `gcc`, `make`, `curl`, `python3` i pięciu obrazów z Dysku
(ID w `diagnostics/drive-inventory.tsv`):

```
tools/build_comp_libs.sh /tmp/comp-build                      # zlib + lz4, ~12 s
COMP_PREFIX=/tmp/comp-build tools/build_erofs_local.sh /tmp/erofs
export FSCK=/tmp/erofs/fsck.erofs MKFS=/tmp/erofs/mkfs.erofs

# 1) drzewo /system z obrazu HyperOS (EROFS czyta fsck, nie trzeba montowac)
$FSCK --extract=/tmp/tree/system_src system.img    # uwaga: --extract tworzy
#    sciezki wzgledem korzenia partycji; katalog 'system_tree' nazywa sie tak samo
#    jak w buildzie CI, wiec nie uzywaj 'tar --strip-components=2' (docs/06 §6.12)

# 2) macierze VINTF poziomu 4/5/6, ktorych w zrodle nie ma (bez nich init TB350FU moze padnac)
for L in 4 5 6; do python3 tools/make_level_matrix.py --from-dir /tmp/tree/system_src/system/etc/vintf \
      --level $L --out /tmp/tree/system_src/system/etc/vintf/compatibility_matrix.$L.xml; done

# 3) /product: fonty (+ opcjonalnie RRO) i dopelnienie sciezek, ktorych szuka system
$FSCK --extract=/tmp/tree/product --path=fonts  product.img
$FSCK --extract=/tmp/tree/product --path=overlay product.img     # tylko dla wariantu -full
tools/enrich_product.sh --src product.img --tree /tmp/tree/product

# 4) budowa + weryfikacja (fsck + 1:1 na kazdym wpisie) + vbmeta + instalator
tools/make_release.sh --product-tree /tmp/tree/product --system-tree /tmp/tree/system_src \
  --compress lz4hc,9 --exclude-regex '\.komentarz\.txt$' \
  --avb <avbtool.py> --key <testkey_rsa2048.pem> --erofs-dir /tmp/erofs --out /tmp/release
#   --exclude-regex wylacza z PARTYCJI pliki-notatki generatora (*.komentarz.txt, 3 x ~400 B);
#   drzewo zostaje z notatkami, obraz jest o 4 096 B czystszy i bez nich w /system/etc/vintf

# 5) dowod, ze to TO SAMO
sha256sum /tmp/release/product_hyperos4_p11g2.img   # a961bec46085883d6d9c…
sha256sum /tmp/release/system_hyperos4_p11g2.img     # cf0b889d45a6bb4f6af3…
sha256sum /tmp/release/vbmeta_hyperos4_p11g2.img     # 9cf2e7e4e165687abe78…
# wariant -full: product da17ffcd20c0ab4e8d0d… (150 560 768 B; system i vbmeta jak wyzej)
```

`make_release.sh --selftest` przechodzi ten łańcuch na drzewie syntetycznym, więc narzędzia
można sprawdzić, zanim ruszy się prawdziwe obrazy.

## Co stwierdzil bieg CI `release-selftest` (35918777924, ubuntu-latest)

Trzy rzeczy, ktorych nie da sie ustalic z samego katalogu wydania i ktore zostaly zmierzone
na swiezej maszynie, 23 IX 2026:

1. **Narzędzia da się odtworzyć poza tym sandboxem**: `tools/build_comp_libs.sh` (zlib + lz4
   ze źródeł, bez pakietów `-dev`) i `tools/build_erofs_local.sh` (erofs-utils 1.8.2 bez
   autoconfu) budują się na czystym runnerze, a `mkfs.erofs` z tej budowy rozpoznaje `-zlz4`.
2. **Cała suite przechodzi tam, gdzie nie ma nic z `/tmp`**: `tools/test_release.sh`
   = 17 kontroli, w tym determinizm (dwa `mkfs` = identyczny plik) i testy negatywne.
3. **Weryfikacja nie jest samoobslugą**: obraz zbudowany *moim* `mkfs.erofs` zostal
   rozpakowany i porównany plik-po-pliku przez `fsck.erofs` **z pakietu Ubuntu** (trzeba
   `add-apt-repository universe` — bez tego apt milcząco nic nie dawał, a krok byl zielony).
   Krzyżowo: każdy obraz czytany każdym narzędziem.

Czego ten bieg **NIE** stwierdzil: ze obraz startuje na TB350FU. To nadal tylko poziom G
w `docs/07-jak-weryfikowac.md` i nikt go nie wykonal.

## Właściciel plików w partiach (korekta z 23 IX 2026)

Korzeń `/product` i `/system` ma `Uid: 0 Gid: 0`, try `0755`, a pliki `0644`/`0755` zgodnie z
drzewem — bo `make_release.sh` nadaje `--force-uid=0 --force-gid=0` (przełącznik `--owner`,
wpis w `build-info.txt`). Poprzednie wydanie dziedziczyło właściciela z drzewa i oba obrazy były
własnością uid 1001 (`radio`). Na `ro` nie dawało to zapisu, ale było błędnym DAC-iem i — ważniejsze
dla Ciebie — **uniemożliwiało odtworzenie moich sum na innej maszynie**, bo uid budującego wchodził
w bajty. Dlatego rozmiary zostały te same, a sha256 się zmieniły. docs/06 §6.19.

## Czym ten obraz różni się od źródła HyperOS (bez owijania)

1. **dobudowane macierze VINTF 4/5/6** (`compatibility_matrix.{4,5,6}.xml`) — w źródle ich nie
   ma, bo HyperOS celuje w poziom 7/8; przy `target_fcm_version` = 5/6 init nie dostałby
   w ogóle macierzy. Razem z nimi do partycji trafiły 3 pliki `*.komentarz.txt` (400 B, notatki
   generatora) — świadomie zostawione, bo dokumentują pochodzenie plików; usunięcie ich
   zmienia sha256 obrazu.
2. **`vbmeta` bez nadbitek AVB w obrazach** — `avbtool` 1.3.0 nie ma `fec`, więc
   `add_hashtree_footer` jest niemożliwe; stąd `Flags: 3` zamiast „zielonego" bootowania.
3. **`/product` jest mój, nie Xiaomi** — tylko fonty (+ RRO w wariancie `-full`). Pełny
   `product.img` Xiaomi ma 6 445 187 072 B; brakujących pozycji (`etc/aconfig_flags.pb`,
   `etc/fonts_customization.xml`, `etc/selinux/product_*.contexts`, `pangu/`) listę z
   liczbą odwołań masz w `diagnostics/product-refs.tsv`, a narzędzie `enrich_product.sh`.

## Awaria — kolejność, która istnieje naprawdę

**Krok 0, przed cokolwiek: zrób kopię `system`, `product`, `system_ext`, `vendor`, `odm` ze
swojego tabletu albo wyciągnij je z oficjalnego firmware Lenovo dla TB350FU.** Brzmi jak
biurokracja, a jest całym ubezpieczeniem: na Dysku leżą obrazy Lenovo `boot`, `vendor_boot`,
`vbmeta` — i ANI JEDEN stockowy `system`/`product` (te dwie pozycje na Dysku to HyperOS z
Xiaomi Pad 9 Pro Max, który nie ma tablicy partycji Twojego tabletu). Kto tego nie zrobi, ten
po awarii układa firmware z pobranej paczki zamiast wlać kopię.

Dalej, w tej kolejności — każda pozycja jest o jeden krok dalej od cegły:

1. **Tablet wisi, ale USB żyje** → przytrzymaj `zasilanie + ściszanie` ~20 s, aż wejdzie w
   fastboot/fastbootd (`fastboot devices` powinno go pokazać). Uruchom `bash rollback.sh`:
   przywraca on `vbmeta_a`/`vbmeta_b` z kopii, którą `flash-all.sh` zrobił PRZED nadpisaniem.
   To odkręca wyłączenie weryfikacji AVB, nie dotyka `product`/`system`.
2. **Przywróć kernel, jeśli go ruszałeś** — ten zestaw NIE flashuje `boot` ani `vendor_boot`,
   więc w normalnym scenariuszu ten krok jest zbędny. Jeśli mimo wszystko flashowałeś:
   `fastboot flash boot boot.img` (plik z Dysku, Lenovo).
3. **Nie licz na przełączenie slotu.** `flash-all.sh` wlewa `product` i `system` na OBA sloty —
   `fastboot --set-active=b` prowadzi do tego samego obrazu. To była cena za to, że flash tylko
   bieżącego slotu daje „flash OK, boot stop" po restarcie na drugi.
4. **Brak fastbootu w ogóle** → zostań na trybie **BROM/DA MediaTeka** (`mtkclient` albo
   SP Flash Tool z obejściem `auth` dla `mt6789`). Nie EDL — EDL to procedura Qualcomma, ten
   tablet go nie ma, i wpisanie go do checklisty byłoby obietnicą bez pokrycia (sprawdziłem,
   że sam tak miałem w trzech dokumentach do 23 IX 2026). Tej ścieżki NIE testowałem tutaj:
   wymaga drugiego komputera i kabla w trybie bootromu, więc traktuj ją jako kierunek, nie
   instrukcję.
5. **NIE robij `fastboot erase userdata`.** Nie daje nic, czego krok 1–4 nie da, a kasuje dane.

Jeśli po kroku 1 tablet wstaje na stock, to znaczy, że `product`/`system` wróciły z Twojej
kopii albo że w ogóle ich nie ruszałeś — w drugim przypadku to wciąż mój obraz, tylko bez
weryfikacji. Wtedy `bash device-probe.sh --release .` zanim spróbujesz ponownie.

## Czego NIE sprawdzono

**Bootalności.** Nic wyżej nie dowodzi, że tablet wstanie; `Flags: 3` wygasza komunikat
weryfikacji, więc awaria wygląda jak cisza. Ratunek: `rollback.sh` (przywraca stock `vbmeta`), stockowe obrazy Lenovo
(`boot`/`vendor_boot`/`vbmeta` — ID w `diagnostics/drive-inventory.tsv`), a na ostatecznosc
**tryb BROM/DA MediaTeka** (`mtkclient` albo SP Flash Tool z obejściem `auth` dla `mt6789`).
Nie ma tu EDL — to jest procedura Qualcomma, nie tego tabletu; wpisanie jej w checklistę
byłoby obietnicą, której nikt nie spełni. NIE testowałem jej w tym sandboxie.
Braki HAL-i, których vendor `mt6789` nie ma (audio AIDL, health, power, thermal — `docs/05`
§5.1), nie znikają przez obniżenie ich do `optional`: to usuwa blokadę startu, nie dodaje
implementacji.

<!-- ROZMIARY-KONTRAKT product_hyperos4_p11g2.img=75198464 system_hyperos4_p11g2.img=920047616 vbmeta_hyperos4_p11g2.img=4096 -->
<!-- tools/test_release.sh, sekcja Q, wywala FAIL jesli ktora kolwiek z tych liczb przestanie
     zgadzac sie z plikiem. Dzieki temu 'odswiezanie dokumentacji' nie moze zostawic przedawnionego
     rozmiaru (23 IX 2026: podmiana sum pomiedzy wariantami wlasnie to zrobila i nikt by nie
     zauwazyl, bo sekcja N patrzyla wtedy wyłącznie na sha256). -->
