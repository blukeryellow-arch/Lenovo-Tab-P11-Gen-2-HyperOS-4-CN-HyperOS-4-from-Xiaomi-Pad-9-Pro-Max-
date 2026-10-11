# Analiza hyperos_boot.txt (rzeczywisty log z urzadzenia, 26 IX 15:21, 19 779 linii)

## Werdykt 1: ten log NIE zawiera bootu HyperOS
- ZERO linii HyperOS/MIUI/Xiaomi/yingtian w calym pliku.
- Dzialajacy system = Lenovo stock A14: fingerprint "Lenovo/TB350FU_EEA/TB350FU:14/
  UP1A.231005.007/TB350FU_S231044_260105_ROW", SystemServerTiming "LgsiEarlyInit",
  launcher = com.tblenovo.launcher, uslugi A14 (WallpaperEffectsGeneration, AltitudeService).
- Czyli: przechwycony boot = HOST/fallback (Lenovo), nie port.

## Werdykt 2: NPE baterii (trzy linie, na ktorych opieraly sie zlecenia) jest NIEGROZNE
- Stack: HealthHalCallbackHidl.healthInfoChanged_2_1 -> BatteryService.processValuesLocked
  (BatteryService.java:580) -> com.lenovo.lgsi.server.battery.IBatteryServiceManager
  .updateHealthInfo na nullu. To KOD STOCKOWY LENOVO A14 (nie nasz obraz).
- Wyjatek zlapany przez JavaBinder (konczy transakcje bindera, nie proces): w TYM SAMYM
  logu system_server zyje dalej - "BatteryService took 278 ms in onStart", boot doszedl
  do OnBootPhase_1000 (15:21:45.9) i startowal launcher (15:21:44.4).
- Wniosek: zglaszany "crash system_server" z tych 3 linii NIE wystapil - to kosmetyka
  stockowego bootu. v3/v4/v5 zostaly zbudowane pod objaw, ktory nie jest przyczyna.

## Werdykt 3: realny problem widoczny w logu - stan /data (klucz odrzucony)
- com.tblenovo.launcher: "Failed to ensure /data/user/0/...: mkdir failed: errno 126
  (Required key not available)" - EKEYREJECTED = klucz CE odrzucony; userdata po
  eksperymentach (vbmeta/system/DSU) jest w stanie niespojnym kryptograficznie
  rowniez dla systemu hosta. To moze byc realny mechanizm "fallback loop".
- 2887 avc denied (permissive=0), z tego 2327x system_server->system_server:capability
  (sel-fdenial w bootcie hosta; dla hosta niesmiertelne, ale potwierdza niespojnosc
  srodowiska po eksperymentach).

## Co jest potrzebne do naprawy portu (kolejnosc)
1. Log z bootu GSI/HyperOS (nie hosta): najlepiej po watchdog-resie z pstore:
   adb shell cat /sys/fs/pstore/console-ramoops* > pstore.txt  (przezywa reset!)
   albo adb bugreport (zawiera poprzedni logcat z pmsg), albo logcat na zywo w trakcie
   bootu GSI zanim padnie: adb wait-for-device && adb logcat -b all > gsi.txt
2. Decyzja o /data: errno 126 = klucze niespojne; przykladany format userdata
   (backup wczesniej!) - bez tego zaden system nie podnies CE spojnie.
3. Dopiero z logiem GSI: realne przyczyny watchdog-resetu (3 wibracje) do naprawy w v6.
