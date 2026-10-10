# Analiza bugreport.zip (27 IX 17:38, host TB350FU A14 po fallbacku) — PRZYCZYNA TWARDEGO RESETU

Źródło: Google Drive `bugreport.zip` (4,5 MB, 15:38 UTC), bugreport
`bugreport-TB350FU_EEA-UP1A.231005.007-2026-09-27-17-38-12.txt` (383 471 linii).
Kopia pstore: `bugreport-2709_pstore-lastkmsg.txt` (3 097 linii konsoli kernela).

## PRZEBŁYSK: sekcja LAST KMSG (/sys/fs/pstore/console-ramoops-0, linia 82 116)

Konsola kernela z crashed boota (uptime ~16 516–16 530 s przy zapisie; pstore ring).
Sekwencja śmierci, z timestampami kernela:

1. 16516.3: **suspend** systemu (wlan SDIO suspend, BT driver-own, mtk_battery_suspend).
2. 16530.15–.17: `halSetFWOwn:(INIT WARN) [SER][L0.5] skip set fw own` ×15
   — firmware WiFi MT7902 nie oddaje "FW OWN" podczas suspend.
3. 16530.171878: `[btmtk_err] btmtk_sdio_subsys_reset poll fail` →
   **"subsys reset failed, do whole chip reset!"** (BT też martwe) + 1. call trace
   (`send_reset_event`).
4. 16530.172: RFSM whole-chip reset WiFi+BT (`PROBED → PRE_RESET`, `wlanRemove`).
5. 16530.779258: **`Unable to handle kernel paging request at virtual address
   ffffffffbfffffc0`** → `Internal error: Oops: 96000145 [#1] PREEMPT SMP`.
6. Call trace (kluczowe ramki): `mtk_sdio_pm_suspend [wlan_mt7902_sdio_mt6789] →
   halSetFWOwn → kalDevReadIntStatus → sdio_readsb → mmc_io_rw_extended →
   msdc_post_req [mtk_sd] → dma_unmap_sg_attrs → __inval_dcache_area →
   do_translation_fault → die → ipanic_die [mrdump]` → **twardy reset**.

## Rozwiązanie zagadki "63 sekund"

Screen timeout w sesji DSU = ~60 s. Bez interakcji (log #2: zero touch po 15:31:0x,
ostatnia linia 15:31:35 = ~77 s od startu logu) tablet gaśnie → suspend → OOPS WiFi →
hard reset + slot-switch. **"3 wibracje / biały błysk / fallback" = suspend + OOPS +
reset + bootloader przełącza slot.** To nie był watchdog frameworku, nie keystore,
nie fscrypt, nie audio.

## Slot-switch (potwierdzenie obserwacji usera)

Kernel crashed boota: **5.10.177-android12-9-00002-g593c61caffd9-ab10731447**
(banner w Oopsie). Kernel hosta w bugreporcie: **5.10.233-android12-9-00062-
g49c66df526b8-ab13101360**. Różne sloty — bootloader przełączył po crashu.

## Odrzucone Claimsy z zlecenia (receipty z tego samego bugreportu)

- **Beanpod keymint "binder mismatch"**: 104 wystąpienia `beanpodkeymaster` — WSZYSTKIE
  to zdrowe operacje (Enter/Exit BeginOperation, cmd:4 response) z hosta 17:37,
  po fallbacku. Zero błędów keymint/keymaster w logach (sekcja SYSTEM LOG przeczyszczona
  pod E/F + fatal). Nie istnieje żaden dowód zaangażowania beanpod w crash.
- **Dolby DMS crash**: 307 wystąpień — żywe wątki `vendor.dolby.media.c2@1.0-service`
  w liście procesów hosta. Audioserver działał do końca w obu logach portu (26-27 IX).
- **"hard-coded binder mismatch at 63 s"**: w pstore ZERO ramek binder/keymint/audio —
  wyłącznie sterowniki WiFi/BT w suspend.

## V9 — realny fix od strony obrazu (repack)

Kernela/sterownika nie da się patchować z system.img, ale **trigger crashu — suspend —
da się zablokować z obrazu**:
- `arena_nosuspend.rc`: named wakelock `arena_nosuspend` (write /sys/power/wake_lock)
  na early-init/boot/boot_completed — kernel nigdy nie wejdzie w ścieżkę suspend WiFi,
- `settings put global stay_on_while_plugged_in 7` w skrypcie neutralizującym
  (ekran żywy przy zasilaniu),
- koszt uczciwie udokumentowany: brak suspend = większe zużycie baterii.

Opcje pozornej naprawy (do decyzji usera): DSU na slocie z kernel 5.10.233
(`fastboot getvar current-slot`), bo OOPS zaobserwowano na 5.10.177; lub wyłączenie
WiFi na czas sesji testowych.

## Rejestr linii (dowody)

- bugreport.txt:82116 — `------ LAST KMSG (/sys/fs/pstore/console-ramoops-0) ------`
- pstore: `halSetFWOwn:(INIT WARN) [SER][L0.5] skip set fw own` ×15 (16530.15-.17)
- pstore: `btmtk_sdio_subsys_reset ... fail` + `subsys reset failed, do whole chip reset!`
- pstore: `Unable to handle kernel paging request at virtual address ffffffffbfffffc0`
- pstore: `Internal error: Oops: 96000145`, `Tainted: P W O 5.10.177-android12-...`
- pstore: `ipanic_die+0x24/0x38 [mrdump]` (ostatnia klatka)
- bugreport.txt:177332-177338 — dropbox: SYSTEM_LAST_KMSG 16:23:31 / 17:35:19 / 17:36:58
- bugreport.txt:12445 — `BootReceiver: Copying /sys/fs/pstore/console-ramoops-0 to DropBox`
