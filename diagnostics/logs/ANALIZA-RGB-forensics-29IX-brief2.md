# FORENSIC BRIEF #2 — ZEWNETRZNY ZWIAD GLOBALNY (XDA / GitHub / AOSP / developer.android.com)
Sprint 29 IX (kontynuacja): dlaczego zmodyfikowany ROM / czesciowy GSI repack daje
white-screen / 50 ms RGB flash pod DSU. Zero logow wewnetrznych - wylacznie receipty
z ekosystemu. Kazdy werdykt = zrodlo.

## WEKTOR 1: "super image container constraint" — MECHANIZM PRAWDZIWY, FORMA ROZKAZU BLEDNA

**Co powiedzialy zrodla (receipty):**

1. **DSU jest ZPROJEKTOWANY do pojedynczego system.img** — oficjalna dokumentacja
   (developer.android.com/topic/dsu): instalacja = `am start-activity
   -n com.android.dynsystem/com.android.dynsystem.VerificationActivity
   -a android.os.image.action.START_INSTALL -d file://...system_raw.gz --el
   KEY_SYSTEM_SIZE ...`. Jeden obraz systemu -> nowa logiczna partycja w /data
   (libfiemap) -> boot goscia na HYSTYCZNYCH product/system_ext/vendor hosta.
   Nie ma zadnej "hard layout crash" dla lone system.img — to jest SCIEZKA
   PODSTAWOWA (DSU Sideloader, VegaBobo: caly ekosystem na tym stoi).
2. **ALE: Android 11+ DSU obsluguje multi-partition (dsu.zip)** — receipt:
   XDA "how to flash a fully working GSI with DSU?" (mohamedfaky, Redmi Note 9S,
   2022): autor dekompresuje system/system_ext/product (.new.dat.br -> sdat2img)
   i flashuje je RAZEM przez DSU. Kluczowe obserwacje empiryczne autora:
   - **samo system.img custom ROM-u NIE bootowalo** — "because of lacking of
     product.img and system_ext files [...] or because the customized rom needs a
     customized product and system_ext and not the stock one";
   - **problem z wyswietlaczem (hole punch display wygladal dziwnie) zniknal po
     dolaczeniu vendor.img do DSU** — ale reszta sie posypala (custom kernel
     nieosiagalny przez DSU; tylko partycje logiczne pod super sa wymienialne).
   To jest dokladnie klasa naszego portu HyperOS: framework MIUI bez MIUI-product.
