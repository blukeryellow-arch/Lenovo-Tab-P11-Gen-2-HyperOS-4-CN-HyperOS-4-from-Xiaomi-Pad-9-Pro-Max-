# MysticalOS GSI-1 - karta poranna (29 IX, 4:55 czasu PL)

## CO MASY GOTOWE TERAZ (build GREEN, wydany 28 IX 17:26 UTC)

### Linki glowne (gofile - trwale):
| plik | link | weryfikacja |
|---|---|---|
| MysticalOS_GSI1.tar.gz (1,38 GB) | https://gofile.io/d/BGovoMDl | gofile potwierdza plik 1.4 GB |
| MysticalOS_GSI1.zip (1,38 GB) | https://gofile.io/d/6Nd6Ztwa | gofile potwierdza plik 1.4 GB |

- Mirrory transferarch (R3sjS / 10dmn0) wygasly po TTL ~4 h - nie uzywac.
- Release GitHub (prywatny): **mysticalos-gsi-1** - tgz + zip + RAW system.img
  (sha256 RAW: ac6ac1bf8e27177a4943ff6bab143075c77698c465ab8b74d8942dc58e2deca1).

### Co jest w srodku (wersja 1 - bez apk MIUI):
- oficjalny Google AOSP Android 17 GSI (QPR2-beta CP41.260831.007, sha256 Google = pin),
- PURGE GMS (audyt: 0 pakietow Google - czysty AOSP),
- microG GmsCore v0.3.16.252432 + FakeStore (priv-app; uprawnienia lokalizacji
  i powiadomien nadane out-of-the-box),
- Aurora Store 4.8.4 (preload),
- 25 fontow Mi donora (HyperOS),
- konteksty SELinux WYPIECZNE w obraz (mkfs.erofs --file-contexts; ENFORCING-safe),
- launcher: AOSP Launcher3 (fallback - bez apk MIUI).

### Instalacja (DSU, jak zwykle):
1. Pobierz zip/tgz, rozpakuj -> mysticalos_gsi1_system.img.
2. DSU Sideloader -> wskaz obraz, slot bez znaczenia.
3. Pierwszy boot dluzszy (odex). Revert = reboot bez DSU.
4. Gosc dostaje product/system_ext/vendor hosta (Lenovo A14) - nakladki Lenovo
   w overlayach to normalne na GSI.

## STATUS NOCNY: wersja 2 (z MiuiHome/Gallery/Music/FileManager) - NIE UKONCZONA

- Run 36474547084 (Tier 2: stream oficjalnego fastboot ROM yingtian 12,6 GB z CDN
  Xiaomi) zakonczyl sie o 21:26 UTC TIMEOUTEM - stream biegł 85+ min przy ~2,5 MB/s
  (pierwszy mirror z brzegu) i nie zmiescil sie w budzecie 100 min.
- Przygotowane fixy (commity lokalne, gotowe do pushu):
  - a271b10: timeout 100 -> 180 min,
  - 57abd4e: wybor NAJSZYBSZEGO mirrora CDN (pomiar 10 MB + sort) - skraca stream,
  - bd9bc19: dokumentacja nocna PROGRESS.
- BLOKADA: token GitHub w sandboxie padl drugi raz o ~21:26 UTC i nie wrocil do
  02:55 UTC (poll co ~5 min przez cala noc). Bez tokenu nie moge pushnac fixow ani
  odpalic runu - to polaczenie platformowe, nie repo.
- JEDNA AKCJA RANO: napisz cokolwiek (np. "push") - sesja odswiezy token, ja
  od razu: push a271b10+57abd4e -> run (60-100 min) -> linki wersji 2 z pelnym
  interfejsem HyperOS (MiuiHome + MiuiGallery + MiuiMusic + MiuiFileManager +
  fonty Mi). PR #2 (branch -> main) jest otwarty i kompletny.

## Rejestr runow MysticalOS GSI-1
| run | wynik | uwagi |
|---|---|---|
| 36467193303 | FAIL | 404 URL GSI (stary wzorzec sciezki) |
| 36468238008 | FAIL | sondy 9x 404 (diagnoza) |
| 36469032983 | FAIL | resolver HTML OK; invalid UUID w mkfs.erofs |
| 36469639937 | **GREEN** | wersja 1 WYDANA (linki wyzej) |
| 36472295147 | CANCELLED | zastapiony retriggerem (timeout fix) |
| 36474547084 | FAIL (timeout) | Tier 2 stream 85+ min; fixy lokalne gotowe |
