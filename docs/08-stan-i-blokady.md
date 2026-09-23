# Stan pracy i rzeczy zablokowane (23 IX 2026, ~22:00 UTC)

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

1. **~~`GH_TOKEN` wygasł~~ — naprawione 24 IX ~00:50 UTC.** Pushy poszły, gałąź
   `arena/01a0ca42-…` stoi na `d84c3cc`, a bieg `release-selftest` **35927660767 ma 15/15
   kroków success**. To pierwszy bieg w historii, w którym „success" znaczy, że
   `tools/test_release.sh` **wyszedł zerem**: poprzednie (w tym chwalone 13/13 z `35918777924`)
   liczyły status `tee`, więc suita mogła failować do woli — `docs/06` §6.27. Sekcje K–N, P i Q
   widziały runnera dopiero teraz, realnie.
2. **~~`codeload.github.com` zwracał 404~~ — minęło.** 24 IX ~01:55 UTC oba tarballe
   (`madler/zlib` v1.3.1, `erofs/erofs-utils` master) odpowiadają `HTTP/2 200`. Cache
   `/tmp/erofs-c` nadal jest najszybszą ścieżką, ale odbudowa od zera znowu jest możliwa.
3. **Logi Actions pozostają nieczytelne z tej piaskownicy**: `gh run view --log` zwraca pusty
   wynik, a `gh run download` na artefakt `weryfikacja-log` 3 razy dostał EOF od
   `blob.core.windows.net`. Widoczne są więc statusy kroków i adnotacje (`::error::`/`::notice::`),
   nie treść logu — i o tym trzeba pamiętać, czytając moje „CI zielone".

## Jak odtworzyć środowisko po reboocie sandboxa

```
tools/build_comp_libs.sh /tmp/comp-build            # zlib + lz4 (wymaga sieci na tarball)
tools/build_erofs_local.sh /tmp/erofs-c             # mkfs/fsck/dump, selfcheck na 3 binarkach
tools/test_release.sh --erofs-dir /tmp/erofs-c --real    # oczekiwane: 45 PASS, 0 FAIL
```

Drzewa `staging/`, `images/`, `rom/` i wszystko w `/tmp` **nie są w gicie** (patrz `.gitignore`):
po reboocie zostaje sam kod narzędzi, a odtworzenie drzewa `product` to `tools/enrich_product.sh`
+ ekstrakcja z plików źródłowych ROM-u (inicjatywa: `diagnostics/drive-inventory.tsv`).

## Dług wobec CI

Sekcje K–P powstały już po ostatnim biegu CI. Na atrapie przechodzą lokalnie, ale
`P` używa `bash`-owych atrybutów i `mktemp`, a `N`/`K` skanu `docs/` — na Ubuntu w Actions nie
winny się różnić, jednak dopóki run tego nie powtórzy, twierdzenie „testy przechodzą" znaczy
„przechodzą u mnie". Zdanie „wszystko przechodzi" pozostaje prawdziwe tylko dla tego sandboxa, dopuki
CI nie powtórzy go na `df32841`.
