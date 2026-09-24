# 07 — Jak zweryfikować to wydanie (i czego każdy test NIE dowodzi)

Napisane dla kogoś, kto ma osiem plików z Dyska i nie ma mnie. Każdy poziom ma
**jedno polecenie, jedno oczekiwane wyjście i jedno zdanie o tym, czego nie dowodzi**.
Kolejność jest celowa: od najtańszego. Poziomu G nie da się pominąć — wszystko poniżej
niego sprawdza *pliki*, nie *uruchamianie*.

Wartości oczekiwane (wydanie po korekcie DAC z 23 IX 2026, uuid `67b7eb22-3ebb-4c21-8b01-8ff545f10d8d`, właściciel wpisów `0:0`):

| artefakt | bajty | sha256 (prefiks) | wpisy 1:1 |
|---|---|---|---|
| `HyperOS4_P11Gen2/product` | 75 198 464 | `a961bec46085883d…` | 67/67 |
| `HyperOS4_P11Gen2-full/product` | 150 560 768 | `da17ffcd20c0ab4e…` | 147/147 |
| `system` (oba warianty) | 920 047 616 | `cf0b889d45a6bb4f…` | 4 565/4 565 |
| `vbmeta` (oba warianty) | 4 096 | `9cf2e7e4…` | — |

---

## 0. Zanim cokolwiek: `device-probe.sh` (krok 0, tylko odczyty)

```
bash device-probe.sh --release .        # w katalogu wydania; rc 0 = go, 2 = nie flashuj
```

Mierzy trzy rzeczy, ktorych z plikami na dysku nie da sie zmierzyc: czy tablet jest w
fastbootd (`is-userspace`), czy oba sloty pomieszcza obrazy (`partition-size:product_a`,
`system_a`, ... porownywane z `release-manifest.tsv`) i czy kernel ma `CONFIG_EROFS_FS=y`
oraz `CONFIG_EROFS_FS_LZ4=y` (przez adb, jezeli device zyje). To trzecie jest warunkiem
wstepnym wydania, nie ciekawostka: bez `LZ4` montaz odmawia, a wariant bez kompresji trzeba
zbudowac samemu (§6.10, §6.21). Scenariusze bramek sa w testach (sekcja P suite, osiem
przypadkow + dwie kontrole formy wypowiedzi).

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

**Dowodzi:** każdy plik po sha256 **i po try** (`0o644` vs `0o600` to rozbieżność od
23 IX 2026), każdy symlink po `readlink`, każdy katalog po istnieniu; `--expect-owner` porównuje
dodatkowo uid/gid korzenia partycji przez `dump.erofs --nid` (działa bez roota).
To jest najmocniejsza kontrola w projekcie i jedyna, która łapie „builder zgubił podkatalog" —
klasę błędu, przy której „wszystkie pliki OK" znaczy tyle, co „nikt nie zajrzał".
**NIE dowodzi:** `uid`/`gid` poszczególnych plików. Ekstrakcja jako zwykły użytkownik nie odda
właściciela (`chown` mu nie wolno) — per plik da się to zmierzyć tylko z rootem,
`sudo fsck.erofs --extract=…`. Korzeń partycji sprawdzam osobno (`dump.erofs`), i to wystarczyło,
żeby 23 IX 2026 złapać realny błąd wydania: oba obrazy miały `Uid: 1001 Gid: 1001` (uid `radio`)
zamiast `0:0`, bo `mkfs.erofs` dziedziczy właściciela z drzewa.
Etykiety SELinux biorą się ze ścieżki w polityce Lenovo, więc plik na dobrej ścieżce dostanie
dobrą etykietę, ale bity wykonania i setuid trzeba sprawdzić na urządzeniu:

```
adb shell 'ls -lZ /system/bin/su /product/bin 2>/dev/null; restorecon -RFv /product 2>&1 | head'
```

## C. Powtarzalność: czy budowanie jest deterministyczne

```
bash tools/test_release.sh --erofs-dir <katalog z mkfs/fsck>
```

Oczekiwane: `=== podsumowanie: 38 PASS, 0 FAIL ===`, a z `--real`: `=== podsumowanie: 46 PASS, 0 FAIL ===`.

Sekcje: A selftest buildera · B determinizm (dwa `mkfs.erofs` na tym samym drzewie = **identyczny
plik**, `cmp` bez różnic) · C **test negatywny** weryfikatora (drzewo ma plik, którego nie ma w
obrazie → musi być rc=1 i wskazanie nazwy) · D symlinki (podmiana celu musi być wykryta) ·
E–I bramka rozmiaru i kolejność flashów na atrapie `fastboot` · J (tylko `--real`) oba wydania ·
K kontrola pisma · L `fsck.erofs` na zbudowanym obrazie (tylko `--real`) · M `device_probe.sh` na
zestawie pułapek (NO-GO przy braku `EROFS_FS_LZ4`, przy `system_a` 256 MB, przy slocie o bajt
mniejszym) · N README-y nie mogą obiecywać rozmiaru mniejszego niż build (patrzy też na blok
`ROZMIARY-KONTRAKT`) · P granica `<` vs `<=` w bramce · Q kontrakt rozmiarów: każdy plik wydania
w `$OUT/README.md` musi mieć w nim tę samą liczbę bajtów co na dysku, a tam, gdzie README w ogóle
o pliku mówi, liczba musi wrócić w prozie; plus spójność liczby kolumn w tabelach markdown.
Licznik „przeanalizowane pozycje kontraktu: 16" jest asercją (`seen<16` = FAIL), nie opisem ·
R pliki workflow: `yaml.safe_load` każdego `.github/workflows/*.yml`, brak poleceń powłoki w
kolumnie 0 i próg `bloki run >= 8` (24 IX 2026 zepsuty `build.yml` dawal zero jobow, czyli ani
jednego FAIL-a — patrz `docs/06` §6.28).

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

