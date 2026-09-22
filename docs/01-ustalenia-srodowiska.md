# Ustalenia: czym realnie dysponujemy (2026-09-22)

Dokument opisuje twarde ograniczenia sandboxa Agent Mode, bo to one wyznaczają,
gdzie może się odbywać ciężka praca nad obrazami. Zmierzono, nie zgadywano.

## 1. Repozytorium / GitHub

| Zdolność | Status | Dowód |
|---|---|---|
| Odczyt repo | ✅ | `gh repo view` zwraca dane, `git ls-remote` działa |
| Push do gałęzi sesyjnej | ✅ | `git push --dry-run` → `* [new branch]` |
| Tworzenie **nowego** repo w koncie | ❌ | `gh api /user` → `403 Resource not accessible by integration` |

Token w tej sesji to **installation token GitHub App** (`arena-ai-coding-agent[bot]`),
nie PAT. Działa w obrębie repo, w które jest zainstalowany, i nie ma uprawnień
kontowych. Wniosek: nowych repozytoriów stąd nie założę — ten nadaje się idealnie,
bo już istnieje i jest podpięty.

## 2. Egress sandboxa — allowlista, nie full internet

Zmierzone `curl`em (czas łączenia, kody HTTP):

```
✅ github.com                     200
✅ pypi.org / files.pythonhosted  200  (pip instaluje pakiety normalnie)
❌ huggingface.co                  000  — DNS zwraca TYLKO AAAA, connect() fail
❌ cdn-lfs.huggingface.co          000  — także serwer plików LFS
❌ raw.githubusercontent.com       000  — nie da się pobrać surowych plików z GH
❌ dl.google.com                   000  — brak Android SDK / platform-tools
❌ deb.debian.org, archive.ubuntu  000  + apt bez roota → instalacja pakietów sys
❌ google.com                      000  — ogólny internet
```

**Kluczowe:** `huggingface.co` jest stąd nieosiągalny. Cały plan „agent pobiera
multi-GB obrazy z HF i miesza partycje u siebie” nie przejdzie — nie z powodu
limitu rozmiaru ani tokena, tylko braku trasy sieciowej. To samo dotyczy LFS.

## 3. Narzędzia do rozbierania obrazów

Brak w obrazie systemu i nie da się ich doinstalować (apt zablokowany, brak roota):

```
lpunpack  simg2img  lpmake  mkfs.erofs  unpack_bootimg  avbtool  magiskboot
payload_dumper  imgextractor  7z  cpio  git-lfs
```

Dostępne: `python3 3.11`, `git`, `unzip`, pełen `pip` (z PyPI).
Czyli: **mogę pisać i testować logikę** (parsowanie nagłówków, skrypty, workflow),
ale **nie mogę wykonać faktycznego unpacku super.img / OTA payloada** w sandboxie.

## 4. Zatem gdzie się to dzieje

Ciężka robota idzie na **runnera GitHub Actions** — on ma pełny internet
(w tym HF i `dl.google.com`), roota do `apt-get`, i nie podlega allowliście sandboxa.

```
Hugging Face (prywatne repo)          ← Twoje multi-GB obrazy, LFS, bez limitów 25 MB
        │  pobierane przez runnera, auth przez sekret HF_TOKEN
        ▼
GitHub Actions (ubuntu-latest)        ← rozbieranie, podmiana partycji, przebudowa, walidacja
        │
        ▼
Artifact + GitHub Release             ← wynik; ew. push z powrotem do HF przez HF_WRITE_TOKEN
        │
        ▼
To repo (GitHub)                      ← jedyne miejsce na skrypty, workflow i dokumentację
```

Dlaczego nie GitHub jako magazyn ROM-ów: limit pliku to 100 MB (twardo 150 MiB dla git),
LFS w darmowym planie ma ograniczenia storage/bandwidth na miesiąc, a repo z kilkoma GB
binarek jest praktycznie nieklonalne. HF jest do tego stworzony i już go masz.

Dlaczego nie workspace: snapshot patchsetu jest limitowany (~128 MB), a sandbox jest
efemeryczny między sesjami — wielogigabajtowy ROM i tak by tu nie przeżył.

## 4b. KOREKTA: punkt o bootloaderze był błędny dla tego egzemplarza

Wcześniejsza teza „prawdopodobnie nie da się trwale odblokować bootloadera" była
**over-generalizacją wyciągniętą z wątków o innych modelach Lenovo:**

