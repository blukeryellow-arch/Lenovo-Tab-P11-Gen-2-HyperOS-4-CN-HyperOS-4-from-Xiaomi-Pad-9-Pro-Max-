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
