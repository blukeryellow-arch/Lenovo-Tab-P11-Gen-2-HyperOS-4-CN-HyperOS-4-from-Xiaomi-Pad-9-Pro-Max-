# MysticalOS 1.0 — Redmi 9C (`angelica` / `angelican` / `blossom`) + Emulator Windows `.exe`

Zautomatyzowany builder GitHub Actions tworzący system **MysticalOS 1.0** (oparty na bazie **HyperOS 4 / Android 17** bez apek użytkownika Xiaomi) dla telefonu **Redmi 9C (`angelica` / `angelican`, rodzina `blossom`)**, z otwartoźródłowymi zamiennikami **Fossify / microG / HeliBoard / Droid-ify**, launcherem **MysticalLauncher** ze zmianą rozmiaru ikon i kafelkami w stylu **ColorOS 17**, natywnym daemonem RAM w **Rust** (`r9c-memd`) oraz lekkim **emulatorem `.exe` na komputer Windows** (`MysticalOS-Emulator.exe`).

## Co zostało zmienione względem zwykłego HyperOS 4

1. **Rebranding na MysticalOS 1.0 (`tools/mysticalos_brand.py`):**
   - właściwości systemowe (`ro.mysticalos.version=1.0`, `ro.mysticalos.codename=Flux17`, `ro.build.display.id`, `ro.product.marketname`),
   - własna animacja startowa `bootanimation.zip` (`720x1600`, `24 fps`) wygenerowana w czystym Pythonie,
   - nakładka RRO `MysticalOSFrameworkOverlay.apk` (`ro.boot.vendor.overlay.theme`) ustawiająca nazwę urządzenia i paletę akcentową MysticalOS.
2. **Usunięcie apek użytkownika Xiaomi + otwarte zamienniki FOSS:**
   - usunięte: `MiuiHome`, `HyperPhone` / `InCallUI`, `MiuiMmsGlobal`, `MIUIGalleryGlobal`, `MIUIFileExplorerGlobal`, `MiuiCamera`, `MIUISecurityCenterGlobal`, `SecurityCoreAdd`, `MISettings` (z zachowaniem systemowego AOSP `Settings`), `MIUIThemeManagerGlobal`, `MIUIXiaomiAccountGlobal`, `MIUICloudServiceGlobal`, `Backup`, `MiuiExtraPhoto`, `Notes`, `MiMusic`, `MiVideo`, `Weather`, `MiBrowser`, `AnalyticsCore`, `MSA`, `Joyose` oraz bloat Google GMS,
   - zainstalowane w `/product/app` i `/product/priv-app`: **Fossify Phone**, **Fossify Messages**, **Fossify Contacts**, **Fossify Gallery**, **Fossify File Manager**, **Fossify Camera**, **Fossify Clock**, **Fossify Calculator**, klawiatura **HeliBoard**, sklep FOSS **Droid-ify**, **microG (`GmsCore` + `FakeStore` + `GsfProxy`)**, otwarty **WebView** oraz **Redmi9CRustApp** (`NativeActivity` w Rust),
   - `MiuiSystemUI` pozostaje z bazy `dew`, aby zachować panel powiadomień, pasek statusu i obsługę warstwy systemowej Androida 17 (opcjonalne `MiuiSystemUIPlugin` zostaje jako moduł pomocniczy SystemUI).
3. **Styl ikon i zmiana rozmiaru apek jak w ColorOS 17 (`apps/mystical-launcher/` -> `MysticalLauncher.apk`):**
   - domyślny launcher `HOME` napisany w 100% na czystym Android SDK (bez zewnętrznych zależności),
   - przytrzymanie pustego pola pulpitu albo kliknięcie **Styl ikon (ColorOS 17)** otwiera panel dostosowywania:
     - **Suwak rozmiaru ikon** (`60%` – `150%`),
     - **Kształt ikon** (`Zaokrąglony kwadrat` / `Pebble` / `Koło` / `Kwiat`),
     - **Siatka pulpitu** (`4` lub `5` kolumn),
     - **Etykiety apek** (`Pokaż` / `Ukryj`),
     - **Tapeta Flux** (`4` warianty),
   - przytrzymanie dowolnej ikony zmienia rozmiar kafelka pomiędzy **`1x1`**, **`2x1`**, **`1x2`** i **`2x2`** (jak duże ikony folderów/aplikacji w ColorOS 17), a kliknięcie otwiera odpowiednią aplikację (`Fossify*`, `Droid-ify`, `Ustawienia`, `Rust Monitor`, `Styl ikon`).
