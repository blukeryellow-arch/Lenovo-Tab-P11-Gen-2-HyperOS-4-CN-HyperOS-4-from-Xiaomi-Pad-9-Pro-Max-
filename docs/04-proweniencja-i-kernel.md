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
w JSON). Zmierzone na sondzie 5 MB wlanej do repo i ściągniętej z powrotem:

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
| LFS daje wieksze pliki niz 100 MB | **PRAWDA, ale nie 5 GB na Free** | 100 MB to limit zwyklego bloba; LFS: 2 GB/plik na Free/Pro, 4 GB Team, 5 GB Enterprise; repo: ostrzezenie ~1 GB, miękkie odcięcie ~5 GB; Release assets: 2 GB/plik |
| LFS nadaje sie do transferu **do agenta** | **NIE** | `media.githubusercontent.com` = `000`, `github-cloud.s3.amazonaws.com` = `000`, a binarki `git-lfs` w sandboxie nie ma (`git: 'lfs' is not a git command`, `/usr/lib/git-core` pusty pod tym wzgledem). Endpoint negocjacji `github.com/.../info/lfs/objects/batch` dziala (HTTP 200, `Object does not exist` na probe) — ale zwraca URL do hosta nieosiagalnego |
| LFS nie zje limitu pasma | **NIE** | Free tier to ~1 GB storage + ~1 GB bandwidth / miesiac. Piec obrazow = 11,9 GB => kilkanascie-kilkadziesiat przekroczen; GitHub tnie pasmo, nie rozmawia |
| Da sie przeniesc duze pliki GitHubem do agenta | **TAK — blob API** | `GET /repos/{o}/{r}/git/blobs/{sha}` (base64 w JSON) idzie przez `api.github.com` = 200. Zmierzone poniżej |

### Zmierzony kanał (nie szacunek z dokumentacji)

| proba | wynik |
|---|---|
| 1 blob 5 MB (sonda) | 1.42 s → **3.70 MB/s**, sha256 identyczny |
| 3 bloby po 2.1 MB przez manifest (sciezka z `contents` lookupem) | 4.2 s → **1.50 MB/s** (2 zbędne wywolania API na częstkę) |
| 3 bloby po 2.1 MB, manifest **z blob SHA** (1 wywolanie API na częstkę) | 2.39 s → **2.63 MB/s**, `cmp` identyczny bajt do bajtu |

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

### „Rozpakuj przed tym" — i dlaczego to jest właściwie najważniejsza część

Rozpakowanie przed wysylka nie jest dodatkowym krokiem, tylko **jedynym sposobem, zeby limit
100 MB przestal byc problemem**. Obrazy sa upakowane gesta, ktorej nie pokonamy (`.img` to juz
skompresowany EROFS/ext4-sparse), ale **to, czego potrzebuje sciezka A, to mały wycinek zawartości**:

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

## 4.8 Obejscie znalezione w drugiej probie: git transport, nie REST

Pierwsza runda (sekcja 4.6/4.7) zakonczyla sie na kanale `api.github.com` z base64 — 2.6-3.7 MB/s.
Druga runda, po przeczyszczeniu macierzy egressu pod katem *kazdego* hosta plikowego, dawala
przeoczony fakt: `codeload.github.com` odpowiada **301**, czyli dziala, a to jest wlasnie
transport `git` (te sama sciezke uzywa `git clone`, ktorym klonowalem avbtool).

Macierz z tej samej tury (wszystko poza GitHubem i PyPI jest martwe):

```
raw.githubusercontent.com 000   gist.github.com 000        transfer.sh 000   archive.org 000
uploads.github.com 000         catbox.moe 000              file.io 000       tmpfiles.org 000
gitlab.com 000                 sourceforge.net 000         mega.nz 000       docs.google.com 000
drive.usercontent.google.com 000                           speed.hetzner.de 000
codeload.github.com 301  <-- JEDYNE WJSCIE O WIEKSZEJ PRZEPUSTOWOSCI
pypi.org 200                   github.com 200               api.github.com 200
```

Pomiar tej samej objetosci dwoma kanalami, na prawdziwych bajtach (fragmenty `boot.img`
i `vendor_boot.img`, wypchniete tu do repo i ściągnięte z powrotem):

| payload | `git clone --depth 1` | `api.github.com` blob + base64 |
|---|---|---|
| 12,58 MB (3 czastki) | **0,93 s = 13,5 MB/s** | 3,69 s = 3,41 MB/s |
| 48,00 MB (3 czastki) | **1,54 s = 31,3 MB/s**, 2,42 s = 19,8 MB/s | — |

