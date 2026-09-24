# Stan pracy i rzeczy zablokowane (23–24 IX 2026)

Notatka dla kontynuacji — skrót tego, co jest zmierzone, a co tylko napisane.

## Wydanie: co jest gotowe

`dist/release/HyperOS4_P11Gen2` (lekki: fonty) i `-full` (fonty + 67 nakładek RRO). Pliki w
każdym: `product_hyperos4_p11g2.img`, `system_hyperos4_p11g2.img`, `vbmeta_hyperos4_p11g2.img`,
`flash-all.sh`, `rollback.sh`, `device-probe.sh` (krok 0), `release-manifest.tsv`,
`SHA256SUMS.txt` (8 pozycji, `sha256sum -c` = 8/8 OK w obu wariantach) i `README.md`
z blokiem `ROZMIARY-KONTRAKT`, który utrzymuje builder (§6.25), `build-info.txt`,
logi `mkfs.log` / `fsck.log` / `system-verify.log`.

| ładunek | bajty | sha256 (prefiks) | zweryfikowane |
|---|---|---|---|
| `product` lekki | 75 198 464 | `a961bec46085883d6d9c…` | ekstrakcja 1:1, 67/67 wpisów; DAC `0:0` |
| `product` -full | 150 560 768 | `da17ffcd20c0ab4e8d0d…` | 147/147; DAC `0:0` |
| `system` lekki (przebudowa VINTF 24 IX) | 920 039 424 | `4836dcd4c8d5f6c0…` | 4 563/4 563 (3 890 plików + 409 symlinków + 264 katalogi) |
| `system` -full (legacy 23 IX, kaskada) | 920 047 616 | `cf0b889d45a6bb4f6af3…` | 4 565/4 565 (3 892 pliki + 409 symlinków + 264 katalogi) |
| `vbmeta` | 4 096 | `9cf2e7e4e165687a…` | `avbtool info_image`: Flags 3, rollback 0, SHA256_RSA2048, klucz testowy `cdbb7717…`, **jeden deskryptor: fingerprint** |

Odtwarzalność: cztery niezależne kompilacje `mkfs.erofs` z tego samego kodu dają **identyczne
bajty** obrazu na tym samym drzewie (`a961bec4…`, `cmp` bez różnicy). Przepis jest w README
wydania; decydują `-T 0`, `--force-uid=0 --force-gid=0` i UUID-obrazu.

## Co twierdzę, a czego nie twierdzę

Zmierzone tutaj: struktura obrazów (fsck, ekstrakcja 1:1, `dump.erofs` dla DAC-a i trybów),
rozmiar vs sloty (bramka w `flash-all.sh`, pięć scenariuszy na atrapie), spójność sum w
dokumentach, determinizm budowania, higiena pisma, werdykty `device-probe.sh` (osiem
scenariuszy atrapy + dwie kontrole formy wypowiedzi).

**Niezmierzone i nie do zmierzenia w tym sandboxie: bootowalność na TB350FU.** Nic z tego nie
wynika z faktu, że obraz jest poprawny strukturalnie. Kolejność decyzji na urządzeniu:
`device-probe.sh` (krok 0) → flash lekkiego wariantu → `adb shell mount | grep erofs`.
Wariant `-full` dokłada nakładki, które mogą nadpisać `config_*` frameworku — do pierwszego
boota jest gorszym podejrzanym, więc jeśli coś nie wstanie, zacznij od lekkiego.

## Zablokowane po stronie narzędzi (nie kodu)

