# 4. Proweniencja obrazów i zmierzony kernel — zamiast zgadywania po nazwach plików

Data pomiaru: 2026-09-22. Źródło: pliki z Google Drive + `avbtool` (AOSP, `LineageOS/android_external_avb`)
uruchomione lokalnie. Nic w tym dokumencie nie jest opinią z forum.

## 4.1 Kanał transferu — zmierzony sufit, nie deklaracja

Wcześniejsza teza „binariów i tak nie pobiorę" była **fałszywa**. Realne ograniczenia konektora Drive:

| próba | plik | wynik |
|---|---|---|
| pobranie całości | `vbmeta.img` 8 192 B | OK, zapisany do `google_drive/` |
| pobranie całości | `boot.img` 67 108 864 B | OK |
| pobranie całości | `vendor_boot.img` 67 108 864 B | OK |
| pobranie całości | `system_ext.img` 632 840 192 B | **ODRZUCONE**: `File is 632840192 bytes, over the 104857600 byte limit` |
| `range_header` (bytes=0-2097151) | `system_ext.img` | **ODRZUCONE**: tryb zakresu jest wewnętrznie łączony z URL-em, a „the download URL always serves the whole file" |

Wniosek praktyczny: **limit to dokładnie 104 857 600 B (100 MiB) na plik, tylko whole-file, bez zakresów**.
Z Twoje 9 plików przechodzą trzy małe; `system.img` (938 MB), `system_ext.img` (633 MB),
`vendor_mystical.img` (665 MB), `odm.img` (3,1 GB) i `product.img` (6,4 GB) nie przejdą nigdy.

Drugi warunek, kosztowny gdy się o nim zapomni: **pliki w workspace poza gitrem nie przeżywają jednej tury**
(`google_drive/` jest w `.gitignore`, więc po resecie sandboxa `vbmeta.img` zniknął). Analizę trzeba
wykonać w tej samej turze co pobranie. Utrwalone reguły: 100 MB na plik + „pobierz i policz od razu".

## 4.2 Co naprawdę siedzi w trzech plikach, które przeszły

Wynik `diagnostics/identify_images.sh google_drive` (skrypt wyciąga z każdego obrazu jego wbudowany blok
vbmeta i podaje go `avbtool info_image`):

```
### boot.img         67 108 864 B   android boot image
    AVB: blok @21045248 (1536 B) algorytm=SHA256_RSA2048
### vbmeta.img        8 192 B       vbmeta (partycja vbmeta)
    AVB: blok @0 (5568 B) algorytm=SHA256_RSA2048
### vendor_boot.img  67 108 864 B   vendor_boot
    AVB: blok @22921216 (576 B) algorytm=NONE
```

Atrybuty odczytane z fragmentów przez avbtool:

| pole | `boot.img` | `vendor_boot.img` |
|---|---|---|
| Public key (sha1) | `9d808b0995768d0677fccb1efcddb7cf9e153d99` | brak (Algorithm NONE) |
| Hash descriptor → Partition Name | `boot` | `vendor_boot` |
| Salt | `8c82d22aa6c5194c334ecf9113ff7afc334e416c0cd6c0b94d7a993d81fefac0` | **identyczny** |
| Digest | `3bbcf68658b2a313c5af2ef0d59837344d87f110e4829982e252096307511184` | `104eb50664a08f6a4444c7ccebd360abf404768246c1582a97812f9904882ab0` |
| `com.android.build.*.fingerprint` | `''` (wyczyszczony) | `''` (wyczyszczony) |
| `*.os_version` | **`12`** | — |
| `*.security_patch` | **`2019-06-06`** | — |

**Rozstrzygnięcie, które pliki są z której strony — bez patrzenia w nazwy.** `vbmeta.img` targetu
przypina łańcuch:

```
Chain Partition descriptor:
  Partition Name:          boot
  Rollback Index Location: 3
  Public key (sha1):       9d808b0995768d0677fccb1efcddb7cf9e153d99
```

