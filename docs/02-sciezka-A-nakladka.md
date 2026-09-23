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

## Etap 4b (2026-09-23, zmierzone na plikach) — dlaczego sam RRO nie wystarczy

Odczytałem podpisy APK-ów ze źródła (`unzip -p … META-INF/CERT.RSA | openssl x509 -fingerprint -sha256`):

| plik | certyfikat (sha256) |
|---|---|
| `system/framework/framework-res.apk` (20 982 848 B) | `c9009d01ebf9f5d0302bc71b2fe9aa9a47a432bba17308a3111b75d7b2149025` (X=Miui) |
| `vendor_mystical/overlay/WifiResOverlay.apk` | `c9009d01ebf9…` — ten sam klucz MIUI |
| `vendor_mystical/overlay/*__auto_generated_rro_vendor.apk` | `d45f076fe23a1a5b7f486e3ff41547a2023dbfe1fe73353b1e48ebdfed72cc6f` |

Żaden z nich to nie jest AOSP testkey. Wymuszenie podpisu nakładek (Android 11+) porównuje
klucz RRO z kluczem nakładanego pakietu, a na tablecie tym pakietem jest `android` z frameworku
Lenovo/GSI. Czyli **skopiowanie `product/overlay/*.apk` HyperOS na ten tablet skutkuje cichym
odrzuceniem nakładek** — nie komunikatem błędu, tylko brakiem zmiany wyglądu. Stąd w playbooku
`--debug-key` (przepodpisanie własnym kluczem), a nie „wgrać i mieć spokój".

**Dopomiar z 2026-09-23 na `product` (bieg `35897100768`, 134 808 062 B assetów, sha256
`a53ff508…` zgodny z runnerem i z sumą Dysku):** w `product/overlay` jest **67 plików APK w 12
katalogach** (80 MB), z czego **54 mają klucz MIUI `c9009d01ebf9…`**, a **13 inny**. Czyli reguła
z tabeli wyżej dotyczy także `product`, nie tylko `vendor_mystical` — i dotyczy 4/5 nakładek.
Rozbiłem to na krzyżówkę „cel nakładki × klucz podpisu" (`diagnostics/rro-crosstab-product.tsv`,
`tools/rro_targets.py` — parser binarnego `AndroidManifest.xml`, bo `res/values.xml` w auto-RRO
nie istnieje):

| cel (`targetPackage`) | klucz MIUI | inny klucz | sens na TB350FU |
|---|---|---|---|
| `android` (= `framework-res.apk`) | 16 | 10 | **26 nakładek** — najcenniejszych (pasek stanu, zaokrąglenia, animacje), ale wymagają klucza `android` z targetu |
| `com.android.settings` | 6 | 0 | działałyby po przepodpisaniu |
| `com.android.systemui` | 4 | 0 | j.w. |
| `com.miui.miwallpaper` | 6 | 0 | **pakiet nie istnieje na Lenovo** → martwy ciężar |
| `com.miui.rom`, `com.miui.securitycore`, `com.miui.system`, `com.xiaomi.phone`, `com.xiaomi.bluetooth`, `com.newcall` | 7 | 0 | **też pakiety Xiaomi** → zawsze bezczynne |
| `providers.settings`, `server.telecom`, `bluetooth`, `phone`, `wifi.resources`, `networkstack`, `thememanager`, `managedprovisioning`, `cellbroadcast*` (AOSP) | 15 | 3 | istnieją na tablecie, czekają na podpis |

Klucze „inne" to nie AOSP: wszystkie 13 mają `d45f076fe23a1a5b…`, czyli klucz
`*__auto_generated_rro_vendor.apk` Xiaomi (`subject=O=Xiaomi, L=Beijing`).ZNACZENIE: **zero
z 67** nakładek podpisanych jest kluczem, który zna tablet Lenovo — więc „wgrać overlaye i
mieć HyperOS-owy framework" nie istnieje jako ścieżka bez przepodpisania *każdej* z 26
frameworkowych nakładek (`apksigner` na runnerze; JDK tam jest, lokalnie nie mam).

Liczby: **54 z 67 na kluczu MIUI, 13 na innym; 13 z 67 celuje w pakiety Xiaomi, których na
tablecie nie ma** (czyli 1/5 paczki to bagaż nie do użycia nigdy). Wniosek dla playbooka:
`--debug-key` (przepodpisanie własnym kluczem, w CI `apksigner`) dotyczy **całych 26**
frameworkowych nakładek, a nie „wybranych"; i przed przepodpisaniem warto odrzucić te 13
xiaomi-only, bo zwiększają tylko ryzyko cichej kolizji nazw pakietów.
Nie jest to wniosek z dokumentacji Xiaomi, tylko policzenie plików.

### Etap 4c — to, co działa bez podpisu: fonty

