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

Wynik: `mkfs.erofs`, `fsck.erofs`, `dump.erofs` 1.8.2 zbudowane i działające. Kompresji nie ma
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
