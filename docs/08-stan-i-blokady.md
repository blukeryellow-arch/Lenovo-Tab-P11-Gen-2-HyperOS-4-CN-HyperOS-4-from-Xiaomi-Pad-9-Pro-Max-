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
| `system` (oba) | 920 047 616 | `cf0b889d45a6bb4f6af3…` | 4 565/4 565 (3892 pliki + 409 symlinków + 264 katalogi) |
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

## Odtwarzanie środowiska jest tanie — `--real` już nie (zmierzone 24 IX 03:41 UTC)

Po re-clone sandboxa (`/tmp` pusty, `~/romtools` skasowane) łańcuch narzędzi wraca w minutę:

```
tools/build_comp_libs.sh /tmp/comp-build      # 11 s, od zera, bez cache: libz.a 150 244 B + liblz4.a 277 634 B
tools/build_erofs_local.sh /tmp/erofs-c       # ~30 s: mkfs 588 376 B, fsck 580 496 B, dump 571 776 B
tools/test_release.sh --erofs-dir /tmp/erofs-c        # 71 PASS / 0 FAIL
```

To przebieg **niezależny od wszystkiego, co miałem wczoraj**: identyczne liczniki, jakich wymaga
sekcja Q (16 pozycji kontraktu, `absent-skip 3`, wiersze `docs/07` 2/2) — czyli dokładnie ten kształt,
który widzi runner, bo oba katalogi wydania mają na czystym checkoutcie tyle samo plików co u mnie.
Z tą różnicą, że ciemna strona jest moja: **`--real` (79 PASS) wymaga drzew donora w `/tmp`
i `~/romtools/avb`, a te nie są w gicie i nie odtwarzają się same** — `system.img` (920 MB) i
`product.img` wariantu `-full` (150 MB) przekraczają limit GitHuba. Dlatego po reboocie mam prawo
napisać „71/0", a nie „79/0". `sha256sum -c` na czystym checkoutcie wychodzi
7/8 (lekki) i 6/8 (`-full`), a każde `FAILED open or read` to właśnie ten brakujący duży obraz —
nie niezgodność; lokalnie po odtworzeniu obrazów (24 IX) oba katalogi mają 8/8. Skrypty generowane
(`flash-all.sh` 8 776 w lekkim i 6 749 w `-full`, `rollback.sh` 1 152, `device-probe.sh` 6 533)
przechodzą `bash -n` i mają rozmiary zgodne z kontraktami README.

## Jak odtworzyć środowisko po reboocie sandboxa

```
tools/build_comp_libs.sh /tmp/comp-build            # zlib + lz4 (wymaga sieci na tarball)
tools/build_erofs_local.sh /tmp/erofs-c             # mkfs/fsck/dump, selfcheck na 3 binarkach
tools/test_release.sh --erofs-dir /tmp/erofs-c --real    # oczekiwane: 79 PASS / 0 FAIL z drzewami sesji (bez --real: 71)
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
