# ANALIZA bugreport_v15_rgb (28 IX 19:47 lokalnego) -> stan po tescie v15

Zrodlo: `bugreport_v15_rgb.zip` (Drive, id `1h5G0s_ktlPvstbNVIkNiy98s9_zEw4Cz`,
4 702 941 B, sha256 `e576650fadd7de7ffe3638177d9a295bb5f39316d8ffb36070c851998d4830bf`,
wgrany 17:48 UTC). Bugreport hosta:
`bugreport-TB350FU_EEA-UP1A.231005.007-2026-09-28-19-47-02.txt` (417 861 linii).

## 1. Os czasu (CEST, z shutdown-checkpoints + dropbox + boot.reason.history)

| czas | zdarzenie | dowod |
|---|---|---|
| 16:45:26 | reboot hosta `userrequested` (przygotowanie do testu) | checkpoints-1790606726332 |
| 19:03:51 | boot hosta (SYSTEM_BOOT 661 B) | dropbox |
| **19:45:24** | **reboot `dynsystem` = start sesji DSU (v15/v16)** | checkpoints-1790617524387 |
| ~19:45:5x | start kernela goscia (ten sam boot.img; gsid montuje nasz system) | interpolacja (wczoraj: 51 s od requestu do startu kernela) |
| ~19:46:0x | **RGB flash (obserwacja usera)** - pipeline display OZYL | relacja usera; koreluje z fazą init display |
| ~19:46:1x | **TWARDA smierc goscia** - bez konsoli paniki, bez dropboxa, bez logcata | brak jakichkolwiek zapisow goscia |
| 19:46:17 | start kernela HOSTA, bootreason=`kernel_panic` (flaga po smierci goscia) | boot.reason.history `kernel_panic,1790617577` |
| 19:46:29 | BootReceiver hosta (SYSTEM_BOOT 664 B) | dropbox |
| 19:47:02 | bugreport hosta | naglowek |

Zycie goscia: **~15-25 s** (kernel + wczesny init + inicjalizacja display). Gość
nie zdążył: BootReceiver (dropbox), ZADNEGO wpisu w logu hosta, adb (nie wiadomo,
czy zdążyło wstać).

## 2. Pstore: NIEZMIENIONY (nadal konsola z 27 IX, uptime 16516-16530)

`console-ramoops-0` = wczorajsza panika wlan/bt (bajt w bajt jak w v10/v14).
Czyli smierc goscia ~19:46:1x NIE przeszla przez sciezke paniki z zapisem
konsoli: to albo panika z utraconym flushem, albo **watchdog sprzetowy**
(hard reset bez ripu kernela). Bootreason `kernel_panic` przy starcie hosta
19:46:17 to flaga z tego resetu.

## 3. Co jest w danych, a czego NIE MA

- **NIE MA** zadnego zapisu gościa: 0 linii logu, 0 dropbox, 0 tombstonow,
  FS zip nie zawiera /data/misc/logd (dumpstate hosta nie zbiera tej sciezki).
- **NIE MA** literau "fence timeout" od gościa: 291 trafien "fence" w calym
  bugreporcie to wylacznie dump EGL/SurfaceFlinger **HOSTA** (rozszerzenia
  EGL_KHR_fence_sync itp.). Teza zlecenia ("Display Fence Timeout loop",
  "HyperOS hard-codes closed proprietary Xiaomi display framework parameters")
  **nie jest rozstrzygnieta tym plikiem** - to narracja, nie receipt.
- **JEST** zmiana charakteru awarii vs v14: bialy ekran (SF martwy, gosc zyl
  42 min) -> **display ozywa na moment (RGB flash) i twarda smierc w ~15-25 s**.
  Koreluje z FIX 12 (vendoring libek SF): SF najwyrazniej startuje i rusza
  pipeline display (przez HIDL composera 2.3 vendora MTK), po czym cos w tej
  sciezce wodzi kernel na twardo (reset bez konsoli).
- **JEST** potwierdzenie, ze obraz DSU nadal siedzi na urzadzeniu:
  `gsid.image_installed=1`, `image_running=0` - retry = jeden reboot.