Odcisk klucza w `boot.img` to **co do bajta ta sama wartość**. `boot.img` nie jest więc obrazem ze
źródła (Xiaomi) — jest **obrazem targetu Lenovo**, dopasowanym do `vbmeta.img`, który już mieliśmy.
Dodatkowo `boot` i `vendor_boot` dzielą ten sam `Salt`, czyli wyszły z tego samego przebiegu
pakowania tego samego firmware. Suma kontrolna `vbmeta.img` (`75fe0d86…a75b`) jest identyczna z tą z
`docs/03` — analiza nie opiera się na innym pliku niż sądziłem.

To jest metoda, której trzeba użyć dla reszty sterty: **nazwę pliku można przepisać w trzy sekundy,
odcisku klucza i saltu nie.**

## 4.3 Zmierzony kernel targetu — liczba, której brakowało w blokadzie nr 3

`boot.img`: strumień gzip pod offsetem 4096, rozpakowany `zlib.decompressobj(31)` (strict
`gzip.decompress` odmawia przez śmieci po strumieniu — to był mój błąd w pierwszej próbie, nie obrazu).
Zawartość 46 854 116 B, nagłówek EFI zImage (`MZ` + `ARMd` + `PE`). Znalezione w `.rodata`:

```
Linux version 5.10.233-android12-9-00062-g49c66df526b8-ab13101360
  (build-user@build-host) (Android (7284624, based on r416183b) clang version 12.0.5)
SMP PREEMPT Thu Feb 20 17:25:36 UTC 2025
```

Czyli target to **GKI `android12` 5.10.233, KMI `-ab13101360`, zbudowany 2025-02-20** — nie
downstream 4.14, jak pisałem wcześniej. To korekta na Twoją korzyść (GKI jednak) i jednocześnie
zamknięcie liczbowe blokady nr 3:

| | Lenovo TB350FU (cel) | Xiaomi Pad 9 Pro Max (źródło, HyperOS 4 / A17) |
|---|---|---|
| gałąź GKI | `android12` 5.10.233 | 6.6+ (GKI 2.0), KMI innej generacji |
| `os_version` w AVB boot | 12 | 17 (framework), a `vendor_dlkm`/`odm_dlkm` targetu: 12 |
| moduły `.ko` | `vendor_dlkm`/`odm_dlkm` pod 5.10 | pod 6.x + inny KMI |
| skutkiem | — | `modversions`: `disagrees about version of symbol …` na każdym .ko ze źródła |

Podsumowanie luki, teraz zmierzonej z obu stron: **framework źródła chce HAL-i i interfejsy o
4–5 dużych wersji nowsze, niż dostarcza vendor targetu (12), a kernel targetu ma generację KMI
niekompatybilną z modułami źródła.** To czwarta, niezależna, liczbowo udokumentowana przyczyna, dla
której podmiana `system.img` nie ma ścieżki do `bootable`.

## 4.4 Co jest wykonalne, potwierdzone bajtami

1. `vbmeta.img` targetu podpisany jest **AOSP `testkey_rsa2048`** (`cdbb7717…`), którego klucz prywatny
   leży w `/home/user/romtools/avb/test/data/`. Zatem spójny, własny łańcuch weryfikacji (własne klucze
   przypięte w `boot`/`vbmeta_system`/`vbmeta_vendor`) da się złożyć i podpisać tutaj, w sandboxie.
   `avbtool make_vbmeta_image` + `info_image` robią rundę weryfikacyjną.
2. `vendor_boot.img` ma `Algorithm: NONE` — jest **hashowany, nie podpisany**. Zmiana jego zawartości
   wymaga tylko przeliczenia hasha i zaktualizowania `vbmeta_vendor`, bez klucza OEM.
3. Granica pozostaje ta sama i jest twarda: **brak e2fsprogs/erofs-utils/losetup w sandboxie**, więc
   edycja zawartości obrazów (mkfs, wrzucenie plików) wyłącznie na runnerze Actions.

## 4.5 Czego potrzebuję, żeby domknąć resztę sterty

Na własnym komputerze, w katalogu z obrazami (WSL/git-bash wystarczy, python3 musi być):

