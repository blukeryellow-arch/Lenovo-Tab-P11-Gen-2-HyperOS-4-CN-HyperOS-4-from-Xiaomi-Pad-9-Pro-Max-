# FORENSIC BRIEF: RGB flash (50 ms) -> twardy watchdog power-cut — TB350FU slot B
Sprint badawczy 29 IX (10 min, cloud-side; host zajety flashem 32-czastkowego super.img).
Metoda: receipt-only (kazda teza = zrodlo). Rozkaz zawieral 3 wektory; dwa z nich
mialy falszywe przeslanki - ponizej korekta z dowodami.

## WERDYKT WYKONAWCZY (nasze receipty: bugreport_v14, bugreport_v15_rgb, pstore)

Gość v15 (framework A17/HyperOS4 na vendorze Lenovo A14, MTK6789, kernel 5.10.177
slot _b): boot OK (gsid.image_installed=1) -> SF start przez HIDL composera 2.3 MTK
(display ozywa = FIX 12 czesciowo dziala) -> RGB flash ~50 ms przy pierwszej zmianie
trybu/refresh -> sciezka display/fence wodzi jadro/RF na twardo -> **sprzetowy
watchdog MTK resetuje SoC BEZ sciezki dump** (zaden rekord pstore nie powstal; host
wstal z bootreason kernel_panic). Zabojca = mtk_wdt (hardware), NIE polityka kernela,
NIE AVB, NIE SPL.

## WEKTOR 1: "skip copying super image avb footer due to sparse image" — SKUPOWANIE

FAKT: string pochodzi z **fastboot.cpp** (platform/system/core, commit
ee4c926247a416d973723cc9623f101e81e564d1), czyli z **fastbootd w czasie FLASHOWANIA**
- NIE z gsid i NIE z czasu wykonania guesta. Logika: fastboot przenosi stopke AVB na
koniec partycji gdy partycja < obraz; dla obrazow sparse przenoszenie stopki psuje
format sparse -> fastboot jawnie rezygnuje i wypisuje to OSTRZEZENIE. Jest lagodne
(receipty uzytkownikow: Essential PH-1, Rabbit R1, Redmi 8 - urzadzenia bootuja).

Wniosek dla TRWAJACEGO flasha 32-czastkowego super.img: widziany warning = oczekiwany,
nieszkodliwy. Jedyny realny warunek brzegowy: partycja docelowa >= rozmiar obrazu
(wtedy relokacja stopki nigdy nie jest potrzebna). Awaria trybu "stopka nie
przeniesiona" objawialaby sie odrzuceniem AVB przy STARCIE (bootloader), a NIE
smiercia w 15-25 s dzialajacego goscia - nasz gosc bootowal, wiec ta klasa jest
wykliczona receiptowo.

FALSZ: "gsid wymusza live SHA-256 geometrii alokacji blokow tuż po handshake
composera" - taki mechanizm nie istnieje. gsid (ImageService/libfiemap) mapuje obraz
do /data/gsi przy instalacji; weryfikacja integralnosci goscia = dm-verity/hashtree
przy montowaniu + lancuch AVB z vbmeta w bootloaderze - wszystko PRZED starciem
goscia, zero sprzezenia z display.

## WEKTOR 2: MTK HWC 2.3 / SurfaceFlinger / watchdog — POTWIERDZONE (klasa awarii)

- Fizyka watchdoga (receipt: techveda, "A Watchdog Is Not Enough", 2026-09-25):
  **hard reset sprzetowego watchdoga NIE jest panic** - SoC po prostu restartuje,
  jadro nigdy nie dociera do sciezki dump, zaden dmesg-ramoops nie powstaje.
  Dokladnie nasz obraz: pstore nietkniety od 27 IX, ZERO zapisow goscia. Tozsame
  klasy receipt: LibreEcho-Linux issue #5 (MT65xx, wdt_by_pass_pwk, brak dowodow).
- mtk_wdt: na vendorowym kernelu 5.10.177 brak pretimeout (upstreamowy patch
  pretimeout dla mediatek wdt dopiero 2026-08, LKML) => reset bez diagnostyki.
  Typowy prog sprzetowego WDT <= 30 s - spina sie z zyciem goscia 15-25 s
  (boot ~10-15 s do SF + proglubienie zawieszenia display).
- Klasa "nowy framework SF na starym vendorze MTK" jest udokumentowana w spolecznosci:
  Vendor15-GSI (Android 16 GSI na vendor 15) utrzymuje 7 warstw mitigacji, w tym:
  warstwa 3 "HWC composer HAL gaps", warstwa 1 "SurfaceFlinger crash recovery,
  watchdog timeout", warstwa 5 "A18 compositor masking". Phh-Treble: katalog
  workaroundow display sterowanych persist.sys.phh.* (device_phh_treble).
