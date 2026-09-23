# HyperOS 4 dla Lenovo Tab P11 Gen 2 (TB350FU) — zestaw do flashowania

Zbudowany i zweryfikowany **lokalnie** (bez chmury buildowej), narzędziami zbudowanymi
w tym samym sandboksie. Historia decyzji i wszystkie pomiary: `docs/06-budowa-lokalna.md`.

**Format obrazów: EROFS + `lz4`.** To nie kosmetyka — bez kompresji `system` miał
1 376 899 072 B, a źródłowy obraz HyperOS ma 937 791 488 B, bo HyperOS pakuje lz4.
Mój `lz4` daje 967 503 872 B (+3,2 % wobec źródła, −29,7 % wobec wersji bez kompresji).

## Warianty

| | co w `/product` | rozmiar `product.img` | dla kogo |
|---|---|---|---|
| `HyperOS4_P11G2` (ten katalog) | `fonts/` (28 plików MiSans VF w 13 wariantach, Arimo, SourceHanSansCN) | **77 619 200 B** | domyślny: minimalny surface zmiany |
| `HyperOS4_P11G2-full` | fonty **+ 67 nakładek RRO** (HyperOS-owy wygląd; `SettingsRroCommonOverlay` itd.) — jedyne miejsce, gdzie te RRO sie powoduja | **153 391 104 B** | jeśli ma być „HyperOS Look", nie tylko fonty |

`system` i `vbmeta` są w obu wariantach **tym samym plikiem** (identyczne sha256 — budowane
z tego samego drzewa i tego samego UUID).

## Skład wydania

| plik | bajty | co to |
|---|---|---|
| `product_hyperos4_p11g2.img` | 77 619 200 | `/product` (EROFS+lz4), zweryfikowany 64/64 wpisów 1:1 |
| `system_hyperos4_p11g2.img` | 967 503 872 | `/system` z HyperOS 4 (framework, `system/fonts` z MiSans, `system/etc/permissions` 27 plików, wygenerowane macierze VINTF 4/5/6). Nakładek RRO **tu nie ma** — `system/product` w tym obrazie nie istnieje (zmierzone: `fsck.erofs --path=system/product` → rc 1), więc `/product` z tego wydania niczego nie przykrywa, tylko dokłada, zweryfikowany **4 565/4 565** wpisów 1:1. **Nie ma go w gicie** (limit 100 MB/blob) — patrz przepis niżej |
| `vbmeta_hyperos4_p11g2.img` | 4 096 | `Flags: 3` (weryfikacja + verity wyłączone), `rollback_index 0`, SHA256_RSA2048, key `cdbb7717…` |
| `flash-all.sh` | ~3,4 kB | bramka sum → `getvar` → kopia vbmeta → **bramka rozmiaru partycji** → oba sloty → reboot |
| `rollback.sh` | 469 | przywraca vbmeta z kopii wykonanej przed flashem |
| `release-manifest.tsv` | ~0,6 kB | `plik ⇥ bajty ⇥ sha256 ⇥ uwaga` |
| `SHA256SUMS.txt` | — | liczony na końcu; `sha256sum -c` = 8/8 OK |
| `build-info.txt` | — | kompresja, UUID, wersja `mkfs.erofs`, ścieżki drzew |
| `mkfs.log`, `fsck.log`, `system-verify.log` | — | surowe logi budowy i obu sprawdzeń |

## Jak to wgrać

```
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

## Wymóg kernela (to jedyne, co może Cię zaskoczyć)

Obraz `system`/`product` z `lz4` wymaga, żeby **kernel Lenovo** miał `CONFIG_EROFS_FS_LZ4=y`:

```
adb shell 'zcat /proc/config.gz | grep EROFS'
```

Nie ma? Wtedy flashuj wariant bez kompresji: `tools/make_release.sh … --compress none`
(pliki ~1,5× większe — `system` 1 376 759 808 B (bez wykluczen: 1 376 899 072 B z CI), `product` 87 973 888 B), albo zrezygnuj.
Format lz4 nie jest tu moim widzimisię: źródłowy `system.img` HyperOS-u jest lz4-owy.

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
  --compress lz4 --exclude-regex '\.komentarz\.txt$' \
  --avb <avbtool.py> --key <testkey_rsa2048.pem> --erofs-dir /tmp/erofs --out /tmp/release
#   --exclude-regex wylacza z PARTYCJI pliki-notatki generatora (*.komentarz.txt, 3 x ~400 B);
#   drzewo zostaje z notatkami, obraz jest o 4 096 B czystszy i bez nich w /system/etc/vintf

# 5) dowod, ze to TO SAMO
sha256sum /tmp/release/product_hyperos4_p11g2.img   # 8dcc73f265c9aaf8f52f…
sha256sum /tmp/release/system_hyperos4_p11g2.img     # 498d85c4986847ee0b49…
sha256sum /tmp/release/vbmeta_hyperos4_p11g2.img     # 9cf2e7e4e165687abe78…
# wariant -full: product f801945b295b253cd208… (system i vbmeta jak wyzej)
```

`make_release.sh --selftest` przechodzi ten łańcuch na drzewie syntetycznym, więc narzędzia
można sprawdzić, zanim ruszy się prawdziwe obrazy.

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

## Czego NIE sprawdzono

**Bootalności.** Nic wyżej nie dowodzi, że tablet wstanie; `Flags: 3` wygasza komunikat
weryfikacji, więc awaria wygląda jak cisza. Ratunek: `rollback.sh`, stockowe obrazy Lenovo
(`boot`/`vendor_boot`/`vbmeta` — ID w `diagnostics/drive-inventory.tsv`), zapasowo EDL.
Braki HAL-i, których vendor `mt6789` nie ma (audio AIDL, health, power, thermal — `docs/05`
§5.1), nie znikają przez obniżenie ich do `optional`: to usuwa blokadę startu, nie dodaje
implementacji.