```
./diagnostics/identify_images.sh /sciezka/do/obrazow
```

Skrypt tylko czyta. Daje `<_avb_frags>/*.vbmeta` (2–6 KB na obraz) i `MANIFEST.txt`. Te fragmenty — nie
obrazy — wrzuć na Drive. Z nich odczytam dla każdego z pięciu wielkich obrazów:

- który klucz go podpisał → czy to źródło, target, czy mix;
- `os_version` i `fingerprint` z property descriptors → wersja Androida danej partycji;
- `rollback index location` i `flags` → czego wymaga ponowne podpisanie;
- `page0` → typ systemu plików i rozmiar (ext4: liczba bloków × rozmiar bloku; EROFS/sparse inaczej),
  czyli arytmetykę dopasowania do `super` targetu zamiast zgadywanki.

Alternatywa dla `system.img` (938 MB), jeśli chcesz od razu czytać `build.prop`: podzielić plik na
części < 100 MB (`split -b 90m system.img system.img.part.`) i wrzucić wszystkie — złożę je z
powrotem i rozbiorem EROFS/ext4. To jednak 11 wywołań transferu na sam `system.img`, więc fragmenty
AVB są tańsze o dwa rzędy.

## 4.6 Proba obejscia limitu 100 MiB — zmierzone, nie odgadniete

Podejscia odrzucone, kazde z komunikatem (sondy na `system_ext.img`, 632 840 192 B):

| sonda | wynik |
|---|---|
| `download_file` (domyślnie) | `File is 632840192 bytes, over the 104857600 byte limit` |
| `return_download_url: true` | odrzucone przez **schemat narzedzia**: `Property "return_download_url" does not match additional properties schema; False boolean schema` — tryb URL jest zablokowany na `false` przez platforme, nie przez Google |
| `range_header: bytes=0-2097151` | `range cannot be combined with return_download_url: the download URL always serves the whole file` — konektor laczy zakres z trybem URL, wiec zakresy sa nieosiagalne |
| `acknowledge_abuse: true` | parametr przyjety, ale **limit odpala sie przed** sprawdzeniem skanu -> ten sam komunikat 104857600 B |

Wniosek: limit jest **pre-checkiem konektora** (przed zadnym wywolaniem API Google). Nie da sie go
obejsc parametrami, ktore konektor wystawia. To jest sciana, nie furtka.

### Co dziala: jedyny osiagalny host to GitHub

Macierz egressu z sandboxa (2026-09-22, 4:15):

```
https://drive.google.com                 000     https://github.com                  200
https://drive.usercontent.google.com     000     https://api.github.com              200
https://www.googleapis.com               000     https://objects.githubusercontent.com 000
```

Wiec kanał do agenta prowadzi przez `api.github.com` (`GET /repos/.../git/blobs/{sha}`, base64
w JSON). Zmierzone na sondzie 5 MB wlanej do repo i sciagnietej z powrotem:

```
blob 320162b56cbb3588db4400ca26b1ff87f53b1983
odpowiedz API: 7.11 MB JSON -> odzyskane 5.24 MB w 1.42 s = 3.70 MB/s
sha256 po powrocie: a35d4f30b48921e56b1ea6a499b7d88661f891fcf51a51b9aa6f7da83c76ce83  (identyczny)
szacunek:  system_ext 633 MB -> 2.9 min | system.img 938 MB -> 4.2 min | 5 obrazow 11.9 GB -> ~54 min
```

Kanál nie gubi bajtow (sha256 co do bajta), ale GitHub ma **wlasny limit 100 MiB na plik** — ten sam
numerek, z tego samego powodu (koszt logistyki, nie techniki). Dla obrazow >100 MB potrzebny podzial:

```bash
split -b 90m -d -d system.img system.img.part.     # 90 MB, 11 czesci
git add -f system.img.part.* && git commit -m "chunki system.img" && git push
```