Status: **bieg `release-selftest` 35927660767 (24 IX 2026, ubuntu-latest, `d84c3cc`) — 15/15
kroków success**; bieg na `059b850` jest poza moim zasięgiem wzroku, bo API odpowiedziało 401, w tym ekstrakcja obrazu zbudowanego moim `mkfs.erofs` narzędziem z pakietu Ubuntu
i porównanie per plik. Od tego commita krok suity liczy `rc=${PIPESTATUS[0]}`, więc zieleń znaczy
naprawdę „`test_release.sh` wyszedł zerem". Biegi wcześniejsze — w tym wielokrotnie przeze mnie
cytowane 13/13 z `35918777924` — patrzyły na status `tee`, czyli na nic; `docs/06` §6.27. Wymaga to `sudo add-apt-repository -y universe`: pierwsza
wersja kroku instalowala z `>/dev/null 2>&1 || true`, pakiet nie wchodzil, a krok byl
**zielony** — blad wyszedl dwa kroki pozniej jako `127`. Dlatego krok instalacji dzis
mowi wszystko i ustawia `DISTRO_OK`, ktorego kroki sluchaja (brak pakietu = `::notice::`
i swiadome pominiecie, NIE FAIL wydania).

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

## F. vbmeta: co jest podpisane, a co NIE jest poświadczone

```
python3 ~/romtools/avb/avbtool.py info_image --image vbmeta_hyperos4_p11g2.img
```

Zmierzone na tym wydaniu (dokładna treść, nie przybliżona):

```
Minimum libavb version:   1.0
Public key (sha1):        cdbb77177f731920bbe0a0f94f84d9038ae0617d
Algorithm:                SHA256_RSA2048
Rollback Index:           0
Flags:                    3
Descriptors:
    Prop: com.android.build.system.fingerprint -> 'hyperos4.p11g2.experiment'
```

**Dowodzi:** że vbmeta jest poprawnie podpisana (własnym, testowym kluczem), że `Flags: 3`
wyłącza weryfikację i łańcuch, oraz że licznik anty-rollback zostaje na 0 — a to decyzja
jednokierunkowa, więc świadoma (`docs/03`).
**NIE dowodzi integralności obrazów.** W tej vbmetcie **nie ma żadnego deskryptora HASHTREE**:
`/product` i `/system` nie są przez nią hashowane ani poświadczone. Kto podmieni bajt w
`product_hyperos4_p11g2.img`, ten nie zostanie wykryty — i nie da się tego naprawić bez klucza
Lenovo. To jest cena wymiany partycji, trzeba ją znać, a nie opisywać.

Sprostowanie, bo poprzednia wersja tego dokumentu była nieprawdziwa: pisałem tu o „jednym
deskryptorze `HASHTREE` dla `product`" i o „17–35× zapasu w deskryptorze". To opis **fabrycznej**
vbmet Lenovo (jeden deskryptor HASHTREE, `image size 2 748 350 464 B`), nie mojej — myliłem
oba obiekty w jednym zdaniu. Skutek dla czytającego: rozmiar z fabrycznej vbmet jest użyteczny
jako **pomiar slotu** i nic poza tym. Jeśli na urządzeniu weryfikacja jest włączona, moja vbmeta
**nie wystarczy** i flash musi iść z `--disable-verification` (patrz README wydania).

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
2. `uid`/`gid` per plik w obrazach — B porównuje try zawsze, a właściciela tylko korzenia
   (pełny pomiar wymaga `sudo fsck.erofs --extract`). Wczesne wydanie miało przez to `Uid: 1001
   Gid: 1001` w obu partiach; naprawione `--force-uid/gid` w `make_release.sh` i pilnowane sekcją
   M w `tools/test_release.sh` (M2 dowodzi, że *bez* flagi błąd wraca).
3. Zawartości prawdziwego `/product` z paczki 6,4 GB (wydanie idzie na drzewie 65/132 plików).
4. Tego, że `--exclude-regex '\.komentarz\.txt$'` nie wyciął niczego potrzebnego — w `system/etc/vintf`
   jest 0 takich plików (zmierzone `fsck --extract`), ale to wycinek, nie pełny audyt.
5. Rzeczywistych rozmiarów slotów na Twoim egzemplarzu (D liczy na atrapie).