| Model | SoC | Stan odblokowania wg społeczności |
|---|---|---|
| Tab M11 `TB330FU` | MT8786 / Helio G88 | `flashing unlock` → *unknown command*, `oem unlock` → *Sn Image Auth fail*, `unlock_ability = 0` → mtkclient + DA.auth albo podpisany `sn.img` |
| Tab K11 `TB330XUP` | MT8786 | prawdziwy unlock wymaga autoryzacji po stronie serwera Lenovo; orange state ze zepsutego vbmeta to nie unlock |
| `TB336FU` | nowszy ZUI 17.x | bootloader weryfikuje sygnatury, certyfikaty, SN i SOC_ID; 18 segmentów tokenu; ostatecznie potrzebny `sn.img` z serwerów Lenovo |

Te ograniczenia są **per-model i per-build**, nie dotyczą całej marki. Skoro na tym
urządzeniu `fastboot flashing unlock` przeszedł od ręki, to jego bootloader implementuje
standardową ścieżkę AVB (zapis stanu do trwałej metadanych + wipe userdata), a nie
tokenową blokadę z tamtych SKU. Tamten argument odpada.

Co to **nie** zmienia: odblokowanie jest warunkiem koniecznym, nie wystarczającym. Odblokowany
bootloader nie wpływa na zgodność interfejsów HAL, wersję kernela, rozmiar `super` ani ilość RAM.
Pięć pozostałych blokad jest architektonicznych i zostaje w mocy.

Status true-unlock warto potwierdzić twardo, bo „fastboot odpowiedział OK" ≠ „stan zapisany":

```
fastboot getvar unlocked
fastboot getvar unlock_ability
adb shell getprop ro.boot.flash.locked            # oczekiwane: 0
adb shell getprop ro.boot.verifiedbootstate       # orange = odblokowany, green = zablokowany
adb shell getprop ro.boot.vbmeta.device_state     # unlocked
```

Reboot i ponowny odczyt — orange musi przetrwać restart. Jeśli po restarcie wraca green,
oznacza to zapis tylko w `vbmeta`, a nie w trwałym state-partycji, i każda próba flashowania
czegoś niepodpisanego wywali weryfikację przy starcie.

## 5. Bezpieczeństwo — do zrobienia przed pierwszą kompilacją

W historii czatów (tej przeklejonej) pojawiły się **dwa tokeny Hugging Face w jawnej
postaci**: jeden write i jego następca read. Oba powinny trafić do kosza bez względu na
to, czy uważasz je za bezpieczne — zostały zapisane w transkrypcie, pobranej jako strona
i wklejonej do nowego czatu, czyli łącznie w co najmniej trzech miejscach, z których żadne
nie jest sejfem na sekrety.

Procedura:

1. Unieważnij **oba** tokeny w HF → Settings → Access Tokens.
2. Utwórz jeden token **Read**, fine-grained, tylko do repo `BBB1239/Lenovo-Tab-P11-Gen-2-HyperOS-4`.
3. Wpisz go w GitHub: `Settings → Secrets and variables → Actions → New repository secret`,
   nazwa `HF_TOKEN`. **Nie wklejaj go do czatu.**
4. Jeśli workflow ma wysyłać wynik do HF — osobny token **Write** jako `HF_WRITE_TOKEN`.
   Startowo zbędny: artifact/Release wystarczą do testów.
5. Zasadą w tym repo jest to, że token istnieje wyłącznie jako sekret. Żaden skrypt ani
   commit nigdy nie ma go w treści — sprawdzam to przed każdym pushem.

## 6. Czego potrzebuję, żeby pisać workflow

Bez tego napiszę skrypty „na ślepo”, które się nie odpalą:

- [ ] dokładny model i codename: Lenovo Tab P11 Gen 2 → `tb330fu`? `tb330xp`? (od tego zależy
      `super.img` layout i konfiguracja dynamicznych partycji)
- [ ] lista plików, które już wyciągnąłeś (nazwy + rozmiary) z obu ROM-ów
- [ ] format źródłowy: `payload.bin` (fastboot OTA) czy osobne obrazy partycji, czy paczka
      z `super.img`
- [ ] sloty: A/B czy A-only (HyperOS na MediaTeku bywa A-only z `snapshot`)
- [ ] czy AVB ma zostać: `vbmeta` patchowany offline, czy odtwarzany z kluczami testowymi
- [ ] czy odblokowany bootloader + rodzaj blokady (MediaTek: `auth` / preloader; Qualcomm: nie dotyczy)

Te sześć punktów decyduje o ~80% poprawności całego przedsięwzięcia. Reszta to
rzemiosło do napisania.
