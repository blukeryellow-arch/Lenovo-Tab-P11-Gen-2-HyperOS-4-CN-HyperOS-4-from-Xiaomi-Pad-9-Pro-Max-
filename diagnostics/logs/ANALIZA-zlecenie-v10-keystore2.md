# ANALIZA: zlecenie v10 (bootloop DSU v9 + keystore2/RKPD/beanpod)

## Stan dowodow (uczciwie)
- Zalacznik `dsu_boot_log.txt` NIE DOTARL (katalog uploads/ nie istnieje; 5. raz z rzedu).
- Google Drive: brak nowych plikow (najnowsze: bugreport.zip 15:38 UTC = stary, juz analizowany;
  boot.log 13:32 = stary z v4). Zatem: ZERO danych z sesji v9 poza opisem w zleceniu.
- BUT: zacytowane w zleceniu stringi zweryfikowano w BINARCE keystore2 donora - patrz nizej.

## Receipts z binarki donora (strings /system/bin/keystore2, 2541456 B, kit 537eb4ea)
Pelny zapis: diagnostics/logs/keystore2-strings-v10-receipts.txt
- super_key.rs:653 "User ECDH super key missing."  (user zacytowal "User ECDH key missing")
- security_level.rs:318 "Failed to handle super encryption."
- rkpd_client/src/lib.rs:227 "Waiting for RKPD key timed out:"
- r#OUT_OF_KEYS_TRANSIENT_ERROR, r#SYSTEM_ERROR (format Debug sie zgadza)
=> Po raz pierwszy zacytowana diagnoza ma pokrycie w realnych stringach A17.

## Przyczyna (dominanta dowodowa)
1. FIX 0 (wprowadzony w v7, utrzymany v8/v9) USUWAL com.android.rkpd.apex z obrazu
   (rename -> .arena-disabled; dowod: reports/v9-build-trace.log linie 445-457).
2. OUT_OF_KEYS_TRANSIENT_ERROR = brak kluczy z RkpdApp (znany mechanizm AOSP, odnotowany
   w sesji). "User ECDH super key missing" + "Failed to handle super encryption" = ta sama
   sciezka: keystore2 A17 nie dostaje kluczy RKP.
3. v4 (apex RKPD OBECNY) bootowal w 100% (ANALIZA-boot-2709.md). v9 = pierwszy test linii
   v7+ => jedyna zmiana typu "usunieto komponent" w delcie v4->v9, ktora produkuj wlasnie
   te bledy, to FIX 0.
4. keystore2.rc donora: `critical window=0` = "Reboot to bootloader if Keystore crashes more
   than 4 times before sys.boot_completed" (kopia: keystore2-rc-donor.txt). Crash-loop
   keystore2 przy boocie = init REBOOTUJE urzadzenie = bootloop. Konsystentne ze zgloszeniem.
   (Uczciwie: "hard kernel panic + slot-switch" z opisu jest niemozliwe z userspace - ale
   bootloop z critical service daje ten sam objaw dla uzytkownika.)

## Claims zlecenia v10 - werdykt
1. "Wi-Fi suspend/Dolby nie jest przyczyna" - CZESCIOWO SLUSZNE dla v9: pstore (v4) dowiodl
   OOPS wifi w suspend, ale to byl INNY crash (v4, 63 s). Bootloop v9 (jesli realny) ma
   inny mechanizm. Anti-suspend z v9 pozostaje (dowod pstore nadal wazny).
2. "beanpodkeymaster nie komunikuje sie z goscie A17" - ODRUCONE (juz raz): beanpod to HAL
   hosta i dziala (104 zdrowe operacje w bugreporcie). Problem nie dotyczy samego HAL-a,
   tylko BRAKU aplikacji RKPD po stronie goscia (my ja usunelismy w v7).
3. Propsy `ro.remote_provisioning.enable` / `ro.remote_provisioning.strongbox.enable` -
   INERTNE: zadna binarka donora (keystore2, rkpd.apex, framework.jar, services.jar) nie
   czyta tych kluczy. Czytana rodzina: remote_provisioning.tee.rkp_only,
   .strongbox.rkp_only, .hostname(.cn), .use_cert_processor, .connect_timeout_millis,
   .skip_network_consent_check (+ ro.keystore.boot_level_key.strategy).
   Wstawione DOSLOWNIE wg zlecenia (jak propsy v7) z adnotacja inertnosci.
4. "Patch binder keystore2 (SYSTEM_ERROR/OUT_OF_KEYS jako mock-null)" - ODMOWIONE:
   keystore2 to binarna kompilacja Rust (2.5 MB), brak zrodel, brak konfigu semantyki
   bledow. Nie da sie tego zrobic w repacku system.img. Naprawe daje przywrocony apex.

## v10 (wykonane)
- FIX 7: PRZYWROCENIE com.android.rkpd.apex (revert FIX 0) + bramka obecnosci w obrazie.
  Zasada usera "nie tnij" donora przywrocona. "Product build.prop matrix" nie istnieje
  w sciezce DSU (product = host A14; nasz product.img nie jest shipowany, sha przypiete)
  => propsy ida do /system/build.prop (jak w v7).
- FIX 7b: propsy zlecenia doslownie -> /system/build.prop.
- Dry-run lokalny na pelnym drzewie kitu: WSZYSTKIE kroki FIX zielone; rkpd apex obecny
  (1544192 B, 0 przemianowanych), propsy v10 w build.prop, 3x wake_lock, linia v7/v9 OK.

## JESLI v10 nadal bedzie bootloopowal
=> potrzebny LOG (logcat z petli: `adb wait-for-device logcat -d -b all > dsu_boot_log.txt`)
   wyslany NA GOOGLE DRIVE (kanal czatu nie dowozi zalacznikow - 5. proba).
