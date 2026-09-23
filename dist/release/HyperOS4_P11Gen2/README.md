# HyperOS 4 dla Lenovo Tab P11 Gen 2 (TB350FU) — zestaw do flashowania

Zbudowane lokalnie 2026-09-23, bez chmury buildowej, narzędziami zbudowanymi w sandboksie
(`tools/build_erofs_local.sh`). Cała historia i liczby: `docs/06-budowa-lokalna.md`.

## Co tu jest

| plik | bajty | co to |
|---|---|---|
| `product_hyperos4_p11g2.img` | 87 973 888 | partycja `/product` w EROFS: `fonts/` (28 plików MiSans VF w 13 wariantach + Arimo + SourceHanSansCN) |
| `vbmeta_hyperos4_p11g2.img` | 4 096 | vbmeta z `Flags: 3` (weryfikacja i verity wyłączone), `rollback_index 0`, SHA256_RSA2048, key `cdbb7717…` |
| `system_hyperos4_p11g2.img` | 1 376 899 072 | `/system` z HyperOS 4 (framework + MiSans + 67 nakładek RRO + VINTF 4/5/6). **Nie ma go w gicie** — patrz niżej |
| `flash-all.sh` | — | flashowanie: bramka sum → `getvar` → kopia vbmeta → **oba sloty** → reboot |
| `rollback.sh` | — | przywraca vbmeta z kopii wykonanej przed flashem |
| `release-manifest.tsv` | 553 | `plik ⇥ bajty ⇥ sha256` |
| `SHA256SUMS.txt` | — | liczony na końcu, `sha256sum -c` przechodzi |
| `mkfs.log`, `fsck.log` | — | surowe logi budowy i sprawdzenia obrazu |

## Skąd wziąć brakujący obraz system

Trzy sposoby, od najtańszego:

1. **Masz już** — jeśli ściągałeś `rom-kit.tar.gz` z gałęzi `transfer-spool` (sha256
   `ae675fdc132707ef…`, `dist/rom-kit/SHA256SUMS.txt`), to ten sam plik:
   ```
   cmp system_hyperos4_p11g2.img <(…)   # albo po prostu: sha256sum i porównaj z manifestem
   ```
2. **Zbuduj** (deterministyczne — obraz wyjdzie co do bajta taki sam):
   ```
   tools/build_erofs_local.sh
   tools/unpack_on_runner.sh      # wyciąga drzewo z product.tar.gz / system_extract*.tar.gz
   tools/make_release.sh --product-tree <drzewo> --system-img <system.img> \
       --avb <avbtool.py> --key <testkey.pem> --erofs-dir /tmp/erofs-build --out <katalog>
   ```
   `make_release.sh` ma `--selftest` (łańcuch mkfs → fsck → round-trip na drzewie syntetycznym).
3. **Z CI** — `rom_build: 1` w `dispatch_events` na `.github/workflows/deploy.yml`; ten kanał
   ma limit ~100 MB/blob, więc `system.img` idzie tam splitowany (`tools/assemble_raw_parts.sh`).

## Zanim wgrasz

```
sha256sum -c SHA256SUMS.txt        # musi byc OK dla kazdej pozycji
bash flash-all.sh                  # bootloader odblokowany, USB przy tablecie
```

`flash-all.sh` wymaga `system_hyperos4_p11g2.img` obok siebie i **przerwie bez flashowania**,
jeśli sumy się nie zgadzają albo tablet nie jest w fastbootd (`is-userspace`). Flashuje oba
sloty — sam bieżący daje „flash OK, boot stop". `/data` zostaje nietknięte, więc przy pierwszej
próbie zrób własnoręcznie `fastboot -w` i licz się z utratą danych.

## Realny stan weryfikacji — bez owijania

Sprawdzone: `fsck.erofs` czysto; round-trip (każdy plik wyciągnięty z obrazu ma identyczne
sha256 ze źródłem); determinizm dwóch budowań; sekwencja `flash-all.sh` na atrapie fastboot
w 4 scenariuszach (brak obrazów, zły produkt, brak fastbootd, komplet).

**Niesprawdzone: czy tablet wstanie.** `Flags: 3` wyłącza komunikat weryfikacji, więc awaria
wygląda jak cisza, nie jak błąd. Ratunek: `rollback.sh` + obrazy stock z Dysku
(`diagnostics/drive-inventory.tsv`), zapasowo tryb EDL.

## Luzy, które są udokumentowane, ale istnieją

`system` z HyperOS woła pod `/product` rzeczy, których minimalny obraz nie ma (pomiar:
`diagnostics/product-refs.tsv`) — m.in. `etc/aconfig_flags.pb`, `etc/fonts_customization.xml`,
`etc/selinux/product_*.contexts`, katalog `pangu/`. Jak je dołożyć z pełnego `product.img`
(6,4 GB): `tools/enrich_product.sh --src <product.img> --tree <drzewo>` i przebudować obraz.
