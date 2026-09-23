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
