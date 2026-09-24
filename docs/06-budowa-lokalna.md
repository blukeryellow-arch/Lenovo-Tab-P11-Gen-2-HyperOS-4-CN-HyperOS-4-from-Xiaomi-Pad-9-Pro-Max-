# 6. Budowanie ROM-u lokalnie — co było zamknięte i jak to obejść

Ten dokument opisuje fazę, w której ROM przestał być „opisem budowy w CI", a zaczął być
obrazem zbudowanym i sprawdzanym w sandboksie. Każdy akapit jest o czymś, co najpierw
**nie działało**.

## 6.1 Sieć: `codeload.github.com` działa, kiedy nic innego nie działa

Zmierzone tego dnia (kolejne `curl` na ten sam host, ta sama chwila):

| endpoint | wynik |
|---|---|
| `https://pypi.org/simple/` | 200 |
| `https://codeload.github.com/erofs/erofs-utils/tar.gz/...` | **200, 185 971 B** |
| `https://github.com/erofs/erofs-utils` | 200 |
| `git clone https://github.com/LineageOS/android_external_avb.git` | **UDANE** (bez kredensów) |
| `https://raw.githubusercontent.com/...` | 000 (TLS zrywane) |
| `https://git.kernel.org/...`, `https://mirrors.edge.kernel.org/...` | 000 |
| `https://dl.google.com/android/repository/`, `http://archive.debian.org/` | 000 |
| `https://drive.usercontent.google.com/download` | 000 (nie da się pobrać `product.img` 6,4 GB) |

Wniosek praktyczny: **źródła narzędzi są dostępne**, mimo że `apt`, mirror kernela i Google są
odcięte. Cała reszta tej sekcji bierze się z tego jednego faktu.

## 6.2 Brak autoconfu → `config.h` pisany ręcznie, przez co `mkfs.erofs` jednak jest

Sandbox miał `gcc`, `make`, `git`, ale nie miał `autoconf`, `automake`, `libtool` ani nagłówków
`-dev` (`lz4.h`, `zlib.h`, `uuid/uuid.h`). `autogen.sh` erofs-utils bez autoconfu nie istnieje.

Rozwiązanie (`tools/build_erofs_local.sh`): autoconf robi w gruncie rzeczy dwie rzeczy —
sonduje cechy i pisze `config.h`. Sondę robię gołym `gcc` (`probe()` w skrypcie), a `config.h`
składam z tego, co przeszło. Trzy pułapki, każda zjadała połowę godziny:

1. **Sonda musi użyć `(void)fnc`.** Z gołym `pread64;` jako zdaniem gcc widzi użycie
   niezadeklarowanego identyfikatora, więc 13 sond padło, `HAVE_MEMRCHR` nie trafiło do
   `config.h`, a kompilacja wywróciła się na `liberofs_private.h:16: static declaration of
   'memrchr' follows non-static declaration`.
2. **`-DHAVE_CONFIG_H` jest wymagane.** Źródła erofs includują `config.h` tylko pod tym
   `#ifdef`. Bez niego `config.h` istniał, ale nikt go nie czytał — stąd te same błędy
   i `PACKAGE_VERSION undeclared`.
