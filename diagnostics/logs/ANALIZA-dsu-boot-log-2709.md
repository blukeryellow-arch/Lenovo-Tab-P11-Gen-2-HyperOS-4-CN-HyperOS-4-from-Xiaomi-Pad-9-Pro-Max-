# ANALIZA: dsu_boot_log.txt (Drive, 2,7 MB, okno 18:28:32-18:30:25 lokalne 27 IX)

## WERDYKT 1: to jest log HOSTA Lenovo ZUI (stock), nie gościa HyperOS
Receipts (policzalne):
- zui: 231 trafien, lenovo: 466, com.google: 2094 (pelne GMS) | miui: 0, xiaomi: 0
- com.zui.performance/power/game, ZuiMiraVisionService, vendor.lenovocamera AVC
- markery arena_* (diag/permissive/v7/v9): 0 trafien
- dynsystem dziala NOTIFY_IF_IN_USE po BOOT_COMPLETED = DSU zainstalowany, NIE uruchomiony
  (ro.gsid.image_running=0 w bugreporcie o 19:24)
Kontekst czasowy: panica kernela 18:28:25 (boot.reason.history), SYSTEM_BOOT hosta 18:28:37
(dropbox) => log zlapany ~7 s po reboocie hosta, ktory wystartowal PO smierci sesji DSU.
Wyjasnienie: `adb wait-for-device` po crashu lapnie HOSTA (DSU one-shot wraca do hosta) -
dokladnie to sie stalo. Log goscia z bialej ekranu NIGDY nie zostal zlapany.

## WERDYKT 2: host (stock, slot _a) bootuje ZDROWO w tym oknie
- boot_completed osiagniety (SystemServerTiming, onStartUser-0, WifiService boot phases)
- SystemUI zywe (70 trafien), SurfaceFlinger zywy (68), zero FATAL EXCEPTION w oknie
=> potwierdza obserwacje usera: stock na slocie _a dziala; pada na _b.

## WERDYKT 3: keystore2 z tego logu (cytaty usera z zlecenia v10) = HOST-side szum
- "Failed to handle super encryption" / "User ECDH key missing" / "Waiting for RKPD key
  timedout" / OUT_OF_KEYS_TRANSIENT pojawiaja sie na HOSTIE (pid 572, boot 18:28:45-57) -
  to WARN-i, host i tak doszedl do boot_completed. Mechanizm: wlan po panice bez sieci ->
  rkpd nie ma internetu -> timeout. Te same stringi w gosciu (v9, apex rkpd usuniety) byly
  FATALNE - stad fix v10 (przywrocony apex). Log nie podwaza v10/v11/v12; po prostu
  pochodzi z innego systemu, niz sadzil user.

## WERDYKT 4: teoria slotu usera - ZGODNA Z DANYMI (i doprecyzowana)
- pstore x2 (17:36 i 19:24 bugreporty): paniki wlan-suspend biegly na kernelu
  5.10.177 = slot _b; urzadzenie po panice ucieka na _a (5.10.233) i tam bootuje zdrowo
  (ten log + bugreport_v10).
- obserwacja usera: stock na _b zamiera z utrata obrazu; ratuje go fastboot --set-active=a.
- => slot _b ma zepsuty lancuch boot (kernel/vendor) na TEJ jednostce - ponizej warstwy
  system.img. Zarowno stock jak i goscia DSU pada na _b; na _a oba zyja.
- Mechanizm rotacji: watchdog/bootloader A/B fallback po panice -> wraca na _b -> Zamrozenie.
  v11/v12 wifi-guard (WiFi off + sdio runtime-PM on) usuwa ZRODLO paniki -> brak rotacji.

## Czemu zadanany patch (servicemanager/init/binder "hard-code SLOT A") nie istnieje
- slot wybiera BOOTLOADER zanim gosc wstanie; ro.boot.slot_suffix przychodzi z cmdline
  (build.prop nie nadpisze - udokumentowane w v12 FIX 9b),
- binder/servicemanager NIE MA routingu po slocie (receipts: 12 linii servicemanager
  w pstore to warningi mtkradioex-o modem; transakcje sa po nazwach interfejsow),
- donor A17 nie ma /system/bin/bootctl (sprawdzone w kicie) - gosc nie ma czym ustawic
  slotu; raw-write do misc/BCB z shella = ryzyko zablokowania bootu na juz androme
  lancuchu - ODMOWA.
- REALNE pinowanie slotu A: fastboot --set-active=a (metoda usera) albo
  `adb shell bootctl set-active-boot-slot 0` na booted hoscie (sprawdzic: which bootctl).

## Plan testu (bez nowego buildu - v12 zawiera juz wifi-guard + markery slotu)
1) fastboot --set-active=a  (albo na hoscie: adb shell bootctl set-active-boot-slot 0)
2) instalacja v12 przez DSU na slocie _a; NIE wlaczac gsi_tool enable dopoki stabilnosc
   nie jest potwierdzona (one-shot po crashu wroci do hosta = bezpieczniej),
3) przy bialym ekranie NAJPIERW sprawdzic kogo lapie adb:
   adb wait-for-device shell getprop ro.product.brand   # Xiaomi = gosc, Lenovo = host
   dopiero potem: adb logcat -d -b all > ws.log -> NA GOOGLE DRIVE.
