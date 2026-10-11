# Analiza: `vbmeta.img` z Google Drive

Źródło: Drive, plik `vbmeta.img`, id `1u3HPzK0HyYu4kvA5WBYPl4Zbv_AWS7Ao`, 8192 B,
właściciel `blukeryellow@gmail.com`, utworzony 2026-09-22 18:34.
W koszu leży duplikat tej samej wielkości i o tym samym `modifiedTime`
(id `1da5EBMjE4uridr5Syh3FV-LW0uaa-oum`) — najpewniej ta sama zawartość.

```
SHA-256 calosci : 75fe0d867a4415cf0adf765cbc7335a694e79047232eaf4f4cd4ce3bdc97a75b
```

## Metadane AVB (odczytane z pliku, nie z nazwy)

| pole | wartosc |
|---|---|
| magic | `AVB0` |
| narzędzie | `avbtool 1.2.0` |
| rozmiar pliku | 8192 B (dokladnie rozmiar partycji `vbmeta`), 2624 B zera na ogonie |
| blok autentykacji | 320 B = hash 32 B + podpis 256 B |
| algorithm | `1` = **SHA256_RSA2048** (wiec NIE jest to wariant `--algorithm none`) |
| **flags** | **0 → verity i weryfikacja WLACZONE**, nikt nie odpalał `--disable-verification` |
| rollback_index / location | 0 / 0 |

### Descriptory

```
CHAIN_PARTITION  boot             rollback_index_location=3   klucz nastepnej partycji 520 B (RSA-4096)
CHAIN_PARTITION  vbmeta_system    rollback_index_location=2   klucz 520 B
CHAIN_PARTITION  vbmeta_vendor    rollback_index_location=4   klucz 520 B
HASHTREE         (dm-verity)      x4  -> product, system_ext, vendor_dlkm, odm_dlkm
HASH             (sha256)         x2  -> rb_loc 4 i 11
PROPERTY         kity com.android.build.* dla: vendor_boot, product, system_ext,
                                   vendor_dlkm, odm_dlkm, dtbo
```

Fingerprint wbudowany w property:

```
alps/ZUIPadLteROWLGSIU/LGSIU:14/UP1A.231005.007/TB350FU_S231044_260105_ROW:user/release-keys
security_patch: 2025-12-05
```

