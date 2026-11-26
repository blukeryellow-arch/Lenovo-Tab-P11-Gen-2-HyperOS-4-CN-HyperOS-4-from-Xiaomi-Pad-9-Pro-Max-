# Redmi 9C (`angelica` / `angelican` / `blossom`) — HyperOS 4.0.8.0 Debloated Port

Zautomatyzowany builder GitHub Actions tworzący zdebloatowany port **HyperOS 4 (`OS4.0.8.0.XBNMIXM`, Android 17)** dla **Redmi 9C (`angelica` / `angelican`, rodzina `blossom`)**, spakowany w **5-częściowe archiwum 7-Zip (`.7z.001` .. `.7z.005`)** w **GitHub Releases**.

## Skład portu

- **Baza sprzętowa (OSS Android 17 + kernel 4.19):** `EvolutionX 17.0 blossom` (`xc112lg/blossom_releases`, fallback `crDroid 17.0 blossom`) — dostarcza `boot.img` (kernel 4.19 z obsługą eBPF dla Androida 17), `dtbo.img`, `vendor.img`, `odm.img`, nakładki sprzętowe RRO, matryce VINTF MT6765 oraz `/system/etc/properties/${ro.boot.hwname}.prop` (automatyczne rozróżnienie `angelica` vs `angelican` NFC).
- **Dawca systemu (HyperOS 4 / Android 17):** oficjalna paczka Global dla **Redmi 15C / POCO C85 (`dew`, `OS4.0.8.0.XBNMIXM`)** (MediaTek, ekran 720×1600 HD+).
- **Kluczowe adaptacje (`tools/port_redmi9c_hyperos4.py`):**
  - scalenie partycji `mi_ext` do `product` / `system_ext` / `system` (ponieważ `fstab.mt6765` na `blossom` nie montuje `/mi_ext`),
  - zachowanie krytycznych bibliotek `*-v32.so` / MTK oraz matryc VINTF i mapowań SELinux z bazy `blossom`,
  - weryfikacja kompilacji połączonej polityki SELinux (`.cil`) narzędziem `secilc`,
  - agresywny debloat usług Xiaomi/Google/3rd-party i wyłączenie efektów rozmycia (blur) pod 2–4 GB RAM i fabryczną partycję `super` (4,5 GiB = `4831838208` B),
  - automatyczny dobór `ext4` lub `erofs` (`lz4hc,9`) z aktualizacją `fstab.mt6765` tak, aby `super.img` zmieścił się w fabrycznej partycji `super` Redmi 9C bez zmiany tablicy GPT.

## Pobieranie i rozpakowanie (5 plików 7-Zip)

1. Przejdź do **Releases** w tym repozytorium i pobierz wszystkie 5 części do jednego katalogu:
   - `Redmi9C-HyperOS4-Debloated.7z.001`
   - `Redmi9C-HyperOS4-Debloated.7z.002`
   - `Redmi9C-HyperOS4-Debloated.7z.003`
   - `Redmi9C-HyperOS4-Debloated.7z.004`
   - `Redmi9C-HyperOS4-Debloated.7z.005`
2. Kliknij prawym przyciskiem myszy **`Redmi9C-HyperOS4-Debloated.7z.001`** i wybierz **Wypakuj** (WinRAR lub 7-Zip).
3. Archiwum automatycznie złoży gotowe obrazy: `super.img`, `boot.img`, `dtbo.img`, `vbmeta*.img` oraz skrypty `FLASH-REDMI9C.bat` / `FLASH-REDMI9C.sh` i instrukcję `INSTRUKCJA-FLASH.txt`.

## Struktura repozytorium

- `.github/workflows/redmi9c-hyperos4-port.yml` — workflow budujący ROM na GitHub Actions i publikujący 5 części `.7z.001`..`.7z.005` do Release,
- `tools/port_redmi9c_hyperos4.py` — skrypt portujący, scalający `mi_ext`, debloatujący i adaptujący właściwości pod Redmi 9C,
- `tools/split_5_7z.sh` — pakowanie do dokładnie 5 części `.7z.001`..`.7z.005` z pełną weryfikacją `7z t`, `7z x` i SHA-256,
- `tools/{avbtool.py,fc_fixup.py,lpinfo.py,payload_extract.py,sdat2img.py,simg2img.py}` — narzędzia do rozpakowywania OTA, sparse/super i metadanych AVB/SELinux,
- `templates/` — skrypty flashujące (`FLASH-REDMI9C.bat`, `FLASH-REDMI9C.sh`) i instrukcja (`INSTRUKCJA-FLASH.txt`).
