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
| `--path=<katalog> --extract=<katalog>` | wyciąga **zawartość** katalogu, spłaszczoną |
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
przed flashem) + obrazy Lenovo z Dysku (`diagnostics/drive-inventory.tsv`), zapasowo EDL.
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
celowo wylatuje. Dowód, a nie obietnica: `fsck.erofs --extract --path=system/etc/vintf` na
wydanym obrazie zwraca 11 plików i zero `komentarz`.

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
tylko sha256 (`16afbc35…` i `b28e1c0e…`; obie kwity sa juz nieaktualne po korekcie DAC
z §6.19: `298ada60…` i `b4bb8064…`). Weryfikacja 1:1 wyszła 67/67 i 147/147, więc pliki
są w partycji, nie tylko w drzewie — sprawdzone `fsck.erofs --extract --path=etc`.

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
**odmówi zamontowania** całego `/system`. I ta sama tabela pokazuje drugą stronę medalu:
1828 z 3892 plików zostało nieskompresowanych (lz4 odrzuciło dane niepakowalne), więc obraz
nigdy nie jest „w całości skompresowany" i porównywanie go z `gzip -9` nie ma sensu.
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

Reguła, którą z tego zostawiam: **każda kontrola w tym projekta ma wydrukowac, ile elementow
przejrzala** (`67 wpisów`, `2738 plikow skompresowanych`, `przeanalizowane sumy: 7`). Zero albo
brak takiej liczby to wynik podejrzaney, nie sukces. Wersja testowa tej zasady: kontrola musi
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
           --force-uid=0 --force-gid=0 --exclude-regex '\\.komentarz\\.txt$' \\
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