3. **`HAVE_LINUX_TYPES_H` musi byc zdefiniowane**, bo `<linux/falloc.h>` ciągnie
   `asm/int-ll64.h` (`__u64` = `unsigned long long`), a `erofs/defs.h` bez tego makra
   typedefuje `__u64` = `unsigned long` → `conflicting types for '__u64'`.
   (Ironia: pierwsza reakcja „undef to" daje ten sam błąd od drugiej strony.)

Wynik: `mkfs.erofs`, `fsck.erofs`, `dump.erofs` 1.8.2 zbudowane i działające. (Uwaga z 2026-09-23: ten akapit był prawdziwy dla *ręcznego* builda, a nie dla skryptu — `build_erofs_local.sh` budował wprawdzie wszystkie trzy, ale selfcheck pilnował tylko `mkfs` i `fsck`, więc skasowanie `dump.erofs` dawało „już zbudowane" i `exit 0`. Naprawione: selfcheck patrzy na trzy binarki i na `--version` każdej.) Kompresji nie ma
(brak nagłówków) i to nie jest osłabienie: **CI dla tego samego obrazu też skończyło na wariancie
bez kompresji** (sonda flag odrzuciła `-O fragment…` w mkfs.erofs 1.9.4), a obraz bez kompresji
da się zweryfikować i przeszukać bez dodatkowych bibliotek.

## 6.3 Obraz `product.img`: budowany, nie opisywany — i sprawdzony round-tripem

```
mkfs.erofs -T 0 -U 67b7eb22-3ebb-4c21-8b01-8ff545f10d8d product.img <drzewo>
```

- rozmiar **87 973 888 B**, 65 inode'ów (63 pliki + katalog `fonts` + korzeń);
- `fsck.erofs` (upstream checker, nie mój parser) → rc 0, „No errors found";
- **round-trip**: `fsck.erofs --extract` wyciąga z mojego własnego obrazu 63/63 plików
  o identycznym sha256 ze źródłem, 87 940 740 B zwróconych;
- **determinizm**: dwa niezależne budowania dają identyczny plik
  (`d59e52cdf2fe1b79037963d6…`). Czyli *przepis* jest tak samo sprawdzalny jak *plik* —
  to jest jedyna sensowna odpowiedź na limit 100 MB/blob w tym kanale.

Zawartość: tylko `fonts/`. `product/etc/permissions` (12 plików) ** celowo poza obrazem**:
zero wpisów `<library>`, za to 467 zezwoleń priv-app dla pakietów, których na Lenovo nie ma
(`privapp-permissions-gms-cn-product.xml` = 176 poz.), plus dwie deklaracje `<feature>`
(`cn.google.services.xml`). To bagaż z ryzykiem, nie zależność.

## 6.4 Czego `system` z HyperOS naprawdę szuka w `/product` — pomiar, nie lista z wiki

`grep -ao '/product/[…]*'` po 1 376 899 072 B obrazu → tabela w
`diagnostics/product-refs.tsv` (60 wierszy). Najczęstsze: `etc` 54×, `pangu/` 18×,
`bin` 18×, `etc/passwd` 6×, `etc/fonts_customization.xml` 4×, `etc/selinux/product_*.contexts`
3–4×, `etc/aconfig_flags.pb` 2×, `etc/vintf/manifest.xml` 2×.

To jest lista *możliwych* braków minimalnego `/product`, więc `tools/enrich_product.sh`
dociąga dokładnie te ścieżki z pełnego `product.img` (6,4 GB, na Dysku użytkownika) — bez pakowania
6,4 GB do kanału. Narzędzie ma udokumentowaną semantykę `fsck.erofs --extract`, bo pierwsza
wersja kopiowała sobie nazwę katalogu docelowego jako nazwę pliku (efekt: `etc/x` zamiast
`etc/aconfig_flags.pb`):

| wywołanie | zachowanie (fsck.erofs 1.8.2, test A/B/C) |
|---|---|
| `--path=<plik> --extract=<katalog>` | **rc=1, nic nie wyciąga** |
| `--path=<katalog> --extract=<katalog>` | wyciąga **zawartość** katalogu do celu — bez prefiksu `katalog/`, ale z podkatalogami w środku (pomierzone na `overlay`: 12 katalogów zostaje katalogami) |
| bez `--path` | cały FS z ścieżkami (za drogie dla 6,4 GB) |

Stąd: wyciągamy katalog nadrzędny i kopiujemy liść. Test na syntetycznym EROFS: 5/11 ścieżek
odczytanych, 6 razy uczciwe „NIE MA w zrodle".

## 6.5 AVB: rezygnacja z nadbitek jest decyzją, nie porażką

- `avbtool` 1.3.0 (mirror LineageOS, klon bez kredensów) **odmawia `add_hashtree_footer`**:
  wywala się na `[Errno 2] No such file or directory: 'fec'` (generator korekcji błędów,
  którego tu nie ma i nie zbuduję bez bibliotek) oraz żąda `--hash_algorithm sha256`,
  a `--partition_uuid` w ogóle nie zna (to nowość 1.4.0).
- Sprawdziłem, czy obraz `system` z CI ma jakikolwiek footer: **nie ma** (ostatnie bajty to nie
  `AVB0`, a `info_image` na nim mówi „Given image does not look like a vbmeta image" — bo to
  payload, nie vbmeta). Skoro tak, to **spójne** jest wydać `product.img` też bez nadbitek i
  wyłączyć weryfikację w `vbmeta` (`Flags: 3`), zamiast udawać hashtree, którego nikt nie
  zweryfikuje.
- `vbmeta_hyperos4_p11g2.img`: Flags 3, SHA256_RSA2048, key `cdbb7717…` (= ten sam odcisk co
  fabryczna vbmeta TB350FU), **`rollback_index 0` — świadomie**. Pierwsza próba brała
  `1785542400` (indeks obrazu źródłowego). Licznik anty-rollback jest jednokierunkowy: jego
  podbicie mogłoby odciąć powrót do stockowego firmware Lenovo, którego indeks jest niższy.
  To jest dokładnie ten typ „działa, a potem nie ma odwrotu", którego nie chcę zostawic
  komuś innemu.

## 6.6 VINTF: sprostowanie liczby, na której stały wnioski

Wcześniejszy raport `vintf_diff.py --matrix <katalog 9 plików>` mówił
**„400 pozycji HAL, obowiązkowych 400, opcjonalnych 0"**. To był artefakt sumowania katalogu:
`VintfObject` wybiera **jedną** macierz frameworku wg `target_fcm_version` urządzenia, a poziom
nie lacza się w jeden zestaw. przy okazji zerowało `optional` (ten sam klucz widziany raz
w pliku obowiązkowych dawał `False and True`).

Pomiar na plikach wyciągniętych **z partycji** (`fsck.erofs --extract`):

| zestaw | pozycji | obowiązkowych | opcjonalnych |
|---|---|---|---|
| katalog 9 plików (suma — **nie tak czyta init**) | 400 | 400 | 0 |
| `--target-level 5` → `compatibility_matrix.5.xml` | 81 | **0** | 81 |
| `--target-level 6` → `compatibility_matrix.6.xml` | 81 | **0** | 81 |
| `--target-level 8` → `compatibility_matrix.8.xml` | 88 | 88 | 0 |

Dokładnie ta różnica (0 vs 88) jest sensem wstrzyknięcia plików na poziomie 4/5/6: TB350FU to
A12L, jego `target_fcm_version` wybiera plik level 5/6, a te pliki w naszym obrazie sa w pełni
opcjonalne. Dodane `--target-level` w `tools/vintf_diff.py` liczy to teraz tak, jak liczy init.

## 6.7 Czego **nie** robię, i dlaczego to jest decyzja, nie brak czasu

Nie pakuję „modułu naprawczego VINTF" (`/system/etc/vintf/*.xml` przez Magisk) jako ścieżki
ratunkowej dla osób, które wgrają HyperOS-owy framework. Mechanicznie plik by się namontował,
ale assembling macierzy, na którym `init` wstrzymuje start, dzieje się **wcześniej** niż
magic-mount Magiska (post-fs-data), więc moduł mógłby ratować `system_server`, a nie `init`
— a sprzedawanie murowanego efektu na tym mechanizmie byłoby zgadywaniem. Kto chce ruszyć
wymagania, ten regeneruje obraz (`tools/make_release.sh`), i to jest w `dist/release/`.

## 6.8 Co nadal NIE jest zweryfikowane

Bootalność. Nic powyżej nie dowodzi, że tablet wstanie: `Flags: 3` wyłącza komunikat weryfikacji,
więc awaria wygląda jak cisza. Ratunek: `dist/release/.../rollback.sh` (vbmeta z kopii wykonanej
przed flashem) + obrazy Lenovo z Dysku (`diagnostics/drive-inventory.tsv`); zapasowo tryb
BROM/DA MediaTeka (`mtkclient`/SP Flash Tool) — **nie EDL**, bo `mt6789` to MediaTek, a EDL jest
terminem i procedurą Qualcomma. Myliłem je w trzech dokumentach do 23 IX 2026.
Wymagania HAL-ów, których vendor `mt6789` nie ma (audio AIDL, health, power — `docs/05` §5.1),
nadal istnieją: obniżenie ich do `optional` usuwa blokadę startu, nie dodaje implementacji.

## 6.9 Weryfikacja 1:1 — i dlaczego „wszystkie pliki się zgadzają" nie znaczyło „wszystko"

Krok 4/6 w `make_release.sh` przez jakiś czas porównywał **tylko pliki** (`find -type f`).
Na drzewie `system` wyszło, co to znaczy: obraz ma 4 568 wpisów — 3 895 plików, **409
symlinków** i 264 katalogi. Sprawdzając same pliki, 409 linków (`/system/bin/sh` → itd.,
linki `../` w `system/etc`, wiszący `adb_keys`) mogłoby zniknąć, a tester powiedziałby
„round-trip OK". Pierwsza próba pełnego porównania padła zresztą na `FileNotFoundError`
właśnie na `adb_keys`: to wiszący symlink, którego `os.walk` nie odrzuca.

Dlatego jest `tools/verify_image.sh`: wyciąga obraz `fsck.erofs --extract` i porównuje
**każdy wpis**: plik po sha256, symlink po `readlink`, katalog po istnieniu. Wyniki:

| obraz | wpisy | zgodne | rozbieżne |
|---|---|---|---|
| `product` (fonty, lz4) | 64 | 64 | 0 |
| `product-full` (fonty + 67 RRO, lz4) | 144 | 144 | 0 |
| `system` (lz4) | 4 568 | **4 568** | **0** |

i ten sam sprawdz jest teraz wbudowany w `make_release.sh` (krok 4/6 + weryfikacja
systemu po zbudowaniu z drzewa — nie ufałem samemu `rc=0` z `mkfs`).

## 6.10 Kompresja: utracone 409 MB i jak je odzyskać bez `apt`

Przez większą część tego projektu `system.img` miał **1 376 899 072 B**, podczas gdy
źródłowy obraz HyperOS — **937 791 488 B**. Podejrzenie było takie, że to mój format
jest gorszy. Pomiar paddingu blokowego na drzewie product dał **32 124 B na 87,9 MB
(0,0 %)**, więc nie padding.

Różnica robi się oczywista, gdy doczytać, że `mkfs.erofs` z `build_erofs_local.sh` był
zbudowany **bez `HAVE_LZ4`/`HAVE_ZLIB`** — bo w sandboksie nie ma `-dev`-pakietów, a `apt`
nie działa. Czyli: nie miałem kompresora, a HyperOS pakuje EROFS+lz4. `rom/BUILD_LOG.txt`
dokumentuje zresztą, że CI też się o to potknęło: `mkfs.erofs: invalid option -- 'O'`
→ „wariant z opcjami nie wszedł - próbujemy domyślnie" → i stąd 1,38 GB.

Obejście: `tools/build_comp_libs.sh` buduje `zlib 1.3.1` i `lz4 1.10.0` ze źródłów z
`codeload.github.com` (12 sekund, bez autoconfu: `configure` zlibu to zwykły shell-skrypt,
lz4 ma `Makefile` w `lib/`), a `build_erofs_local.sh` sonduje je przez **linkowanie**
(`probe_lib`), nie przez sam nagłówek — bo `configure.ac` erofs robi `AC_CHECK_LIB`
+ `AC_CHECK_DECL`, a pierwsze wydanie tej sondy zapomniało `-lz -llz4` i wszystkie trzy
binarki padły na `undefined reference to 'gzerror'` w `tar.c`.

| przypadek (drzewo 1 376 006 579 B) | bajty obrazu | wobec źródła |
|---|---|---|
| `system` bez kompresji (jak z CI) | 1 376 899 072 | +46,8 % |
| `system` z `-zlz4` (moja budowa) | **967 507 968** | **+3,2 %** |
| `system` źródłowy (HyperOS) | 937 791 488 | — |

Czyli mój obraz jest o 3,2 % większy niż oryginalny — tyle, ile wynosi różnica między
`lz4` a opcjami, których HyperOS użył dodatkowo (dopasowanie `max_pcluster` itd.).
To dowód, a nie wymówka: **źródło jest spakowane lz4**, więc lz4 jest tu formatem
rodzimym, a nie moją fanaberią. Na product: 87 973 888 → 77 619 200 (`lz4`) →
75 198 464 (`lz4hc`).

**Ryzyko, które trzeba znać**: obraz z `-zlz4` wymaga `CONFIG_EROFS_FS_LZ4` w kernelu
**tabletu Lenovo** (to jego kernel zostaje w tej eksperymentalnej konfiguracji). Jeśli
go nie ma — mount padnie. Dlatego `--compress none` nadal istnieje i jest jedyną drogą,
która nie wymaga niczego ponad `EROFS_FS`. Sprawdzenie na urządzeniu:

```
adb shell 'zcat /proc/config.gz | grep -E "EROFS_FS(_LZ4)?="'      # albo /boot/config-…
```

## 6.11 Bramka rozmiaru partycji i atrapa `fastboot` jako narzędzie testowe

Rozmiar **slotu logicznego** w `super` zna tylko urządzenie — w fabrycznej vbmeta Lenovo
są rozmiary *źródłowych* obrazów (`product 2 748 350 464 B`, `system_ext 744 968 192 B`),
czyli co innego. `flash-all.sh` ma więc krok „5. czy obrazy mieszczą się w partycjach":
pyta `getvar partition-size:<part>_<slot>` dla obu slotów, porównuje z `stat -Lc%s` i
**przerywa przed pierwszym flaszem**, jeśli nie mieści. Jeśli `fastboot` nie zna tego
zapytania — ostrzega i idzie dalej (brak informacji nie może blokować flashowania).

Testowane na atrapie `fastboot` (`/tmp/fb2/bin/fastboot`, sterowana zmiennymi
`FB_SIZE_*`, `FB_SLOT`, `FB_USERSPACE`) — pięć scenariuszy:

| scenariusz | oczekiwanie | wynik |
|---|---|---|
| duże sloty (product 4 GB, system 64 GB) | 6 flashów, reboot | rc 0, 6 ✓ |
| `system` 768 MB (obraz 922 MB) | abort, „brakuje 155 MB" | rc 1, **0 flashów** ✓ |
| `product` wariantu `-full` 128 MB (obraz 146 MB) | abort | rc 1, 0 flashów ✓ |
| `product 0xA3B10000` (2 619 MB = rozmiar z vbmeta Lenovo) | przejdź, hex wielkimi literami | rc 0 ✓ |
| brak odpowiedzi na `partition-size` | ostrzeżenie + kontynuacja | rc 0, 6 flashów ✓ |

Trzy prawdziwe usterki, które ta atrapa złapała — po mojej stronie, nie po stronie sprzętu:
1. `stat -c%s` na **symlinku** zwraca długość ścieżki, nie rozmiar pliku → bramka widziała
   `need=0` i przepuszczała nawet 1,38 GB na partycję 768 MB → teraz `stat -Lc%s`;
2. `$(((need-have)+1048575)/1048576)` to dla basha **podstawienie polecenia**, nie
   arytmetyka → komunikat „brakuje  MB" (pusto) → spacja po `$((`;
3. warunek `*[!0-9]*` odrzucał każdy rozmiar z prefiksem `0x` (bo w nim jest `x`) →
   najpierw odejmij prefiks, potem sprawdzaj cyfry.

## 6.12 Pułapka, którą sobie sam wykopałem: `tar --strip-components`

`tar xzf rom-kit.tar.gz --strip-components=2 -C /tmp/x` na ścieżkach `./system_tree/system_ext/`
skracza je do **zera** i takie katalogi po prostu znikają. Efekt: drzewo do `mkfs` miało
`system/` i `init.environ.rc`, ale **żadnego punktu montowania** (`product`, `system_ext`,
`vendor`, `odm`, `apex`, `metadata`, `mnt`, `dev`…) — obraz 922 MB, `fsck` czysty,
round-trip plików OK, a tablet by na nim nie zamontował nawet `/product`.
Stąd dwa rzeczy w procedurze: ekstrakcja z `--strip-components=1`, i **krok „parity korzenia"**
(40 ścieżek porównanych między moim obrazem a obrazem CI — wynik: 40 zgodnych, 0 rozjazdów).
Zapamiętać: *sprawdzanie, czy obraz jest poprawnym EROFS, nie sprawdza, czy jest poprawnym
systemem plików Androida*.

## 6.13 Notatki generatora poza partycją (`--exclude-regex`)

Drzewo `system`, które dostałem z kitu CI, zawierało 3 pliki `compatibility_matrix.{4,5,6}.komentarz.txt`
(405/400/400 B) — to notatki `make_level_matrix.py` o tym, że plik jest generowany, nie AOSP-owy.
W partycji `/system/etc/vintf` nie mają niczego do roboty, a `VintfObject` i tak czyta tylko
`*.xml`. `mkfs.erofs` ma `--exclude-regex`, więc: drzewo zostaje z notatkami (widoczne w gicie),
obraz jest ich pozbawiony.

Efekt pomierzony: `system` 967 507 968 → **967 503 872 B** (−4 096 B, dokładnie jeden blok),
liczba wpisów w weryfikacji 4 568 → **4 565** (pliki 3 895 → 3 892), a `verify_image.sh`
dostaje te same wykluczenia (`--exclude`), żeby nie krzyczeć „brak w obrazie" na tym, co
celowo wylatuje. Dowód, a nie obietnica: `fsck.erofs --extract --path=system/etc/vintf`
na obrazie z tamtej budowy zwraca 11 plików i zero `komentarz` (dziś wariant lekki trzyma
tam 6 plików).

Lekcja przy okazji: `mkfs.erofs -C <rozmiar>` (większe pcluster) pozwala dobijać rozmiar
jeszcze niżej, ale grandes pclusters wymagają `EROFS_FEATURE_INCOMPAT_BIG_PCLUSTER` w kernelu —
a tu zostaje kernel Lenovo. Nie ryzykuję montowania partycji startowej dla kilku megabajtów.

## 6.14 Dwie rzeczy, które wyszły przy sprawdzaniu własnego tekstu

**a) `fsck.erofs` abortuje na sciezce „o jeden poziom za gleboko".** Na obrazie `system`:

```
--extract=X --path=system/product            -> rc=1  (uczciwie: nie ma takiego wpisu)
--extract=X --path=system/product/overlay    -> SIGABRT, rc=134, zero komunikatu
```

Czyli ta sama nieistniejaca sciezka, ale glebiej o szczebel, konczy sie `Aborted` zamiast
kodu bledu. Dla mnie to nie ciekawostka: kazdy skrypt, ktory pyta `fsck --path=…` i
podejmuje decyzje po kodzie wyjscia, musi traktowac **kazdy** wynik inny od zera jako
„nie ma/odmowa", nie tylko `1`. `tools/enrich_product.sh` i `make_release.sh` tak robia
(`if … && [ -e … ]`), `verify_image.sh` w ogole nie uzywa `--path` (berze caly FS) - stad
zadna z tych awarii nie mogla przeoczyc bledu. Zgloszone tutaj, bo to jest zachowanie
narzedzia, nie moje: nie buduje sie na tym skryptu „sprawdz, czy plik istnieje w obrazie".

**b) Nie wolno pisać do README zdania, którego się nie zmierzyło.** W README było
„67 RRO w `/system/…`" — fałsz, wryty dlatego, że skoro brałem te nakładki z
`product.img`, założyłem, iż CI włożył je również do `system`. Pomiar mówi co innego:
`system/product` w tym obrazie nie istnieje (rc=1), za to `system/etc/permissions`
istnieją (27 plików, 110 965 B). Konsekwencja jest odwrotna, niż myślałem: montując
własny `/product` **niczego nie przykrywam** — wariant lekki nie „kasuje" HyperOS-owego
wyglądu, bo ten w `system` nigdy nie był; `--full` go dokładnie dokłada. Koszt pomiaru
to dwie minuty, a koszt założenia — cały akapit do wyrzucenia.

