# Lenovo Tab P11 Gen 2 (Helio G99) ← HyperOS 4 (Xiaomi Pad 9 Pro Max)

Repozytorium procesu, nie repozytorium ROM-u. Trzyma skrypty, moduł, wydania i CI.
Duże obrazy (>100 MB) żyją w gałęzi `transfer-spool` (odbudowa recepturą z docs/08)
i na Google Drive użytkownika; runner Actions to jedyna maszyna z trasą do Dysku.

## Status: co jest wykonalne, a co nie

Zmierzone, nie ocenione na oko.

**Pełny port (framework Androida 17 + HyperOS na tym tablecie) — nie.**
Źródło i cel różnią się wszystkim w warstwie, która decyduje o starcie systemu:

| | Xiaomi Pad 9 Pro Max (źródło) | Lenovo Tab P11 Gen 2 (cel) |
|---|---|---|
| SoC | Xring O3, 3 nm, 10 rdzeni C1, własność Xiaomi | MediaTek MT6789 Helio G99, 6 nm, 2×A76 + 6×A55 |
| GPU | Mali-G2-Ultra (16) | Mali-G57 MC2 |
| RAM / flash | 8–16 GB LPDDR5X/LPDDR6, UFS 4.1 | 6 GB LPDDR4X, UFS 2.2 |
| OS | HyperOS 4 / Android 17 | 12L → 14 |

Cztery blokady, z których żadna nie dotyczy składania obrazów:

1. `vendor` i HAL-e źródła są skompilowane pod Xring O3 — nie mają czego obsługiwać na MT6789.
2. VINTF: framework z A17 żąda nowszych wersji interfejsów, niż dostaje vendor Lenovo. `init` staje na `Waiting for HAL`.
3. Kernel: **zmierzone z `boot.img`** — target to GKI `android12` `5.10.233-ab13101360`
   (skompilowany 2025-02-20), a nie downstream 4.14. Źródło A17 to GKI 2.0 / 6.x i inna generacja
   KMI, więc każdy `.ko` z `vendor_dlkm` źródła dostanie `disagrees about version of symbol`.
   Zamknięte sterowniki MTK zostają jako osobny problem. (Dowód: `docs/04`, sekcja 4.3.)
4. Brak publicznych źródeł/BSP dla Xring O3 (debiut 2026‑09, rynek CN). Nie ma z czego zbudować warstwy sprzętowej.

Odblokowany bootloader nic tu nie daje — blokady są w binariach i kernelu, nie w podpisie.

**Nakładka „HyperOS Look" — tak, i to jest to, co ten kod robi.**
Style, fonty, tapety, dźwięki, krzywe animacji, launcher i gotowe overlaye RRO ze źródła,
na stockowym firmware Lenovo. Zero ruszenia `vendor`, kernela i tablicy partycji, więc
ryzyko sprowadza się do „wyłącz moduł i zrestartuj".

## Wydania ROM — cztery warianty (stan 26 IX 2026)

| wariant | katalog | czym się różni | szanse (docs/09 §5) |
|---|---|---|---|
| lekki | `dist/release/HyperOS4_P11Gen2/` | system A17 + macierz VINTF poziomu 5 (miękka), product = fonty | init ~85%, system_server ~50-60%, pulpit ~10-25% |
| -full | `dist/release/HyperOS4_P11Gen2-full/` | + product donora (fonty+overlaye, 147 wpisów) | j.w. |
| coherent | `dist/coherent-release/…-coherent/` | + donorski system_ext (A17 sdk 37, oryginalne bajty) | j.w., spójniejszy VINTF |
| **CLEAN** | `dist/clean-release/…-clean/` | **coherent minus 7 pakietów diagnostyki/telemetrii** (EngineerMode, MiSightService, DebugLoggerUI, VsimCore, CameraMind, PowerInsight, RtMiCloudSDK) | j.w. — czyszczenie nie zmienia bramek bootu |

**Gotowy do pobrania komplet jest na Google Drive użytkownika** (folder
`HyperOS4_P11Gen2-release/clean/`, 40 plików: części 60 MB + skrypty + sumy).
Sklejanie: `zloz.sh` / `zloz.bat` — przetestowane end-to-end 26 IX: sklejone obrazy
byte w byte identyczne z wydaniem (sha256 4836dcd4…/53dd7dfb…/a961bec4…/9cf2e7e4…).
MSA/GetApps/reklamy nie występują w żadnym wariancie z konstrukcji (product donora
z bloatem nigdy nie jest wgrywany). Kontrola jakości: `tools/test_release.sh`
(**173 PASS no-real / 181 z --real**, sekcje ZC+AA+AB pilnuja m.in. anty-zamiennosci
system_ext), CI zielone na obu workflowach.

## Układ