Fonty to pliki, nie pakiety APK, więc żadnego wymuszenia podpisu nie przechodzą. Zbudowałem
generator modułu na podstawie realnych plików źródłowych:

```bash
# 1) ściągnięta paczka assetów 'product' (134 808 062 B, sha256 a53ff508…):
tar xzf images/drive-1IjQ…-assets.tar.gz -C staging/product ./fonts ./overlay ./etc/permissions
# 2) moduł:
tools/make_font_module.sh --fonts staging/product/fonts --out modules-build/hyperos4_fonts_p11g2 --family MiSans
# 3) ZIP dla Magiska (walidowany: module.prop w korzeniu + CRC):
tools/pack_module.sh modules-build/hyperos4_fonts_p11g2 hyperos4_fonts_p11g2.zip
```

**Wykonane 2026-09-23 na prawdziwych bajtach, nie na próbce:** `product/fonts` to **63 pliki,
87 940 740 B**, w tym **28 plików `MiSans*`**. Pierwszy przebieg generatora wybrał `sans-serif`
na podstawie **nazwy** i dostał `MiSansLatinVF.ttf` + `serif` = `MiSerif.ttf`. Rozłożyłem to
parserem `cmap` w `tools/fontgen.py` (funkcja `coverage()`, liczby z plików):

| plik | kodów | łacina | CJK (U+4E00–9FFF) | wniosek |
|---|---|---|---|---|
| `MiSansVF.ttf` (20 093 424 B) | 29 572 | tak | **20 976** | prawdziwa rodzina → to ma być `sans-serif` |
| `MiSansLatinVF.ttf` (481 220 B) | 1 337 | tak | **0** | podzbiór łaciński, nie nadaje się na jedyny font UI CN |
| `MiSerif.ttf` (303 844 B) | **14** | nie | 0 | zakładka/demo, nie rodzina |
| `MiSerifSCVF.ttf` / `TCVF` | 208 / 209 | tak | 128 / 129 | za małe na `serif` całego systemu |
| `MiSansJapaneseVF.ttf` | 13 873 | tak | 10 767 | słusznie poza `sans-serif` (ma swoją rodzinę) |

Generator ma teraz bramki: kandydat na `sans-serif` musi mieć łacinę **i** CJK, priorytet idzie od
pokrycia a nie od nazwy, a `serif` jest **pominięty z komunikatem**, jeżeli żaden plik nie ma
≥ 400 kodów — bo wstawienie fontu 14-glifowego psuje tekst bardziej niż zostawienie fontu
systemowego. Stan po naprawie: **19 referencji w `fonts.xml`, 25 plików, 44 MB, 0 błędów**,
`sans-serif` → `MiSansVF.ttf`, 17 rodzin `lang=` (ar/bn/bo/gu/hi/ja/ko/km/lo/my/or/ru/th/ta/te/ti…).
ZIP: **32 wpisy, 29 015 567 B**, sha256 `62b688a890fd1ef8…`, w `dist/modules/hyperos4_fonts_p11g2.zip`.
`make_font_module.sh` odrzucił 44 pliki bez rozpoznanego skryptu (logo-fonty typu
`Coca-ColaCareFontKaiTi.TTF`, `BebasNeue-Mono.otf`) — nie wchodzą do `fonts.xml`, więc nie
zagradzają ścieżki dobierania glifów.

Dlaczego moduł, a nie podmiana `system/fonts`: w źródle `./system/fonts/MiSans*` to **dowiązania symboliczne do `/product/fonts/…`** (21 linków), więc sam `product` niesie rodzinę. Zostawiając
fonty w `product` przez Magisk nie ruszamy partycji, która ma hashtree w `vbmeta` źródła
(2 748 350 464 B), a `fonts.xml` i tak trzeba generować, bo oryginalny wskazuje
`/data/system/fonts/theme_webview/…` — ścieżkę, której na tablecie nie ma.

Trzy rzeczy, które ten generator naprawia względem „skopiuj pliki":

- w źródle `/system/fonts/MiSans*.ttf` to **symlinki** do `/product/fonts/…` (21 takich w samej
  paczce `system`), więc bez `product` nie ma żadnych bajtów do skopiowania;
- `/system/etc/fonts.xml` źródła to symlink do `/data/system/fonts/theme_webview/fonts.xml`
  (motyw Xiaomi) — kopiowanie tego na tablet dałoby odwołania do nieistniejących ścieżek,
  dlatego plik jest **generowany**, a rodzice dobierają się tylko z plików realnie w module;
- `FontListParser` przyjmuje `<family>` wyłącznie z `name` albo `lang`; fonty bez rozpoznawalnego
  skryptu są **odrzucane z listy** (w teście na 206 prawdziwych plikach: 110 odpada), zamiast
  trafić do nieważnej rodziny, którą parser i tak by pominął.