- RGB flash = inicjacja/underrun panelu przy pierwszym mode-switch: A17-SF wysyla
  do HIDL composera 2.3 sekwencje (present fence / zmiana refresh), ktorej legacy
  driver MTK nie gwarantuje; fence nie wraca -> watek w D-state/uninterruptible ->
  petting WDT ustaje albo IRQ storm -> twardy reset bez flushu.

## WEKTOR 3: SPL mismatch / spoof ro.build.version.security_patch — NIEOBOWIAZKOWE U NAS

- Realny mechanizm (oficjalny receipt: source.android.com GSI docs): urzadzenia z
  **Keymaster <= 3** weryfikowaly version/SPL systemu vs bootloader -> GSI z nowszym
  SPL nie bootowal. Od Androida 9 wymog zniesiony; phh-Treble utrzymuje fixSPL()
  (patchuje biblioteki keymastera pod stare stacki) - receipt: deepwiki/device_phh_treble.
- NASZ PRZYPADEK, receiptowo: vendor hosta A14 wystawia **AIDL KeyMint**
  (IKeyMintDevice/IRemotelyProvisionedComponent/ISecureClock/ISharedSecret - dowod:
  macierz hosta z bugreport_v14, 127 HIDL + 32 AIDL). AIDL KeyMint nie robi weryfikacji
  SPL-vs-bootloader. Decydujacy receipt: gosc v15 BOOTOWAL i zyl 15-25 s z display
  - bramka keymasterowa zabija w sekundach 1-3 (przed display), wiec NIE to go zabilo.
- FALSZ: "host kernel zabija wirtualna maszyne" - DSU guest NIE jest VM; wspoldzieli
  kernel hosta. Zabojca = sprzetowy watchdog (wektor 2), nie polityka kernela.
- Konkluzja: spoof SPL u nas = inertny (mozna ustawic dla higieny; nic nie naprawi).

## PATCHES PROGRAMOWE (stabilizacja display-tree; do przyszlych obrazow, bez rotacji)

1. Do INJECT w linii GSI-1 (A17 GSI na tym samym MTK A14 composerze = TEJ SAMEJ
   klasy ryzyka - to jest realny action item z tego sprintu):
   - ro.surface_flinger.use_content_detection_for_refresh_rate=false (staly refresh),
   - wylaczenie HWC overlay / wymuszenie client composition dla legacy MTK (styl
     warstwy 3 Vendor15-GSI; katalog phh persist.sys.phh.*),
   - maskowanie AIDL composera -> wymuszenie sciezki HIDL 2.3 (analog "A18
     compositor masking"),
   - SF crash-recovery/watchdog-budget (styl warstwy 1 Vendor15-GSI).
2. Obserwowalnosc zanim cokolwiek zlego: protokol v15_guest.log (root-adb +
   kumulujacy logcat) - JEDYNA droga receiptu, bo hard-WDT reset z definicji nie
   zostawia dumpu (wektor 2). pstore po tej klasie smierci pozostanie pusty.
3. Flash super.img (trwa u usera): warning sparse/footer = lagodny; utrzymac
   partycje docelowe >= rozmiar obrazu; po flashu ewentualnie avbtool
   calculate_vbmeta_digest dla potwierdzenia lancucha (receipt: dc1-lineage-gsi #10).

## ZRODLA (receipty)
- AOSP fastboot.cpp diff (origin stringu): android.googlesource.com/platform/system/core/+/ee4c9262...
- techveda.live 2026-09-25 "A Watchdog Is Not Enough" (hard WDT = brak ramoops)
- LKML 2026-08-24 [PATCH] watchdog: mediatek: pretimeout (brak pretimeout w vendor 5.10)
- github.com/aslater3/LibreEcho-Linux-6.1#5 (MTK wdt_by_pass_pwk bez dowodow)
- github.com/zerofrip/Vendor15-GSI (7 warstw mitigacji GSI-on-old-vendor)
- deepwiki.com/phhusson/device_phh_treble (fixSPL, katalog persist.sys.phh.*)
- source.android.com/docs/core/tests/vts/gsi (Keymaster <=3 weryfikacja SPL, A9+ zniesiona)
- xdaforums 3919628 (change_security_patch_ver.sh - procedura dla starych urzadzen)
- nasze: ANALIZA-bugreport-v15-rgb.md, host-hal-inventory-v14.tsv, pstore-v15