## 6.15 Dwie pozycje z listy „życzeń systemu" jednak dostały treść — a jedna nie

Pomiar (`diagnostics/product-refs.tsv`) mówił: `/product/etc/passwd` 6×, `/product/etc/group` 6×,
`/product/etc/vintf/manifest.xml` 2× (oraz `/product/etc/vintf/manifest/` 2× jako katalog).
Wcześniejsza decyzja brzmiała: „nie da się bez paczki 6,4 GB". Dla dwóch z tych pozycji to był
błąd — te pliki w AOSP mają treść **z góry wiadomą**, nie „xiaomiową" do wyjęcia z obrazu:

```
etc/passwd:  system:x:1000:1000:system:/none:/bin/false
etc/group:   system:x:1000:
```

Dorzucone do obu wariantów. Efekt, którego nie oczekiwałem: **rozmiar obrazu ani drgnął**
(77 619 200 B i 153 391 104 B), bo 58 B weszło w bloki, które i tak były wolne; zmieniło się
tylko sha256. Żadne z tamtych „kwitów" nie jest już aktualne — sumy przepisały później korekta
DAC (§6.19) i przejście na `lz4hc,9` (§6.23), a żywy rejestr kwot trzyma `docs/07`, nie ta
sekcja. Weryfikacja 1:1 wyszła 67/67 i 147/147, więc pliki są w partycji, nie tylko w drzewie —
sprawdzone `fsck.erofs --extract --path=etc`.

**`etc/vintf/manifest.xml` pomijam świadomie** i to jest decyzja cenniejsza niż samo dodanie.
Brak pliku jest dla `VintfObject` stanem normalnym (partycja bez manifestu = zero nowych
żądań), a plik *sformatowany o włos źle* albo *ogłaszający coś, co już jest ogłoszone* to
zupełnie inna kategoria ryzyka. Pierwsza wersja, którą napisałem, miała być „pusta", a zawierała
`android.hidl.manager` — czyli dokładała deklarację HAL-a i mogła dać `multiple instances` przy
assemblingu macierzy. Asymetria jest pełna: zysk = usunięcie odwołania, które i tak jest
opcjonalne; strata = boot, którego nie da się zdiagnozować bez serialu. Więc: nie.

Nie dorzucam też `etc/selinux/product_*.contexts` ani `etc/aconfig_flags.pb` w wersji „niech
będą puste". Pierwsze muszą mieć **właściwe etykiety SELinux** (wynikają z `file_contexts`
urządzenia, nie z mojego widzimisię) i realną treść policy — pusty plik w tym miejscu nie jest
„mniejszym złem", tylko nowym stanem, którego nikt nie testował. Drugie to protobuf ze flagami
czasu uruchomienia, więc zgadywanie zmieniłoby zachowanie frameworku. Oba można wziąć wyłącznie
z prawdziwego `product.img` — do tego służy `tools/enrich_product.sh`, tak jest opisane w jego
nagłówku i tak zostanie.

## 6.16 `tools/test_release.sh` — i dwa błędy, które znalazł w dniu, w którym powstał

Do tej pory „sprawdzone" znaczyło „agent uruchomił właściwe polecenia właściwej kolejności".
To nie jest własność, którą da się przenieść na inną maszynę, więc łańcuch kontroli trafił do
skryptu: `bash tools/test_release.sh [--erofs-dir KATALOG] [--real]`. Bez `--real` działa na
drzewach syntetycznych (sekundy, zero zależności od 1,4 GB), z `--real` dokłada weryfikację
1:1 wydanych obrazów i spójność `SHA256SUMS.txt` / `release-manifest.tsv`.

Co testuje: `make_release --selftest`, determinizm (dwa `mkfs` = identyczny plik),
**test negatywny weryfikatora** (drzewo ma plik, którego nie ma w obrazie → musi być FAIL
i wskazanie nazwy), symlinki (zmiana celu linka musi być wykryta), bramkę rozmiaru
na atrapie `fastboot` w pięciu scenariuszach (E–I) i — w `--real` — oba wydania.

Dwa błędy, które ten skrypt znalazł **w dniu, w którym go pisałem**, oba po mojej stronie:

1. **`SHA256SUMS.txt` obejmował `README.md`.** Po przebudowie wydania poprawiłem jedno zdanie
   w dokumentacji i `sha256sum -c` w katalogu przestało przechodzić — czyli redakcja tekstu
   „unieważniała" wydanie, a `flash-all.sh` (który zaczyna się od tej bramki) odmówiłby
   flashowania. Rozwiązanie: `*.md` jest wyłączone z sum (ładunek = to, co leci na urządzenie),
   a fakt jest opisany w README, żeby nikt nie uznał tego za dziurę.
2. **Test `--real` podstawiał lekkie drzewo do wariantu `-full`.** Efekt: 67 nakładek RRO
   wyglądało jak „DODATKOWE wpisy w obrazie", czyli jak usterka wydania, a była usterka testu.
   Po naprawie: 24 PASS / 0 FAIL (product 67/67 i 147/147, system 4 565/4 565 w obu wariantach).

Warto to zapisać jako lekcję metodologiczną: test, który nigdy nie zawodzi na poprawnych
danych, nie dowodzi niczego — dlatego w suite jest celowe psucie obrazu (test C) i podmiana
symlinka (test D). To one pokazały, że poprzedni „round-trip" patrzył tylko na pliki.

## 6.17 Co właściwie dowodzi, że `lz4` jest bezpieczne — i gdzie granica tego dowodu

Pierwszy pomiar, który zrobiłem, był fałszywie pocieszający i warto go opisać, bo taka pułapka
czai się w każdym „sprawdziłem": w drzewie testowym leżał **losowy** 300 KB plik, więc `-zlz4`
nie zbijał nic (2 191 360 B → 2 191 360 B) i `fsck` zbudowany **bez** `HAVE_LZ4` zgłaszał sukces.
Wniosek „kompresja nic nie daje, a stary build i tak czyta" byłby wtedy błędem na całe wydanie.
Dopiero dane podatne na kompresję (4 MB powtarzalnego tekstu) dały 2 191 360 → 217 088 B i
odmowę starego `fsck` przy `--extract` (`Failed to extract filesystem`).

Rozstrzygający jest jednak nie `fsck`, tylko **superblock** wydanego obrazu:

```
Filesystem incompatible features:      lz4_0padding
Filesystem lz4_max_distance:           65535
Required upstream Linux kernel version: 5.4
Filesystem compressed files:           2738      Filesystem uncompressed files: 1828
Filesystem total original file size:   1 376 005 374 B   (obraz: 967 503 872 B = -29,7 %)
```

To jest dowód o klasę mocniejszy niż test odczytu: `lz4_0padding` jest w **`incompatible`**
features, więc kernel bez `CONFIG_EROFS_FS_LZ4` nie „pokaże błędu przy czytaniu pliku" — on
**odmówi zamontowania** całego `/system`. I ta sama tabela pokazuje drugą stronę medalu: liczniki `compressed`/`uncompressed` obejmują
**wszystkie inode'y** (2 738 + 1 828 = 4 566 = 4 565 wpisów + korzeń tamtego obrazu — katalogi
i symlinki lądują w `uncompressed`, bo nie mają czego kompresować), więc obraz nigdy nie jest
„w całości skompresowany" i porównywanie go z `gzip -9` nie ma sensu.
Druga, przykra strona: `fsck.erofs` **bez** `--extract` sprawdza tylko metadane i dlatego zwraca
rc=0 na obrazie, którego nie umie rozpakować. Ktokolwiek będzie kiedyś wnioskował o obsłudze
kompresji z „`fsck` przeszedł" — nie przeszedł w tym sensie, co trzeba. Trzeba `--extract`
albo `dump.erofs -s`.

**Czego ten pomiar NIE dowodzi** i nie będę tego zapisywać jak dowodu: że *urządzenie*
zmontuje mój obraz. Twierdzenie „źródłowy `system.img` Lenovo też jest lz4, więc kernel
TB350FU umie lz4" opieram na dwóch poszlakach — stosunku rozmiarów (937 791 488 B źródła
vs 1 376 899 072 B mojego buildu bez kompresji) i `rom/BUILD_LOG.txt` z bieżni CI — a nie na
zrzucie superblocku źródła, bo plik `rom/system_hyperos4_p11g2.img` (1,4 GB) usunąłem z
workspace'u, żeby starczyło miejsca na build. Zrzut jest do powtórzenia jednym poleceniem na
świeżej ekstrakcji (`dump.erofs -s`) i to jest pierwsza rzecz, którą zrobi każdy, kto będzie to
kiedyś weryfikował — dlatego jest wpisane do `docs/07` jako test, nie jako przypis.
Jeśli źródło okazałoby się `lz4hc` albo miało starszy zestaw feature, mój obraz nadal się nada
(jest samoistnie spójny), ale `--compress lz4hc` przestanie być fanaberią, a stanie się
opcją „bliżej oryginału".

Dlatego w wydaniu zostaje zdanie, które wcześniej brzmiało jak paranoja: sprawdź
`adb shell 'zcat /proc/config.gz | grep EROFS'` **przed** flashem, a `--compress none`
jest ścieżką awaryjną dla kernela bez `EROFS_FS_LZ4` (wtedy product rośnie ~1,5×, a `system`
przestaje się mieścić — patrz tabela w §6.10 i bramka w §6.11 — więc awaryjność tej ścieżki
też ma swój limit i to jest uczciwe zdanie na koniec sekcji).

## 6.18 Narzędzie, które złapało własnego autora trzy razy pod rząd

`tools/lint_pismo.py` pilnuje, żeby do wydania nie wchodziły znaki obcego pisma. Powstał,
bo trzy razy wplotem CJK i trzy razy tego nie widziałem: `\u62ff` w `docs/06`,
`\u5916\u90e8` w `scripts/build_overlay_apk.sh`, `\u4e0b\u6e38` w `.github/workflows/release-selftest.yml`.
Przyczyna za każdym razem była ta sama i **nie leżała w tekście, tylko w metodzie sprawdzenia**:
`glob.glob("**/*", recursive=True)` nie zagląda do katalogów zaczynających się od kropki,
czyli cały `.github/` był slepy. Narzędzie bierze listę plików z `git ls-files` — z tego, co
realnie trafia do wydania.

Trzy decyzje warte zapisania:

