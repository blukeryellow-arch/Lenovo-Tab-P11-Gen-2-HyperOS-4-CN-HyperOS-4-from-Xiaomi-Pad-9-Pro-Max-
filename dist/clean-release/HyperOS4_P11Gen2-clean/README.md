# HyperOS 4 na Lenovo Tab P11 Gen 2 — wariant CLEAN

Czwarty wariant obok **lekkiego**, **-full** i **coherent**. To coherent z dokladnie
jedna zmiana: **donorski `system_ext` po usunieciu diagnostyki i telemetrii Xiaomi**
i przebudowie EROFS. System, product i vbmeta to te same, zweryfikowane bajty co
w lekkim wydaniu (sha256 nizej — identyczne).

## Co usunieto (i dlaczego akurat to)

Donorski system_ext (Xiaomi Pad 9 Pro Max, HyperOS 4 CN) mial 1910 wpisow; clean ma
1867 (usuniete 7 pakietow, reszta nietknieta):

| pakiet | czym byl | dlaczego out |
|---|---|---|
| `app/EngineerMode` (16 MB) | tryb inzynierski MTK (*#*#3646633#*#*) | nigdy niepotrzebny userowi, otwiera radio/testy |
| `app/DebugLoggerUI` | zbieranie logow systemowych | diagnostyka |
| `app/MiSightService` (9,4 MB) | telemetria/raportowanie Xiaomi | telefonuje do chmury CN |
| `app/VsimCore` | wirtualna karta SIM Xiaomi | tablet bez eSIM |
| `app/CameraMind` (4,5 MB) | AI-asystent aparatu Xiaomi | aparat i tak jest od Lenovo |
| `app/PowerInsight` | statystyki zuzycia energii Xiaomi | diagnostyka |
| `priv-app/RtMiCloudSDK` | SDK chmury MiCloud | usluga CN, nieuzywana |

**Co ZOSTALO i musi zostac** (to nie jest bloat, to fundament HyperOS 4 — dawniej
mial 'miui' w nazwach, stad np. `miuix`, `miuisystem`, `MiuiSystemUI`, `Settings`):
framework UI (`miuix`), warstwa systemu (`miuisystem`), pasek statusu i powiadomienia
(`MiuiSystemUI`), Ustawienia, dialer/telefonia, Provision, GoogleServicesFramework.
Ich usuniecie to nie debloat, tylko rozbior — bez nich nie wstaje Zygote ani pulpit.

MSA, GetApps, reklamy i sklep Xiaomi **nie wystepuja** w tym wydaniu w ogole: one
zycza w donorskim `product`, ktorego tu nie ma (nasz product = 63 fonty MiSans +
etc/{passwd,group}).

## Czego uczciwie oczekiwac

Te same bramki co w coherent (docs/09 §5): init ~85%, system_server ~50-60%,
pulpit ~10-25% (SurfaceFlinger A17 vs composer HIDL 2.1 na vendorze A12).
Czyszczenie nie zmienia tych liczb — usuwa pakiety, ktore dzialaja PO starcie
systemu (albo wcale, bo sa nieaktywne bez reszty ekosystemu Xiaomi).

## Zawartosc

<!-- ROZMIARY-KONTRAKT
system_hyperos4_p11g2.img=920039424
system_ext_hyperos4_p11g2.img=602189824
product_hyperos4_p11g2.img=75198464
vbmeta_hyperos4_p11g2.img=4096
flash-all.sh=8177
rollback.sh=1345
device-probe.sh=6897
-->

| plik | bajty | co to |
|---|---|---|
| `system_hyperos4_p11g2.img` | 920 039 424 | HyperOS 4 A17, macierz poziomu 5 wygenerowana (wariant miekki); sha256 `4836dcd4…` — identyczny z lekkim |
| `system_ext_hyperos4_p11g2.img` | 602 189 824 | **CLEAN**: donorski system_ext minus 7 pakietow, przebudowany deterministycznie (`-T 0`, uid/gid 0:0, lz4hc,9); sha256 `53dd7dfb…`; slot 744 968 192 B — miesci sie z zapasem 142 MB |
| `product_hyperos4_p11g2.img` | 75 198 464 | lekki product: etc/{passwd,group} + 63 fonty MiSans; sha256 `a961bec4…` |
| `vbmeta_hyperos4_p11g2.img` | 4 096 | Flags 3 (weryfikacja i verity wylaczone), testkey AOSP; sha256 `9cf2e7e4…` — identyczny we wszystkich wariantach |
| `flash-all.sh` | 8 177 | bramki: sumy -> identyfikacja -> kopia vbmeta -> rozmiar (zapytany) -> resize tylko po zgodzie -> flash |
| `rollback.sh` | 1 345 | przywraca vbmeta z kopii; ostrzega o braku rollbacku system_ext bez slotow |
| `device-probe.sh` | 6 897 | krok 0 przed flashem (GO/NO-GO): fastbootd, rozmiary slotow, CONFIG_EROFS_FS_LZ4 |

Weryfikacja budowy: `tools/verify_image.sh` — obraz oddaje drzewo **1:1**
(1866 wpisow: 1683 pliki + 21 symlinki + 162 katalogi, 0 rozbieznosci);
md5 donora przed czyszczeniem = `f879747f…` (suma serwera Google — to TE bajty).

## Jak wgrac

```bash
./device-probe.sh     # 1. GO/NO-GO
./flash-all.sh        # 2. sloty system_ext_a/b -> zwykly flash obu
```

Gdy `system_ext` nie ma slotow a/b — flash jednokierunkowy (brak rollbacku tej
partycji): `I_ACCEPT_SYSTEM_EXT_ONEWAY=yes ./flash-all.sh`.
Gdy `system` nie miesci sie w slocie: `RESIZE_SUPER=1 I_ACCEPT_DATA_LOSS=yes ./flash-all.sh`
(kasuje product, poszerza system). Po flashu, gdy pulpit nie wstanie w 5-10 min:

```bash
adb wait-for-device && adb logcat -b all -d > log.txt
bash tools/postflash_triage.sh log.txt    # nazwie stoper i nastepny krok
```

## Wlasny system.img / vbmeta (plan "dokladam system + vbmeta")

Zestaw jest kompletny — system.img i vbmeta juz tu sa (zweryfikowane sumami).
Jesli jednak chcesz podmienic ktorys obraz na wlasny: podmien plik, odswiez sumy
(`sha256sum <plik>` i wpisz do `SHA256SUMS.txt`) — bramka 0 flash-all zaufa wtedy
Twoim bajtom. vbmeta z tego zestawu (Flags 3) wylacza weryfikacje AVB, wiec
wspolpracuje z dowolna kombinacja obrazow; rollback AVB = `./rollback.sh`.

Dwa duze obrazy (>100 MB) nie zyja w gicie — odbudowa: `tools/build_clean_kit.sh`
(idempotentny: toolchain -> spool -> czyszczenie -> mkfs -> weryfikacja -> ten katalog).
