# 10. Rejestr twardych dowodów

Kompendium: każde istotne twierdzenie tego projektu ma pod sobą dowód, który da się
odtworzyć. Bez dowodu twierdzenie nie wchodzi do wydania. Stan: **maraton 26 IX 2026**.

## 1. Tożsamość bajtów wydania (odbudowa i transfer)

| # | twierdzenie | dowód | odtworzenie |
|---|---|---|---|
| 1 | Obrazy `dist/release/*` odbudowują się z gałęzi `transfer-spool` **bajt w bajt** | 6 zimnych replayy receptury (dokument `docs/08`, sekcja „Odbudowa obrazów wydań"); ostatni 26 IX rano | `sed -n '/^# 0) toolchain/,/^```$/p' docs/08-stan-i-blokady.md \| grep -v '^```$' \| bash` |
| 2 | Determinizm mkfs.erofs (ta sama zawartość → te same bajty) | `make_release --selftest` (linia „IDENTYCZNY sha256"); system_ext CLEAN odbudowany po ENOSPC z identycznym sha `53dd7dfb…` | `tools/make_release.sh --selftest --erofs-dir /tmp/erofs-c --out /tmp/x` |
| 3 | Części 60 MB na Google Drive = bajty wydania | md5 wszystkich 29 części + 11 małych plików: serwer Google = lokalne cięcia, 1:1 (upload 25 IX); inwentarz `diagnostics/drive-clean-kit.tsv` | listing folderu + `download_file` + `md5sum` |
| 4 | Sklejanie ścieżką użytkownika daje obrazy wydania | `zloz.sh` e2e 26 IX ×2 (wersja stara i auto-weryfikująca): 4/4 obrazy IDENTYCZNE, idempotentne | pobierz folder `clean` z Dysku → `bash zloz.sh` |
| 5 | Przekłamana część NIE przejdzie do flashowania | nowy `zloz.sh`: ZLE + exit 1 (negatywny test: 1 bajt w part-007); flash-all bramka 0: sha256 przed każdym flashem (atrapa, sekcje E-H i ZC) | podmień bajt w `.part-*.bin` → `bash zloz.sh` |

## 2. Kontrola jakości wydania (suite)

| # | twierdzenie | dowód | odtworzenie |
|---|---|---|---|
| 6 | Suite przechodzi w całości | **170 PASS / 0 FAIL** (no-real) i **178 / 0** (`--real`), 26 IX po południu; CI zielone na `9689c7a` (release-selftest 1m31s) | `tools/test_release.sh --erofs-dir /tmp/erofs-c` (+ `--real` z drzewami) |
| 7 | Negatywny test anty-zamiennej działa | podmiana sumy system_ext CLEAN na donorską → FAIL; przywrócenie → 166/0 (26 IX) | sekcja ZC w test_release.sh + ręczny negatyw |
| 8 | Negatywny test anty-nadpisu działa | flash-all cleana podmieniony na wersję coherent → 3× FAIL; przywrócenie → 166/0 (26 IX) | sekcja ZC + `cp` + suite |
| 9 | Bramka oneway system_ext pilnuje | bez `I_ACCEPT_SYSTEM_EXT_ONEWAY` → rc=1, 0 flashów; ze zgodą → rc=0, 7 flashów, system_ext 1× bez sufiksu (atrapa) | sekcja ZC, kontroli 12–13 |
| 10 | df-guard nie puści budowy przy braku miejsca | 100 KB wolnego → FATAL rc=2, zero obrazów; śmieciowy output df → FATAL (fail-closed); test izolacyjny ze stubem df w PATH | sekcja AA; `PATH=/tmp/dfstub:$PATH bash tools/make_release.sh …` |
| 11 | fałszywe GO na slotach wyłapane | latentny bug NEED_S (regex `^system_` łapał `system_ext`, w coherent porównywał slot z 602 MB zamiast 920 MB) — znaleziony przeglądem adwersarza, naprawiony, sumy/kontrakty odświeżone (26 IX) | `awk -F'\t' '$1 == "system_hyperos4_p11g2.img" {print $2}' <manifest>` |

## 3. Proweniencja i granice

| # | twierdzenie | dowód | odtworzenie |
|---|---|---|---|
| 12 | Donor = Xiaomi Pad 9 Pro Max, HyperOS 4 CN, ze źródła usera | docs/04: fingerprint 260916, yingtian/M367FC, miuirom.org/tablets/xiaomi-pad-9-pro-max (katalog oficjalnych ROM-ów Xiaomi); md5 donorskiego system_ext na Dysku = f879747f… (suma serwera) | docs/04 + `diagnostics/drive-clean-kit.tsv` |
| 13 | Target = Lenovo Tab P11 Gen 2 (TB350FU, MT6789, GKI 5.10.233) | docs/04 §4.3: kernel zmierzony z boot.img; GSMArena/Amazon/Newegg TB350FU | docs/04 |
| 14 | Pełny port NIE jest wykonalny (4 blokady) | docs/04: Xring O3 vs MT6789, VINTF A17 vs vendor A12, KMI 5.10 vs 6.x (`disagrees about version of symbol`), brak BSP Xring O3 | docs/04, sekcja „Cztery blokady" |
| 15 | Szanse startu: init ~85% / system_server ~50-60% / pulpit ~10-25% | docs/09 §5 (analiza bramek startowych) | docs/09 |
| 16 | MSA/GetApps/reklamy NIE występują | product wydana = 63 fonty + etc/{passwd,group} (67 wpisów, fsck round-trip 1:1); bloat donora żyje w donorskim product, który nie jest wgrywany | `tools/verify_image.sh` + sekcja J suity |

## 4. Proces i bezpieczeństwo transferu

| # | twierdzenie | dowód | odtworzenie |
|---|---|---|---|
| 17 | Dysk: kit CLEAN kompletny i domknięty | folder `clean` 40/40, uprawnienia **owner-only** (list_permissions 26 IX), stare foldery prób trwale skasowane | `diagnostics/drive-clean-kit.tsv` |
| 18 | update przez konektor potrafi zniekształcić bajty | update_file_content: UTF-8 → inne bajty + zjedzony trailing newline (wykryte od razu przez md5) — dlatego bajt-dokładne pliki idą przez delete + upload_file | `cmp` pobranego z lokalnym |
| 19 | CI buduje i testuje to samo, co lokalnie | release-selftest + build-hyperos-look zielone na każdym commicie tools/; flake z 25 IX wyjaśniony przez tag `ci-repro-b69ff4c` (ten sam commit → zielony 1m27s) | `gh run list` |

## 5. Czego świadomie NIE udowadniamy

- **Czy system wstanie na tablecie** — brak urządzenia w sandboxie; szanse z pkt 15
  to analiza, nie obietnica. Postflash: `tools/postflash_triage.sh` nazwie stoper.
- **Zgodności z konkretnym egzemplarzem TB350FU** — dlatego device-probe.sh (GO/NO-GO)
  biega PRZED flashem na urządzeniu usera, a flash-all pyta rozmiary partycji z
  urządzenia, nie z dokumentu.
- **Windows-path (zloz.bat)** — zweryfikowany przeglądem (copy /b + certutil,
  listy części zgodne z konwencją 60 MB: 16+11+2), ale nie wykonany na Windowsie.