1. **`GH_TOKEN` działa i nie działa — raz na kilka minut.** Naprawione 24 IX ~00:50 UTC
   (pushy poszły), ale ~02:30 UTC `gh api` zwracało `401 Bad credentials`, a `git ls-remote`
   „could not read Username", więc **wyniku biegu dla `059b850` nie znam** i nie podaję go.
   Co wiem z pewnych odczytów: gałąź jest na remote (`1a8adf8..059b850` potwierdzone przez sam
   `git push`), `release-selftest` na `d84c3cc` = **35927660767, 15/15 kroków success**, a
   `build-hyperos-look` na `b4934a4` = **35927919967 success / 35927918927 failure**. Ten
   failure nie jest czerwonym testem: to mój zepsuty `build.yml` (patrz §6.28), zero jobów,
   nic nie było sprawdzane — i dokładnie dla tego istnieje sekcja R.
   To pierwszy bieg w historii, w którym „success" znaczy, że
   `tools/test_release.sh` **wyszedł zerem**: poprzednie (w tym chwalone 13/13 z `35918777924`)
   liczyły status `tee`, więc suita mogła failować do woli — `docs/06` §6.27. Sekcje K–N, P i Q
   widziały runnera dopiero teraz, realnie.
2. **~~`codeload.github.com` zwracał 404~~ — minęło.** 24 IX ~01:55 UTC oba tarballe
   (`madler/zlib` v1.3.1, `erofs/erofs-utils` master) odpowiadają `HTTP/2 200`. Cache
   `/tmp/erofs-c` nadal jest najszybszą ścieżką, ale odbudowa od zera znowu jest możliwa.
3. **Sandbox bywa przywracany ze snapshotu w trakcie pracy.** 24 IX ~03:38 UTC `git rev-parse HEAD`
   nagle zwracał `5b03aea` (korzeń `main`), a `reflog` miał jeden wpis: `clone: from https://github.com/…`.
   Cała praca była na dysku jako pliki **nieśledzone** (reset --hard je nadpisuje bez ostrzeżenia), a
   na remote sięgała do `059b850`. Procedura, która przeszła: `tar --exclude=.git -cf /tmp/kopia.tar .`
   → `git fetch` + `git reset --hard FETCH_HEAD` → porównanie dwóch interesujących plików z kopią →
   przywrócenie ich z kopii. Dlatego commit `0ec000d` (docs/07 + docs/08) istnieje podwójnie: raz
   zgubiony przez re-clone, raz odzyskany.

4. **Logi Actions pozostają nieczytelne z tej piaskownicy**: `gh run view --log` zwraca pusty
   wynik, a `gh run download` na artefakt `weryfikacja-log` 3 razy dostał EOF od
   `blob.core.windows.net`. Widoczne są więc statusy kroków i adnotacje (`::error::`/`::notice::`),
   nie treść logu — i o tym trzeba pamiętać, czytając moje „CI zielone".

## Odtwarzanie środowiska jest tanie — `--real` też (aktualizacja 24 IX ~14:00 UTC)

Po re-clone sandboxa (`/tmp` pusty, `~/romtools` skasowane) łańcuch narzędzi wraca w minutę:

```
tools/build_comp_libs.sh /tmp/comp-build      # 11 s, od zera, bez cache: libz.a 150 244 B + liblz4.a 277 634 B
tools/build_erofs_local.sh /tmp/erofs-c       # ~30 s: mkfs 588 376 B, fsck 580 496 B, dump 571 776 B
tools/test_release.sh --erofs-dir /tmp/erofs-c        # 120 PASS / 0 FAIL (z sekcjami F2/F3/V/W)
```

