# Sciezka A: HyperOS jako nakladka, nie jako ROM

Cel: na stockowym firmware Lenovo Tab P11 Gen 2 miec warstwe stylu HyperOS
(fonty, tapety, dzwieki, launcher, animacje, gotowe overlaye Xiaomi), bez
przebudowywania zadnego obrazu partycji.

## Dlaczego akurat tak

Port w pelni (framework A17 na G99) rozbija sie o cztery rzeczy, ktorych zaden
skrypt nie obejdzie: HAL-e skompilowane pod Xring O3, roznice wersji interfejsow
(VINTF), brak GKI dla tego BSP i brak zrodel Xiaomi dla tego SoC. One leza
**ponizej** warstwy, ktora daje wyglad. Wyglad lezy **powyzej** - w zasobach
i w overlayach, ktore Android projektowo umie nadkladac bez ruszenia
przeslanianego pakietu. Stad taki, a nie inny ksztalt tego repo.

Warstwa, ktora przenosimy: `res/`, fonty, tapety, `*.apk` overlayy.
Warstwa, ktorej nie przenosimy: `.so`, `.jar` frameworka, `*.img`, sepolicy, fstab.

## Etap 0 - punkt wyjscia musi byc znany

```bash
diagnostics/collect_device_state.sh
```

Z tego wyniklu potrzebuje konkretnie: `ro.board.platform` (potwierdzenie mt6789),
`ro.build.version.release` + `ro.build.id`, `ro.boot.dynamic_partitions`,
`ro.virtual_ab.enabled`, `ro.boot.slot_suffix`, liste z `/dev/block/by-name`
i rozmiary, `lpdump` jesli jest, `ro.boot.verifiedbootstate`.

Bez tego etapu nie wiemy, czy overlay w ogole ma gdzie lezec (`/product/overlay`
istnieje tylko przy pewnych konfiguracjach partycji) i czy przypadek A/B nie
wymaga FLASH NA OBU SLOTACH. To nie jest biurokracja - to rozstrzyga, ktore
polecenie w ogole wolno wydac.

## Etap 1 - co wolno nadpisac

```bash
scripts/list_overlayable.sh
```

Wynik: pliki `overlayable.xml` celow + dump `framework-res.apk`. Nadpisac legalnie
mozna tylko to, co (a) istnieje w tym buildzie i (b) nie jest chronione przez
`<overlayable>` (Android 12+ „Enforce RRO changes" dla overlayy niestatycznych).

Regula, ktora obejscia nie ma: **nazwa resource'u w overlayu musi istniec w celu.**
Zla nazwa nie daje bledu - daje overlay, ktory „dziala" i nic nie zmienia, albo
zmienia cos obok. Stad pusty `overlay.xml` w repo jako stan domyslny.

## Etap 2 - zasoby ze zrodla

```bash
scripts/extract_hyperos_assets.sh <katalog z rozpakowanym drzewem> ./modules/hyperos-look/staging
```

Skrypt ma biala liste (fonty, tapety, UI dzwieki, overlaye, launcher/theme) i
liste odmowy (gralloc, hwcomposer, camera HAL, RIL, fingerprint, keymaster,
boot/vbmeta/dtbo, `services.jar`, `framework.jar`, obrazy partycji...).
Odrzucone pliki trafiaja do `refused.txt` - nie dlatego, ze sa „niebezpieczne",
tylko dlatego, ze na MT6789 nie ma ich kto uzyc.

**Uwaga o rozpakowaniu.** Ten skrypt chce drzewa katalogow, nie `.img`. Rozpisanie
`super.img` / `payload.bin` wymaga `lpunpack`, `simg2img`, `erofs-utils` - a te:
* w sandboxie agenta: nie ma ich, nie ma roota do `apt`, i nie ma trasy sieciowej
  do `huggingface.co` (zmierzone: `connect()` pada, DNS zwraca tylko AAAA);
* na runnerze GitHub Actions: sa (albo da sie je wciagnac), a internet ma pelny.
Dlatego job `unpack-source` w `.github/workflows/build.yml` robota wykonuje tam, nie tutaj.

## Etap 3 - nadpisania

Jeden resource na commit, w `overlay-app/res/values/overlay.xml`. Kolejnosc
wdrazania od najlatwiejszej do najtrudniejszej:

1. **fonty** - podmiana przez `system/etc/fonts.xml` wskazujacy na nowy plik w module;
   czesto wystarczy `HyperOS Sans` jako fallback bez dotykania `fonts.xml`
2. **tapety / dzwieki** - czysta wymiana plikow, zero ryzyka
3. **`cmd overlay enable` dla gotowych RRO Xiaomi** - jezeli `targetPackage`
   istnieje na Lenovo (`com.android.systemui`, `android` - zwykle tak;
   `com.miui.*` - nigdy)
4. **wlasne RRO na `android`** - to jest miejsce, gdzie faktycznie sedzi sie
   „HyperOS-owy" charakter (status bar, gesty, animacje otwarcia)

## Etap 4 - budowa i instalacja

```bash
scripts/build_overlay_apk.sh --debug-key
scripts/install_module.sh
```

Instalacja idzie **katalogiem** (`/data/adb/modules/<id>/`), nie ZIP-em - swiadomie:
flashable ZIP wymaga `update-binary`, ktorego wzor bierze sie z Magisk, a nie z
memorii; katalog jest obslugiwany bezposrednio i zdjecie jest jednym `rm -rf`.

## Etap 5 - weryfikacja i rollback

```bash
scripts/verify_module.sh
```

Mowi, ktory etap padl: instalacja → nadmontowanie → skan PMS → enable → aplikacja.
Typowe objawy i przyczyny:

| Objaw | Przyczyna | Naprawa |
|---|---|---|
| `cmd overlay list` puste | APK nie w `/product/overlay` po zamontowaniu | `ls -l /product/overlay` w srod modulu; uprawnienia 0644 |
| Overlay widoczny, nie aplikuje sie | zla nazwa lub typ resource'u | wrocic do etapu 1, porownac z dumpem celu |
| Bootloop SystemUI | nadpisanie resource'u uzytego przez `WindowManager` przy starcie | `adb shell su -c "touch /data/adb/modules/hyperos_look_p11g2/disable" && adb reboot` |
| Modul w ogole nie odpala | `module.prop` bez wymaganego pola | `customize.sh` i `build.yml` to wylapuja |

Rollback, zawsze ten sam i zawsze calkowity:

```bash
adb shell su -c "rm -rf /data/adb/modules/hyperos_look_p11g2" && adb reboot
```

## Czego tu nie bedzie

Gwarancji „100%, ze sie wgra" dla czegokolwiek, co dotyka partycji systemowych.
Ta gwarancja nie istnieje na zadnym sprzecie - jest tylko prawdopodobienstwo
kupowane wiedza o buildzie. Na tym etapie (modul, zero zmian partycji)
prawdopodobienstwo jest wysokie wlasnie dlatego, ze nie ma czego zepsuc:
`vendor`, kernel i tablica partycji pozostaja stockowe.