3. **fastbootd/super receipty** (hovatek 47900, XDA 4159153 "Solved GSI
   Installation", fl0w mod): na urzadzeniach z dynamicznymi partycjami GSI flashe
   sie do partycji system W fastbootd (albo lpunpack/lpmake super.img); mozna
   usuwac product/system_ext dla miejsca, vendor NIE (unbootable).

**Werdykt:** nie istnieje "layout crash" gsid przy 1,5 GB system.img. Istnieje
natomiast UDOKUMENTOWANA klasa: **custom ROM (port) wymaga WLASNYCH product/
system_ext — bez nich gosc nie bootuje lub pada przy inicjalizacji UI**. Linker
dynamiczny goscia nie "rozwiazuje wiazan miedzy-partycyjnych w kernelu" —
system_server/SurfaceFlinger gosciaпадaja w USERSPACE, gdy framework oczekuje
zasobow (RRO overlaye, apk, uprawnienia) z product/system_ext, ktorych host
nie dostarcza. Twarde smierci kernela przychodza z drugiej strony (wektor 2).

## WEKTOR 2: 50 ms RGB flash — BRAK RECEIPTU NA "verification power-cut"; PRAWDZIWE KLASY

**Rozkladanie przeslanki na receiptach:**

1. **VerificationActivity = komponent INSTALL-TIME.** Oficjalna dokumentacja DSU
   (developer.android.com/topic/dsu) i zrodla gsid (android.googlesource.com/
   platform/system/gsid, commit 1ecc3af0 "closeInstall() and enableGsi() code
   cleanup"): VerificationActivity odbiera URI obrazu, pokazuje userowi potwierdzenie
   (odcisk/PIN - receipt XDA 4230239), uruchamia DynamicSystemInstallationService,
   gsid mapuje obraz do /data/gsi (libfiemap). Po "Restart" bootloader montuje
   obraz DSU. **W tej sciezce NIE MA zadnego runtime "hash watchdoga" nad
   uruchomionym gosciem** — weryfikacja integralnosci goscia to dm-verity/AVB przy
   montowaniu, nie proces pilnujacy display.
2. **Wymog "signed by Google or your OEM"** (oficjalna dokumentacja DSU) dotyczy
   GATE przy instalacji (DSU Loader pobiera tylko podpisane; sciezka pliku
   lokalnego przez VerificationActivity dziala z niepodpisanymi na odblokowanym
   bootloaderze — receipt: mohamedfaky flashowal PE/phh przez `am`; XDA 4230239
   instalowal phh system-roar). Nie ma mechanizmu "host zetnie zasilanie panelu
   gdy wykryje zmieniony hash" — zero trafien w dokumentacji, gsid, XDA, GitHub.
3. **PRAWDZIWE klasy "white screen / dziwny obraz / smierc display" na GSI
   (receipty):**
   - phh Treble Settings ma gotowe TOGGLE'e: **"workaround for white-ish screen"**,
     "extended brightness range" itd. (receipt: XDA "[AOSP GUIDE] A few tips...",
     4499779) — biale/wyblakle ekrany GSI to znana klasa z workaroundami runtime;
   - "blank screen after the third restart with any GSI ROM" (XDA 4041255) —
     czarny ekran po restarcie na GSI; useri omijaja przez reboot z kombinacja
     klawiszy / bez hasla szyfrowania — klasa: inicjaliza display po wczesnym
     restarcie;
   - **vendor.img przez DSU naprawil "hole punch display"** (receipt mohamedfaky,
     wektor 1) — dowod, ze anomalie obrazu na DSU pochodza z NIEDOPASOWANIA
     composera/overlaye'ow vendor-vs-gosc, nie z weryfikacji;
   - brightness/display fixes w phh changelogach (XDA 3895860: "BRIGHTNESS FIXED",
     pliki vendor per-device).
   - Fizyka twardej smierci: sprzetowy WDT MTK resetuje SoC bez sciezki dump
     (receipt techveda "A Watchdog Is Not Enough": hard reset != panic, zero
     dmesg-ramoops; brak pretimeout w vendor mtk_wdt 5.10 - LKML 2026-08-24).
     RGB flash = re-init panelu (sekwencja DSI reset / test pattern przy
     mode-switch), potem sciezka kernela zawisa -> WDT. Panel "gasnie" bo reset
     gasi cale SoC — nie dlatego, ze "verification activity" ucina zasilania.

**Werdykt:** 50 ms RGB = artefakt re-inicjalizacji panelu przy pierwszym
mode-switch/underrun w zarzadzanym przez goscia pipeline display (SF A17 ->
HIDL composer 2.3 MTK). Zabojca = zawisnie sciezki kernela (fence/DSI/ESD) ->
sprzetowy WDT. Zero dowodow na "external verification failure cuts panel power".

## WEKTOR 3: SPL mismatch — MECHANIZM ISTNIEJE, ALE NIE WATCHEM KERNELA

1. Oficjalnie (source.android.com/docs/core/tests/vts/gsi): **Keymaster <= 3**
   weryfikowal version/SPL systemu vs bootloader -> GSI z innym SPL nie bootowal.
   **Od Android  9 wymog zniesiony** ("Keymaster shouldn't perform verification").
2. phh-Treble utrzymuje **fixSPL()** (rw-system.sh) — patchuje biblioteki keymastera
   by czytaly wlasnosci zamiast ro.build.version.security_patch (receipt:
   deepwiki/phhusson/device_phh_treble; XDA 3919628: change_security_patch_ver.sh
   dla urzadzen sprzed P).
3. **Kernel NIGDY nie czyta build.prop goscia** — build.prop to userspace (init/
   property service). Nie istnieje sciezka "kernel porownuje SPL i cicho wlacza
   WDT bez flushu console-ramoops". Brak ramoops po twardej smierci = fizyka
   sprzetowego WDT (wektor 2), nie "cicha kara za SPL".

**Werdykt:** spoof ro.build.version.security_patch jest **nieobowiazkowy** dla
urzadzen z Keymasterem 4+/AIDL KeyMint (nasz host A14: AIDL KeyMint - receipt
macierzy HAL). Dla starych stackow (KM<=3) istnieje gotowy workaround fixSPL.

## SYNTEZA DLA NASZYCH DWUCH LINII (co receipty mowia o naszym przypadku)

- **MysticalOS GSI-1 (AOSP GSI repack)** = wlasciwa sciezka architektury DSU
  (pojedynczy system.img, gosc bez wlasnosciowych oczekiwan). To, ze czysty AOSP
  GSI + microG jest klase bezpieczna, potwierdza projektowanie DSU pod GSI
  (official docs) i caly ekosystem (DSU Sideloader).
- **Port HyperOS (v15/v16)** = klasa receiptu mohamedfaky: custom ROM wymagajacy
  wlasnych product/system_ext — na cudzych (Lenovo) albo nie wstaje, albo umiera
  w UI. Droga eksperymentalna na przyszlosc (z receiptu): **multi-partition DSU
  (dsu.zip: system + system_ext + product z yingtian)** — Android 11+ to
  obsluguje; vendor przez DSU jest ryzykowny (receipt: "everything else broken").
- Zabezpieczenia display pod GSI-1 (z receiptow phh/Vendor15-GSI, z briefu #1):
  staly refresh rate, wylaczenie content-detection, maskowanie AIDL composera na
  HIDL, SF crash-recovery; obserwowalnosc przez kumulujacy logcat (twardy WDT nie
  zostawi dumpu z definicji).

## REJESTR ZRODEL (wszystkie zewnetrne, tej sesji)
- developer.android.com/topic/dsu (oficjalna procedura DSU + wymog podpisu)
- android.googlesource.com/platform/system/gsid @ 1ecc3af0 (closeInstall/enableGsi)
- XDA 4385905 "how to flash a fully working GSI with DSU?" (multi-partition DSU,
  product/system_ext konieczne dla custom ROM, vendor.img a display, custom
  kernel poza zasiegiem DSU)  <- receipt koronny wektora 1
- XDA 4159153 "[Solved] GSI Installation — Finally booted!!!" (fastbootd/super)
- hovatek 47900 + XDA 4713724 (fl0w: delete-logical-partition, vendor niefachowy)
- XDA 4499779 "[AOSP GUIDE] repair stuff" (phh: "workaround for white-ish screen")
- XDA 4041255 "blank screen after the third restart with any GSI ROM"
- XDA 3895860 "[GUIDES][LIST] Boot Pie GSIs and Fix Issues (Brightness...)"
- XDA 4230239 "dynamic system update install failed" (VerificationActivity flow)
- source.android.com/docs/core/tests/vts/gsi (Keymaster<=3 vs A9+)
- deepwiki/phhusson/device_phh_treble (fixSPL, persist.sys.phh.*)
- techveda.live "A Watchdog Is Not Enough" + LKML 2026-08-24 mtk_wdt pretimeout
  (fizyka: hard WDT = reset bez ramoops) — z briefu #1, utrzymane