To przebieg **niezależny od wszystkiego, co miałem wczoraj**: identyczne liczniki, jakich wymaga
sekcja Q (16 pozycji kontraktu, `absent-skip 3`, wiersze `docs/07` 2/2) — czyli dokładnie ten kształt,
który widzi runner, bo oba katalogi wydania mają na czystym checkoutcie tyle samo plików co u mnie.
Z tą różnicą, że ciemna strona jest moja: **`--real` (128 PASS) wymaga drzew donora w `/tmp`
i `~/romtools/avb`, a te nie są w gicie i nie odtwarzają się same** — `system.img` (920 MB) i
`product.img` wariantu `-full` (150 MB) przekraczają limit GitHuba. Dlatego po reboocie mam prawo
napisać „88/0", a nie „96/0". **Aktualizacja 24 IX ~14:00 UTC: to prawo przestało być potrzebne.**
Drugie mrugnięcie snapshotu zabrało właśnie te trzy nieśledzone obrazy, a odbudowa z
`transfer-spool` odtworzyła je **bajt w bajt** w kwadrans (receptura: sekcja na końcu pliku).
`--real` jest odtwarzalny w pełni: pełne PASS potwierdzone po odbudowie (96/0 w chwili odbudowy;
128/0 po dodaniu sekcji F3, V i W jeszcze tego samego dnia — liczby historyczne niżej dotyczą
suity sprzed F3/V/W). `sha256sum -c`
na czystym checkoutcie wychodzi
7/8 (lekki) i 6/8 (`-full`), a każde `FAILED open or read` to właśnie ten brakujący duży obraz —
nie niezgodność; lokalnie po odtworzeniu obrazów (24 IX) oba katalogi mają 8/8. Skrypty generowane
(`flash-all.sh` 8 776 w lekkim i 6 749 w `-full`, `rollback.sh` 1 152, `device-probe.sh` 6 533)
przechodzą `bash -n` i mają rozmiary zgodne z kontraktami README.

## Jak odtworzyć środowisko po reboocie sandboxa

```
tools/build_comp_libs.sh /tmp/comp-build            # zlib + lz4 (wymaga sieci na tarball)
tools/build_erofs_local.sh /tmp/erofs-c             # mkfs/fsck/dump, selfcheck na 3 binarkach
tools/test_release.sh --erofs-dir /tmp/erofs-c --real    # oczekiwane: 128 PASS / 0 FAIL z drzewami sesji (bez --real: 120)
```

Drzewa `staging/`, `images/`, `rom/` i wszystko w `/tmp` **nie są w gicie** (patrz `.gitignore`):
po reboocie zostaje sam kod narzędzi, a odtworzenie drzewa `product` to `tools/enrich_product.sh`
+ ekstrakcja z plików źródłowych ROM-u (inicjatywa: `diagnostics/drive-inventory.tsv`).

## Dług wobec CI — zamknięty 24 IX