```
modules/hyperos-look/          moduł Magisk/KSU
  module.prop                  id, wersja, opis
  system.prop                  resetprop (heap, niska pamięć) - nie trwałe
  post-fs-data.sh            tuning pamieci + log diagnostyczny
  service.sh                 wlaczanie overlayy + skale animacji
  customize.sh               only for ZIP flashing; sprawdza SoC, czysci stara wersje
  overlay-app/               zrodka RRO (manifest + res/values/overlay.xml)
  system/product/overlay/    tu trafia zbudowany .apk (generowane, nie w gicie)

scripts/
  list_overlayable.sh        CO mozna nadpisac na Twoim buildzie (przed jakiejkolwiek edycja)
  extract_hyperos_assets.sh  biala lista zasobow + odmowa dla HAL-i, z uzasadnieniem
  build_overlay_apk.sh       aapt2 -> APK -> zipalign -> apksigner, bez Gradle
  install_module.sh          instalacja katalogiem przez adb (+ --disable/--remove)
  verify_module.sh           czy modul realnie dziala po restarcie

diagnostics/collect_device_state.sh   jeden przebieg, caly wynik do wklejenia w czat
diagnostics/identify_images.sh        sortowanie sterty obrazow po odciskach kluczy AVB (nie po nazwach)
tools/ship_to_github.sh                Twoja strona: rozpakuj -> odfiltruj -> split -> push (kanal >100 MB)
tools/pull_from_github.py              Moja strona: manifest -> blob API -> sha256 -> geometria FS
tools/fs_probe.py                      ext4/EROFS/sparse w czystym pythonie, z --selftest
.github/workflows/build.yml           build-module (codziennie) + unpack-source (HF, recznie)
docs/01-ustalenia-srodowiska.md       limity sandboxa, korekta o bootloaderze
docs/02-sciezka-A-nakladka.md         procedura krok po kroku i rollback
docs/03-analiza-vbmeta.md             pelna analiza vbmeta targetu + granica wykonania
docs/04-proweniencja-i-kernel.md      limit transferu, skad ktory obraz, zmierzony kernel
docs/05-analiza-i-projekt-romu.md     analiza donorow, projekt wydania i wariantow
docs/06-budowa-lokalna.md             toolchain EROFS bez apt/root, lekcje budowy
docs/07-jak-weryfikowac.md            jak sprawdzic wydanie (suite, sumy, round-trip)
docs/08-stan-i-blokady.md             receptura odbudowy + pelna kronika utwardzen
docs/09-analiza-targetu.md            bramki startu TB350FU i szanse wariantow
docs/10-rejestr-dowodow.md            KOMPENDIUM: twierdzenie -> dowod -> odtworzenie
```

## Kolejność pracy (nie skracać)

```bash
# 0a. Posortowac sterte obrazow (ktory jest zrodlo, ktory target) - mala, tanio
./diagnostics/identify_images.sh /sciezka/do/obrazow   # wynik: _avb_frags/*.vbmeta

# 0b. Stan urzadzenia - bez tego kazda dalsza decyzja jest wrrozeniem
diagnostics/collect_device_state.sh              # wynik -> do czatu

# 1. Co w ogole mozna nadpisac na tym buildzie
scripts/list_overlayable.sh

# 2. Zasoby ze zrodla (rozpakowanym drzewem partycji, NIE .img)
scripts/extract_hyperos_assets.sh ./unpacked ./modules/hyperos-look/staging

# 3. Dopisac konkretne nadpisania w overlay-app/res/values/overlay.xml
#    (tylko nazwy potwierdzone w kroku 1; jeden resource na commit)

# 4. Budowa + instalacja
scripts/build_overlay_apk.sh --debug-key
scripts/install_module.sh                        # reboot w pakiecie

# 5. Kontrola
scripts/verify_module.sh
```

Kroki 1–3 wymagają `adb` i Twojego tabletu po swojej stronie. Kroki 4–5 działają też
w CI (`build-module`) — tam jest Android SDK, którego sandbox agenta nie ma i nie dociągnie.

## Czego ten kod świadomie nie robi

- Nie pisze do `vendor`, `boot`, `init_boot`, `dtbo`, `vbmeta` ani do tablicy partycji.
- Nie udaje, że `apt` w CI ma `lpunpack`: job sprawdzają dostępność pakietu i zatrzymują
  się z komunikatem, zamiast produkowac pol-zepsuty obraz.
- Nie podpisuje niczym „platformowym” — RRO w `/product/overlay` nie potrzebuje podpisu
  platformowego, a klucza Lenovo i tak nie ma.
- Nie przechowuje tokenów. `HF_TOKEN` istnieje wyłącznie jako sekret repozytorium.

## Ryzyko, które zostaje

Nawet przy module: wgranie czegokolwiek do `/product` przez nadmontowanie zmienia zachowanie
PMS przy starcie. Złe nadpisanie resource'u = bootloop SystemUI, nie = cegła. Ratunek:

```bash
adb reboot recovery          # lub: Magisk app > Modules > wylacz
# najpewniejszy: usunac katalog modulu
adb shell su -c "rm -rf /data/adb/modules/hyperos_look_p11g2" && adb reboot
```

Modul nie rusza partycji, wiec usuniecie go przywraca stan wyjsciowy w 100%.
Zapasowo: Lenovo Rescue & Smart Assistant + EDL działają na tej rodzinie (potwierdzone
na forach dla TB336FU/TB330FU), więc awaryjny powrót do stock jest realny.
