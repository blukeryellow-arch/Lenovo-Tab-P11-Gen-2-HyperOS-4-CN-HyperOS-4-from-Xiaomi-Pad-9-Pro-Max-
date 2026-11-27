# MysticalOS 1.0 — Redmi 9C (`angelica` / `angelican` / `blossom`) + Emulator Windows `.exe`

Zautomatyzowany builder GitHub Actions tworzący system **MysticalOS 1.0** (oparty na bazie **HyperOS 4 / Android 17** dla **Redmi 9C (`angelica` / `angelican`, rodzina `blossom`)**), łączący **oryginalny HyperOS 4 System_launcher (`8.01.02.9248`)** z **zawsze włączonym Dynamic Island (Always-On)**, **silnikiem zmiany rozmiaru ikon i kafelków w stylu ColorOS 17 (`MysticalFluxStudio`)**, usuniętym bloatware'em Xiaomi i otwartym zestawem **Fossify / microG / HeliBoard / Droid-ify**, natywnym daemonem RAM w **Rust** (`r9c-memd`) oraz lekkim **emulatorem `.exe` na komputer Windows** (`MysticalOS-Emulator.exe`).

## Co zostało zrobione względem zwykłego HyperOS 4

1. **Oryginalny HyperOS 4 `System_launcher` jako baza pulpitu (`apps/hyperos4-launcher/`):**
   - wkompilowany oryginalny **HyperOS 4 `System_launcher_RELEASE-8.01.02.9248-261013-11112305-R.apk`** (`com.miui.home`, architektura ARM64 Flutter + Rust FRB, oryginalny podpis Xiaomi `CN=MIUI` zachowany w 100% — bez łamania certyfikatu systemowego),
   - weryfikowana w CI zgodność z `hyperos.rustruntime.v*.jar` oraz zależnościami natywnymi `DT_NEEDED` w drzewie dawcy `dew` (Android 17),
   - wygenerowany `/product/media/theme/default/runtime_largeicon.config` i zachowane `media/theme/miui_mod_icons` dla natywnego silnika dużych ikon `LargeIconModeRuntimeManager`,
   - przyznane pełne uprawnienia `privapp-permissions-miuihome.xml` i wykluczenie z oszczędzania energii `sysconfig/miuihome.xml`.
2. **Always-On Dynamic Island (`tools/patch_hyperos4_island.py` + `tools/mysticalos_brand.py`):**
   - odblokowane flagi w `device_features/*.xml` (`support_dynamic_island`, `support_dynamic_island_blur`, `support_dynamic_island_middle`, `support_largeicon`),
   - wygenerowane natywne nakładki RRO **`MysticalOSIslandSystemUIOverlay.apk`** oraz **`MysticalOSIslandHomeOverlay.apk`** (`priority="960"`) w `/product/overlay/`, wymuszające zasoby boolowskie Dynamic Island i BigIcon,
   - patcher bajtkodu DEX (`tools/patch_hyperos4_island.py`) znoszący bramki niskiego RAM-u / poziomu urządzenia (`isMiuiLiteVersion`, `isMiuiMiddleVersion`, `DeviceLevelUtils`, `supportDynamicIsland`, `isSupportBigIcon`) w `framework.jar` / `miui-framework.jar` / `hyperos.rustruntime.v*.jar` bez naruszania podpisu `MiuiHome.apk` ani `MiuiSystemUI.apk`,
   - odpowiednie właściwości `build.prop` (`ro.mysticalos.dynamic_island=always_on`, `persist.sys.dynamic_island.enabled=true`, `ro.config.device_level_for_animation=3`, `ro.config.low_ram.go=false`).
3. **Zmiana rozmiaru ikon i kafelki jak w ColorOS 17 (`apps/mystical-launcher/` -> `MysticalFluxStudio.apk` & `MysticalLauncher.apk`):**
   - na oryginalnym HyperOS 4 Launcherze działa bez konfliktu `CATEGORY_HOME` aplikacja towarzysząca i zestaw widżetów **`MysticalFluxStudio.apk`** ("Ikony ColorOS 17" + widżet **"ColorOS 17 Kafelek · Flux"**):
     - **zmiana rozmiaru ikon dla każdej aplikacji osobno** lub globalnie (`60%` – `150%`),
     - **kształty ikon ColorOS 17** (`Zaokrąglony kwadrat` / `Pebble` / `Koło` / `Kwiat`),
     - **zmiennorozmiarowe kafelki pulpitu `1x1`, `2x1`, `1x2`, `2x2`** możliwe do umieszczenia bezpośrednio na ekranie głównym HyperOS 4 z własną ikoną i tytułem wybranej aplikacji,
     - przełącznik **Dynamic Island (Zawsze włączony)** i obsługa natywnego `IconSizeProvider` / podgląd na żywo,
   - opcjonalny pełny launcher standalone **`MysticalLauncher.apk`** nadal budowany jest jako osobny pakiet w GitHub Release.
