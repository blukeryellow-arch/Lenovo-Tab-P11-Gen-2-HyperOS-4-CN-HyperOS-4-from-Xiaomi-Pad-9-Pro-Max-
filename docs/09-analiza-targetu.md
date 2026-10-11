# Analiza targetu TB350FU z prawdziwych artefaktów (24 IX, noc)

Do tej pory wszystko, co wiedzieliśmy o urządzeniu, pochodziło z aftermarketu (Amazon/Newegg:
„mt6789 12L") i z pomiarów `adb` z 23 IX. Ta noc zmieniła źródło prawdy: z Dysku usera przez
konektor (`download_file`, pliki <100 MB) pobraliśmy trzy artefakty **targetu** — `boot.img`,
`vendor_boot.img`, `vbmeta.img` — i każdy md5 zgadza się z sumą kontrolną serwera Google
(`diagnostics/drive-inventory.tsv`). Poniższe ustalenia nie są więc wnioskowaniem, tylko
odczytem bajtów, które fizycznie siedzą w tablecie.

## 1. Skrót: co naprawdę jest w tablecie

| pytanie | odpowiedź | skąd |
|---|---|---|
| SoC | **MT6789** (board `mgvi_t_64_7xxx_armv82`, mgk `…wifi_k510`) | `ro.vendor.mediatek.platform`, moduły `clk-mt6789-*` |
| kernel | **5.10.233 GKI `android12-9`**, clang 12.0.5, Image.gz w boot.img | string w rozpakowanym kernelu |
| vendor | **Android 12**: `ro.vndk.version=31`, `version.sdk=31` | default.prop z ramdiska vendor_boot |
| system stocka | **LGSIU = Lenovo GSI, baza A14** (`Lgsi:14:34/AOSP`, fingerprint `…/LGSIU:14/UP1A.231005.007/TB350FU_S231044_260105_ROW`), patch 2025-12-05 | properties w vbmeta + `ro.config.lgsi.*` |
| boot.img | **Google GSI boot** (`GSI on ARM64`, `SGR1.250204.002.A1`, luty 2025) | build.prop w ramdisku boota |
| fstab | system weryfikowany kluczami **GSI Googlea**: `/avb/q-gsi.avbpubkey:/avb/r-gsi.avbpubkey:/avb/s-gsi.avbpubkey` | `fstab.mt6789` |
| dynamiczne partycje | `system`, `vendor`, `product` (+ `vendor_dlkm`, `odm_dlkm`); **Virtual A/B** z kompresją i snapshotami userspace | fstab + `ro.virtual_ab.*` |
| A/B wg OTA | `boot,system,vendor,product` — **system_ext NIE jest na liście** (ale ma hashtree w vbmeta — patrz §3) | `ro.product.ab_ota_partitions` |
| userdata | f2fs, metadane szyfrowane aes-256-xts v2+inlinecrypt, reserve_root 128 MB | fstab |
| grafika | Mali (vulkan=mali, egl=`meow` — nowy sterownik MTK), composer **HIDL 2.1** `mtk_common` | default.prop |
| AVB stocka | vbmeta 8 KB: **flags=0** (weryfikacja włączona), SHA256_RSA2048, **klucz = AOSP testkey `cdbb7717…`**, avbtool 1.2.0 | nagłówek vbmeta |

## 2. Najważniejsze odkrycie: urządzenie jest CELEM GSI

Trzy niezależne dowody w bajtach: (1) boot.img to obraz GSI od Google („GSI on ARM64",
identyfikator `SGR1.250204.002.A1`), (2) fstab montuje `system` z `avb_keys=` wskazującym na
klucze publiczne GSI q/r/s — czyli łańcuch weryfikacji **przewiduje systemy GSI**, (3) sam stock
to „LGSIU" — Lenovo GSI Universal, a properties mówią wprost `ro.config.lgsi.*`, UI TABUI 5.1.
Conajmniej: swap systemu na cudy obraz jest na tym sprzęcie **ścieżką projektową**, nie hackiem.

Jednocześnie stock pokazuje rozmiar przepaści, jaką Lenovo samo akceptuje: system A14 (sdk 34)
na vendorze A12 (sdk 31, VNDK 31). Nasz donor idzie dalej: system A17 (sdk 37) na tym samym
vendorze A12 — **pięć wersji API nad vendor**, z czego stock pokazuje, że dwie wersje nad
są bezpieczne, ale pięć to terytorium nieznane.

## 3. AVB i łańcuch zaufania (z deskryptorów vbmeta)

Główny vbmeta stocka: własna sygnatura = AOSP testkey (potwierdza docs/03 §A.1), `flags=0`,
`rollback_index=0`. Deskryptory (4440 B, format potwierdzony spójnym przejściem całego bloku):

- **chained**: `boot` (rollback-slot 3, klucz sha1 `9d808b09…`), `vbmeta_system` (slot 2,
  `8284d0b9…`), `vbmeta_vendor` (slot 4, `2d978807…`) — trzy różne klucze, żaden nie jest
  testkeyem z nagłówka;
- **hash**: `dtbo` (42 192 B), `vendor_boot` (obraz 22 921 216 B w slocie 64 MB);
- **hashtree** (rozmiary obrazów stocka): `product` **2 748 350 464 B (2,56 GiB)**,
  `system_ext` **744 968 192 B**, `vendor_dlkm` **30 785 536 B** (dokładnie tyle, co
  w docs/05), `odm_dlkm` (mały).

Dwa wnioski praktyczne: (a) nasz vbmeta z `flags=3` wyłącza weryfikację **całego łańcucha**
(wraz z chained partitions) — dokładnie po to jest ta flaga; (b) rozmiar `system_ext` stocka
(745 MB) **mieści** donorski `system_ext.img` (632 840 192 B z inwentarza Dysku), bo slot jest
zawsze ≥ obrazu stocka — to otwiera wariant „coherent" (system + system_ext donora).

Zagadka do rozstrzygnięcia NA URZĄDZENIU: `ab_ota_partitions=boot,system,vendor,product` nie
wymienia `system_ext`, choć partycja istnieje (hashtree). Skrypt wariantu coherent musi najpierw
sprawdzić `partition-size:system_ext_a/b`; jeśli slotów nie ma, flash system_ext jest
**jednokierunkowy** (bez rollbacku) i wymaga osobnej, jawnej zgody.

## 4. Kernel i ramdiski (parsowane bez fastboota/mkbootimg)

- `boot.img` v4: kernel Image.gz 19 652 970 B → `Linux version 5.10.233-android12-9-00062-
  g49c66df526b8-ab13101360`; ramdisk 1 380 093 B **lz4-legacy** → cpio 2,5 MB: init (2,5 MB),
  `system/etc/ramdisk/build.prop` (GSI props), katalogi first_stage.
- `vendor_boot.img` v4: cmdline `bootopt=64S3,32N2,64N2`; ramdisk 22 717 610 B **lz4-legacy**
  @0x1000 → cpio 58,4 MB, 668 wpisów: 4 fstabe (`emmc`, `mt6789`, `mt8781` — dwie platformy
  rodzinne, moduły są tylko mt6789), `default.prop` z pełnymi propsami vendor/odm/product
  (stąd tabela §1), 188 modułów `.ko` (MT6789: clk, aee, chargery bq, connac1x BT/WiFi,
  camera ISP, sensors), binaria first-stage (e2fsck, snapuserd).
- Dekoder lz4-legacy + cpio napisany w czystym Pythonie (brak binaria `lz4` w sandboxie) —
  kod żyje w historii tej sesji; ekstrakty w `/tmp/tgt/` (nietrwałe).

## 5. Co to zmienia w ocenie szans (B′ = donorski system A17)

Poprzednie widełki zakładały vendor A14. Prawda: **vendor A12 (VNDK 31) + kernel 5.10**, czyli
przeciw systemowi A17 stoi pięć wersji API i architektura HAL-ów:

- **init (~85%)**: bez zmian — bramka VINTF otwarta miękką macierzą poziomu 5; kernel 5.10
  ma wszystko, czego wymaga bionic/ART (stare, stabilne API);
- **Zygote → system_server (~50-60%)**: A17 framework będzie szukał HAL-i AIDL wprowadzonych
  w A13-A15 (power, health, lights, vibrator…); na A12 są w najlepszym razie HIDL. Brak HAL-a
  zwykle ma ścieżkę fallback w frameworku, ale nie zawsze;
- **pulpit (~10-25%)**: pojedynczy punkt krytyczny to **SurfaceFlinger vs composer HIDL 2.1**
  (`ro.vendor.composer_version=2.1`). GSF utrzymywał wsparcie HIDL composer 2.x bardzo długo,
  ale A17 może go już nie mieć — wtedy SF crashuje w pętli i pulpitu nie będzie w ogóle,
  niezależnie od reszty. Drugi kandydat: audio (HIDL audio@7.x na A17?). Bez urządzenia nie
  da się tego rozstrzygnąć — trzeba logcatu.

To są **szacunki na dowodach** (co którego komponentu wymaga), nie pomiary. Jedno jest pewne:
100% nie istnieje bez urządzenia i nikt uczciwy tego nie obieca.

## 6. Konsekwencje praktyczne (co z tego robimy dziś w nocy)

1. **Wariant „coherent"**: donorski `system` + donorski `system_ext` (632 MB, mieści się w
   slocie 745 MB) + lekki `product` + vbmeta `flags=3`. Stockowy LGSIU system_ext (A14)
   wymieszany z A17 systemem to gwarantowany chaos klas; donorski system_ext usuwa jedną z
   dwóch największych niespójności. Zostaje luka vendor A12 ↔ system A17 — nie do domknięcia
   bez flashowania vendora donora, a tego się nie da podpisać (ścieżka C, docs/05).