1. **Wyjątek jest zawężony co do pliku i co do znaku.** W `*.md` zezwalam wyłącznie na
   `\u2713 \u2717 \u2705 \u274c` (znaki stanu w tabelach). Nie „emoji wolno", bo wtedy
   wyjątek jest cały plik, a ma być cztery kod punktu. W `*.sh`/`*.py`/`*.yml`/`*.tsv`/`*.txt`
   zakaz jest pełny.
2. **Narzędzie nie zawiera tego, czego zabrania.** Pierwsze uruchomienie zgłosiło
   `tools/lint_pismo.py` — słusznie, bo w docstringu *zacytowałem* znaki, które były bugiem.
   Mógłbym dodać wykluczenie dla siebie. Nie dodałem: citat z CJK w pliku kontrolnym psuje
   kazde `grep -r` i byłby pierwszym wyjątkiem w pliku, ktory ma wyjątków nie mieć. Jest
   opis przez `\uXXXX`, a tresc pozostala.
3. **Binaria sa pomijane jawnie, z liczba w wyniku** („2 binarnych (pominiete)") — zeby
   „czysto" nigdy nie mogło znac „nie zajrzalem". To jest ta sama zasada, co test negatywny
   w §6.16: kontrola, ktora nie potrafi powiedziec, ze nic nie zrobila, kłamie.

Sprostonie mojego bledu proceduralnego z tego wieczora: commit `880a67a` oglosil
„Suite teraz: 17 kontroli", a w chwili pusha suite dawala **16 PASS / 1 FAIL** (wlasnie ten
punkt 2 powyzej). Nie poprawiam sily, bo commita już wypchnalem — zamiast tego jest tu, w
historii dokumentu, i to jest koszt własny: komunikat o sukcesie trzeba ogłaszac po
uruchomieniu, nie po napisaniu.

## 6.19 Obie wydane partie były własnością uid 1001 — jak to wyszło i dlaczego testy tego nie widziały

`mkfs.erofs` zapisuje w inode'ach właściciela **z drzewa**. Moje drzewa powstały z
`fsck.erofs --extract` odpalonego na koncie sandboxa (uid/gid 1001), więc 1001:1001 przeszedł do
obrazów i nikt nie protestował:

```
$ dump.erofs -s product.img | awk -F': *' '/root nid/{print $2}'   # -> 36
$ dump.erofs --nid=36 product.img | grep Uid:
  Uid: 1001   Gid: 1001  Access: 0755/rwxr-xr-x        # blednie, powinno byc 0:0
```

To jest **jedyny błąd w tym projekcie, który zmienił coś w obrazie, a nie zmienił żadnego
pomiaru**. Trzy rzeczy, które trzeba tu nazwać po imieniu:

1. **Ekstrakcja nie jest lustrem własności.** `fsck.erofs --extract` jako zwykły użytkownik nie
   wykona `chown` i dostanie uid *wyodrabiającego*, nie obrazu. Pierwszy wniosek, jaki wyciągnąłem
   z takiego pomiaru, brzmiał „`--force-uid` nie działa" — fałsz. Własność czyta się z
   `dump.erofs --nid`, a ekstrakcja z `chown` wymaga roota (i wtedy działa: `sudo` potwierdziło
   1001 na wadanym obrazie i 0 na poprawionym).
2. **„Deterministyczne 3/3" nie znaczy „niezależne od hosta".** Mój test determinizmu porównywał
   dwa budowania na *tej samej* maszynie, więc dziedziczony uid był w obu taki sam i kontrola była
   ślepa na całą klasę błędu. Właściciel partycji systemowej musi być **normowany**, nie
   dziedziczony.
3. **Nie mam `--fs-config-file`.** AOSP normalizuje DAC właśnie przez `fs_config`; w mojej budowie
   tej opcji nie ma (brak pliku źródłowego w tarballu 1.8.2, więc `#ifdef` nigdy się nie załaczył),
   a jest `--force-uid/--force-gid` — i one wystarczają do korzenia sprawy: `0:0` dla wszystkiego
   + `mode` z drzewa (try krążą wiernie, nawet `4755`).

Zaimplementowane w `tools/make_release.sh`: `--owner UID:GID` (domyślnie `0:0`) i
`--keep-host-owner` (wyłącznie do pomiaru, bo dowodzi, że bez flagi wada wraca). Ustawienie trafia
do `build-info.txt` (`wlasciciel_w_obrazie`), a `verify_image.sh --expect-owner` pilnuje go w
środku builda (krok 4/6) — przy braku `dump.erofs` build **mówi**, że DAC nie został zmierzony,
zamiast milcząco przepuszczać. Suite ma sekcje M (M1: z flagą jest 0; M2: bez flagi jest uid hosta;
M3: weryfikator odrzuca zły obraz; M4: akceptuje dobry) i L (podmiana `mode` w drzewie musi byc
wykryta przy identycznej treści pliku).

Po przebudowie rozmiary są **identyczne** (77 619 200 / 153 391 104 / 967 503 872), zmieniły się
sha256: product `298ada60…`, product `-full` `b4bb8064…`, system `5cf58995…` w obu wariantach.
`vbmeta_hyperos4_p11g2.img` ma **tę samą** sumę `9cf2e7e4…` i to jest poprawne: zawiera tylko
Prop fingerprint (bez deskryptora HASHTREE), więc nic w niej nie zależy od treści partii — patrz
`docs/07` sekcja F, gdzie prostuję własne wcześniejsze zdanie o „drzewie haszy dla producta".

## 6.20 Trzeci raz ta sama patologia: kontrola, która nie mówi, ile razy coś sprawdziła

Lista zdarzeń z jednego dnia, w których check istniał, był zielony i **nie patrzył na nic**:

| # | co miało sprawdzać | dlaczego było martwe | jak sie wydalo |
|---|---|---|---|
| 1 | symlinki w `verify_image.sh` (sekcja D) | test szukał `ZGODNE` w `tail -3`; dołożenie bloku DAC wypchnęło tekst z okna | fail przy zdrowym obrazie (na szczęście *widać* było) |
| 2 | sumy w dokumentach (`--real`) | regex `([0-9a-f]{8,16})…`, a README cytuje 20 znaków → zero linii dopasowanych | **PASS przy nieaktualnych sumach** — cicho |
| 3 | ta sama kontrolka po raz pierwszy | `docs/*.md` poza invariantem (cytuje sha modułu `.apk`/`.zip`) | fail na dokumentach, które miały rację |

Wypadek 2 jest najgroźniejszy z całej trójki, bo *nikt nic nie zobaczył*: nieaktualne
`8dcc73f2…` i `498d85c4…` (product i system sprzed korekty DAC) świeciły w README, a kontrolka
donosiła „dokumenty cytują istniejące sumy". Dlatego sekcja N ma dziś asercję, która nie dotyczy
wyniku, tylko **wysokości zainteresowania**:

```python
if total_seen == 0:
    print("  BRACK: zadna suma nie zostala przeanalizowana - kontrola jest martwa, nie zielona")
    ok = False
else:
    print(f"  (przeanalizowane sumy w dokumentach wydania: {total_seen})")
```

Reguła, którą z tego zostawiam: **każda kontrola w tym projekcie ma wydrukowac, ile elementow
przejrzala** (`67 wpisów`, `2738 plikow skompresowanych`, `przeanalizowane sumy: 7`). Zero albo
brak takiej liczby to wynik podejrzany, nie sukces. Wersja testowa tej zasady: kontrola musi
przechodzic **po wmieszaniu błędu** — i to jest jedyny sposób, żeby odróżnić „sprawdzone" od
„nic nie było do sprawdzenia". `tools/test_release.sh` robi to dla weryfikatora (C, L, M3)
i teraz także dla samej siebie (test negatywny N: wbitie `deadbeef…` daje FAIL, usuniecie — 0).

## 6.21 `--compress none` byl sciezka, ktora nie istniala — naprawione, i teraz zmierzone

README wydania od dawna radzil: „jesli Twoj kernel nie ma `EROFS_FS_LZ4`, zbuduj z
`--compress none`". Zdanie bylo uczciwe co do intencji i **nieprawdziwe co do skutku**: taka
budowa padala na linku, bo `build_erofs_local.sh` przy braku `zlib` wykluczal
`compressor_deflate.c`, `kite_deflate.c` i `gzran.c` — a te pliki SAME mają
`#ifdef HAVE_ZLIB` w środku i ścieżkę zapasową, natomiast `lib/compressor.c:33` woła
`&erofs_compressor_deflate` **bez warunku**. Efekt: `undefined reference` i `FATAL`, czyli
rada „awaryjna" byla niedostepna dokladnie wtedy, gdy ktos jej potrzebowal.

Poprawka: przy braku `HAVE_ZLIB` wykluczamy tylko `compressor_libdeflate.c` (ten naprawde
wymaga biblioteki), a `lz4` wykluczamy dalej — `compressor_lz4.c` include'uje `lz4.h` bez
guardu i to jest jedyny plik, ktory wolno wyciac. Zasada, ktora z tego zostaje:
**„nie mam biblioteki" to nie to samo co „ten plik nie ma byc skompilowany"** — najpierw
sprawdz, czy plik sam sie nie strzeze, bo wykluczenie go psuje link, a nie naprawia.

Zmierzone po poprawce (23 IX 2026, obie sciezki na tej samej maszynie, `COMP_PREFIX` wskazujace
pusty katalog vs `/tmp/comp-build`):

| budowa | `-zlz4` | obraz drzewa 1 588 894 B (dane podatne) | `fsck` wlasnego obrazu |
|---|---|---|---|
| bez `zlib`/`lz4` | **rc=1 — odmowa** (zgodnie z §6.10) | 1 806 336 B (bez kompresji) | rc=0 |
| z `zlib`+`lz4` | rc=0 | 237 568 B | rc=0 |

I rzecz, ktora liczy sie dla Ciebie najbardziej: **ta nowo skompilowana budowa odtwarza
wydany `product.img` bajt w bajt** (`298ada607150d3f71099…`, `cmp` bez roznicy), tak samo jak
dwa wczesniejsze, niezalezne kompilacje (`cb1d5940…` na tym samym drzewie bez `--exclude`).
Czyli `odtworzenie bit w bit` nie jest tu haslem, tylko poleceniem do wpisania:

```
mkfs.erofs -T 0 -U 67b7eb22-3ebb-4c21-8b01-8ff545f10d8d -zlz4 \\
           --force-uid=0 --force-gid=0 --exclude-regex '\.komentarz\.txt$' \
           out.img <drzewo-product>
```

Kolumna „1 806 336 vs 237 568" dotyczy drzewa syntetycznego z tekstem powtarzalnym — na
prawdziwym `/system` roznica jest inna i zmierzona osobno: 1 376 899 072 B bez kompresji vs
967 503 872 B z `lz4` (+42 % zamiast −85 %). Nie mixuj tych dwoch liczb, bo primera jest
dowodzie, ze lz4 dziala, a druga tym, ile miejsca zostaje na partycji.

## 6.22 `device-probe.sh`: decyzja przed flashem jest częścią wydania, nie moją notatką