4. **Rebranding MysticalOS + usunięcie bloatware'u Xiaomi + otwarte zamienniki FOSS:**
   - rebranding (`ro.mysticalos.version=1.0`, `ro.mysticalos.codename=Flux17`, `bootanimation.zip` `720x1600`, `MysticalOSFrameworkOverlay.apk`),
   - usunięte zbędne apki Xiaomi (`HyperPhone`, `MiuiMmsGlobal`, `MIUIGalleryGlobal`, `MIUIFileExplorerGlobal`, `MiuiCamera`, `MIUISecurityCenterGlobal`, `MISettings`, `MIUIThemeManagerGlobal`, `MIUIXiaomiAccountGlobal`, `MIUICloudServiceGlobal`, `Backup`, `Notes`, `MiMusic`, `MiVideo`, `Weather`, `MiBrowser`, `AnalyticsCore`, `MSA`, `Joyose` itd.) oraz bloat GMS,
   - zainstalowane w `/product/app` i `/product/priv-app`: **Fossify Phone**, **Fossify Messages**, **Fossify Contacts**, **Fossify Gallery**, **Fossify File Manager**, **Fossify Camera**, **Fossify Clock**, **Fossify Calculator**, **HeliBoard**, **Droid-ify**, **microG (`GmsCore` + `FakeStore` + `GsfProxy`)**, **Cromite WebView** oraz **Redmi9CRustApp** (`NativeActivity` w Rust).
5. **Emulator `.exe` + silnik odczytu `super.img` / `system.img` na Windows (`rust/mystical-emulator/` -> `MysticalOS-Emulator.exe`):**
   - samodzielny plik wykonywalny **x86_64 Windows** (`kernel32.dll` + `user32.dll` + `gdi32.dll` + `comdlg32.dll` + `shell32.dll`, zero zewnętrznych bibliotek DLL),
   - **natywny dekoder obrazów Androida w czystym Rust**: obsługuje **Android Sparse**, **`super.img` (`liblp`)**, **EROFS (z LZ4 `big_pcluster` i `ztailpacking`)** oraz **EXT4**,
   - weryfikuje w obrazie m.in. obecność `com.miui.home` (`HyperOS 4 Launcher`), konfigurację `Always-On Dynamic Island`, `build.prop`, `services.jar` (`R9cMicrogSpoof`), `bootanimation.zip`, eksplorator katalogów oraz eksport `system.img`,
   - dodatkowo wyświetla interaktywny symulator UI z pigułką **Dynamic Island** i suwakiem rozmiaru ikon ColorOS 17 (`60%–150%`).

## Uczciwe ograniczenia techniczne

1. **`MysticalOS-Emulator.exe` łączy symulator UI/UX z prawdziwym analizatorem plików `super.img` / `system.img`**, natomiast nie jest sprzętowym emulatorem QEMU/ARM64 procesora MediaTek MT6765: otwiera i weryfikuje zawartość obrazów ROM na Windows x86_64, ale **nie uruchamia binarnie jądra Linux 4.19 ani sterowników sprzętowych ARM64 z telefonu**.
2. Zamkniętoźródłowe komponenty szkieletu Androida 17 z `dew` (`system_server`, `SurfaceFlinger`, `MiuiSystemUI`, `ART`, oryginalne `MiuiHome.apk` + `hyperos.rustruntime`) pozostają na poziomie binarnym, natomiast zbędne aplikacje użytkownika Xiaomi zostały usunięte i zastąpione pakietami FOSS.
3. Obrazy są budowane oraz weryfikowane przez `secilc`, `simg2img`, `lpinfo`, `lpunpack`, `openssl pkcs7`, `MysticalOS Emulator --verify-image` i pętlę `mount` w GitHub Actions — nie były uruchamiane na fizycznym Redmi 9C.

## Pobieranie z GitHub Releases

- **Na komputer Windows (podgląd / emulator):** pobierz sam plik **`MysticalOS-Emulator.exe`** i uruchom go dwuklikiem.
- **Na telefon Redmi 9C (prawdziwy ROM do wgrania):** pobierz wszystkie 5 części archiwum **`MysticalOS-Redmi9C.7z.001` .. `.7z.005`** do jednego folderu, rozpakuj `.7z.001` programem 7-Zip/WinRAR i użyj `FLASH-REDMI9C.bat` lub `FLASH-REDMI9C.sh` zgodnie z `INSTRUKCJA-FLASH.txt`.