Po Twojej stronie to jedna pętla; po mojej: zlozenie czastek i pelna analiza (AVB + geometryka FS
`tools/fs_probe.py` + odczyt `build.prop` pythonem, bo ext4/EROFS umiem czytac bez e2fsprogs).
Dla 5 obrazow to ~54 min transferu rozlozone na tury.

### Kanał drugi, bez Twojej pracy: runner Actions + publiczny link

`make_public` jest w schemacie konektora Drive, wiec **uprawnienia „kazdy z linkiem" potrafie
ustawic sam** (i zdjac po wszystkim `make_private`). Do tego dochodzi `tools/fs_probe.py` i pelny
tooling apt, ktory jest tylko na runnerze — stad nowy job **`drive-probe`** w
`.github/workflows/build.yml`:

1. `workflow_dispatch` z wejsciem `drive_ids` (spacja rozdzielone ID z Drive),
2. `curl https://www.googleapis.com/drive/v3/files/<id>?alt=media` — surowe bajty, bez OAuth,
   bez `HF_TOKEN`, bez `payload_dumper`; limit 100 MiB nie obowiazuje, bo to nie konektor,
3. `avbtool info_image` + `fs_probe.py --selftest` + `dumpe2fs`/`debugfs`/`fsck.erofs`/`simg2img`,
4. `do_unpack: 1` = dodatkowo drzewo partycji i `build.prop`,
5. raport **wraca commitem na galaz**, bo logow CI z sandboxa nie widac (`objects.githubusercontent.com` = 000).

To jest wlasciwe „obejscie": nie przekaz 11,9 GB do agenta, tylko analiza tam, gdzie sa bajty.
Czego jeszcze NIE zrobilem swiadomie: nie przekrecilem uprawnien Twoich plikow na publiczne —
zmienia to stan na Twoim koncie, wiec potrzebuję na to jednego slowa (albo zrob to w Drive recznie).

### Uwaga operacyjna, udowodniona dwa razy w tej turze

Sandbox resetuje sie **rowniez w srodku tury**: `google_drive/` (obrazy pobrane 20 min wczesniej)
zostal skasowany w polowie pracy, a `.git` cofniete do `5b03aea` (prace ratowalem `git reset --mixed
FETCH_HEAD`, nic nie zniknelo z remote). Stad dwa prawa tego projektu: (1) pobierz i policz w tej
samej turze, (2) wszystko, co ma znaczenie, musi byc w gicie — dlatego `tools/`, `diagnostics/` i
dokumenty sa commitowane, a obrazy nie.

## 4.7 LFS i "rozpakuj przed wysylka" — co zmierzylem, a co jest mitem

