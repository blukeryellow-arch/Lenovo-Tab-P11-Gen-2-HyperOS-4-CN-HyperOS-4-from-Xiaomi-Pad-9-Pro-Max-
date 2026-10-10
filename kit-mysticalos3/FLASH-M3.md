# MysticalOS 3 - flash (TB350FU / Lenovo Tab P11 Gen 2)

## Wymagania
- bootloader ODBLOKOWANY (OEM unlocking w opcjach deweloperskich + `fastboot flashing unlock`),
- `fastboot` + `fastbootd` (platform-tools >= 31; fastbootd = `fastboot reboot fastboot`),
- bateria > 30%,
- **slot B zostaje nietkniety = rollback** (`fastboot --set-active=b`).

## Kolejnosc (fastbootd!)

1. `fastboot flash vbmeta vbmeta_disable.img`
2. `fastboot flash vbmeta_system vbmeta_system_disable.img`
3. `fastboot flash vbmeta_vendor vbmeta_vendor_disable.img`
4. `fastboot reboot fastboot`   *(przejscie w fastbootd - WAZNE, super to partycja dynamiczna)*
5. `fastboot flash super super_mystical3.img`   *(fastbootd sam rozpakuje sparse)*
6. `fastboot --set-active=a`   *(build zawiera TYLKO slot A!)*
7. `fastboot reboot`

Pierwszy boot: 5-15 min (optymalizacja aplikacji).

## JESLI bootloop
Kernel w boot (S231044 z HyperOS usera vs moduly S230982 z bazy) moe nie pasowac:

```
fastboot flash boot boot_TB350FU_S230982_251013_ROW.img
fastboot reboot
```

## Rollback
```
fastboot --set-active=b && fastboot reboot
```
(slot B ma oryginalny stock - build nie dotyka go).

## SP Flash Tool (alternatywnie)
super_mystical3.img jest w formacie SPARSE. Przed wgraniem przez SPFT przekonwertuj:
```
python3 simg2img.py super_mystical3.img super_raw.img
```
(magic 0xED26FF3A; simg2img.py jest w kicie).

## Co siedzi w srodku
- system MysticalOS 3: PURGE GMS (zostaje TYLKO WebView), microG GmsCore v0.3.17.252432,
  FakeStore, [Aurora jesli dostepna], props `ro.mysticalos.version=3`,
  display mitigation `use_content_detection_for_refresh_rate=false` (staly refresh),
- **transplant apk MIUI z HyperOS 4.0.13 (Xiaomi Pad 9 Pro Max "yingtian")**:
  kalkulator / aparat / notatki oraz galeria, muzyka, video, pliki, pogoda, zegar
  itd. w `/system/app/Miui*` (pelna lista w release notes i MIUI-APKI.md) +
  fonty MiSans + motywy (inertne). To apki SYSTEMOWE z donora - nie Lenovo.
- product/system_ext: bez Google (purge 22+4 pakietow),
- vendor/vendor_dlkm/odm_dlkm/boot: ORYGINALNE S230982 (spojnosc z kernelem),
- geometria super = FABRYCZNA (9 663 676 416 B, VAB, metadata 3 sloty).

## Sprawdzenie pobranych plikow
```
sha256sum -c SHA256SUMS.txt
```
