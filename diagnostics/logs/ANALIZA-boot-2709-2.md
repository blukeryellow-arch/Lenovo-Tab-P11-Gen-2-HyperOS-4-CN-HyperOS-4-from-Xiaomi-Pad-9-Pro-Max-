# Analiza boot.log #2 (27 IX 15:30:18–15:31:35, 22 903 linie) — twardy reset w DSU

Źródło: ten sam plik Drive `boot.log` (nadpisany, 3 603 769 B, 13:32 UTC). Poprzednia
zawartość zachowana jako `boot-2709_1419_DSU.log`.

## Fakty

1. **fscrypt NIE jest momentem crashu — to hipoteza obalona własnym logiem usera:**
   - 15:30:32.027–32.043: vold instaluje klucz CE (`Installed fscrypt key with ref
     706fe564… to /data`, `Installed ce key for user 0`) i **weryfikuje polityki**
     (`Verified that /data/system_ce|vendor_ce|media|misc_ce|user/0 has the encryption
     policy … v2 modes 1/4 flags 0xa`) — wszystko **SUKCESEM**,
   - OnBootPhase_1000 zaszło WCZEŚNIEJ (15:30:31.902), system pełni działał:
     launcher, GMS, sieć, bateria 100%, isOverheat=false, OomAdjuster normalnie
     ubijał puste procesy,
   - **crash = 15:31:35, tj. 63 sekundy PO fscrypt** — log urywa się w środku
     rutynowej aktywności (battery uevents, am_pss, BoundBrokerSvc onUnbind).
   => A14 MTK kernel obsługuje fscrypt v2 bez problemu; szyfrowanie DZIAŁA.

2. **Podpis końca = NAGŁE UCIĘCIE (nie framework-reboot):** brak ShutdownThread,
   brak vold shutdown(), brak kaskady SIGTERM — inaczej niż w sesji #1 (14:19, czysty
   reboot dynsystem po 3,5 min). Tym razem twardy reset/watchdog (kernel), ~77 s
   od startu logu. To PIERWSZY potwierdzony twardy reset w logu portu.

3. **Uruchomiony obraz = v4 (znów!):** com.android.rkpdapp żyje (17 wystąpień),
   zero znaczników arena_* (v5+ je ma) => user dalej bootuje stary slot DSU z v4;
   **v7 nie zostało zainstalowane** (sesja #2 miała miejsce przed instalacją v7 albo
   bez niej).

4. Brak śladów: thermal shutdown, I/O errors, ext4/f2fs errors, framework Watchdog
   kill. Przyczyna kernelowa jest NIEWIDOCZNA w logcat (v4 nie jest debuggable, brak
   bufora kernela) — potrzeba pstore.

## Wnioski operacyjne

- Zlecenie usera („strip fileencryption/metadata_encryption/forceencrypt z fstab w
  system.img") jest **zrealizowane od v4** — z zastrzeżeniem udokumentowanym: w drzewie
  /system donora NIE MA fstab (fstab /data pochodzi z vendora hosta i z system.img
  nie da się go zmienić); aktywne dźwignie obrazu to propsy ro.crypto.volume.*
  (footer/none) — a własny log usera dowodzi, że szyfrowanie i tak działa poprawnie.
- Hipoteza „kernel nie wspiera fscrypt" obalona (punkty 1).
- Kolejny krok BEZ ZMIAN: **zainstalować v7** (debuggable + logd persistent +
  znaczniki), odtworzyć crash, pobrać pstore + /data/misc/logd. Bez kernelowego
  dowodu budowanie v8 pod tę hipotezę byłoby spekulacją.

## Rejestr linii (dowody)

- 4779: `vold: fscrypt_unlock_user_key 0 serial=0`
- 4782: `vold: Installed fscrypt key with ref 706fe564bb03c366643251cfe2d4a1f2 to /data`
- 4784: `vold: Installed ce key for user 0`
- 4801-4823: `vold: Verified that /data/… has the encryption policy … v2 modes 1/4 flags 0xa` (5×)
- 3002: `Watchdog: Watchdog timeout updated to 60000 millis`
- ostatnia linia: `15:31:35.022 am_pss [1194,1000,system,…]` — potem cisza (hard reset)
- 15:31:33.360: `Killing 3468:com.android.dynsystem (adj 999): empty #47` — proces
  dynsystem ubity przez OomAdjuster jako pusty (nie on zainicjował końca)
