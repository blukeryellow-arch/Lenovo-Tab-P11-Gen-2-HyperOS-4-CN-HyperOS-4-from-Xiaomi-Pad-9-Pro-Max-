# HyperOS 4 na Lenovo Tab P11 Gen 2 — wariant COHERENT

Ten katalog to trzeci wariant obok **lekkiego** (`dist/release/HyperOS4_P11Gen2/`) i **-full**.
Różni się od lekkiego jedną partycją: dokłada **donorski `system_ext`** (Xiaomi Pad 9 Pro Max,
HyperOS 4, A17). Wszystko inne — system, product, vbmeta — to te same, zweryfikowane pliki
co w lekkim.

## Dlaczego coherent (i dlaczego dopiero teraz)

Do nocy 24/25 IX wiedzieliśmy o tablecie tyle, ile mówił aftermarket. Potem z Dysku pobraliśmy
prawdziwe artefakty targetu (`boot`, `vendor_boot`, `vbmeta` — md5 = sumy serwera Google) i
odczytaliśmy fakty: **MT6789, kernel 5.10.233 GKI (android12), vendor A12 (VNDK 31), stock =
LGSIU A14** — pełna analiza w `docs/09-analiza-targetu.md`. Stockowy `system_ext` (A14, sdk 34)
wymieszany z donorskim systemem A17 (sdk 37) to gwarantowany chaos klas — donorski `system_ext`
usuwa tę niespójność. Nazwa „coherent" znaczy: **system + system_ext z jednego buildu**.

Co NIE jest spójne i nie da się domknąć bez podpisu vendora: **vendor A12 ↔ system A17**
(pięć wersji API; stock sam akceptuje dwie — A14 na A12). To jest realne ryzyko tego wariantu.

## Czego uczciwie oczekiwać

| etap | szansa | najczęstsza przyczyna porażki |
|---|---|---|
| init (bramka VINTF) | ~85% | macierz poziomu 5 w wariancie miękkim otwiera bramkę (docs/06 §6.29) |
| Zygote / system_server | ~50-60% | brak HAL-i AIDL (A13+) na vendorze A12; apexd A17 na kernelu 5.10 |
| pulpit | ~10-25% | SurfaceFlinger A17 vs composer HIDL 2.1 (A12) — patrz docs/09 §5 |

**Nikt uczciwy nie da Ci tu 100%** — jedyna konfiguracja z gwarancją bootu to stock + moduł
fontów (`dist/modules/hyperos4_fonts_p11g2.zip`, ścieżka A). Ten wariant jest dla osoby, która
chce spróbować pełnego HyperOS 4 i umie czytać logcat.

## Zawartość

<!-- ROZMIARY-KONTRAKT
system_hyperos4_p11g2.img=920039424
system_ext_hyperos4_p11g2.img=632840192
product_hyperos4_p11g2.img=75198464
vbmeta_hyperos4_p11g2.img=4096
flash-all.sh=7662
rollback.sh=1345
device-probe.sh=6533
-->

| plik | bajty | co to |
|---|---|---|
| `system_hyperos4_p11g2.img` | 920 039 424 | HyperOS 4 A17 (ten sam co lekki): 4 563 wpisów, macierz poziomu 5 **wygenerowana**, wariant miękki; sha256 `4836dcd4…` |
| `system_ext_hyperos4_p11g2.img` | 632 840 192 | **donor oryginal** (bez przebudowy): 1 909 wpisów, A17 sdk 37; sha256 `7340a836…`, md5 Google `f879747f…` — te same bajty co na Dysku |
| `product_hyperos4_p11g2.img` | 75 198 464 | lekki product: `etc/{passwd,group}` + 63 fonty MiSans; sha256 `a961bec4…` |
| `vbmeta_hyperos4_p11g2.img` | 4 096 | Flags 3 (weryfikacja i verity wyłączone), testkey AOSP; sha256 `9cf2e7e4…` — identyczny w obu wcześniejszych wariantach |
| `flash-all.sh` | 7662 | bramki: sumy → identyfikacja → kopia vbmeta → **bramka rozmiaru (pytana!)** → resize tylko po zgodzie → flash vbmeta/system/system_ext/product |
| `rollback.sh` | 1 345 | przywraca vbmeta z kopii; **ostrzega**, że system_ext bez slotów nie ma rollbacku |
| `device-probe.sh` | 6 533 | krok 0 przed flashem (GO/NO-GO) — ten sam co w lekkim |

Sumy wszystkich plików: `SHA256SUMS.txt`; wiersz-per-plik: `release-manifest.tsv`.
Dwa duże obrazy (>100 MB) nie żyją w gicie — odbudowa: `docs/08` §„Odbudowa obrazów wydań"
(system: receptura; system_ext: `assemble_raw_parts.py` na gałęzi `transfer-spool`, bieg
`36030150849`, oczekiwane md5 `f879747f…`).

## Jak wgrać

```bash
./device-probe.sh                # 1. GO/NO-GO (fastbootd, rozmiary slotów, CONFIG_EROFS_FS_LZ4)
./flash-all.sh                   # 2. wariant A/B — zobacz niżej
```

`flash-all.sh` sam wykryje, czy urządzenie ma `system_ext_a/b` (flash zwykły, oba sloty), czy
`system_ext` bez slotów — **jednokierunkowy, bez rollbacku** — i wtedy wymaga dodatkowej zgody:

```bash
I_ACCEPT_SYSTEM_EXT_ONEWAY=yes ./flash-all.sh
```

Gdy `system` nie mieści się w slocie (stockowy slot bywa ciasny), ścieżka resize — jak w lekkim:

```bash
RESIZE_SUPER=1 I_ACCEPT_DATA_LOSS=yes ./flash-all.sh
# delete product_a/b + resize system_a/b (+64 MiB); product pominięty
```

Bez tych zmiennych skrypt **przerywa zamiast działać po cichu**.

## Awaria

1. `./rollback.sh` — vbmeta wraca na stock (kopia z kroku 2 flash-alla).
2. Boot/vendor_boot: `fastboot flash boot boot.img` + `vendor_boot` (pliki Lenovo z Dysku).
3. `system_ext` **bez slotów nie ma rollbacku** — powrót = stockowa paczka Lenovo (TB350FU).
4. Brick końcowy: BROM/DA MediaTek (to nie jest EDL Qualcomma) — naprawialne, opis w docs/05.

## Po flashu: triage (to jest nowość tej nocy)

Jeśli pulpit nie wstanie w 5–10 minut:

```bash
adb wait-for-device
adb logcat -b all -d > /tmp/logcat.txt
bash tools/postflash_triage.sh /tmp/logcat.txt
```

Skrypt powie **dokładnie, który podsystem stanął** (VINTF / montowanie / apexd / Zygote /
SurfaceFlinger / HAL-e / audio) i co z tym zrobić — lista podejrzanych jest znana z góry,
bo pochodzi z analizy targetu (docs/09), nie ze zgadywania.
