# 5. Analiza blokady i projekt ROM-u — liczby z plików, nie z opisów w sieci

Punkty 4.2–4.9 (`docs/04`) ustaliły proweniencję i kanał transferu. Ten dokument ustala
**co fizycznie blokuje boot** i **jak to zostało obejście zbudowane**. Każda liczba poniżej
pochodzi z pomiaru na pobranych plikach (runner Actions + `avbtool 1.2.0/1.4.0`,
`fsck.erofs`, `tools/vintf_diff.py`), nie z dokumentacji Xiaomi/Lenovo.

## 5.1 Zmierzone: dwie blokady, a nie jedna

### Blokada A — AVB (opis partycji nie opisuje tych plików)

`vbmeta.img` targetu (Lenovo TB350FU, sha256 `75fe0d867a44…`) zawiera hashtree i hash
deskryptory o rozmiarach, które **nie równają się rozmiarom plików z Dysku**:

| partycja | hashtree w `vbmeta` targetu | plik źródłowy (HyperOS 4) | różnica |
|---|---|---|---|
| `product` | 2 748 350 464 B | 6 445 187 072 B | +3,70 GB |
| `system_ext` | 744 968 192 B | 632 840 192 B | −112 MB |
| `odm` | 262 144 B (`odm_dlkm`) | 3 096 117 248 B | +2,83 GB |
| `vendor` | 30 785 536 B (`vendor_dlkm`) | 665 260 032 B (`vendor_mystical`) | +634 MB |
| `system` | (chain `vbmeta_system` `fa41159a…`) | 937 791 488 B | inny opis |

Wniosek, którego nie da się obejść podpisem: żaden zestaw tych pięciu plików nie jest
spójny z łańcuchem uwierzytelniania targetu. Klucze podpisujące łańcuch targetu
(`9d808b09…` boot, `fa41159a…` vbmeta_system, `9577bc6c…` vbmeta_vendor) są w HSM OEM —
nie do odtworzenia. Natomiast **sam top-level `vbmeta` targetu jest podpisany AOSP
testkeyem** (odcisk `cdbb7717…`, klucz prywatny jest w `LineageOS/android_external_avb`)
— więc mój własny łańcuch mogę podpisać tak, żeby `fastboot flash vbmeta` przeszedł,
ale „zielony" boot nie wchodzi w grę; realny stan to pomarańczowy + `flags=3`.

### Blokada B — VINTF (brak pliku, nie brak magii)

Z rozpakowanego źródłowego `system.img` (EROFS, `ro.build.version.sdk=37`,
`release=17`, `security_patch=2026-08-01`, `incremental=17OS4.0.260916…XRPDCN.S`),
katalog `system/etc/vintf`:

```
manifest.xml                      version="9.0", HAL-e z max-level="7|8"
device.xml                        144 wpisy
compatibility_matrix.7.xml        lvl 7
compatibility_matrix.8.xml        lvl 8
compatibility_matrix.202404.xml   lvl 6
compatibility_matrix.202504.xml   lvl 7
compatibility_matrix.202604.xml   lvl 8
```

Czego **nie ma**: `compatibility_matrix.4.xml`, `.5.xml`, `.6.xml`. Vendor targetu
zgłasza `ro.product.first_api_level=31` → `VINTF_TARGET_LEVEL=5`, a `init` przy starcie
szuka pliku macierzy dla swojego poziomu. Brak pliku = `Failed to initialize VINTF
Object` i stop **przed zygote**. To jest jedyna blokada, którą da się zdjąć po mojej
stronie — przez wygenerowanie pliku.