Warunki wstępne (§6.10 kernel, §6.11 rozmiary slotu) żyły do dziś wyłącznie w dokumentach,
których nikt nie czyta w połowie nocy, zanim wpisze `flash-all.sh`. Od tej wersji budowanie
wydania dołącza `device-probe.sh` (kopia z `tools/`, wpisywana do `release-manifest.tsv`
i `SHA256SUMS.txt` jak każdy ładunek), a README każe go uruchomić jako krok 0. Skrypt tylko
czyta: `fastboot getvar` + `adb shell`, zero zapisów, zero montowań. Werdykt ma trzy stany i
kody wyjścia: `0` GO (także „GO z zastrzeżeniami"), `2` NO-GO, `1` brak urządzenia w fastboot.
Testowane sekcją P w `tools/test_release.sh`: osiem scenariuszy plus dwa sprawdzające, że
odmowa **cytuje powód z liczbą**, a nie jest samotnym kodem wyjścia.

Co przy pisaniu tego wyszło — wszystko złapane przez atrapę, nic przez patrzenie w kod:

| usterka | co by dala na żywym urządzeniu |
|---|---|
| parser przyjmował `cokolwiek przed dwukropkiem` | `product=0.001s` z linii `OKAY`, czyli `[OK ]` przy zerowym odczycie |
| `getvar` czytany tylko ze stdout | puste odpowiedzi (fastboot pisze je na **stderr**) i samo `[UW]` |
| zapytanie `partition-size:systema` (bez `_`) | bramka rozmiaru, która nigdy nic nie zmierzyła, ale grzecznie ostrzega |
| `go()` bez `GO=$((GO+1))` | werdykt „kontrol OK: 0" przy ośmiu udanych kontrolach |
| `"$part_$slot"` pod `set -u` | bash czyta `part_` jako nazwę → `unbound variable` → wyjscie `1` zamiast `2` |

Wnioski do zapamiętania są dwa i oba są o formie komunikatu, nie o logice. Pierwszy: **brak
pomiaru nie może wyglądać jak sukces** — dlatego `toparse` zwraca błąd zamiast zera, a
nieznane `partition-size` idzie jako `[UW]`, nigdy jako `[OK]`. Drugi: licznik w podsumowaniu
musi być **inkrementowany w funkcji drukującej**, bo licznik inkrementowany „w miejscach,
gdzie pamiętałem" pokazuje 0 i nadal mówi „GO".

## 6.23 Wydanie jest na `lz4hc,9`: 45,3 MiB zapasu za 14 sekund budowania

Decyzja z 23 IX 2026 wieczorem. Zmierzone na **tym samym** drzewie `system` (surowe
1 376 899 072 B, 3 892 pliki + 409 symlinków + 264 katalogi), ta sama kompilacja
`mkfs.erofs`, te same flagi (`-T 0`, UUID, `--force-uid/gid=0`, `--exclude-regex`):

| kompresja | rozmiar obrazu | vs surowe | czas `mkfs` na 1,37 GB | wymagane bity on-disk |
|---|---|---|---|---|
| `-zlz4` (bylo) | 967 503 872 B | −29,7 % | 11 s | `compat: sb_csum mtime`, `incompat: lz4_0padding` |
| `-zlz4hc,9` (jest) | 920 047 616 B | −33,2 % | 25 s | **identyczne** |
| bez kompresji | 1 376 899 072 B | 0 % | ~7 s | `compat: sb_csum mtime`, `incompat: (brak)` |

Zysk: **47 456 256 B (45,3 MiB, 4,9 %)** na `system` i 2 420 736 B na `product` — razem
49 876 992 B (47,6 MiB) mniej do wgrania. Wariant `-full` zyskuje 2 830 336 B.

Dlaczego to jest darmowe, a nie „tansze na jakims wymiarze": **identyfikator algorytmu na
dysku zostaje ten sam**. `lib/compressor.c` w erofs-utils wpisuje
`{ "lz4hc", &erofs_compressor_lz4hc, Z_EROFS_COMPRESSION_LZ4, true }` (linie 21–22) —
`hc` oznacza tylko mocniejsze naprezenie kompresora przy budowie, kernel widzi zwykly `lz4`. `dump.erofs` obu
obrazow zwraca ten sam zestaw bitow, a `tools/verify_image.sh` przechodzi na obrazie `hc`
**4565/4565 z hashy 1:1 plus DAC 0:0**, wiec dekompresja nie gubi zawartosci. Placimy
wyłącznie czasem budowy i miejscem w głowie: `--compress lz4` zostaje w drabince, a
`flash-all.sh` teraz wypisuje wszystkie trzy liczby, zamiast radzić jedną.

Reguła, którą z tego wyciągam: **jeśli partycja jest wąskim gardłem, najpierw szukaj free
zapasu w parametrach, ktore nic nie kosztuja na urzadzeniu, dopiero potem ruszaj
`super`/tabele partycji** (to drugie dotyka `/data` i jest nieodwracalne).

## 6.24 Dwa bledy, ktore sam sobie zrobilem w tej turze — i ktore nie sa bledami w obrazie

1. **`No space left on device` udawało awarię formatu.** Drugi bieg `lz4hc` skonczył sie
   `Assertion '!(__erofs_bflush(...))' failed` i `Aborted`, a pierwszy — `FATAL: system.img
   NIE przechodzi weryfikacji 1:1`. Oba miały tę samą przyczynę: /tmp wypchany czterema
   kopiach obrazu po ~1 GB (`df`: 21 G użyte, 0 wolne). Pierwsza reakcja powinna byc
   `df -h`, nie „narzędzie jest zlej wersi". Obie pomylki kosztowalyby mnie odwolanie
   slusznego wyniku, gdybym zalac komentarz do dokumentacji zamiast spojrzec w `mkfs.log`.
2. **Automatyczna podmiana liczb w dokumentach przemapowala `product` miedzy wariantami.**
   Skrypt `old->new` kluczujac po *nazwie pliku* wstawil do lekkiego README sume `product`
   z `-full` i pozostawił martwy `b4bb8064…` w trzech plikach. Klucz musi byc pelnym sha,
   nie nazwą — poza tym dokumenty historyczne (`docs/06`) w ogole nie powinny byc dotykane
   przez taka podmianke, bo tam liczby sa **pomiarami**, a nie stanem wydania. Cofnalem
   dokumenty do `HEAD` i zrobilem podmiane parami jawnymi z asercjami trafien. Reguła:
   automat edytujacy dokumentacje musi miec zakresem *pliki biezacego stanu* i mapa po
   pelnym identyfikatorze; inaczej 'odswiezanie sum' produkuje dokument ladniejszy i
   glupszy niz poprzedni.

## 6.25 Kontrakt rozmiarów: nie „poprawię opis later“, tylko builder wpisuje liczby do opisu

Leczenie §6.24 nie polega na tym, żeby pamiętać. `make_release.sh` po policzeniu sum przepisuje
w `$OUT/README.md` linię `<!-- ROZMIARY-KONTRAKT product…=B system…=B vbmeta…=B -->` wartościami
**z dysku**, a sekcja Q w `tools/test_release.sh` pilnuje trzech rzeczy: (1) każdy wpis bloku
zgadza się z plikiem, (2) ta sama liczba w formie czytelnej (`75 198 464`) istnieje w prozie
**tego samego** README, (3) przeanalizowano ≥3 wpisy — bez tego zero trafień wygląda jak sukces.

Zmierzone na obu ścieżkach (23 IX 2026):

| wstrzyknięty stan | co zrobił `make_release` | co na to sekcja Q |
|---|---|---|
| blok z `99999999` (przedawniony) | nadpisany prawdziwymi rozmiary | po przebudowie PASS |
| blok usunięty z README | dopisany od nowa z komentarzem | PASS, 6 pozycji |
| proza kłamie (`77 619 200` przy bloku `75 198 464`) | — (builder nie czyta prozy) | **FAIL** z cytatem obu liczb |

Punkt (2) miał początkowo postać „liczba jest w *którymkolwiek* README" i test negatywny
przeszedł na zielono, bo `-full` przywołuje rozmiar lekki przy porównaniu wariantów. To ta sama
klasa błędu co `glob` pomijający kropki: kontrola, która wybacza za dużo, nie istnieje.

Wersja Q po dwóch poprawkach (23 IX, noc) pilnuje juz nie tylko bloku kontraktowego, ale i
tabelki w `docs/07` — **wierszami**: dla każdego wiersza z `system|vbmeta|product` para
`(rozmiar, prefiks sumy)` musi istnieć w katalogu wydania, który wiersz wskazuje. Powód jest
konkretny i jest to szóstma odmiana tego samego błędu: pierwsza wersja sprawdzała „czy ta suma
występuje *gdziekolwiek* w pliku", więc podmiana sumy w wierszu na `DEADBEEF…` przeszła na
zielono, bo identyczny prefiks został w akapicie niżej. Test negatywny to wykrył — i dlatego
każda nowa kontrola w tym repo dostaje swój negatyw, zanim trafi do commita.

## 6.26 Kontrakt rozmiarów objal caly katalog — i przy okazji pokazal, ze umiem usunac wlasna kontrole

Rozszerzenie §6.25 poszło o krok dalej: blok `ROZMIARY-KONTRAKT` w README liczy **wszystkie**
pliki wydania (`*.img`, `flash-all.sh`, `rollback.sh`, `device-probe.sh`, `build-info.txt`,
`release-manifest.tsv`), poza `*.md`, `*.log` i `SHA256SUMS.txt` (ten ostatni nie może: jego
własny rozmiar zmienia się *po* wpisaniu bloku, byłoby to równanie samoodwołujące). Q wymaga
więcej niż 16 przeanalizowanych pozycji i sprawdza dodatkowo **liczbę kolumn wierszy tabeli**
w README.

Po co ta druga kontrola: podmieniając rozmiary w tabeli „Skład wydania", wstawiłem `| 6 749 | |`
— pięć wierszy z czterema kolumnami przy nagłówku trójkolumnowym. Markdown i tak by to
wyrenderował, tylko przesunięte; nikt nie nazwałby tego błędem merytorycznym, a jest.

Co z tej tury naprawdę warto zapamiętać, bo dotyczy nie tabeli, a mnie:

1. **Wpisałem `6 631` tam, gdzie `stat` mówił `6 749`.** Ręka, z głowy, przy pliku `.sh`,
   którego kontrakt wtedy nie pilnował. Odpowiedź nie brzmi „będę uważniejszy" — brzmi:
   rozmiar każdego pliku w wydaniu ma być maszynowo trzymany i maszynowo sprawdzony.
2. **Rozbudowując Q, zgubiłem jego własny próg.** Wstawka z `docs/07` wzięła jako kotwicę linię
   `if seen<3: …` i *zastąpiła* ją, zamiast dopisać się obok. Q zostało przez dwie przebudowy
   bez asercji „ile przejrzałem" — czyli dokładnie z tą wadą, dla której §6.20 powstało.
  Reguła: przy rozbudowie kontrolki nie wolno używać jej linii ochronnej jako kotwicy; nowe
   zdania dopisuje się **powyżej** albo **poniżej**, a potem `git diff` pokazuje, że stara linia
   nadal istnieje.
3. **Strażnik, który wyłączal kontrolę.** Napisałem `if os.path.isfile(d7) and 'rows_done' not
   in globals():` i w tym samym secie dodałem `rows_done=0` na górze. Warunek stał się wiecznie
   fałszywy, skan wierszy nigdy się nie odpalił, a `rows_done<4` — JEDYNA rzecz, która została
   po punkcie 2 — krzyknęło „kontrola martwa" na zielonym baseline'owym przebiegu. Progi
   „ile przejrzałem" nie są dekoracją: to one zamieniły moje dwa kolejne samobójstwa w testy.
4. Trzy negatywy, każdy osobno uruchomiony i każdy czerwony: kolumna `+1` w tabeli → FAIL
   z numerem linii; skrócony blok kontraktowy → FAIL „przeanalizowano tylko 9 pozycji"; zły
   rozmiar vbmeta w bloku → FAIL „kontrakt mówi 8192 B, plik ma 4096 B".

## 6.27 CI było głuche: „15/15 success" nie znaczyło, że suita przeszła

Krok `suite wydania` w `.github/workflows/release-selftest.yml` wyglądał tak:

```bash
if bash tools/test_release.sh --erofs-dir "$EROFS_DIR" 2>&1 | tee -a "$RUNLOG"; then :; else exit 1; fi
```

Domyślny shell kroków to `bash -e {0}` — bez `pipefail`. Status rury jest wtedy statusem
**ostatniego** elementu, czyli `tee`, a `tee` nie ma powodu zwracać czegoś innego niż zero. Warunek
`if` był więc zawsze prawdziwy i `exit 1` nigdy się nie odpalił. Symulacja w powłoce:
`if bash -c "exit 1" | tee /tmp/x; then ...` → „krok zielony mimo rc=1".

Ślad, po którym to w ogóle zobaczyłem: `git archive HEAD` (emulacja świeżego checkoutu) dał
**dwa FAIL-e Q** — brakujący `system.img` wariantu lekkiego i `vbmeta` wariantu `-full`, którego
w ogóle nie było w `git ls-files` (`.gitignore` ma `*.img`, a negacje były wypisane tylko dla
katalogu lekkiego). Na runnerze te same braki istnieją od zawsze, bo obrazu 920 MB GitHub nie
pomieści. CI było zielone, bo patrzyło na `tee`.

Co zostało zrobione, a czego nie:

1. Krok liczy `rc=${PIPESTATUS[0]}` i wychodzi z nim. Nie dałem `set -o pipefail` na górę kroku,
   choć to pokusa: te same kroki **celowo** połykają `dpkg -l erofs-utils | tail -1` (pakietu może
   nie być → rc=1) i `$MK --version | head -1` (SIGPIPE = 141). `pipefail` na całym kroku wywracałby
   bieg rzeczami, które nie są blokerem wydania — czyli zamieniłbym głuchotę na szum.
2. Q rozróżnia „pliku nie ma, bo jest większy niż limit GitHuba" (odpowiedzialny pominięty
   i **policzony**: `pominiętych (za duze na GitHuba): 3`) od „pliku nie ma, a powinien być"
   (FAIL). Wiersze `docs/07` mają to samo: `zweryfikowane 4, pominiete 0` lokalnie,
   `2 / 2` na czystym checkoutcie.