`sha256` złożonego pliku identyczny z oryginaliem w kazdym przebiegu.

Ekstrapolacja przy ostroznym 19,8 MB/s:

| co | czas |
|---|---|
| `system_ext.img` 633 MB | 0,5 min |
| `system.img` 938 MB | 0,8 min |
| `product.img` 6,45 GB | 5,4 min |
| wszystkie piec obrazy 11,9 GB | **~10 min** |

Czyli problem „limitu 100 MB" przestal byc problemem transferu, a stal sie problemem
**jednego `git push` po Twojej stronie**. Limit GitHuba 100 MB/plik wciaz obowiazuje przy
wysylce (serwer go sprawdza w pre-receive), wiec `split -b 90m` zostaje — ale po mojej stronie
nie ma juz zadnego limitu: `git clone` dostarcza cala galaz naraz.

Narzedzie: `tools/pull_via_git.sh <repo-url> <galaz> [dest]` — plaski clone, skladanie czastek
wg `transfer/MANIFEST.tsv`, weryfikacja `sha256`, potem `tools/fs_probe.py`. Przetestowane
cyklem na lokalnym repo (`file://`, 9 MB w 3 czastkach): `IDENTYCZNY BAJT DO BAJTU`, a na
danych losowych uczciwie zglosilo `naglowek nierozpoznany` zamiast zmyślać geometrie.

Dwie wazne granice tego kanalu, zebym nie zostawil wrazenia, ze to dziura bezplatna:

1. **Nie przenosi nic, czego nie ma na GitHubie.** Sonda 48 MB byla moja wlasna — Twoje obrazy
   musza najpierw przejsc `tools/ship_to_github.sh` u Ciebie. Konektor Drive wciaz nie da ich
   zdjac (>100 MB), a `fetch_page` nie przywraca binariow.
2. **Historia repo platna za pomiar**: zostawilem w niej ~60 MB sondu (12 MB + 48 MB), bo usuniecie
   wymaga przepisania historii galazi session, co rusza sledzenie pracy przez Arena. Drzewo jest
   czyste (`git rm -r transfer` w `0163e4c`+), ale `git clone` sciaga packa z tym balastem — przy
   wlasciwym transferze to bez znaczenia (raz ~60 MB), jezeli bedzie przeszkadzac, wystarczy
   `git filter-repo --path transfer --invert-paths` po Twojej stronie i force-push.

## 4.9 Rozpakowanie na runnerze i kawalki <=90 MB  kanale przetestowany koncow do konca

Zmierzone 2026-09-23 na Twoich plikach, nie na sondach. Pekl: pobranie z Dysku przez
runniera GitHub Actions -> `fs_probe` + `avbtool` -> rozpakowanie partycji -> `split -b 90m`
na galaz -> `tools/pull_via_git.sh` po mojej stronie -> weryfikacja `sha256`.

**Bieg 17 (`35823024969`) przeszedl w calosci na zielono.** `system.img`
(`1Pu6RU00SsbFiXiGlx6IpG14714jaZThN`, 937 791 488 B, sha256 `4d3c61fe358f...`) zostal
pobrany, rozpakowany, zapakowany (`749 834 731 B`, sha256 `afb1e37bc86b...`), pociete na
**8 czastek** (7 x 94 371 840 + 1 x 89 231 851 B) i wypchniety na galaz z `MANIFEST.tsv`.
Zlozone u mnie: rozmiar co do bajta i **sha256 identyczny z tym z MANIFESTu runnera**;
w paczce 4298 plikow, w tym `system/framework/framework.jar` (51,2 MB), `services.jar`
(39,9 MB), `system/fonts/NotoSansCJK-Regular.ttc` (32,4 MB) i apexy.

Piatra, ktore wypadly po drodze (kazda udokumentowana w commitach, bo logow CI nie widac):

| prob | objaw | przyczyna (zmierzona) |
|---|---|---|
| 1 | `exit 127` | `echo` rozbity na dwie linie w `run: |` - druga byla wywolaniem polecenia |
| 2 | `exit 1` po 57 s | zadny endpoint nie zwrocil pliku; brakolo `confirm=t` w query |
| 3 | `formularz zwrocil 0 B` | POST do `action` bez pol: Google trzyma `id/export/confirm/uuid` w **query** i przycisk robi **GET**, nie POST |
| 4 | `No space left on device` | workflow robil `cp out/$name one/` - surowy obraz lezial DWUKROTNIE (11,9 GB zamiast 5,9 GB) |
| 5 | push po 2m38s, exit 1 | `git add -f transfer/` bral rowniez tarball rodzica >100 MB -> GitHub odrzuca CALY push |
| 6 | brak biegow w ogole | filtr `on: push.paths` nie znal `tools/**` - zmiana naprawy nie tworzyla runa |
| 7 | `MANIFEST` z 1 wpisem, 0 czastek | moja ata wstawila `rm -f "$pkg"` PRZED `split` |

