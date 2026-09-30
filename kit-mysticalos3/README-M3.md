# MysticalOS 3 - LOKALNY KIT BUILD (bez GitHub Actions)

Kompletny build super.img MysticalOS 3 na Twoim komputerze. Wszystkie narzedzia
w kicie (statyczne lpmake/lpunpack z AOSP 15, mkfs/fsck/dump.erofs 1.8.2,
avbtool 1.3.0, parsery liblp + streaming unsparse - bit-identyczne z AOSP,
zwalidowane w CI GitHub).

## Szybki start (Windows - JEDNO KLIKNIECIE)

Pobierz i uruchom `START-MYSTICALOS3.bat` (Drive, publiczny):
https://drive.google.com/uc?id=1_YsqtYnHTqfXwTS6StCumrWoLYIrQEPj&export=download
(rowniez: `RUN-WINDOWS.ps1` - https://drive.google.com/uc?id=1eZ9EtJyEbTsqfVoY4cu0OTKChv-2VBCR&export=download)

Skrypt sam: sprawdzi/zainstaluje WSL2 (raz, moze wymagac restartu), dolozy
pakiety w WSL, pobierze kit z Drive (kontrola SHA256), odpali build i wyda
wyniki do folderu `WYNIKI-mysticalos3` obok .bat. Nie zamykaj okna do konca.

## Szybki start (Ubuntu / WSL2 - recznie)

```bash
sudo apt-get install -y e2fsprogs python3 curl unzip   # debugfs potrzebny
tar xf mysticalos3-local-kit.tar.gz
cd kit-mysticalos3
./build-mystical3.sh            # ~30-60 min; wznowienie pobierania dziala (-C -)
```

Wynik w `build/out/`:
- `super_mystical3.img` (sparse, ~4,5G) - flash przez **fastbootd**
- `vbmeta_disable.img` + `vbmeta_system_disable.img` + `vbmeta_vendor_disable.img`
- `boot_TB350FU_S230982_251013_ROW.img` (rollback na bootloop)
- `FLASH-M3.md` (instrukcja flash) + `SHA256SUMS.txt`

## Wymagania
| co | ile |
|---|---|
| system | Linux x86_64 (natywnie albo WSL2; fastboot na Windowsie obok) |
| miejsce na dysku | 20 GB |
| RAM | 4 GB (streaming - nie materializuje 9,7G raw) |
| root | NIE (debugfs rdump zamiast mount) |
| internet | 4,5G (baza lolinet) + ~150M (microG/FakeStore) |

## Co robi skrypt (pełny audyt w `build/stream-manifest.txt`)
1. pobiera `TB350FU_S230982_251013_ROW.zip` (lolinet, pin rozmiaru),
2. **streamuje** super.img z zipa (`unzip -p | simg2img_stream | stream_lpunpack`)
   - partia po partii, z weryfikacja rozmiarow partycji vs PINY,
3. ekstrahuje drzewa (ext4: debugfs rdump; erofs: fsck.erofs --extract),
4. system: PURGE GMS (8 katalogow; WebView zostaje) + INJECT microG + FakeStore
   (+ Aurora jesli URL zyje) + props + repack EROFS z kontekstami SELinux,
5. product/system_ext: PURGE GMS (22+4) + repack,
6. vendor* + boot: oryginaly (spojnosc z kernelem),
7. lpmake -S: super w FABRYCZNEJ geometrii (9 663 676 416 B, VAB, slot A),
   z weryfikacja metadanych zbudowanego pliku,
8. vbmeta_disable x3 (flags=3) + SHA256SUMS.

## Bezpieczniki
- kazda partycja weryfikowana rozmiarem (piny z trace CI),
- obraz systemu po mkfs sprawdzany ekstrakcja (microG/FakeStore/props obecne),
- geometria super sprawdzana parserem lpinfo (nie tylko "lpmake sie udal"),
- slot B nietkniety = zawsze masz rollback.

## Uwagi
- AuroraStore: jesli oba URL-e martwe, build leci bez niej (doinstaluj z
  auroraoss.com albo F-Droid - pelnoprawny sklep na microG),
- fonty Mi / apki MIUI: nie ma w tym kicie (donor yingtian niedostepny z
  poziomu lokalnego; jak wrzucisz product.img donora obok, daj znac - dolacze
  faze transplantu),
- `fastboot flash super` wymaga **fastbootd** (partycje dynamiczne) - patrz FLASH-M3.md.
