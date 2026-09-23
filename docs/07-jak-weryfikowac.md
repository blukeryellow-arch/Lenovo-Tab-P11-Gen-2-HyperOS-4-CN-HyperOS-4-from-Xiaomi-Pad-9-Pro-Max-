# 07 — Jak zweryfikować to wydanie (i czego każdy test NIE dowodzi)

Napisane dla kogoś, kto ma osiem plików z Dyska i nie ma mnie. Każdy poziom ma
**jedno polecenie, jedno oczekiwane wyjście i jedno zdanie o tym, czego nie dowodzi**.
Kolejność jest celowa: od najtańszego. Poziomu G nie da się pominąć — wszystko poniżej
niego sprawdza *pliki*, nie *uruchamianie*.

Wartości oczekiwane (wydanie `9372bcb`/`3c32fb5`, obie warianty, uuid `67b7eb22-3ebb-4c21-8b01-8ff545f10d8d`):

| artefakt | bajty | sha256 (prefiks) | wpisy 1:1 |
|---|---|---|---|
| `HyperOS4_P11Gen2/product` | 77 619 200 | `16afbc350e75fda3…` | 67/67 |
| `HyperOS4_P11Gen2-full/product` | 153 391 104 | `b28e1c0eb0c769cd…` | 147/147 |
| `system` (oba warianty) | 967 503 872 | `36238fac308fb674…` | 4 565/4 565 |
| `vbmeta` (oba warianty) | 4 096 | `9cf2e7e4…` | — |

---

## A. Integralność pobrania

```
cd <katalog wydania> && sha256sum -c SHA256SUMS.txt
```

Oczekiwane: 7 linii `OK`, rc=0.

**Dowodzi:** że pliki są identyczne z tymi, które wyszły z `make_release.sh`.
**NIE dowodzi:** że te pliki są *dobre* — sumy liczy ten, kto budował. Złe wydanie z dobrymi
sumami istnieje; dlatego są poziomy B, C i E. Uwaga celowa: `*.md` **nie jest w sumach**, więc
inny tekst w README nie jest rozbieżnością (patrz docs/06 §6.16, punkt 1).

## B. Zawartość: czy w obrazie jest dokładnie to, co w drzewie

```
tools/verify_image.sh --img <product|system>.img --tree <drzewo> --fsck <fsck.erofs> \
    [--exclude '\.komentarz\.txt$']
```

Oczekiwane dla producta lekkiego: `zrodlo: 67 wpisów (pliki 65, symlinki 0, katalogi 2)`,
`ZGODNE: 67  rozbiezne: 0  brak z obrazu: 0  dodatkowe: 0`. Dla systemu: 4 565 (3 892 + 409 + 264)
i `--exclude` **konieczne**, bo trzy pliki `.komentarz.txt` są wykluczone z obrazu świadomie.

**Dowodzi:** każdy plik po sha256, każdy symlink po `readlink`, każdy katalog po istnieniu.
To jest najmocniejsza kontrola w projekcie i jedyna, która łapie „builder zgubił podkatalog" —
klasę błędu, przy której „wszystkie pliki OK" znaczy tyle, co „nikt nie zajrzał".
**NIE dowodzi:** poprawności `mode`/`uid`/`gid` — tego mój `verify_image.sh` **nie porównuje**
(znana dziura, wpisana w docs/06). Etykiety SELinux i `fs_config` biorą się ze ścieżki w
polityce Lenovo, więc plik na dobrej ścieżce dostanie dobrą etykietę, ale *try* wykonawczy
(-rws, -rwx) trzeba sprawdzić na urządzeniu:

```
adb shell 'ls -lZ /system/bin/su /product/bin 2>/dev/null; restorecon -RFv /product 2>&1 | head'
```

## C. Powtarzalność: czy budowanie jest deterministyczne

```
bash tools/test_release.sh --erofs-dir <katalog z mkfs/fsck>
```

Oczekiwane: `=== podsumowanie: 24 PASS, 0 FAIL ===` (bez `--real`: 16 PASS, 0 FAIL).