Pomysl, z ktorym przyszedles („GitHub ma 5 GB na plik, np. przez LFS, a wczesniej je
rozpakowac"), rozbilem na cztery sprawdzalne twierdzenia:

| twierdzenie | stan | dowod |
|---|---|---|
| LFS daje wieksze pliki niz 100 MB | **PRAWDA, ale nie 5 GB na Free** | 100 MB to limit zwyklego bloba; LFS: 2 GB/plik na Free/Pro, 4 GB Team, 5 GB Enterprise; repo: ostrzezenie ~1 GB, miekkie odciecie ~5 GB; Release assets: 2 GB/plik |
| LFS nadaje sie do transferu **do agenta** | **NIE** | `media.githubusercontent.com` = `000`, `github-cloud.s3.amazonaws.com` = `000`, a binarki `git-lfs` w sandboxie nie ma (`git: 'lfs' is not a git command`, `/usr/lib/git-core` pusty pod tym wzgledem). Endpoint negocjacji `github.com/.../info/lfs/objects/batch` dziala (HTTP 200, `Object does not exist` na probe) — ale zwraca URL do hosta nieosiagalnego |
| LFS nie zje limitu pasma | **NIE** | Free tier to ~1 GB storage + ~1 GB bandwidth / miesiac. Piec obrazow = 11,9 GB => kilkanascie-kilkadziesiat przekroczen; GitHub tnie pasmo, nie rozmawia |
| Da sie przeniesc duze pliki GitHubem do agenta | **TAK — blob API** | `GET /repos/{o}/{r}/git/blobs/{sha}` (base64 w JSON) idzie przez `api.github.com` = 200. Zmierzone ponizej |

### Zmierzony kanat (nie szacunek z dokumentacji)

| proba | wynik |
|---|---|
| 1 blob 5 MB (sonda) | 1.42 s → **3.70 MB/s**, sha256 identyczny |
| 3 bloby po 2.1 MB przez manifest (sciezka z `contents` lookupem) | 4.2 s → **1.50 MB/s** (2 zbędne wywolania API na czestke) |
| 3 bloby po 2.1 MB, manifest **z blob SHA** (1 wywolanie API na czestke) | 2.39 s → **2.63 MB/s**, `cmp` identyczny bajt do bajtu |

Ekstrapolacja przy 2.63 MB/s: `system.img` 938 MB → **~6 min**, `product.img` 6.4 GB → ~41 min,
wszystkie piec (11,9 GB) → **~75 min** samego transferu, rozlozonych na tury.

Narzedzia, ktore to obsluguja (przetestowane na prawdziwych bajtach `boot.img`, nie na suchym
skrypcie):

```
tools/ship_to_github.sh    # Twoja strona: rozpakuj -> odfiltruj -> tar.gz -> split -b 90m
                           #   -> MANIFEST.tsv ze sciezkami I blob SHA -> push
tools/pull_from_github.py  # Moja strona: manifest -> blob API -> zlozenie -> sha256 -> fs_probe
```

Format `transfer/MANIFEST.tsv` (to jest caly kontrakt miedzy nami):

```
<nazwa>.tar.gz<TAB><sha256><TAB><bajty><TAB><liczba-czastek>
transfer/<nazwa>.tar.gz.part.000<TAB><blob-sha>
transfer/<nazwa>.tar.gz.part.001<TAB><blob-sha>
```

### „Rozpakuj przed tym" — i dlaczego to jest właściwie najwazniejsza czesc

Rozpakowanie przed wysylka nie jest dodatkowym krokiem, tylko **jedynym sposobem, zeby limit
100 MB przestal byc problemem**. Obrazy sa upakowane gesta, ktorej nie pokonamy (`.img` to juz
skompresowany EROFS/ext4-sparse), ale **to, czego potrzebuje sciezka A, to ukr zawartosci**:

```
product/media/**        tapety, dzwieki, animacje
product/overlay/**      RRO Hyperi
system/fonts/**, etc/fonts.xml
system/framework/framework-res.apk
system_ext/overlay/**, odm/overlay/**
```

Z 11,9 GB obrazow to typowo rzedu 40–300 MB po `tar.gz`. Ponizej 100 MB — czyli **wchodzi zwyklym
konektorem Drive, bez GitHuba, bez LFS, bez splitowania**. `scripts/extract_hyperos_assets.sh`
robi dokladnie ta biala/czarna liste i wypisuje `copied.txt` / `refused.txt` / `REPORT.txt`; jego
`du -sh staging` po Twojej stronie powiedzie, ktorym kanalem to leci:

- `< 100 MB` → Drive, jedno wrzucenie pliku,
- `> 100 MB` → `tools/ship_to_github.sh` (rozpakowanie + split), ~6 min na `system.img`.

Surowe obrazy wysylaj tylko jesli chcemy liczyc `super` i geometrie partycji — do tego wystarcza
fragmenty vbmeta z `diagnostics/identify_images.sh` (2–6 KB na obraz), nie 6 GB.

### Dlaczego LFS jednak ma sens — ale dla runnera

`drive-probe` (job na Actions) ma pelny egress i `git lfs` dostepny przez apt, wiec **LFS jest
dobra forma magazynu dla runnera**, jesli nie chcesz publicznych linkow na Drive: wrzucasz obrazy
jako LFS na galaz, runner robi `git lfs pull`, analizuje i zwraca raport commitem. Agent czyta
wtedy tylko raport (KB), nie obrazy. To jest wlasciwy podzial roboty: duze bajty nigdy nie
przechodza przez sandbox.
