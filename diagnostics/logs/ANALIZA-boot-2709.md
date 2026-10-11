# Analiza boot.log (27 IX 14:19-14:23, 26 209 linii) — boot HyperOS w trybie DSU

Źródło: Google Drive `boot.log` (4 091 980 B), pobrany konektorem 27 IX ~13:00 UTC.
To PIERWSZY prawdziwy log z bootu portu (poprzedni — hyperos_boot.txt 26 IX — był bootem hosta).

## Fakty ustalone z logu

1. **To jest boot trybu DSU (Dynamic System Update), nie fastboot:**
   - MTK power HAL: `set +prefix:dsu_mode 1;` (×12 wystąpień),
   - `com.android.dynsystem` (AOSP priv-app) startuje po boot_completed, `isInstalled(): true`,
   - /product i /system_ext pochodzą z HOSTA Lenovo (procesy: com.tblenovo.launcher ×255,
     com.zui.wifip2p, com.lenovo.ue.device, com.huaqin.sarsensor, ZuiHandWritingService),
     /system zaś zawiera komponenty Xiaomi (snet_event_log — brak ich w logu hosta).
   - DSU ma własny, świeży userdata 2 GiB (DEFAULT_USERDATA_SIZE w źródle AOSP)
     => errno 126/EKEYREJECTED z bootów fastbootowych TU NIE WYSTĘPUJE.

2. **System HyperOS startuje w 100% i jest w pełni interaktywny:**
   - dotyk, gesty (NoBackGesture), Taskbar, NotificationShade, Launcher (pid 2030),
     aplikacje (deskclock, mediahome), sieć, bateria 100%, isOverheat=false,
   - brak FATAL, brak system_server-Watchdog, brak ANR, brak panic w kernelu,
   - keystore2 OUT_OF_KEYS_TRANSIENT_ERROR (14:19:56-57) = poziom WARN, niesmiertelne
     (RkpdApp żyje w tym obrazie, nie może wyprovisionować kluczy — szum).

3. **KONIEC SESJI = jawny reboot DSU, nie crash:**
   - 14:23:20.300 `DynamicSystemInstallationService: onStartCommand(): action=ACTION_REBOOT_TO_DYN_SYSTEM`
   - 14:23:20.353 ShutdownThread start (uporządkowane zamykanie: SIGTERM usług, vold unmount)
   - 14:23:24.805 `ShutdownThread: Rebooting, reason: dynsystem`
   - Uptime sesji: ~3 min 50 s. "3 wibracje i fallback" = wzorzec rebootu Lenovo +
     powrót do hosta (DSU bez sticky mode wraca do systemu oryginalnego).

4. **Który obraz działa jako DSU:** v4 (wnioskowanie pośrednie, wysoka pewność):
   - com.android.rkpdapp ŻYJE => to NIE v5/v6 (od v5 wyłączony .arena-disabled),
   - zero znaczników arena_* => v4 (rc bez markerów; markery dopiero od v5/v6),
   - boot przechodzi z Lenovo product/system_ext => obraz z naszymi fixami VINTF
     (goły donor RAW prawdopodobnie by nie wystartował).

## Wnioski operacyjne

- **Port jest stabilny.** Jedyne, co kończy sesję, to mechanizm DSU (brak sticky mode).
- Trwałe rozwiązania:
  a) **fastboot flash** v7 (permanentnie, bez pośrednika DSU), lub
  b) **DSU sticky**: w sesji DSU wykonać `adb shell gsi_tool enable`
     (wtedy każdy reboot wraca do systemu dynamicznego zamiast do hosta).
- v7 w obrazie dodatkowo wyłącza `com.android.dynsystem` (koniec rebootów sesyjnych
  inicjowanych z wnętrza obrazu) i zawiera propsy usera (dosłownie wg zlecenia;
  inertne w AOSP — udokumentowane w build.prop).

## Rejestr kluczowych linii (dowody)

- 5768: `DynamicSystemService: isInstalled(): true`
- 24412: `DynamicSystemInstallationService: onStartCommand(): action=com.android.dynsystem.ACTION_REBOOT_TO_DYN_SYSTEM`
- 24413: `DynamicSystemService: isInstalled(): true`
- 25980: `ShutdownThread: Rebooting, reason: dynsystem`
- 25996: `MobileLogD: userShutDown for: 1dynsystem`
- 14:19:53.922: `am_proc_start: com.android.rkpdapp BootReceiver` (obraz bez fixu v5)
- 14:19:56.843: `keystore2: get_rkpd_attestation_key() Pending: 500ms` (WARN, niesmiertelne)
- Źródło AOSP: packages/DynamicSystemInstallationService (mOneShot=true, DEFAULT_USERDATA_SIZE=2GiB)