`TB350FU` to oznaczenie handlowe wariantu **Lenovo Tab P11 Gen 2** (wariant LTE/ROW) — potwierdzone
ofertami handlowymi („Lenovo Tab P11 Gen 2 TB350FU … MediaTek Helio G99 … Android 12L").
Czyli model się zgadza, **ale poziom oprogramowania to Android 14**, nie 12L.

## Co z tego wynika — cztery twarde wnioski

**1. To jest vbmeta CELOWA (Lenovo), nie źródłowa (Xiaomi).**
Jeśli ten plik miał być „tym vbmeta z ROM-u, z którego bierzemy system" — nie jest nim.
Pochodzi ze stockowego ZUI dla TB350FU na Androidzie 14 z patchem 2025‑12‑05.
Nazywanie go „vbmeta ze źródła" w dokumentacji projektu to przyszły błąd na etapie
flashowania, więc warto poprawić nazwę przy najbliższej okazji.

**2. Plik jest nietknięty — sprawdziłem to, nie założyłem.**
`sha256(naglowek_256B + blok_aux)` = `ef557468d85823ec740deabad22c51d57c752a7f3c66f24c4376c0d7031972a1`
i to jest **dokładnie** hash zapisany w bloku autentykacji. Każdy, kto zmieniałby
descriptory albo `flags`, rozjechałby ten hash (nie da się go przerachować bez klucza
OEM w sensowny sposób, a `--disable-verification` w fastbootu *tylko* ustawia flagi
i zostawia stary hash). Stąd: dostaliśmy obraz fabryczny, nie czyjś wcześniejszy eksperyment.

**3. Ten vbmeta sam w sobie zablokuje każdy zmodyfikowany build.**
Leży w nim 4 deskryptory HASHTREE (root digesty dm‑verity dla `product`, `system_ext`,
`vendor_dlkm`, `odm_dlkm`) i 3 łańcuchy do `boot`, `vbmeta_system`, `vbmeta_vendor`
z kluczami RSA‑4096. Zmiana któregokolwiek z tych obrazów przy `flags=0` = weryfikacja
nie przechodzi. Standardowe obejście, jedyne realne bez kluczy Lenovo:

```bash
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
```

Uwaga na kolejność: ta komenda **poprawia** kopię w locie i wgrywa wersję z flagami
`HASHTREE_DISABLED|VERIFICATION_DISABLED`. Twoj plik na Dysku takiej poprawki nie ma
(słusznie — to kopia referencyjna). Trzymaj go jako „powrót do stanu stock":
`fastboot flash vbmeta vbmeta.img` + przywrócenie stockowych obrazów = weryfikacja znowu spójna.

**4. Dwie korekty mojej wcześniejszej oceny portu, wymuszone przez ten plik.**
Obecność `vendor_dlkm` i `odm_dlkm` dowodzi, że docelowy build A14 **już jest na GKI**
(moduły wydzielone), a nie na downstreamowym jądrze 4.14 — mój punkt „kernel" był
przesadzony. Po drugie: pułap startowy urządzenia to nie Android 12L, a 14
(fingerprint `:14/UP1A.…`), więc luka framework to 14→17, nie 12→17.
To nie odwraca wyroku (VINTF dalej nie domknie 3 wersji, a HAL-e Xringa są nadal bezużyteczne
na MT6789), ale przestaje to być „niemożliwe z definicji" i staje się „niemożliwe bez BSP,
którego nie ma" — to druga, uczciwsza kategoria.

## Czego teraz potrzebuję, żeby policzyć lukę, a nie ją zgadywać

Te pliki mają kilkadziesiąt KB, więc **wystarczy Drive** — przy malych elementach
blokada `huggingface.co` nie ma zastosowania:

```bash
adb pull /vendor/etc/vintf/manifest.xml
adb pull /vendor/etc/vintf/compatibility_matrix.xml
adb pull /system/etc/vintf/manifest.xml
adb pull /odm/etc/vintf/manifest.xml        # moze nie istniec
adb pull /vendor/build.prop
```

albo wrzuć na Drive `vbmeta_system.img` + `vbmeta_vendor.img` (tegoroczne, z tego samego buildu).

Mając `manifest.xml` + `compatibility_matrix.xml` potrafię wypisać **dokladna** liste
interfejsów, których zabraknie frameworkowi A17 — zamiast mówić „VINTF się nie zgadza",
pokażę liczby: ile HAL-i, które których wersji, i czy którykolwiek da się zadowolić
szkieletem (`libhwbinder` stub). To jest jedyny pomiar, który realnie rozstrzyga, czy
jakakolwiek wersja „HyperOS na tym tablecie" ma sens, czy nie.

---

# Dodatek A: co zmienilo sie po uruchomieniu prawdziwego avbtool

`avbtool.py` wyciagniety z `LineageOS/android_external_avb` (git clone przez
github.com - jedyny dostepny stąd kanal na kod AOSP). Uruchomiony lokalnie:

```
python3 avbtool.py info_image --image vbmeta.img
```

potwierdza kazde pole z tabeli powyzej (Header 256, Auth 320, Aux 4992,
SHA256_RSA2048, Rollback 0, Flags 0) i doklada trzy rzeczy kluczowe.

## A.1. Lenovo podpisalo AVB kluczem testowym AOSP

```
Public key (sha1): cdbb77177f731920bbe0a0f94f84d9038ae0617d
testkey_rsa2048.pem -> cdbb77177f731920bbe0a0f94f84d9038ae0617d   == TO SAMO
```

Klucz prywatny do tego publicznego lezy w kazdym checkoutie AOSP
(`external/avb/test/data/testkey_rsa2048.pem`) - mam go tu lokalnie.
Warstwa "zweryfikowany boot" nie jest wiec na tym urzadzeniu zadna granica
dla kogoś, kto chce podmienic obrazy.

Odwrotnie dla łańcucha - trzy klucze podpięte w `Chain Partition` NIE sa
kluczami AOSP (porownane z cala rodzina testkey_rsa2048/4096/8192):

```
boot            9d808b0995768d0677fccb1efcddb7cf9e153d99   -> brak w sposrod AOSP
vbmeta_system   fa41159a5d696abdef93176a07d0b0d001263f01   -> brak
vbmeta_vendor   9577bc6c0772975ecce93c4d8a178662c728dadf   -> brak
```

Czyli: vbmeta glowny = testkey, podpiete pod niego sub-vbmeta = klucze Lenovo.
Zielonego stanu (green verified boot) nie odtworzymy - potrzebujemy prywatnych
kluczy OEM, ktorych nie ma i nie bedzie. Natomiast **zestaw samospojny,
podpisany naszym kluczem i przechodzacy kontrole libavb przy orange state -
tak, to sie da zbudowac tutaj** i to jest realna wartesc, jaka z tego wychodzi.

## A.2. Zmierzona luka, o ktora prosilem: vendor jest z epoki Android 12

Property descriptors z tego samego pliku:

```
com.android.build.product.os_version      = 14
com.android.build.system_ext.os_version   = 14
com.android.build.vendor_dlkm.os_version  = 12   <--
com.android.build.odm_dlkm.os_version     = 12   <--
com.android.build.vendor_boot.fingerprint = ''
```

`vendor_dlkm`/`odm_dlkm` to moduly sprzedawane razem z warstwa sprzetowa.
Ich odcisniety poziom to **Android 12**, podczas gdy polowa systemowa jest na 14.
Lenovo zaktualizowalo system, nie ruszajac HAL-i.

To jest ta liczba, ktorej potrzebowalem zamiast mowic "VINTF sie nie zgadza":
swap `system.img` z HyperOS 4 (Android 17) na ten sprzet oznacza framework, ktory
zada interfejsow o piec duzych wersji nowszych, niz dostarcza vendor. Nie jest to
zgadywanka - wynika z fingerprintow w pliku, ktory sam mi podates.

## A.3. Granica mozliwosci tego sandboxa (zkody, nie opinia)

Dziala tutaj:
- `avbtool.py` pelna giba: `info_image`, `make_vbmeta_image`, `add_hashtree_footer`,
  `add_hash_footer`, `--chain_partition`, `extract_public_key` - zweryfikowane
  generowaniem `vbmeta` na kluczu wygenerowanym przez `openssl` (8192 B, poprawny odcisk);
- `payload_dumper` w `/home/user/romtools/venv` (pip dziala) - rozbiorze `payload.bin`;
- parsowanie wlasne (Python/struct): LP metadata `super.img`, format sparse,
  naglowki `boot.img`/`vendor_boot`, superblocki ext4 i EROFS (odczyt);
- cala arytmetyka dopasowania: czy image X zmieci sie w grupie Y, ile brakuje,
  jak przelicic bloki.

NIE dziala tutaj - i zaden skrypt tego nie obejdzie:
- `mke2fs`, `mkfs.ext4`, `debugfs`, `resize2fs`, `dumpe2fs`, `losetup`,
  `mksquashfs`, `mkfs.erofs` - **nie ma ich i nie doinstaluje** (apt zablokowany, brak roota);
- ergo: **nie zmieniam zadnych bajtow wewnatrz obrazu plikowego.** Moglbym odczytac,
  policzyc, podpisac i zlozyc AVB, ale nie wgran pliku do srodka `system.img`.
- brak `dl.google.com`, `huggingface.co`, `raw.githubusercontent.com` - allowlista wyjsc.

Stad podzial, ktory jest jedynym uczciwym:
`analiza + AVB + podpisy + walidacja = sandbox`,
`edycja systemow plikow + mkfs + budowa = runner GitHub Actions`.

## A.4. Kanal Drive - co wiadomo po pierwszym przejsciu

`download_file` zapisal 8192 B do workspace i zwrocil sciezke, nie strumien
w kontekcie - czyli kanal nie jest "na tekst", tylko na pliki. Sufit dla
GB-owych obrazow nieznany; ustalimy go empirycznie na pierwszym realnym pliku,
wg kolejnosci: `vbmeta_system.img` -> `dtbo.img` -> `vendor_boot.img` -> `super.img`.
Jezeli connector sie podda, `unpack-source` w CI przejmuje te najwieksze.

---

## Dodatek B (korekta Dodatku A, 2026-09-22): realny sufit kanału Drive

W Dodatku A zapisałem, że „Google Drive jest działającym kanałem transferu binarek". To wymaga
precyzji, bo bez niej wprowadza w błąd: limit to **100 MiB na plik (104 857 600 B)**, wyłącznie
cały plik, bez zakresów bajtowych (odsłona `bytes=0-2097151` została odrzucona z komunikatem
„the download URL always serves the whole file"). Drugi warunek: pliki w workspace poza gitrem
**nie przeżywają tury** — `google_drive/vbmeta.img` zniknął i trzeba go było pobrać ponownie.

Konsekwencja dla tej analizy: `vbmeta.img`, `boot.img`, `vendor_boot.img` nadają się do pobrania i
pobrania im wszystkiego; `system.img`, `product.img`, `system_ext.img`, `odm.img`,
`vendor_mystical.img` (łącznie 11,9 GB) nie — dla nich jedyną sensowną drogą są fragmenty bloków
vbmeta (`diagnostics/identify_images.sh`) albo runner Actions z Hugging Face.

Pomiary z tych trzech plików, łącznie z dowodem proweniencji i wersją kernela: `docs/04`.
