# Audyt donora `yingtian` OS4.0.11.0.XBMCNXM

Ten dokument zapisuje wynik sprawdzenia **oryginalnego**, chińskiego fastboot
ROM-u Xiaomi Pad 9 Pro Max (`yingtian`) wskazanego dla tego portu. Nie zmienia
wersji donora i nie dotyczy wydania `.13`.

## Zweryfikowane źródło

- pakiet: `yingtian-images-OS4.0.11.0.XBMCNXM-user-20260916.0000.00-17.0-cn-60633b4ba6.tgz`
- URL Xiaomi: `https://bkt-sgp-miui-ota-update-alisgp.oss-ap-southeast-1.aliyuncs.com/OS4.0.11.0.XBMCNXM/yingtian-images-OS4.0.11.0.XBMCNXM-user-20260916.0000.00-17.0-cn-60633b4ba6.tgz`
- pobrany rozmiar: `12,645,527,753` B
- SHA-256 pakietu: `03f187f7f025513efb0791322840b6537e75d6630b07687a853e50eca4f07a6f`

Fastboot archive zawiera `super.img`, a nie osobne `system.img` i
`system_ext.img`. Audit wyodrębnił z niego logiczne partycje `system` i
`system_ext` bez pełnego rozwijania sparse `super.img`; dzięki temu sprawdzenie
nie opiera się na nazwie wydania, fingerprintach ani na zgadywaniu struktury
obrazu.

Pełny, reprodukowalny zapis inwentarza jest w
[`reports/donor-011-36257855835.md`](reports/donor-011-36257855835.md). Job
GitHub Actions zakończył się powodzeniem.

## Wynik dotyczący baterii

W oficjalnym donorze znaleziono normalny
`/system/framework/services.jar` (39,875,204 B) oraz framework HyperOS/MIUI w
`system_ext`. Skan DEX-ów frameworku dla:

- `IBatteryServiceManager`,
- `mBatteryServiceManager`,
- `com.lenovo.lgsi`

nie zwrócił żadnego wyniku ani w `system`, ani w `system_ext`.

To rozstrzyga istotną kwestię portu: **oryginalny donor Xiaomi nie zawiera
Lenovo `IBatteryServiceManager` ani wywołania, które powoduje zgłoszony NPE**.
Nie ma więc z niego brakującej implementacji Lenovo, którą można bezpiecznie
skopiować do finalnego obrazu jako „naprawę procentu baterii”. Donorowa obsługa
BatteryService jest zwykłą obsługą Xiaomi/Androida; nie implementuje HAL-a
`vendor.lenovo.hardware.battery`.

## Konsekwencja dla naprawy TB350FU

Log z urządzenia pokazuje, że uruchomiony `BatteryService` faktycznie próbuje
wywołać Lenovo `IBatteryServiceManager.updateHealthInfo(...)`, a następnie
uzyskuje `SecurityException: SELinux denied` podczas próby dostępu do battery
HAL. Ten kod pochodzi z Lenovo runtime/classpath (lub jego skompilowanego
artefaktu), nie z oficjalnego donora `yingtian`.

Dlatego właściwy następny patch to:

1. namierzyć **rzeczywisty Lenovo** `services.jar` / ODEX-VDEX / warstwę
   `system_ext`, która jest ładowana na urządzeniu;
2. dodać null guard dokładnie wokół tego jednego wywołania;
3. naprawić minimalną politykę SELinux dla battery HAL po teście diagnostycznym;
4. nie podmieniać w ciemno frameworku Xiaomi innym donorowym plikiem i nie
   zmieniać wersji `OS4.0.11.0.XBMCNXM`.

`tools/apply_compat_patches.py` pozostaje celowo restrykcyjny: zadziała tylko
na źródle zawierającym faktyczny hook Lenovo, a nie na standardowym
BatteryService z donora.