Sekcje: A selftest buildera · B determinizm (dwa `mkfs.erofs` na tym samym drzewie = **identyczny
plik**, `cmp` bez różnic) · C **test negatywny** weryfikatora (drzewo ma plik, którego nie ma w
obrazie → musi być rc=1 i wskazanie nazwy) · D symlinki (podmiana celu musi być wykryta) ·
E–I bramka rozmiaru i kolejność flashów na atrapie `fastboot` · J (tylko `--real`) oba wydania.

**Dowodzi:** że nie ma ukrytej losowości (timestampy, UUID, kolejność katalogowania), więc
porównywanie sha256 między maszynami ma sens — i że kontroli B i D nie da się przejść przez ich
*nieistnienie*. **NIE dowodzi:** że obrazy da się zbudować z oryginalnego ROM-u — test idzie na
drzewach syntetycznych; 1:1 z `product.img` 6,4 GB to inna praca (`tools/enrich_product.sh`).

## D. Instalator: że nie zbrickuje przy złych warunkach

Te same sekcje E–I co wyżej, na atrapie `fastboot`:

| scenariusz | oczekiwane |
|---|---|
| brak `system.img` w katalogu | rc=1, **zero** flashów |
| sloty obszerne (product 4 GB, system 64 GB) | rc=0, 6 flashów |
| system 900 MB na slocie 768 MB | rc=1, zero flashów |
| product na slocie 4 KB | rc=1, zero flashów |
| `fastboot` nie zna `partition-size` | rc=0, ostrzeżenie + 6 flashów |
| `is-userspace: no` (nie fastbootd) | rc=1, zero flashów |

**Dowodzi:** że bramka `stat -Lc%s` kontra `partition-size` działa **zanim** cokolwiek zostanie
napisane, i że instalator nie „idzie dalej" przy braku obrazu. **NIE dowodzi:** że *prawdziwy*
fastboot odpowiada tak jak atrapa — na urządzeniu sprawdź ręcznie:

```
fastboot getvar partition-size:product_a ; fastboot getvar partition-size:system_a
fastboot getvar is-userspace ; fastboot getvar current-slot
```

`system_a` **nie ma** deskryptora HASHTREE w fabrycznej vbmeta, więc jego rozmiar zna tylko
`getvar` — i dlatego bramka istnieje (docs/06 §6.11, docs/03).

## E. Format: że patrzy na to narzędzie z zewnątrz

```
# to robi .github/workflows/release-selftest.yml — bieg 'release-selftest'
mkfs.erofs (moja budowa) -> fsck.erofs (pakiet Ubuntu) --extract -> porownanie per plik
dump.erofs -s <obraz>   # superblock
```

Oczekiwane na `system.img`: `Filesystem incompatible features: lz4_0padding`,
`Required upstream Linux kernel version: 5.4`, `compressed files: 2738`, `uncompressed: 1828`.

**Dowodzi:** że obrazu nie da się zmontować kernelowi bez `EROFS_FS_LZ4` — i to jest
*pozytywny* wniosek: feature jest w `incompatible`, więc odmowa nastąpi przy **montowaniu**,
nie przy czytaniu pliku. Kernel 5.10/5.15 w TB350FU (A12L) ma EROFS+lz4, a źródłowy obraz
HyperOS też jest lz4 (docs/06 §6.10, §6.17).
**NIE dowodzi — i tu jest najgroźniejsze nieporozumienie — że „`fsck` przeszedł" znaczy „obsługuje
kompresję".** Bez `--extract` `fsck.erofs` sprawdza tylko metadane i zwraca **rc=0** na obrazie,
którego nie umie rozpakować. Tak samo nie mówią nic testy zrobione na danych **losowych**:
`-zlz4` na 300 KB szumu nie zbija bajta i wtedy nawet stary build „czyta" (patrz §6.17).
Każdy, kto powtarza te pomiary, musi mieć w drzewie dane podatne na kompresję.

## F. vbmeta: co jest podpisane, a co nie

```
python3 ~/romtools/avb/avbtool.py info_image --image vbmeta
```