3. `vbmeta` wariantu `-full` to te same 4 096 B co w lekkim (`cmp`: identyczne), więc trafił do
   gita przez negację w `.gitignore` — oba katalogi są teraz sprawdzalne osobno, bez luzowania
   kontrolki.
4. `tools/lint_pismo.py` przestał wymagać metadanych gita: przy braku `.git` chodzi po katalogu
   i **pisze w linii wyniku, którego źródła użył** (`zrodlo: git ls-files` / `przejscie kataloga`),
   bo „kontrola nie zadziałała" nie może wyglądać jak „kontrola czysta". Obie ścieżki dają u mnie
   identyczne 90 plików, co jest przy okazji krzyżowym sprawdzeniem samego lintu.

Wniosek do zapamiętania jest szerszy niż ten plik: zielony przebieg, który nie patrzy na kod
wyjścia testu, nie jest dowodem niczego — a ja przez cztery dni budowałem na nim poczucie
bezpieczeństwa. Emulacja świeżego checkoutu (`git archive HEAD` do katalogu poza repo) jest tania i
jest pierwszym czymś, co warto zrobić, gdy kontrola „przecież przechodzi".

## 6.28 Zepsuty plik workflow nie jest czerwonym testem — jest brakiem testów

Naprawiając głuchotę suity (patrz §6.27), podmieniłem dwie linie w `build.yml` i **zgubiłem ich
wcięcie**: `bash tools/raw_parts_on_runner.sh …` wylądowało w kolumnie 0. Dla YAML-a to nie jest
„brzydko wcięty skrypt", tylko koniec bloku scalarowego w środku zdania — cały workflow stał się
nieparsowalny, GitHub zgłosił `workflow file issue`, a `jobs` zwróciło **zero jobów** (`total_count: 0`).
Inaczej niż przy FAIL-u testów: tu nikt niczego nie uruchomił, więc nawet adnotacji w UI nie było.

Mój własny walidator z tej samej tury (patrzyłem, czy po zmianach nie ma dziur) **tego nie złapał**:
sprawdzał tylko, że każda linia bloku ma wcięcie większe od rodzica, a nie że jest **spójne w obrębie
bloku**. Czym innym jest „nie weszłem za płytko", czym innym „nie wyskoczyłem za wysoko".

Teraz pilnuje tego sekcja R w `tools/test_release.sh`:

* `yaml.safe_load` każdego pliku w `.github/workflows` (runner ubuntu-latest ma PyYAML; w tym
  sandboxie musiałem go doinstalować `--break-system-packages` — bez niego zostałem na heurystyce,
  i to jest uczciwie zapisane w wyniku jako `pyyaml: NIEACCESSNY (tylko heurystyka wciecen)`),
* plus heurystyka niezależna od parsera: żadne polecenie powłoki (`bash `, `rc=`, `if `, `fi`, `done`,
  `echo `, `set `, `exit `, `mkdir `, `sudo `, `[ `, `export `) nie może stać w kolumnie 0,
* oraz próg `bloki run >= 8` — zeby „znalazłem zero bloków" nie było zielone.

Test negatywny: wstrzyknąłem z powrotem dokładnie tę podmianę, która zepsuła `build.yml`. R mówi
dwa razy — `BLAD parsowania YAML -> while scanning a simple key` i `build.yml:418: polecenie powloki
w kolumnie 0` — i cały przebieg jest czerwony. Po przywróceniu: 46 PASS / 0 FAIL z `--real`,
38 PASS bez.

