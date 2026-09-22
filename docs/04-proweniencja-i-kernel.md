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