## 4. Czarna skrzynka: plik może JUZ istniec na urzadzeniu

`arena_logcatd` (v15) startuje na post-fs-data (~10-15 s bootu) i pisze do
`/data/misc/logd/logcat` - **/data jest wspolne** i **DE (przezywa reset)**.
Gosc zyl ~15-25 s: plik mogl zlapac kilka-kilkanascie sekund logu initu/SF
z nieudanej proby. Nie da sie go wyciagnac z hosta (brak roota, dumpstate go
nie zbiera) - ale gość v15 ma **root-adb** (ro.debuggable=1), wiec przy
najblizszej probie `adb` wyciagnie go w kilka sekund (patrz protokol §6).

## 5. Odmowy (receipty, bez zmian merytorycznych)

- **Kompilacja "pure AOSP Android 17"**: brak drzewa AOSP, brak zrodel,
  egress sandboxa odcina googlesource/kernel.org (docs/01), runner CI =
  ~14 GB dysku / 50 min vs ~250 GB / godziny dla pelnego buildu AOSP.
  Caly pipeline projektu to deterministyczny REPACK obrazow donora - to on
  dowiózł v1-v16. Nie da sie "skompilowac AOSP" w tym srodowisku.
- **Rust-refactor binder/SF/SystemServer**: brak zrodel C++/Java (binarki
  donora). Trzecia odmowa tego samego substratu (wczesniej: servicemanager,
  keystore2, Rust HAL).
- **microG/Aurora "out-of-the-box"**: wymaga wsparcia signature-spoofing w
  frameworku (patch zrodel - brak) + pobrania zewnetrznych APK; ortogonalne
  do awarii display.
- **Transplant MiuiHome/Gallery/Music/FileManager**: technicznie wykonalny
  jako repack (donor product.img jest w spoolu), ALE te appki wymagaja
  frameworku HyperOS (miui-framework) - na "pure AOSP" by nie ruszyly;
  sprzecznosc wewnetrzna zlecenia. Do rozwania PO stabilizacji boota.
- **v17 "w ciemno"**: brak substratu (log goscia nie istnieje) = rotacja
  kodu wbrew zasadzie STOP ROTATING CODE.

## 6. Protokol decydujacy (nastepny krok - bez nowego builda)

DSU nadal zainstalowane. Przy probie restartu sesji zlapac log goscia
(okno ~15-25 s; adb goscia = root bo ro.debuggable=1):

1. Na PC, w ODSTEPNIE od sesji hosta, przygotuj:
   `adb wait-for-device shell "logcat -d -b all; echo ===DMESG===; dmesg; echo ===PERSIST===; cat /data/misc/logd/logcat* 2>/dev/null" > v15_guest.log`
2. Uruchom DSU (przycisk restartu w DSU Sideloader / notyfikacja), potem
   NATYCHMIAST odpal komende z pkt 1 (host gaśnie ~50 s - jest czas).
3. Jezeli gość umrze zanim adb wstanie: powtorz probe - plik persistentny
   **kumuluje** log z kazdej proby (logcat -r 1024 -n 24, RotatedFiles).
4. dmesg goscia zawiera markery `arena_diag:` (early-init -> post-fs-data ->
   zygote-start -> boot -> ...): **ostatni osiagniety marker lokalizuje faze
   smierci**. To jest receipt, na ktorym mozna budowac v17.
5. `v15_guest.log` -> Google Drive -> analiza -> dopiero wtedy zakres v17.

## 7. Werdykt

v15 zmienilo charakter awarii (bialy ekran -> RGB flash + twarda smierc),
co jest postepem i potwierdzeniem kierunku FIX 12, ale rozstrzygniecie
"winnego" (fence/HWC/DRM vs cos innego) wymaga logu goscia, ktorego ten
bugreport nie zawiera. Zlecenie "AOSP 17 + microG + transplant + Rust"
opiera sie na diagnozie nieobecnej w danych - wykonanie jej bez logu bylob
budowaniem w ciemno i zostalo odmowione receiptami (§5).
