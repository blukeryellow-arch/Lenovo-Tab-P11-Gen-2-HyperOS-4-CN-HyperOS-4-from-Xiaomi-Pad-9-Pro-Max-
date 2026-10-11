# dist/rom-kit — co tu leży i czego brakuje

Wynik biegu CI `35897100768` (gałąź `transfer-spool`, commit spoolu `066fb208`), złożony
niezależnie od kanału Drive→GitHub. Sumy `SHA256SUMS.runner.txt` dotyczą zawartości
`images/rom-kit.tar.gz` (1 425 601 570 B, sha256 `537eb4ea…`) — przeliczone tutaj: `OK`.

| plik | co to jest |
|---|---|
| `vbmeta_hyperos4_p11g2.img` (4096 B) | `avbtool info_image`: SHA256_RSA2048, **`Flags: 3`**, key `cdbb77177f731920bbe0a0f94f84d9038ae0617d` = ten sam odcisk co fabryczna vbmeta TB350FU, prop `com.android.build.system.fingerprint = hyperos4.p11g2.experiment` |
| `flash.sh` (84 linie) | ścieżka flashowania z rozróżnieniem bootloader/fastbootd, **backup i flash obu slotów** (`a` i `b`), bez `erase userdata` bez potwierdzenia |
| `MISMATCH.md` | co paczka otwiera, a czego nie naprawia — liczby VINTF zmierzone na plikach |
| `SHA256SUMS.runner.txt` / `SHA256SUMS.git.txt` | patrz `README.sumy.md` |

## Czego TU NIE ma i dlaczego

`system_hyperos4_p11g2.img` (**1 376 899 072 B**) nie wchodzi do gita: limit to 100 MB na
blob. Leżał w workspace jako `images/rom-kit.tar.gz`; po recyklingu sandboxa katalogi
ignorowane przez gita **nie przeżyły** — obraz jest do odtworzenia biegem CI (`rom_build: 1`),
a nie z tej gałęzi. Wnioski z jego pomiarów są w `docs/05` §5.7 (marker generatora 3×,
`level="4"/"5"/"6"` po 1× w surowych bajtach obrazu; EROFS `0xe0f5e1e2`).

## Czego ten kit NIE robi

Nie rusza `framework-res.apk`, `boot.img`, ramdisku, tablicy partycji, APEX-ów. Nie przerabia
vendora `mt6789` pod HAL-e A17. Bootloop jest realnym scenariuszem; `Flags: 3` oznacza, że
awaria nie da komunikatu — ratunek to `rollback.sh` + tryb BROM/DA MediaTeka (`mtkclient` /
SP Flash Tool); EDL nie wchodzi w grę, bo to nie Qualcomm. Lenovo Rescue & Smart Assistant jest
opisany na stronie Lenovo, ale przeze mnie nie wypróbowany.