Oczekiwane: `Flags: 3` (verification + chain *wyłączone*), `Rollback Index: 0`, jeden descriptor
`HASHTREE` dla `product`, klucz sha1 `cdbb7717…` (klucz **testowy**, nie Lenovo).

**Dowodzi:** że `product` ma drzewo haszy zgodne z *moim* obrazem i że rozmiar partycji w
deskryptorze (2 748 350 464 B) daje 17–35× zapasu, więc wariant `-full` mieści się z luzem.
**NIE dowodzi żadnego zaufania:** to klucz testowy AOSP. `Flags: 3` znaczy, że weryfikacja jest
**wyłączona** — obraz jest *samo-spójny*, nie *zaufany*. Nie da się tego obejść bez klucza
Lenovo, którego nie ma i być nie powinno. Jeśli na urządzeniu weryfikacja jest włączona, ten
vbmeta **nie** wystarczy i flashing musi iść z `--disable-verification` (patrz README wydania).

## G. Urządzenie: jedyne, co dowodzi uruchomienia

```
adb shell 'zcat /proc/config.gz | grep -E "EROFS"'         # PRZED flashem
adb shell 'getenforce; mount | grep -E " /(system|product) "'
adb shell 'ls -l /product/etc/passwd /product/fonts/MiSansKRVariable.ttf'
adb shell 'pm list packages -p /product/overlay | head'   # tylko -full
adb shell 'dmesg | grep -iE "erofs|avb|denied" | tail -40'
adb shell 'logcat -b all -d | grep -iE "vintf|HAL|failed to" | head -40'
```

Oczekiwane: `CONFIG_EROFS_FS=y`, `CONFIG_EROFS_FS_LZ4=y` (bez tego: nie flashuj, użyj
`--compress none` i licz się z tym, że `system` przestaje się mieścić — §6.10); `erofs`
zamontowane na `/system` i `/product`; `avb: verified` albo jawne „disabled", ale **bez**
`avb: hashtree descriptor digest mismatch`; `denied` dotyczące `/product/*` = źle odtworzone
etykiety → `restorecon`, potem zgłoś.

**Dowodzi:** tylko to, że ten obraz na tym urządzeniu startuje. Bootowalność **nie jest**
w tym projekcie udowodniona ani jedną kontrolą — nikt z nas nie odpalił tego na TB350FU.

---

## Progi decyzyjne

- rc≠0 w A → nie flashuj, pobierz ponownie.
- rc≠0 w B (rozbieżność) → drzewo nie zgadza się z obrazem; winny jest **albo** build, **albo**
  test (patrz §6.16 punkt 2 — przydarzyło się raz, i to test był winny). Nie zgaduj: odpal
  `verify_image.sh` z `--fsck` i czytaj nazwy wpisów.
- rc≠0 w C na determinizmie → w `mkfs.erofs` lezie losowość; sprawdź `-T 0` i `-U` w
  `make_release.sh`, zanim uznasz, że „to tylko cosmetic".
- brak `CONFIG_EROFS_FS_LZ4` w G → `--compress none` (albo nic), nie „jakoś to zadziała".
- `avb: digest mismatch` w G → `vbmeta` nie pasuje do `product.img`; wgraj parę z tego samego
  katalogu wydania, nie mixuj wariantów.

## Czego w tym projekcie NIE sprawdzono (żeby nikt nie czytał ciszy jako zgody)

1. Bootowania na sprzęcie — patrz G.
2. `mode`/`uid`/`gid` w obrazach (B ich nie porównuje).
3. Zawartości prawdziwego `/product` z paczki 6,4 GB (wydanie idzie na drzewie 65/132 plików).
4. Tego, że `--exclude-regex '\.komentarz\.txt$'` nie wyciął niczego potrzebnego — w `system/etc/vintf`
   jest 0 takich plików (zmierzone `fsck --extract`), ale to wycinek, nie pełny audyt.
5. Rzeczywistych rozmiarów slotów na Twoim egzemplarzu (D liczy na atrapie).