4. **Emulator `.exe` + silnik odczytu `super.img` / `system.img` na Windows (`rust/mystical-emulator/` -> `MysticalOS-Emulator.exe`):**
   - samodzielny plik wykonywalny **x86_64 Windows** (`kernel32.dll` + `user32.dll` + `gdi32.dll` + `comdlg32.dll` + `shell32.dll`, zero zewnętrznych bibliotek DLL i zero instalacji),
   - **natywny dekoder obrazów Androida w czystym Rust** (bez zewnętrznych programów): dekoduje **Android Sparse**, **`super.img` (`liblp`)**, **EROFS (w tym skompresowany LZ4 z `big_pcluster` i `ztailpacking`)** oraz **EXT4**,
   - po wczytaniu `super.img` lub `system.img` (oknem wyboru pliku, przeciągnięciem na okno lub automatycznie z tego samego folderu) wyciąga prawdziwy `build.prop`, wczytuje z obrazu rzeczywistą animację startową `bootanimation.zip`, skanuje prawdziwe pakiety `.apk` (AXML), sprawdza status patcha microG w `services.jar`, udostępnia eksplorator plików partycji (`ImageExplorer`) i potrafi wyodrębnić z `super.img` samodzielny `system.img`,
   - dodatkowo oferuje interaktywny symulator UI/UX: animację startową MysticalOS, pulpit, suwak rozmiaru ikon `60%–150%`, kształty ikon, siatkę `4/5` kolumn, powiększanie kafelków (`prawy klik` / `przytrzymanie`) na `1x1`/`2x1`/`1x2`/`2x2`, kalkulator i zapis zrzutu ekranu `.bmp`.

## Uczciwe ograniczenia techniczne

1. **`MysticalOS-Emulator.exe` łączy symulator UI/UX z prawdziwym analizatorem plików `super.img` / `system.img`**, natomiast nie jest sprzętowym emulatorem QEMU/ARM64 procesora MediaTek MT6765: potrafi otwierać, przeglądać i wyodrębniać zawartość prawdziwych obrazów ROM na Windows x86_64 oraz odtwarzać prawdziwą animację `bootanimation.zip` i listę paczek bezpośrednio z obrazu, ale **nie uruchamia binarnie jądra Linux 4.19 ani sterowników sprzętowych ARM64 z telefonu**.
2. Zamkniętoźródłowe komponenty szkieletu Androida 17 z `dew` (`system_server`, `SurfaceFlinger`, `MiuiSystemUI`, `ART`) pozostają na poziomie frameworku, natomiast usunięte zostały aplikacje użytkownika Xiaomi oraz zbędne usługi w tle.
3. Obrazy zostały zbudowane oraz zweryfikowane przez `secilc`, `simg2img`, `lpinfo`, `lpunpack` i pętlę `mount` w GitHub Actions — nie były uruchamiane na fizycznym Redmi 9C.

## Pobieranie z GitHub Releases

- **Na komputer Windows (podgląd / emulator):** pobierz sam plik **`MysticalOS-Emulator.exe`** i uruchom go dwuklikiem.
- **Na telefon Redmi 9C (prawdziwy ROM do wgrania):** pobierz wszystkie 5 części archiwum **`MysticalOS-Redmi9C.7z.001` .. `.7z.005`** do jednego folderu, rozpakuj `.7z.001` programem 7-Zip/WinRAR i użyj `FLASH-REDMI9C.bat` lub `FLASH-REDMI9C.sh` zgodnie z `INSTRUKCJA-FLASH.txt`.
