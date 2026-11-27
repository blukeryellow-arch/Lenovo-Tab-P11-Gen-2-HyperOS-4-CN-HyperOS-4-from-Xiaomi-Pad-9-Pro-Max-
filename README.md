# Redmi 9C (`angelica` / `angelican` / `blossom`) — HyperOS 4.0.8.0 (microG + FOSS + Rust)

Zautomatyzowany builder GitHub Actions tworzący mocno odchudzony, od-Googlowany port **HyperOS 4 (`OS4.0.8.0.XBNMIXM`, Android 17)** dla **Redmi 9C (`angelica` / `angelican`, rodzina `blossom`)**, z integracją **microG**, otwartoźródłowych zamienników FOSS, natywnego daemona RAM w **Rust** (`r9c-memd`) oraz wsparciem dla aplikacji **`.apk` pisanych w Rust** — spakowany w **5-częściowe archiwum 7-Zip (`.7z.001` .. `.7z.005`)** w **GitHub Releases**.

## Skład portu (v2)

- **Baza sprzętowa (OSS Android 17 + kernel 4.19):** `EvolutionX 17.0 blossom` (`xc112lg/blossom_releases`, fallback `crDroid 17.0 blossom`) — dostarcza `boot.img` (kernel 4.19 z obsługą eBPF dla Androida 17), `dtbo.img`, `vendor.img`, `odm.img`, nakładki sprzętowe RRO, matryce VINTF MT6765 oraz `/system/etc/properties/${ro.boot.hwname}.prop` (automatyczne rozróżnienie `angelica` vs `angelican` NFC).
- **Dawca systemu (HyperOS 4 / Android 17):** oficjalna paczka Global dla **Redmi 15C / POCO C85 (`dew`, `OS4.0.8.0.XBNMIXM`)**.
- **Pełne usunięcie Google GMS & bloatu + microG (`--gms-mode microg`):**
  - usunięte `GmsCore` (Google), `Phonesky`, `WebViewGoogle64`, `TrichromeLibrary64`, `LatinImeGoogle`, `Messages_arm64_hdpi` (pozostaje lekkie `MiuiMmsGlobal`), `GoogleDialer` (pozostaje `HyperPhone`), `GoogleRestore`, `VelvetCtS`, `Chrome64`, `YouTube`, `Maps`, `Gmail2`, `Drive`, `Photos`, `Meet`, `MSA`, `AnalyticsCore`, `Joyose`, `MiBrowser`, `AppFinder`, `VoiceUnlock` itd.,
  - wbudowane **microG (`GmsCore` + `FakeStore`/`Companion` + `GsfProxy`)** z kompletem plików `privapp-permissions-microg.xml`, `sysconfig/microg.xml` i `default-permissions-microg.xml`,
  - wbudowana otwartoźródłowa klawiatura **HeliBoard**, sklep FOSS **Droid-ify** oraz otwartoźródłowy **WebView** (zweryfikowany z `config_webview_packages.xml`),
  - inspekcja i bezpieczne patchowanie `services.jar` (`tools/patch_services_spoof.py`) pod ograniczony Signature Spoofing microG (wykonywane wyłącznie, gdy `services.jar` zawiera `classes*.dex` i sygnatury w `framework.jar`/`ComputerEngine` zgadzają się 1:1 — w obrazach odex/vdex-only pomijane bezpiecznie z czytelnym raportem).
- **Natywny Rust w systemie oraz wsparcie `.apk` w Rust:**
  - `rust/r9c-memd/` (`/system_ext/bin/r9c-memd` + `r9c-memd.rc` + dynamiczne reguły SELinux CIL `r9c_memd`): lekki daemon w Rust monitorujący `/proc/meminfo` i PSI (`/proc/pressure/memory`) oraz strojący zRAM/VM (`swappiness`, `page-cluster`, `vfs_cache_pressure`),
  - `rust/rust-app/` (`Redmi9CRustApp.apk`, preinstalowana w `/product/app/Redmi9CRustApp/`): czysto natywna aplikacja Android `.apk` napisana w 100% w Rust (`NativeActivity` + `EGL`/`GLESv2` bez Javy/Kotlina),
  - aplikacje **Java i Kotlin działają bez zmian** (pełny ART + `zygote64_32`),
  - `tools/apk2rust.py`: eksperymentalny parser `AndroidManifest.xml` (AXML) + `classes*.dex` tłumaczący proste metody skalarne Dalvik bezpośrednio na kod Rust i generujący szkielet projektu Rust + mostki JNI.

## Uczciwe ograniczenia techniczne

1. Zamkniętoźródłowe binarki i framework HyperOS (`system_server`, `MiuiSystemUI`, `SurfaceFlinger`, `ART`) nie mają publicznego kodu źródłowego i nie da się ich w całości przepisać na Rust — dlatego przeniesiono do Rusta warstwę zarządzania pamięcią (`r9c-memd`), zoptymalizowano limity ART/LMKD/blur w `build.prop` oraz usunięto zbędne usługi Google/MIUI w tle.
2. Automatyczny tłumacz `tools/apk2rust.py` nie konwertuje w 100% złożonych aplikacji UI (`android.view.*`, Jetpack Compose, refleksja) na sam kod Rust bez ART — dla nich generuje mostki JNI i zachowuje współpracę z warstwą Java/Kotlin.
3. Obrazy zostały zbudowane, skompresowane (`erofs` + `ext4`) oraz zweryfikowane narzędziami `secilc`, `simg2img`, `lpinfo`, `lpunpack` i pętlą `mount`, lecz nie były uruchamiane na fizycznym egzemplarzu Redmi 9C.

## Pobieranie i rozpakowanie (5 plików 7-Zip)

1. Przejdź do **Releases** w tym repozytorium i pobierz wszystkie 5 części do jednego katalogu:
   - `Redmi9C-HyperOS4-Debloated.7z.001` .. `Redmi9C-HyperOS4-Debloated.7z.005`
2. Kliknij prawym przyciskiem myszy **`Redmi9C-HyperOS4-Debloated.7z.001`** i wybierz **Wypakuj** (WinRAR lub 7-Zip).
3. Archiwum złoży obrazy `super.img`, `boot.img`, `dtbo.img`, `vbmeta*.img` oraz skrypty `FLASH-REDMI9C.bat` / `FLASH-REDMI9C.sh` i instrukcję `INSTRUKCJA-FLASH.txt`.