2. **Triage po flashu** jest teraz konkretny: wiadomo, CZEGO szukać w logcacie (SF/composer
   HIDL, audio HIDL, braki AIDL) i które property potwierdzają właściwy stan (VNDK 31, GSI keys).
3. Ścieżka A (moduł fontów) pozostaje jedyną z gwarancją bootu — stock LGSIU nie rusza AVB.

## 7. Reprodukcja analizy

```
# pobranie (konektor Drive, pliki <100 MB; md5 = sumy serwera Google)
#   boot.img 1funWH4Bdcf7XCouKu9eAu-umCv9L1NgG, vendor_boot 14hSJeBkfX1zNnVWd99NCxoskC-oKfy9f,
#   vbmeta 1u3HPzK0HyYu4kvA5WBYPl4Zbv_AWS7Ao  (google_drive/ w workspace, poza gitem przez *.img)
python3 - <<'PY'   # naglowek vbmeta: flags, klucz, deskryptory (layout z libavb; offsety
 ...               # klucza/deskryptorow WZGLEDNE wobec blokow AUTH/AUX - patrz docs/06 6.35)
PY
# boot v4: kernel@align(hdr=1584) Image.gz; ramdisk za kernelem, lz4-legacy (02 21 4c 18)
# vendor_boot v4: ramdisk@0x1000 lz4-legacy; cpio newc; fstab w first_stage_ramdisk/
```

Pliki źródłowe (md5 zweryfikowane): `google_drive/{boot,vendor_boot,vbmeta}.img`. Ekstrakty
są nietrwałe (`/tmp/tgt/`); trwałe wnioski — ten dokument.