Drugi pomiar, najważniejszy dla oceny ryzyka: `tools/vintf_diff.py` na najniższej
dostępnej macierzy (`202404`, level 6) zwraca **84 pozycje HAL, w tym 0 z flagą
`optional`** (`grep -c '<optional>'` = 0 we wszystkich pięciu plikach). Struktura:
**0 HIDL / 83 AIDL**. Vendor epoki A12 nie ma tych interfejsów w ogóle (AIDL-owe

**Korekta liczb po naprawie samego narzędzia** (2026-09-23): na całym zestawie sześciu
plików `vintf_diff.py` zwraca **400 pozycji** i ta liczba NIE jest tym, co widzi init —
patrz §6.6 w `docs/06`: to suma wszystkich poziomów macierzy, a `VintfObject` wybiera
**jedną** wg `target_fcm_version`. Dla TB350FU (A12L, level 5/6) wychodzi **81 pozycji,
0 obowiązkowych, 81 opcjonalnych**; przy level 8 bywałoby 88. Słowo „obowiązkowych" przy
400 było błędem, który przez pewien czas ustawiał cały plan pracy na niewłaściwej półce.

(oryginalny tekst zdania brzmiał: „…zwraca 400 pozycji obowiązkowych, nie 412 — wcześniej liczył")
też `device.xml`/`manifest.xml` jako wymagania, bo filtrował po nazwie pliku zamiast po
korzeniu dokumentu; dodatkowo `optional` było liczono jako `False and opt`, więc każde
oznaczenie w pliku ignorowano. Naprawione.

**Korekta z 24 IX 2026 (po tej turze).** Poniższy test zwierciadlany dowodził *filtrowania HAL-i*
i niczego więcej. Nie sprawdzał, czy element `<level>` w wygenerowanym pliku równa się żądanemu
poziomowi — a generator nadpisywał tylko atrybut, więc plik `compatibility_matrix.5.xml` miał w
środku `<level>6</level>`. Test był zielony na narzędziu, które dla `init` nie otwiera niczego.
Dziś: `make_release.sh --vintf-level` (dokłada plik do budowanego obrazu, sprząta z drzewa),
asercja w samym generatorze (`rc=4` przy rozjeździe levelu) i sekcja S w teście wydania, która
czyta plik z **rozpakowanego** obrazu — `docs/06` §6.29.

Test zwierciadlany (bez niego nie ufałbym własnemu narzędziu): macierz level 5 wygenerowana
przez `make_level_matrix.py` i *zmiękczona pod konkretny manifest vendor* vs ten sam manifest
daje **0 braków obowiązkowych (“VINTF SPOJNE”)**; ta sama miękka macierz vs vendor źródła
daje 4 braki, a wersja strict vs vendor źródła 53 braki i vs symulowany vendor A12 70 braków.
Czyli: generowanie otwiera bramkę `init` dokładnie wtedy, kiedy twierdzę, że ją otwiera.
   **Ta ostatnia pewność była przedwczesna** — patrz `docs/06 §6.32`: zero braków liczono
   narzędziem, które czytało to samo pole, które zapisywał generator (element `<optional>`),
   a nie to, które czyta libvintf (atrybut). Po naprawie `make_level_matrix.py` i `vintf_diff.py`
   ten sam eksperyment daje 0 dopiero wtedy, gdy zmiękczenie jest w atrybucie — i dopiero to
   znaczy coś o `init`. Liczby strict (53 / 70) pozostają prawdziwe.
`audio.core`, `health`, `power`, `thermal`, `dumpstate`, `gatekeeper` weszły później).
Czyli otwarcie bramki init nie jest tożsame z bootem do pulpitu.

## 5.2 Co z tego wynika dla trzech możliwych ścieżek

| ścieżka | na czym polega | status |
|---|---|---|
| A | nakładka (RRO + assety HyperOS) na istniejącym frameworku, moduł Magisk/KernelSU | **dostarczana jako działający staging** (`scripts/*`, `docs/02`); boot gwarantowany, bo nie rusza AVB |
| B' | przebudowany `system.img` z wstrzykniętymi macierzami + `vbmeta flags=3` | **zbudowana i wpięta w CI** (`tools/build_rom_on_runner.sh`, `rom_build: 1`) — flashuje i montuje; co dalej, rozstrzyga dump z urządzenia |
| C | pełny swap 5 obrazami + oryginalny łańcuch AVB | **niemożliwe do podpisania** — patrz tabela w 5.1. Nie „trudne": opisy hashtree dotyczą innych bajtów |

Ścieżka B' jest kompromisem wymuszonym pomiarem: zamienia „boot nie przechodzi bramki"
na „bramka otwarta, ryzyko przesuwa się na serwis HAL-i". Bez niej nie da się even
przetestować czegokolwiek, więc jest warta zbudowania; ale nazywam ją po imieniu:
**eksperyment**, nie „100 % flashable ROM" w sensie „pewny boot".

## 5.3 Jak zdjęto blokadę B (mechanika, nie modlitwa)

`tools/make_level_matrix.py` — bierze najniższą dostępną macierz, tnie po
`min-level`/`max-level`, zapisuje plik żądanego poziomu i **sam się weryfikuje**
(parsowanie + liczba HAL-i). `--optional-missing`: pozycje, których vendor nie
dostarcza, dostają `<optional>true</optional>` — init panikuje wyłącznie na braku
pozycji **obowiązkowej**, więc to jest jedyne półotwarcie, jakie istnieje bez wymiany
vendora. Jeżeli mam `/vendor/etc/vintf` z urządzenia (ściągany przez
`scripts/collect_device_state.sh`), `optional` dostają **tylko realne braki** —
dopasowanie po nazwie interfejsu (AIDL `<interface><name>…`) lub po `name` (HIDL).
Test na fałszywym vendorze z 2 HAL-ami: zostaje 1 pozycja obowiązkowa (druga nie
występuje w tej macierzy) — czyli mielenie bez potrzeby nie zachodzi.

`tools/build_rom_on_runner.sh` — pięć kroków: rozpakowanie (`fsck.erofs --extract`),
wstrzyknięcie `compatibility_matrix.{4,5,6}.xml`, przebudowa EROFS (`-zlz4`, bo kernel
5.10 targetu ma lz4, a `zstd` bywa bez `CONFIG_EROFS_ZSTD`), `avbtool make_vbmeta_image
--flags 3` podpisany testkeyem, paczka (`MISMATCH.md`, `flash.sh`, `SHA256SUMS.txt`),
która wraca do mnie przez kanał ≤90 MB (udokumentowany w `docs/04 §4.9`).
Tryb testowy (bez `erofs-utils`) przechodzi kroki 1,2,4,5 lokalnie — to on dał
`vbmeta` 4096 B z odciskiem `cdbb7717…`.

## 5.4 Co jest w paczce dla flashowania i jak się wycofać

`flash.sh`: sprawdza `fastboot getvar product` pod kątem `TB350FU`, robi `fetch vbmeta_a`
(kopia zapasowa), flashuje `vbmeta_a/_b` nową (flags=3), `system_a/_b` przebudowanym
obrazem, **pyta przed `erase userdata`** (inny framework ⇒ bez wipe-a zapętli),
reboot. Rollback = `fastboot flash vbmeta_a backup_vbmeta_a.img` + trzy obrazy Lenovo z
Dysku (ID i md5 w `diagnostics/drive-inventory.tsv`, md5 serwera zgodne z tymi, które
policzyłem po złożeniu części).

## 5.5 Czego nie wiem i czego ten sandbox nie ustali

1. Czy `system_a` targetu przyjmie 938 MB przebudowanego obrazu — partycja `system`
   w `getvar all` jeszcze nie jest zmierzona (do zrobienia przez `flash.sh`/`fastboot`).
2. Ile z 83 AIDL-ów vendor realnie ma — bez `/vendor/etc/vintf` z urządzenia pracuję na
   „szerokim" oznaczeniu `optional`, więc liczba crashujących usług jest nieznana.
3. `/system/etc/fonts.xml` w źródle to symlink do `/data/system/fonts/theme_webview/fonts.xml`,
   a `framework-res.apk` leży obok `.apk.fsv_meta` (fs-verity per plik) — oba szczegóły
   potrafią unieruchomić boot **niezależnie** od VINTF (patrz `diagnostics/hyperos4_fonts_note.md`).
4. W `system.img` źródła jest **0** odwołań typu `/overlay/*.apk` — RRO HyperOS nie leżą
   w `system`, tylko w `product`/`system_ext`/`vendor_mystical`. Dlatego podzbiór
   allowlisty w `tools/unpack_on_runner.sh` celuje w `*/overlay`, `*/etc/vintf`,
   `*/etc/permissions`, a `product/app|priv-app` zostały wyrzucone (apk HyperOS bez usług
   MIUI nie wstaną, a budżet transferu to 2 GB/push).

## 5.6 Stan biegów (żeby kolejne zdanie nie powtarzało logów CI)

Zamknięte: `35894152349` (4 obrazy, allowlistą, `max_total: 1 900 000 000`),
`35896026438` (padł: brak `simg2img`, nazwy z Drive puste, straż miejsca odcinała `product`),
`35897100768` (**dane zebrane**: `product` 134 808 062 B, `rom-kit.tar.gz` 1 425 601 570 B,
`rom-docs` 30 452 B, `odm` 6317 B, `system` 72 809 115 B — te dwie ostatnie tylko jako
wpis w manifeście, patrz niżej). Protokół po każdym biegu: `tools/ingest_run.sh` (albo
ręcznie `git archive` ze spoolu) → weryfikacja sum → `bash tools/pull_spool.sh wipe` →
`make_private` + kontrola `list_permissions`.

Dwa biegi na tej samej gałęzi `transfer-spool` rywalizują o force-push, więc ROM-start jest
po dowiezieniu assetów, nigdy równolegle.

## 5.7 Co zmierzyłem na zbudowanym ROM-ie (nie na opisie skryptu)

Obraz `system_hyperos4_p11g2.img`: **1 376 899 072 B**, sygnatura EROFS `0xe0f5e1e2` pod
offsetem 1024, suma sha256 zgodna z tą, którą zapisał runner (`sha256sum -c` w kieszeni kitu:
pozycje `system_hyperos4_p11g2.img`, `vbmeta_hyperos4_p11g2.img`, `flash.sh`, `MISMATCH.md` = `OK`, a `BUILD_LOG.txt` = `FAILED` z powodu usterki nr 1 poniżej). Sonda flag w `tools/build_rom_on_runner.sh` odrzuciła `-O fragment…`
(`mkfs.erofs 1.9.4-g1c230a48` nie zna tej opcji) i zeszła na wariant bez kompresji — dzięki
temu pliki w obrazie da się odnaleźć w surowych bajtach:

- marker `wygenerowane przez tools/make_level_matrix.py`: **3 wystąpienia**,
- atrybuty `level="4"`, `level="5"`, `level="6"`: po **1** każdemu → wstrzyknięte macierze
  faktycznie weszły do partycji, a nie tylko do katalogu tymczasowego budowania.

Cały blok bajtów pojedynczej macierzy nie leży w obrazie ciągiem (EROFS upakował małe pliki
we fragmenty wymieszane z innymi) — dlatego dowód opieram na markerze i atrybutach, a nie na
szukaniu kontenera pliku.

`vbmeta_hyperos4_p11g2.img` (4096 B) odczytana `avbtool info_image`: `Algorithm: SHA256_RSA2048`,
**`Flags: 3`** (verification + hashtree wyłączone), key `cdbb77177f731920bbe0a0f94f84d9038ae0617d`
= dokładnie ten klucz, którym podpisana jest fabryczna vbmeta TB350FU, oraz prop
`com.android.build.system.fingerprint = hyperos4.p11g2.experiment`. To jest minimalny zestaw
potrzebny, żeby fastboot przyjął obraz bez `verity`.

Dwa błędy warsztatu znalezione dopiero na prawdziwym kicie (i naprawione):

1. `SHA256SUMS.txt` był liczony **przed** dopisaniem ostatnich linii do `BUILD_LOG.txt`, więc
   `sha256sum -c` na nim krzyczał. Sumy są teraz liczone na końcu, a `BUILD_LOG.txt` jest z nich
   **świadomie wyłączony** (log urasta, dopóki żyje krok budowania) — to nie błąd weryfikacji, tylko właściwość logu.
2. Kit zawierał `system_tree/` (1,3 GB rozpakowanego źródła) obok właściwego obrazu, bo
   `tar czf … -C rom .` nie miał `--exclude`. Paczka miała 1,43 GB zamiast ~0,9 GB i zużywała
   limit 2 GB/push na bezwartościowy ciężar.

Pojawił się też niecodzienny drobiazg: **kit zamroził starszy `flash.sh`**. Bieg `35897100768`
startował z `fcf056d`, a wersja z rozpoznaniem slotów i fastbootd weszła w `52f06bd` — czyli
**po** starcie. W efekcie `SHA256SUMS.runner.txt` opisuje plik 25-liniowy, który wgrawał
`vbmeta` tylko na slot `a`. Przy `current-slot: b` to flashowanie jest „udane", a urządzenie nie
wstaje, bo weryfikuje `vbmeta_b`. W `dist/rom-kit/` leży zregenerowana wersja (84 linie) z
backupem i flashem **obu** slotów, a sekwencję sprawdziłem na atrapie `fastboot`
(`dist/rom-kit/README.sumy.md`) — nie na urządzeniu. Lekcja dla kanału: kit jest zamrożony w
momencie startu biegu, więc każdy commit narzędziowy po starcie wymaga nowego biegu, nie
„dopisania" do paczki.

Nie zweryfikowane (uczciwie): bootalność na urządzeniu. Nic z powyższego nie dowodzi, że
tablet wstanie — dowodzi tylko, że to, co skrypt obiecuje włożyć do partycji, tam jest.
