# ANALIZA: bugreport_v10.zip (Drive, pobrany 27 IX 19:25 UTC) - co naprawde zabija tablet

Zrodlo: Google Drive bugreport_v10.zip (sha256 dbfce3f97c7208696d01af88593e124291d06e508f96e63d99207ff6316e04f7),
bugreport-TB350FU_EEA-...-2026-09-27-19-24-43.txt (412 563 linii, host ROW A14, uptime ~0, load 9.29).

## 1. TL;DL (werdykt)
**Kernel panic w sciezce SUSPEND WiFi na slocie _b (kernel 5.10.177) - TA SAMA sygnatura co crash v4.
ZERO dowodow na keystore2/beanpod/servicemanager/VINTF/Dolby.** v10 nie bylo testowane (timeline niemozliwy).
Urzadzenie przez cale popoludnie petlowalo panica co ~52-72 min; obecnym bootem ucieklo na slot _a (5.10.233).

## 2. Receipty
- pstore (LAST KMSG, kopia: bugreport-v10_pstore-lastkmsg.txt, 3099 linii):
  - kernel: 5.10.177-android12-9-00002-g593c61caffd9-ab10731447 (SLOT _b; host teraźniejszy: 5.10.233, slot_suffix=_a)
  - sciezka smierci: mtk_sdio_pm_suspend -> halSetFWOwn (skip set fw own) -> SDIO kalDevPortRead ->
    dma_direct_map_sg -> do_translation_fault -> **Internal error: Oops: 96000145** -> ipanic_die [mrdump]
  - uptime w momencie paniki: 16530 s = 4 h 35 min (dluga sesja, NIE swiezy boot)
  - 275 linii suspend/resume w ostatnich 14 s okna = petla suspend urzadzenia wlan (runtime/driver-level),
    nie systemowy suspend => wakelock z v9 (wake_lock arena_nosuspend) NIE zatrzymuje tej sciezki
  - keystore2/keymint/beanpod/dolby w pstore: **0 ramek**
  - servicemanager: 12 linii - tylko lagodne ostrzezenia VINTF o mtkradioex (modem w tablecie nie istnieje;
    te same warningi sa na kazdym zdrowym boocie, takze v4)
- dropbox (SYSTEM_BOOT + SYSTEM_LAST_KMSG + SYSTEM_AUDIT): booty o 16:23:31, 17:35:19, 17:36:58, 18:28:37, 19:24:37 (lokalne)
- persist.sys.boot.reason.history: kernel_panic @ 17:36:46, 18:28:25, 19:24:25 (lokalne; pokrywa sie z 3 ostatnimi
  SYSTEM_BOOT) => co najmniej 3 konsekwatywne kernel_panic wieczorem; sesje 52-72 min (idle -> suspend -> oops),
  jedna sesja 99 s (17:35:19 -> 17:36:58)
- ro.boot.bootreason = "kernel_panic" (obecny boot); gsid.image_installed=1, ro.gsid.image_running=0
  (DSU zainstalowany nadal - obraz z ery v4/v9; instalacja v11 przez Sideloader go zastapi)

## 3. Timeline v10 - dlaczego NIE BYLO testowane
- run v10 (36335019110) zakonczyl sie 17:10 UTC = 19:10 lokalnego; linki 19:11 lokalnego.
- Sesje konczace sie panica: start 18:28:37 lokalnego (przed 19:11), bugreport wziety 19:24:43 lokalnego
  (13 min po linkach). Rekord pstore ma uptime 16530 s = sesja startowana ~14:49 lokalnego.
  => zaden crash w tym bugreporcie nie mog byc spowodowany v10. Claim "V10 proved..." jest niepoprawny faktualnie.

## 4. Claims zlecenia v11 - werdykty
1. "servicemanager/hwservicemanager down-negotiation patch" - ODMOWA: binarki C++ bez zrodel;
   receipts: 12 lagodnych linii VINTF-warning, zero fatalnych ramek. VINTF softening ISTNIEJE juz w obrazie
   od wczesnych wersji (compatibility_matrix.5.xml generowany do obrazu + optional-missing; make_release.sh).
2. "keystore2 Rust patch (security_level.rs:318 / super_key.rs:653)" - ODMOWA: binarna kompilacja Rust;
   receipts: ZERO ramek keystore2 w pstore. Realna odpowiedz na keystore2 to przywrocony rkpd apex (v10, FIX 7)
   - nadal nietestowany.
3. "arena_nowifi.rc wakelock utrzymac" - UTRZYMANY (v9), ale dane pokazuja, ze wakelock systemowy nie blokuje
   suspend urzadzenia SDIO => v11 doklada: SDIO runtime-PM power/control=on + WiFi domyslnie OFF.
4. "wipe Family Link / parental" - NO-OP: donor CN HyperOS nie ma zadnych pakietow Google/Family Link/parental
   (receipts: listing tar kitu; jedyne trafienie "guard" to libscopeguard.dylib.so - niespokrewnione).
5. "suppress Second Space / 700MB RAM" - ODMOWA: logika system_server bez zrodel; brak dowodow, ze profile
   userow cokolwiek powoduja.

## 5. v11 (FIX 8) - co realnie wchodzi
- arena_v11_wifi.sh (boot_completed): (a) /sys/bus/sdio/devices/*/power/control = on (blokuje runtime-PM
  urzadzenia wlan MT7902 - sciezka paniki), (b) wakeup=enabled na SDIO, (c) svc wifi disable DOMYSLNIE
  (sciezka paniki nie ruszy bez aktywnego wlan; user wlacza recznie: svc wifi enable).
- utrzymane: wakelock v9, rkpd apex v10, propsy v10, dynsystem-off, FBE-off, permissive, logd, arena_diag.
- NAJWAZNIEJSZE (poza obrazem): instalowac DSU bedac na slocie _a (kernel 5.10.233 - bez buga wlan).
  Urzadzenie jest na _a TERAZ (po panice 19:24). Sprawdzenie: adb shell getprop ro.boot.slot_suffix.
