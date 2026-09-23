# Stan pracy i rzeczy zablokowane (23 IX 2026, ~22:00 UTC)

Notatka dla kontynuacji — skrót tego, co jest zmierzone, a co tylko napisane.

## Wydanie: co jest gotowe

`dist/release/HyperOS4_P11Gen2` (lekki: fonty) i `-full` (fonty + 67 nakładek RRO). Pliki w
każdym: `product_hyperos4_p11g2.img`, `system_hyperos4_p11g2.img`, `vbmeta_hyperos4_p11g2.img`,
`flash-all.sh`, `rollback.sh`, `device-probe.sh` (krok 0), `release-manifest.tsv`,
`SHA256SUMS.txt` (8 pozycji, `sha256sum -c` = 8/8 OK w obu wariantach), `build-info.txt`,
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

1. **GitHub: `GH_TOKEN` wygasł.** `git push` → „could not read Username for 'https://github.com'".
   Pięć commitów nad `41f1ebf` leży tylko lokalnie: `ef1918c` (DAC 0:0), `7623c87` i `2ce5343`
   (kontrola N w testach + naprawa tej kontroli), `45854a7` (ścieżka `--compress none`),
   `df32841` (krok 0 w wydaniu). CI **nigdy nie widziało sekcji K, L, M, N, P** — ostatni
   zielony run (`35918777924`, 13/13) dotyczy commita sprzed korekty DAC-a. Trzeba odświeżyć
   połączenie z GitHubem w Arena, potem: push + `gh run list --workflow=release-selftest.yml`.
2. **`codeload.github.com` zwraca 404** na tarballu źródeł (np. `madler/zlib` v1.3.1), więc
   `tools/build_comp_libs.sh` nie da się teraz uruchomić od zera. Cache w `/tmp/erofs-src` i
   `/tmp/comp-build` działa; po reboocie sandboxa trzeba będzie pobrać inaczej (repo `git clone`
   działało, `codeload` nie).

## Jak odtworzyć środowisko po reboocie sandboxa

```
tools/build_comp_libs.sh /tmp/comp-build            # zlib + lz4 (wymaga sieci na tarball)
tools/build_erofs_local.sh /tmp/erofs-c             # mkfs/fsck/dump, selfcheck na 3 binarkach
tools/test_release.sh --erofs-dir /tmp/erofs-c --real    # oczekiwane: 44 PASS, 0 FAIL
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