Poprzednie zdanie („CI nie powtórzy tego na `df32841`") zestarzało się: `aaa5919` (sekcje A–S)
przeszedł na runnerze — `release-selftest` = `success`, a w nim krok `suite wydania (selftest,
determinizm, testy negatywne, bramka rozmiaru)` = `success`. To już coś znaczy, bo od `d843cc`
krok bierze `PIPESTATUS[0]`, a nie status `tee` (patrz §głuchota w `docs/08` wyżej i `docs/06`).

Drugi dług też zamknięty 24 IX: **`--real` przebiegł na odzyskanych drzewach donora** — 67 PASS /
0 FAIL po przebudowie lekkiego, a po odtworzeniu obrazów `-full` (hash-orakul `da17ffcd…`,
`cf0b889d…`) ten sam przebieg daje 79 PASS / 0 FAIL z czterema obrazami sprawdzonymi 1:1.

## Odzysk drzewa donora — ROZWIĄZANE 24 IX, odpowiedź leżała w repo

Pierwsza wersja tej sekcji (dopisana kilka godzin wcześniej) mówiła, że drogi do pliku są
zamknięte i że potrzebuję kliknięcia po stronie użytkownika: publiczny link na Dysku albo dispatch
workflowu z HuggingFace. **Nie było takiej potrzeby** — i to jest główna lekcja tej sekcji, a nie
lista adresów.

Wszystkie szyni drogi z tamtej tabeli były prawdziwe i pozostają prawdziwe (limit konektora
104 857 600 B/plik; `return_download_url` zablokowany w schemacie; prywatne pliki na Dysku dają
redirect na `accounts.google.com/v3/signin` dla anonimowego curla; sandbox nie ma wyjścia na
`huggingface.co` (`SSL_ERROR_SYSCALL`); `gh run download` kończy się EOF-em z `blob.core.windows.net`).
Zabrakło kroku zero: **sprawdzić, czy te bajty już nie leżą w repo.** Leżały.

`origin/transfer-spool` — gałąź, którą dla tego projektu wymyślono właśnie po to, żeby duży ładunek
nie musiał przechodzić przez sandbox — trzymała kawałki `rom-kit.tar.gz` z biegu `35897100768`
(16 × 94 371 840 B). `tools/assemble_raw_parts.py` złożył je z pełną weryfikacją
(`ZGODNY z runnerem`, suma rodzica), a w środku było `system_tree` w całości: 4568 wpisów,
1,3 GB — czyli dokładnie drzewo donora, którego szukałem. To samo dla assetów `/product` donora
(134 808 062 B w dwóch kawałkach).

Co z tego wynika dla przyszłych sesji:
1. Zanim poprosisz użytkownika o cokolwiek, sprawdź gałęzie `transfer-spool` i `reports/` w tym
   samym repo. GitHub jest jedyną siecią, którą sandbox ma na pewno.
2. `git archive origin/transfer-spool` daje zawartość bez zmieniania gałęzi roboczej.
3. Jeśli plik ma w `MANIFEST.tsv`/`RAW_MANIFEST.tsv` sumy — weryfikuj je składając; to nie jest
   formalność, bo dziś właśnie te sumy pozwoliły uznać drzewo za kompletne.

## Odbudowa obrazów wydań z `transfer-spool` — WYKONANA 24 IX ~14:00 UTC, bajt w bajt

Drugie mrugnięcie snapshotu (24 IX, opis w §3 wyżej) zabrało trzy **nieśledzone** obrazy wydań:
`system` lekkiego, `system` i `product` wariantu `-full`. Orakulem były sumy w śledzonych
`SHA256SUMS.txt` obu katalogów — i wszystkie cztery duże obrazy (łącznie z lekkim `product`,
który przetrwał) odbudowały się **bajt w bajt**:

| obraz | rozmiar | sha256 (prefiks) | status |
|---|---|---|---|
| lekki `system` | 920 039 424 | `4836dcd4…` | ZGODNY |
| lekki `product` | 75 198 464 | `a961bec4…` | ZGODNY (przebudowany dla kontroli) |
| `-full` `system` | 920 047 616 | `cf0b889d…` | ZGODNY |
| `-full` `product` | 150 560 768 | `da17ffcd…` | ZGODNY |

Po odbudowie: `sha256sum -c` = 8/8 w obu katalogach, suita `--real` z drzewami = **96 PASS /
0 FAIL**. Całość zmierzona dwukrotnie: pierwsza odbudowa (z rekonstrukcją receptury z pomiarów)
trwała ~15 minut; **replay dosłowny** — blok kodu poniżej wycięty z TEGO pliku i wykonany bez
zmian po wyczyszczeniu ścieżek — trwał **189 s** i zakończył się rc=0: oba tarballe ZGODNE
z runnerem, oba buildy, 16/16 sum, 96 PASS / 0 FAIL. Toolchain od zera to dodatkowe ~45 s;
na ciepłym `/tmp` skrypty same się skracają (»już zbudowane«, »już pobrane«), więc recepturę
można bezpiecznie odpalać ponownie.

Receptura krok po kroku (ścieżki jak w sesji 24 IX):

```
# 0) toolchain (jeśli /tmp/erofs-c nie żyje)
tools/build_comp_libs.sh /tmp/comp-build
tools/build_erofs_local.sh /tmp/erofs-c

# 1) spool -> dwa tarballe (sumy weryfikuje skrypt, rc 0 = ZGODNY z runnerem)
mkdir -p /tmp/spool /tmp/romkit /tmp/ta-product
git fetch origin transfer-spool                 # UWAGA: na czystym klonie ref origin/transfer-spool
git archive FETCH_HEAD | tar -x -C /tmp/spool   # NIE istnieje - archive idzie po FETCH_HEAD
tools/assemble_raw_parts.py --parts /tmp/spool/transfer --out /tmp/rom-kit.tar.gz \
    --expect-sha256 537eb4ea0c98f4b87bd1ccdb2e0ab502745dfd0820ef1deefb9d42e2a5b0923b
tar -xzf /tmp/rom-kit.tar.gz -C /tmp/romkit          # w srodku m.in. system_tree (4568 wpisow)
tools/assemble_raw_parts.py --parts /tmp/spool/transfer \
    --out /tmp/ta-product/drive-1IjQeuVkiaE6B5c9YZkZJTpiAI-n4EU_1-assets.tar.gz \
    --expect-sha256 a53ff508fb4e9224350635fb87a5bc60e8829504b93f86a61e4ae1963c063ff6
tar -xzf /tmp/ta-product/drive-*.tar.gz -C /tmp/ta-product   # 172 wpisy: etc/ fonts/ overlay/
#    (oba --expect-sha256 to sumy z RAW_MANIFEST*.tsv / MANIFEST.tsv na spoolu - nie trzeba
#     ich pamietac, sa w plikach; skrypt sam znajduje manifesty z sufiksem biegu)

# 2) cztery drzewa (artrytmyka wpisow sprawdza sie przy kazdym kroku)
mkdir -p /tmp/donor
cp -al /tmp/romkit/system_tree /tmp/donor/            # FULL system: 4568 (obraz: -3 komentarze = 4565)
mkdir /tmp/tree2 && cp -al /tmp/romkit/system_tree /tmp/tree2/
rm -f /tmp/tree2/system_tree/system/etc/vintf/compatibility_matrix.{4,5,6}.{xml,komentarz.txt}
                                                      # LEKKI system: 4562 (build doklada macierz 5 -> 4563)
mkdir -p /tmp/prod-lekki-extract                       # wyciag z LEKKIEGO product, ktory zyje w gicie
/tmp/erofs-c/fsck.erofs --extract=/tmp/prod-lekki-extract \
    dist/release/HyperOS4_P11Gen2/product_hyperos4_p11g2.img    # (flaga --extract=, nie --out)
cp -a /tmp/prod-lekki-extract /tmp/tree-product        # LEKKI product: 67 (etc/{passwd,group} + 63 fonty)
mkdir -p /tmp/tree-full/etc                          # FULL product: 147 (132 pliki + 15 katalogow)
cp -a /tmp/ta-product/fonts /tmp/ta-product/overlay /tmp/tree-full/
cp -a /tmp/prod-lekki-extract/etc/passwd /tmp/prod-lekki-extract/etc/group /tmp/tree-full/etc/
                                                      # UWAGA: etc/{permissions,sysconfig,vintf} z tara
                                                      # NIE wchodza; puste katalogi usuniete (inaczej 150!=147)

# 3) dwa buildy (vbmeta NIE budowac - 9cf2e7e4… zyje w gicie)
tools/make_release.sh --product-tree /tmp/tree-product --system-tree /tmp/tree2/system_tree \
    --vintf-level 5 --vintf-optional-missing --out /tmp/rebuild-lekki \
    --erofs-dir /tmp/erofs-c --exclude-regex '\.komentarz\.txt$' --allow-no-vbmeta
tools/make_release.sh --product-tree /tmp/tree-full --system-tree /tmp/donor/system_tree \
    --out /tmp/rebuild-full --erofs-dir /tmp/erofs-c \
    --exclude-regex '\.komentarz\.txt$' --allow-no-vbmeta
#    pelne sumy sprawdz względem dist/release/*/SHA256SUMS.txt; wygenerowana macierz lekkiego
#    musi wyjsc 19197 B sha256 9ada17034a4880b5… (kontrola zrodla kaskady)

# 4) kopiuje sie TYLKO brakujace obrazy (flash-all/vbmeta/README juz sa z gita)
cp /tmp/rebuild-lekki/system_hyperos4_p11g2.img dist/release/HyperOS4_P11Gen2/
cp /tmp/rebuild-full/{system,product}_hyperos4_p11g2.img dist/release/HyperOS4_P11Gen2-full/

# 5) dowod
(cd dist/release/HyperOS4_P11Gen2 && sha256sum -c SHA256SUMS.txt)        # 8/8
(cd dist/release/HyperOS4_P11Gen2-full && sha256sum -c SHA256SUMS.txt)   # 8/8
SYSTREE=/tmp/tree2/system_tree SYSTREE_FULL=/tmp/donor/system_tree \
PRODTREE=/tmp/tree-product PRODTREE_FULL=/tmp/tree-full \
    tools/test_release.sh --erofs-dir /tmp/erofs-c --real               # 128 PASS / 0 FAIL (replay 24 IX ~14:10 dal 96/0 - sprzed F3/V/W)
```

Dwa szczególy, które kosztowaly najwiecej namyslu przy rekonstrukcji receptury:
- **lekki vs full system**: drzewo lekkiego to donor minus SZESC plikow runnera w `etc/vintf/`
  (trzy macierze kaskadowe `.4/.5/.6.xml` i trzy `.komentarz.txt`) — macierz 5 generuje sie
  na czas budowy (19197 B) i jest sprzatana; drzewo `-full` to donor w calosci, a `.komentarz.txt`
  wylacza `--exclude-regex`. Rownowazne byloby zostawienie komentarzy w drzewie i wylaczenie
  ich flaga — obraz wychodzi ten sam.
- **lekki vs full product**: lekki to tylko `etc/{passwd,group}` + 63 fonty (67 wpisow); `-full`
  doklada `overlay/` (67 apk w 12 podkatalogach) z assetow donora, ale NIE doklada 24 plikow
  `etc/` donora (`build.prop`, `permissions/`, `sysconfig/`, `vintf/`) — passwd/group pochodza
  z lekkiego obrazu, nie z tara donora.

## Maraton 24 IX (popołudnie): od trzech brakujących obrazów do 128/0

Godziny ~15:55–17:30: (1) odbudowa trzech nieśledzonych obrazów z `transfer-spool` **bajt w bajt**
(4/4 hashe — sekcja wyżej), (2) utwardzenie receptury trzema poprawkami znalezionymi dopiero przy
sprawdzaniu na czystym klonie (`git fetch origin transfer-spool` przed `git archive FETCH_HEAD`;
składanie assetów product donora przez `assemble_raw_parts.py`, nie `cat`; dokładna linijka
`fsck.erofs --extract=` zamiast komentarza), (3) **replay dosłowny** — blok kodu wycięty z tego
pliku wykonany bez zmian: 189 s, rc=0, (4) trzy nowe sekcje suity w schemacie F2/P2
(„ładunek wydania, którego żadna sekcja nigdy nie odpalała"):

| sekcja | co domknęła | kontroli |
|---|---|---:|
| F3 | `rollback.sh` — jedyny skrypt wydania nigdy nie wykonany: bash -n, sloty a/b, flash `vbmeta_stock_*`, heredoc „NIE przywraca product ani system", samolokalizacja z cudzego cwd, negatyw | 13 |
| V | wnętrze `vbmeta` — `flags=3`, testkey AOSP (sha1 `cdbb7717…` wg docs/03 §A.1), parsowane bez avbtoola; pułapka: offsety klucza względne wobec bloku AUX, nie początku pliku | 16 |
| W | `release-manifest.tsv` 1:1 — kolumna sha256 i wiersze skryptów nie były porównywane z plikami; zgodność manifest↔`SHA256SUMS` także dla plików nieobecnych (>100 MiB); negatyw z dwiema klasami błędu | 3 |

Liczniki suity: **88/96 → 120/128**. CI zielone dla `4e3452e` (F2), `9437ffa` (F3), `33ecec0` (V)
i `d4cebe2` (W) — oba workflow; sekcja W przeszła na runnerze z trzema nieobecnymi obrazami
(absent-skip + zgodność manifest↔SHA256SUMS dla nieobecnych — dokładnie po to jest ta gałąź
kontroli). Lekcja dnia numer jeden: dokument, który
opisuje procedurę odzysku, sam jest ładunkiem — dopóki nie został wykonany słowo w słowo, jest
hipotezą (a był w nim błąd: `git archive origin/transfer-spool` pada na czystym klonie).