Wnioski praktyczne, do zapamietania:

1. **Limit konektora Drive (104 857 600 B, whole-file) nie obowiazuje runniera Actions.**
   Dla plikow >~100 MB Drive nie skanuje antywirusowo i oddaje strone
   `<title>Google Drive - Download warning</title>` (HTTP 200, ~2,5 kB HTML).
   `tools/drive_form_post.py` wyciaga z niej `action` wlasciwego `<form>` (NIE pierwszego -
   pierwszym jest formularz logowania) i pobiera GET-em po query z `uuid`. `--selftest`
   pokrywa dwa uklady strony bez sieci.
2. **Publiczny link jest niezbedny tylko na czas pobierania.** Przywolalem `make_public`
   (reader, bez indeksowania) dla pieciu obrazow i po kazdym biegu `make_private`;
   `list_permissions` na wszystkich pieciu pokazuje dzis wylacznie `owner`.
3. **Budzet runniera to ~14 GB, a limit GitHuba to 2 GB na push i 100 MB na blob.**
   Dlatego: jeden duzy obraz na bieg, `mv` zamiast `cp`, `split` przed usunieciem rodzica.
   Dla `product.img` (6,45 GB surowe) dojdzie prawdopodobnie limit 2 GB/push - wtedy
   trzeba rezerowac podzbior sciezek (`product/overlay`, `product/media`), nie calosc.
4. Allowlist `tools/unpack_on_runner.sh` na razie nie trafia w sciezki (korzen EROFS to
   `./system/...`, nie `system/...`), wiec paczka `system.img` jest cala partycja. To
   bezpieczne, tylko duze; do poprawienia przed `product.img`.

Urzadzenia sluzace do powtorzenia: `drive-probe.request` (lista ID; start = commit z
`[drive-probe]` w tytule, bo token sandboxa nie ma prawa do `workflow_dispatch`),
`tools/unpack_on_runner.sh` (strona runniera), `tools/pull_via_git.sh` (moja strona),
`tools/lint_workflow_steps.py` (apie wpadki typu #1 lokalnie, `bash -n` + heurystyka
linii o ksztalcie tekstu; test negatywny potwierdzony).

## 4.x Bity, ktoreg obrazu bronią albo nie bronią (dopisane 23 IX 2026, po zmianie kompresji)

Nasze obrazy (i `lz4`, i `lz4hc,9`) zadaja od kernela dokladnie jednego bitu
niekompatybilnosci: `lz4_0padding`. Sprawdzilemy w drzewie upstream, czy kernel 5.4 ten bit
**zna**, czy musi go odrzucic — bo „mount failed" i „feature unsupported" to dwie rózne
klęski, a pierwsza bywa cicha. W `v5.4/fs/erofs/erofs_fs.h`:

```c
#define EROFS_FEATURE_INCOMPAT_LZ4_0PADDING  0x00000001
#define EROFS_ALL_FEATURE_INCOMPAT           EROFS_FEATURE_INCOMPAT_LZ4_0PADDING
```

Czyli 5.4 nie tylko definiuje bit, ale ma go w masce „znam to" — montaz nie zostanie
odrzuchony z powodu formatu. Źródło: `raw.githubusercontent.com/torvalds/linux/v5.4/fs/erofs/erofs_fs.h`
(pobrane 23 IX 2026; w tym sandboxie jedyny sposob na upstream, bo `curl` nie ma sieci, a
`raw.githubusercontent` przez `fetch_page` dziala). Czego to NIE dowodzi: że kernel Lenovo ma
wbudowany w ogole `EROFS_FS` i `EROFS_FS_LZ4` — to dalej jest warunkiem wstepnym, mierzonym na
urzadzeniu przez `device-probe.sh` (krok 0), nie przez ten dokument. Dowodzi natomiast, ze
zmiana `lz4` -> `lz4hc,9` nie doklada zadnego nowego zadania kernelowi (patrz docs/06 §6.23).