Drobna, ale dla mnie ważna obserwacja: `pip install pyyaml` domyślnie odmawia (PEP 668, „externally
managed"). Odmowa instalacji to nie to samo co brak biblioteki w sensie logicznym — kontrola musi
działać w obu światach, a jej wynik musi mówić, w którym właśnie działa.

## 6.29 `--vintf-level`: bramka init zamknięta plikiem, a nie wyrokiem — i dlaczego wcześniej była otwierana na pokaz

`tools/make_level_matrix.py` istniał od wczoraj, `docs/05` chwalił się testem zwierciadlanym,
a `tools/make_release.sh` **nigdy go nie wywoływał**. Cała ścieżka „dokładamy macierz level 5 do
systemu" żyła więc w narzędziu, którego nikt nie odpalał przy budowie wydania: wypuszczony
`system.img` nie zawierał `etc/vintf/compatibility_matrix.5.xml` i w ogóle nie mógł się uruchomić
(`init`: `Failed to initialize VINTF`, czyli stop przed `zygote`).

Od dziś `make_release.sh --system-tree ... --vintf-level 5`:

* szuka `etc/vintf` w drzewie (`find -maxdepth 4 -type d -path '*etc/vintf'`, bez zgadywania, czy
  drzewo ma prefiks `system/` — layouty z `fsck.erofs --extract` różnią się między źródłami);
* jeśli pliku dla zadanego poziomu **nie ma** — generuje go, buduje obraz, weryfikuje obraz 1:1
  z drzewem (z plikiem w obu miejscach!) i **dopiero potem** usuwa plik z drzewa wejściowego.
  Kolejność jest częścią kontroli: usunięcie przed `verify_image.sh` dałoby fałszywą niezgodność
  „plik jest w obrazie, nie ma go w drzewie";
* jeśli plik **jest** w drzewie — nie dotyka go (S11 pilnuje, że sha pliku użytkownika jest
  identyczna przed i po budowie);
* jeśli flagi nie ma — nic nie dokłada, ale `build-info.txt` dostaje `vintf_macierz  BRAK: ...`
  z nazwaniem tego bramką do zdjęcia, a nie „pominięte", bo „pominięte" brzmi jak decyzja.

Stan trafia do `build-info.txt`, więc da się po fakcie rozstrzygnąć, co było w obrazie, bez
rozpakowywania go przez autora.

**Błąd, który znalazł się tylko dzięki testowi od końca do końca.** Generator ustawiał
`new.set('level', str(want))`, czyli *atrybut*, a element `<level>` był przepisywany ze źródła i
nigdy nadpisywany. Plik `compatibility_matrix.5.xml` zawierał `<level>6</level>`. Nazwa mówiła
jedno, treść drugie — a `VintfObject` czyta treść. Poprawione w `build()` (nadpisuje element,
wstawia go gdy brak), a sam generator ma asercję na koniec: parsuje zapisany plik i wychodzi
`rc=4`, jeśli `<level>` nie równa się żądanemu poziomowi.

**Druga nauczka, o niebo brzydsza.** Pierwsze uruchomienie sekcji S dało `FAIL` na teście „plik
zgubił HAL-e". Kod był poprawny; mój wzorzec to `grep -qE 'name>.thermal'`, napisany pod
jednoliniowy XML, a `ET.indent` zapisuje `<name>thermal</name>` w osobnej linii — czyli *zero*
znaków między `name>` a `thermal`, a wzorzec wymagał jednego. Asercja, która nie opisuje
dokładnie tego, co produkuje narzędzie, generuje błędy tam, gdzie ich nie ma. Naprawione na
`<name>thermal</name>`, a przy okazji dodane `S4b`: HAL z `min-level="7"` musi **zniknąć**, więc
gdyby generator był kopią źródła, test i tak by to złapał.

Sekcja S (13 kontroli) liczy przebieg na syntetycznym drzewie i zrywa z nawysem „rc=0 znaczy
dobrze": cała ścieżka to `make_release` → `fsck.erofs --extract` → czytanie pliku z rozpakowanego
obrazu. Basela suite po dodaniu S: **51 PASS / 0 FAIL** (było 38).

## 6.30 README wydania przez dwa dni opisywało cudzy build — i czego to uczy o testach dokumentacji

Znaleziono 24 IX przy przygotowywaniu przebudowy, NIE dzięki testowi. Stan faktyczny jest w
`dist/release/HyperOS4_P11Gen2/build-info.txt`; porównanie z tym, co twierdził README:

| klucz w `build-info.txt` | wartość | co z tego wynika dla README |
|---|---|---|
| `kompresja` | `lz4hc,9` | te same bajty były podpisane słowem „`lz4`" — liczby prawdziwe, etykieta myląca |
| `wykluczenia_mkfs` | `--exclude-regex=\.komentarz\.txt$` | README pisał, że 3 pliki `*.komentarz.txt` „świadomie zostały" w partycji; zostały wykluczone |
| `vintf_macierz` | **klucza nie ma** | README punktem 1 obiecywało „dobudowane macierze VINTF 4/5/6" |

Trzeci wiersz jest najgroźniejszy, bo to nie kwestia stylistyki. Zdanie zostało przeniesione ze
ścieżki runnerowej: `tools/build_rom_on_runner.sh` realnie dokłada macierze i jego efektem jest
`dist/rom-kit/`. Ten sam opis trafił do katalogu, którego obrazy nigdy przez tę ścieżkę nie
przeszły. Skutek dla urządzenia byłby taki, że ktoś wgra `system.img` 920 047 616 B, ufając temu,
co czyta, i dostanie `Failed to initialize VINTF Object` w `init` — stop przed zygote, bez żadnej
winy sprzętu. (Prognoza z rana 24 IX: §6.33 pokazał, że w tym obrazie trzy pliki jednak były —
usterką była kaskada i forma `optional`, nie brak.)

**Lekcja dotyczy testów, nie README.** Kontrolka `N` pilnuje sum, `Q` rozmiarów — obie patrzą w
liczby. Nic nie pilnowało, czy zdanie w README nie obiecuje zawartości, której w obrazie nie ma.
Stąd sekcja `T` w `tools/test_release.sh`: dla każdego katalogu wydania porównuje zdania trafione
kluczami `macierz|vintf` oraz `dobudowan|zawiera|trafił|wpięt` ze stanem klucza `vintf_macierz` w
`build-info.txt`. Jest dwukierunkowa celowo: claim bez dowodu FAILuje, ale i dowód bez claimu
FAILuje. Bez tego drugiego kierunku naprawa kłamstwa wyglądałaby najprościej na świecie — ktoś
usuwa zdanie z README i kontrolka milczy razem z prawdą.

Dwie rzeczy wyszły przy wstawianiu `T`:

1. **Pierwszy przebieg uderzył we mnie.** `T` FAILowało na NOWYM README, na zdaniu
   „Wcześniejsza wersja tego punktu obiecywała «dobudowane macierze 4/5/6»". To nie był false
   positive do wygłuszenia: dokument wydania, który ktoś czyta przed flashem, nie powinien zawierać
   historii błędów. Historia poszła tutaj, w README został jeden fakt: tego nie ma w tym obrazie.
   Testu nie rozmiękczałem.
2. **Trzeba odróżnić czas przeszły**, bo inaczej każda wzmianka historyczna w README byłaby
   claimem: doszły `wcześniejsz|poprzedni|było przepisane|nieaktualn|przestał`. To zawężenie, nie
   furtka — świadczy o nim test negatywny poniżej.

Test negatywny, dowodzący, że `T` nie jest dekoracją: `git checkout HEAD -- README.md` (stary
tekst) → `52 PASS / 1 FAIL`, z wydrukowanym zdaniem-błędem w linii `claim:`; przywrócenie nowego →
`54 PASS / 0 FAIL`. Notuję oba numerami, bo `tail -N` nie jest asercją.

Czego `T` NIE dowodzi: nie zagląda do bajtów. Realnego `system.img` wydania nie ma w gicie
(>100 MB), więc kontrolka opiera się na `build-info.txt`, czyli na deklaracji parametrów budowy.
Jedyna kontrola na bajtach to `fsck.erofs --extract` i `grep` po rozpakowanym obrazie — po to jest
`S2` w tej samej suicie, tyle że na atrapie. Dla wydania realnego wykonuje się to ręcznie i przepis
jest w README wariantu lekkiego.

## 6.31 Przebieg, którego nie umiem odtworzyć — i co to zmieniło w suicie

24 IX, tuż po dopisaniu §6.30: `bash tools/test_release.sh --erofs-dir /tmp/erofs-c 2>&1 | tail -3`
zwróciło `53 PASS / 1 FAIL`. Nazwy tej kontroli nie widziałem, bo `tail -3` utnął ją razem z
resztą, a ja i tak zrobiłem `git add -A && git commit` w tej samej linii — czyli wpuściłem commit
przy czerwonym wyniku i dowiedziałem się o tym dopiero, kiedy zacząłem szukać przyczyny.

Co wiadomo na pewno:
- powtórzenie identycznego polecenia na identycznym drzewie daje `54 PASS / 0 FAIL` — pięć
  kolejnych przebiegów; ten jeden się nie powtórzył ani razu;
- stan plików w tamtym momencie to §6.30 w wersji, której już nie ma (nadpisałem ją minutę
  później, nie commitując), więc odtworzenie jest niemożliwe nie z lenistwa, tylko z braku
  materiału;
- żadna kontrolka nie czyta `docs/06` (K liczy pismo za pomocą `lint_pismo.py`, N patrzy w
  README, Q w `docs/07`) — więc jeżeli to §6.30 wywołał tamten FAIL, to mogło to być tylko
  `K`/`lint_pismo.py`, który skanuje całość repo.

Nie zgaduję dalej, tylko usuwam klasę błędu: `bad()` dopisuje teraz każdy FAIL do
`$WORK/PADDLE.txt`, a podsumowanie wypisuje te linie pod licznikiem — „--- co padło (te same
linie, których nie utnie żadne tail)". Mechanizm sprawdzony tak jak wszystko inne: świadomie
fałszywe zdanie w README wydania → `52 PASS / 1 FAIL` z widoczna nazwa „README i build-info
opisuja dwa rozne swiaty" przy `tail -4`; po usunięciu zdania → `54 PASS / 0 FAIL`.

Wniosek do zapamietania jest mniej komfortowy niż zwykle: `tail` przy uruchamianiu suity to nie
jest skrot, to kasowanie dowodow. Jeżeli wynik ma być jednozdaniowy, niech go poda sama suita.

## 6.32 `optional` jest atrybutem: dlaczego wczorajszy „VINTF SPOJNE" nie znaczył nic

Zmierzone 24 IX na źródle, nie na zgadywance. W formacie FCM i w manifeście urządzenia
`optional` jest **atrybutem** elementu `<hal>`:

```
<hal format="aidl" optional="true">      <- tak czyta i pisze libvintf
    <name>android.hardware.thermal</name>
```

Potwierdzenie w kodzie (`LineageOS/android_system_libvintf`, plik `parse_xml.cpp`):
`MatrixHalConverter::mutateNode` zapisuje `appendAttr(root, "optional", ...)` (linia 520),
a `buildObject` czyta `parseOptionalAttr(root, "optional", false, ...)` (linia 528).
`parseChildren` przejmuje tylko znane dzieci (`<version>`, `<interface>`), więc **nieznany
element `<optional>` jest po prostu ignorowany**.

Co z tego wynika dla naszej ścieżki:

1. `make_level_matrix.py --optional-missing` od początku dopisywał **element**
   `<optional>true</optional>`, zostawiając atrybut `optional="false"`. Plik wyglądał na
   zmiękczony i nie zmieniał niczego, co init miałoby zobaczyć.
2. `vintf_diff.py` czytał `h.findtext('optional')`, czyli **ten sam element**. Generator i
   przyrząd pomiarowy zgadzały się ze sobą — i oba mijały się z init.
3. Stąd wczorajszy wniosek w `docs/05 §5.1` („miękka macierz vs manifest vendor:
   **0 braków obowiązkowych, VINTF SPOJNE**") był pomiarowo pusty: zera wzięły się z tego,
   że `vintf_diff` patrzył w pole, które generator podmazał, a nie w pole, które czyta system.
   Liczby strict (53 braki vs vendor źródła, 70 vs symulowany vendor A12) zostają — one
   nie zależą od `optional`.
4. Dotyczy to też `dist/rom-kit/`: ten zestaw budował `tools/build_rom_on_runner.sh`, który
   wywołuje `--optional-missing`. Jego `MISMATCH.md` twierdzi, że bramka init została otwarta;
   przy ówczesnym generatorze to zdanie nie ma oparcia. Przebudowa tym samym kodem (już
   naprawionym) otworzy ją naprawdę — sam skrypt się nie zmienia, bo woła ten sam generator.

Naprawa i jej dowody (nie „zaufałem", tylko policzone):

- `mark_optional()` ustawia teraz atrybut i sprząta ewentualne dzieci; `main()` po zapisie
  liczy pozycje z `optional="true"` i zwraca `rc=4`, jeśli liczba się nie zgadza;
- `build()` pilnuje **obu** form poziomu (atrybut `level=` i element `<level>`), bo ten ROM ma
  dwóch czytających: `init` z `/system` (libvintf frameworku A17) i narzędzia po stronie
  `/vendor` (A12) — atrybut to jest dokładnie to, na co patrzy strona A12;
- `vintf_diff.py` czyta atrybut, a rozjazd atrybut ↔ element zgłasza jako `ODSTEPSTWA FORMATU`;
- demo na jednym fixture'u, dwie wersje tego samego pliku, ten sam manifest vendora:
  forma-elementowa → `BRAKI obowiazkowych: 1`, `WYROK: INIT STANIE`; forma-atrybutowa →
  `BRAKI obowiazkowych: 0`, `WYROK: VINTF SPOJNE`; przy pierwszym podejściu wypisane
  `ODSTEPSTWA FORMATU (2)` z nazwami HAL-i;
- w suicie: `S13` (miękki wariant NA SZEROKO daje atrybut w **rozpakowanym obrazie**),
  `S13b` (build-info nazywa wariant), `S14` (z manifestem vendora zwalniane są tylko pozycje
  naprawdę brakujące — `audio.core` zostaje `optional="false"`, `gatekeeper` dostaje `true`),
  `S14b` (podstawa zmiękczenia w build-info), `S15` (drzewo posprzątane po miękkich wariantach),
  a `S3` sprawdza obie formy poziomu. Razem `61 PASS / 0 FAIL`.

Ostatnia rzecz, którą trzeba przy tym uczciwie nazwać: zmiękczanie przez `optional` to nie jest
„naprawa zgodności", tylko **umowa z init**, że nie zatrzyma startu, dopóki framework nie
zażąda usługi realnie. 20 brakujących HAL-i po stronie vendora nie znika — one się pojawią jako
crashe `audioserver`/`healthd`/`gatekeeperd` po starcie. Natomiast wariant strict (bez
`--optional-missing`) na A12 vendorze daje 53–70 pozycji wymaganych, a więc bramka zostaje
zamknięta: to jest powód, dla którego `make_release.sh` ma oba tryby i zapisuje wybrany w
`build-info.txt`.

## 6.33 Nie wnioskuj o zawartości obrazu z braku klucza w metadanych

Ten rozdział jest o moim błędzie z 24 IX rano i o tym, co go znalazło — bo to drugie jest
wartościowsze niż pierwsze.

**Co zrobiłem.** Zauważyłem, że `build-info.txt` wydania nie ma klucza `vintf_macierz` (klucz
dopiero powstał razem z flagą `--vintf-level`). Wniosek, który wydawał się oczywisty: „obraz nie
zawiera macierzy, `init` padnie na braku pliku". Wpisałem to w oba README, sekcję T i odpisałem
użytkownikowi. **Wniosek był fałszywy.**

**Co mówią bajty.** Drzewo donora odzyskałem z gałęzi `transfer-spool` (rom-kit z biegu
`35897100768` zawierał `system_tree` w całości — 4568 wpisów). Drzewo z trzema plikami wygenerowanymi
23 IX przez `build_rom_on_runner.sh` wprawione z powrotem w `make_release.sh` dało `system.img`
**bajt w bajt identyczny z wydanym**: 920 047 616 B, sha256
`cf0b889d45a6bb4f6af3d7eeb349a5c453d95d871212b8e86defa8eb83a9ebf6`. Czyli wydany obraz **ma**
`etc/vintf/compatibility_matrix.{4,5,6}.xml` — a cały mój poranny akapit o „braku pliku" był
wnioskowaniem z braku klucza w metadanych. To jest dokładnie ta klasa błędu, którą w tym projekcie
wyłapuję u innych: `build-info` opisuje przebieg, nie zawartość; o zawartości rozstrzyga
`fsck.erofs --extract` i `grep` po rozpakowanym obrazie.

**Pierwsza różnica wskazała prawdziwą usterkę.** Rebuild bez trzech plików wyszedł
920 035 328 B = dokładnie 12 288 B mniej = 3 × 4096 B (trzy rekordy plików w EROFS). To był
punkt, w którym powinienem zamiast „brak pliku" powiedzieć „rozmiar mówi, że tam są". Dalej już
pomiar na rozpakowanych obrazach:

| co jest w obrazie | atrybut `level` | pozycji | obowiązkowych wg libvintf | martwe dzieci `<optional>` |
|---|---|---|---|---|
| wydany 23 IX (3 pliki, kaskada) | 5 | 84 | **84** | 84 |
| nowy `--vintf-level 5` (strict) | 5 | 84 | **84** | 0 |
| nowy `+ --vintf-optional-missing` | 5 | 84 | **0** | 0 |

Kaskada też jest z pomiaru: komentarz generatora w wydanym pliku mówi
`zrodlo: compatibility_matrix.4.xml`, czyli level 5 był cięty z pliku, który skrypt utworzył
sekundę wcześniej dla level 4, a ten z `202404` — trzy przebiegi w jednym katalogu, każdy z
następstwa poprzedniego. `make_level_matrix.py` odfiltrowuje teraz własne wyjście po markerze
pierwszej linii (`is_generated()`), co robi z niego narzędzie odtwarzalne.

**Co zostało zbudowane (24 IX, na odzyskanym drzewie).** Wariant lekki przebudowany jest
kompletnie i to on jest „tym dobrym" wydaniem:

```
system   920 039 424 B  4836dcd4c8d5f6c0…  (4 563/4 563; 84 pozycje, 0 obowiazkowych)
product     75 198 464 B  a961bec46085883d…  (identyczny co poprzednio, potwierdzone sha256)
vbmeta          4 096 B  9cf2e7e4…         (identyczny; Flags: 3)
```

`--real` na tym samym drzewie: **67 PASS / 0 FAIL** — pierwszy taki przebieg w projekcie (wcześniej
`--real` dało 46 PASS, bo drzewa musiały istnieć). Sekcja J sprawdziła 8 sum w wariancie lekkim
(wszystkie obecne) i 6 w `-full` (2 obrazy >100 MB nieobecne w checkoutcie — taka jest cena limitu
GitHuba, i teraz test to mówi zamiast klęczeć). Po odtworzeniu obrazów `-full` ten sam przebieg
daje **79 PASS / 0 FAIL** — wszystkie cztery obrazy sprawdzone 1:1 i 8+8 sum; wymaga to
`SYSTREE_FULL` = drzewo donora, bo `-full` trzeba porównywać z drzewem, z którego powstał.

**Wariant `-full` też jest odtworzony — i to bez zgadywania.** Jego `product.img`
(150 560 768 B) powstawał jako kuracja z `staging/product/overlay` — 147 wpisów 1:1. Z tara
assetów wychodziło 174 wpisy (154 pliki + 18 katalogi + `passwd`/`group`), a różnica to cały
`etc` poza tymi dwoma plikami: `build.prop`, `permissions/` (12 plików), `sysconfig/` (10) i
`vintf/` — razem 27 wpisów. Zestaw miał cztery niezależne przesłanki przed budową: tabela §6.9
(„fonty + 67 RRO" = 144 wpisy przed `passwd`/`group`, 147 po), liczba RRO w §6.16 i w
`diagnostics/rro-crosstab-product.tsv` (67 apk) oraz komentarz w `enrich_product.sh`
(„`etc/permissions` świadomie poza listą"). Rozstrzygnął jednak hash-orakul: przebudowa z drzewa
`fonty + overlay + passwd + group` dała `da17ffcd20c0ab4e…` — **bajt w bajt** wydany obraz, a
przebieg z drzewem donora (z trzema plikami runnera) odtworzył `system` `cf0b889d45a6bb4f…` i
`vbmeta` `9cf2e7e4…`. Odtwarzalność tym razem nie posłużyła do przechwałek, tylko do
rozstrzygnięcia pytania, na które sama dokumentacja odpowiedzi nie miała. Ostrzeżenie z README
`-full` pozostaje aktualne: jego `system` to build 23 IX (84 obowiązkowe → bramka zamknięta),
a dobry obraz jest u sąsiada.

**Dwa testy, które tego pilnują** (obok opisanej wyżej sekcji T):
- sekcja J porównuje teraz „drzewo vs obraz" **z** wykluczeniem pliku dodanego przez buildera — i
  mówi głośno, że to wykluczenie zaslepia też macierze donorowe, więc ich zgodności tam NIE
  dowodzi (dowodzi jej builder w trakcie budowy, gdy plik jest w drzewie, oraz S2 na obrazie);
- `sha256sum -c` liczy tylko pliki obecne i FAILuje na nieobecnym pliku, który **mieści się** w
  limicie 100 MB — bo brak małego pliku to niekompletne wydanie, a brak 920 MB to po prostu
  GitHub.

Wniosek do kieszeni: „klucza nie ma w metadanych" jest przesłanką do pomiaru, nie do wyroku.

## 6.34 Resize `super` — świadoma zgoda zamiast „nawet na request"

Dotąd `flash-all.sh` odpowiadał na brak miejsca w slocie tekstem „powiększanie super rusza `/data`
i jest nieodwracalne, więc tego nie robię — nawet na request". Ta polityka **zostaje domyślna**;
zmieniło się tylko to, że istnieje świadoma ścieżka obok niej. Powód: bez niej cała reszta
roboty (VINTF, wariant miękki) leży przed bramką, której nie da się otworzyć — obraz 920 MB na
slocie 768 MB.

Ścieżka, którą sprawdziłem na atrapie i której wygląd jest zamrożony testami RS1–RS3:

```
RESIZE_SUPER=1 I_ACCEPT_DATA_LOSS=yes ./flash-all.sh
  -> delete-logical-partition product_a
  -> delete-logical-partition product_b
  -> resize-logical-partition system_a <rozmiar obrazu zaokraglony do 4 MiB + 64 MiB>
  -> resize-logical-partition system_b <to samo>
  -> flash vbmeta_a/b + system_a/b (product POMINIETY - partycji juz nie ma)
```

Dlaczego tak, a nie inaczej:
- `delete-logical-partition product_*` to sztuczka, którą wymagały GSI na tym sprzęcie
  (opisana w `docs/05`, źródło: reddit/androidtablets) — uwalnia miejsce w `super`;
- `product` w tym wydaniu to w wariancie lekkim same fonty, a fonty Xiaomi są i tak w
  `/system/fonts`; tracisz więc najwyżej nakładki RRO z wariantu `-full`, a ten i tak
  pozostaje buildem 23 IX;
- nowy rozmiar slotu liczę z pliku (4 MiB w górę + 64 MiB zapasu), nie z liczby z dokumentu —
  bo liczba z dokumentu zmienia się z każdą przebudową;
- bez frazy `I_ACCEPT_DATA_LOSS=yes` skrypt odmawia **przed** jakimkolwiek `fastboot` poza
  odczytami — sprawdzone w RS2 jako test negatywny (zero polecen w logu atrapy).

Co to NIE jest: to nie jest zgoda na zrobienie tego kiedykolwiek za czytnika. Testy mówią, że
kolejność poleceń jest taka, jak wyżej, i że domyślna ścieżka nie dotyka układu partycji. Na
prawdziwym urządzeniu jedyny sensowny przebieg to: `device-probe.sh` → kopia pięciu obrazów
stockowych → `flash-all.sh` ze zgodą → `logcat -b all` po starcie. Awaryjnie: BROM/DA
MediaTeka, nie EDL.

## 6.35 Cztery sekcje w jedno popołudnie: „ładunek, którego nikt nie odpalał"

Schemat powtórzył się cztery razy z rzędu (F2 rano, F3/V/W/X po południu), więc to już nie
przypadek, tylko metoda: przejrzyj katalogi wydania i zapytaj o KAŻDY plik — „która sekcja to
wykonała?". Wszystko, czego odpowiedź brzmi „żadna", jest ładunkiem, który jedzie do urządzenia
na słowo honoru generatora.

- **F3 — `rollback.sh`**: jedyny skrypt wydania nigdy nie wykonany. 21 linii, a w nich
  samolokalizacja, pętla slotów a/b i heredoc z ostrzeżeniem „to NIE przywraca partycji
  product ani system" — czyli dokładnie to, co użytkownik odpala w panice, gdy coś poszło
  źle. Testowany na kopiach po nazwie względnej (lekcja F2) z jawnie sterowanym stanem
  `vbmeta_stock_*.img`, bo atrapa fastboot plików nie tworzy.
- **V — wnętrze `vbmeta`**: J sumował plik całościowo, ale strategia wydania siedzi w polach
  nagłówka (`flags=3`, testkey AOSP wg docs/03 §A.1). avbtool znika z `/tmp` przy każdym
  restarcie sandboxa, więc V parsuje nagłówek ręcznie. Pułapka, na którą wszedłem przy
  pisaniu: `public_key_offset` jest względny wobec bloku AUX (plik = nagłówek 256 B + auth +
  aux), nie wobec początku pliku — pierwsza wersja czytała „klucz" z bajtów nagłówka. Ta sama
  względność dotyczy hash/signature (wobec AUTH) i deskryptorów (wobec AUX); dokładnie tak
  robi to libavb.
- **W — `release-manifest.tsv`**: dokument, który czyta człowiek, miał kolumnę sha256 i
  wiersze skryptów nieporównane z plikami (J brał rozmiary tylko dla `.img`). Nieobecność
  >100 MiB tolerowana jak w J, ale nawet nieobecny plik musi mieć zgodną sumę w manifeście
  i w `SHA256SUMS.txt` — dwa dokumenty nie mogą rozjeżdżać się o plik, którego nie widzą.
- **X — `dist/modules` i `dist/rom-kit`**: katalogi z wyjątkami w `.gitignore`, więc żyją
  w gicie, ale poza zasięgiem suity. Moduł Magisk (druga ścieżka flashowania) dostał kontrolę
  trzech kopii sumy (plik, sidecar `.sha256`, `SHA256SUMS.txt`), struktury i CRC całego zipa;
  rom-kit — `bash -n` i sumy gita 1:1. Najważniejsza asercja X jest negatywna: rom-kit niesie
  **donorski** vbmeta (`3506d20e…`), wydanie **testkey** (`9cf2e7e4…`) — to świadoma decyzja
  z docs/03, a kontrola istnieje po to, żeby nikt nie „naprawił" rozjazdu kopią jednego pliku
  na drugi.

Druga lekcja popołudnia, większa niż wszystkie cztery sekcje razem: **dokument opisujący
procedurę odzysku też jest ładunkiem** — dopóki nie został wykonany słowo w słowo, jest
hipotezą. Receptura odbudowy obrazów z `transfer-spool` (docs/08) wyglądała na kompletną,
a przy pierwszym sprawdzeniu na czystym klonie miała błąd: `git archive origin/transfer-spool`
pada, bo ten ref nie istnieje lokalnie po czystym klonie (poprawnie: `git fetch origin
transfer-spool` + `git archive FETCH_HEAD`). Replay dosłowny — blok kodu wycięty z docs/08
i wykonany bez zmian — trwał 189 s i przeszedł rc=0. Od teraz receptura w docs ma prawo
istnieć tylko w wersji, która była tak wykonana.

Co to NIE jest: licznik 126/134 nie jest celem samym w sobie. Cztery sekcje dodały 38 kontroli,
ale ich wartość to cztery pytania, które przestały wisieć: „czy rollback flashuje dokładnie to,
co zrobił flash-all?", „czy vbmeta na pewno ma wyłączone weryfikacje?", „czy manifest mówi
prawdę?", „czy moduł i rom-kit są tym, czym mówią ich sumy?". Kolejne sekcje tego typu mają
powstawać tylko po znalezieniu następnego pliku bez świadka — nie na zapas.
