# MysticalOS GSI-1 - dostawa (28 IX, 21:55 czasu PL)

## GOTOWE TERAZ - linki zweryfikowane zywe (run 36469639937, GREEN)

| plik | link | status |
|---|---|---|
| MysticalOS_GSI1.tar.gz (1,38 GB) | https://gofile.io/d/BGovoMDl | ZYWY (gofile: 1.4 GB) |
| MysticalOS_GSI1.zip (1,38 GB) | https://gofile.io/d/6Nd6Ztwa | ZYWY (gofile: 1.4 GB) |
| tar.gz (mirror) | https://transfer.archivete.am/R3sjS/HyperOS4_P11Gen2.zip | probe 200 (TTL ~4 h!) |
| zip (mirror) | https://transfer.archivete.am/10dmn0/HyperOS4_P11Gen2.zip | probe 200 (TTL ~4 h!) |

- Release GitHub (prywatny): mysticalos-gsi-1 (tgz+zip+RAW system.img).
- RAW system sha256: ac6ac1bf8e27177a4943ff6bab143075c77698c465ab8b74d8942dc58e2deca1
- Zawartosc: oficjalny AOSP Android 17 GSI (QPR2-beta, CP41.260831.007, sha Google)
  + PURGE GMS (audyt: 0) + microG GmsCore/FakeStore (priv-app, uprawnienia
  out-of-the-box) + Aurora Store 4.8.4 preload + fonty Mi (25) + KONTEKsty
  SELinux wypieczone w obraz (ENFORCING safe).
- Bez apk MIUI (product.img zniknal z Drive) - Launcher3 AOSP = launcher.

## Instalacja (DSU, jak zawsze)
1. DSU Sideloader -> MysticalOS_GSI1 (zip albo tgz po rozpakowaniu:
   mysticalos_gsi1_system.img), slot bez znaczenia.
2. Pierwszy boot dluzszy (odex). Revert = reboot bez DSU.
3. Gosc dostaje product/system_ext/vendor HOSTA (Lenovo A14) - nakladki Lenovo
   w overlayach to normalne zachowanie GSI.

## W TOKU - pelny transplant MIUI (Tier 2, run 36474547084)
- Zrodlo (znalezione po wskazaniu miuirom.org): oficjalny fastboot ROM CN
  yingtian HyperOS 4.0.11.0.XBMCNXM z CDN Xiaomi - w srodku PELNY product.img
  z MiuiHome/MiuiGallery/MiuiMusic/MiuiFileManager. Stream 12,6 GB (bez zapisu
  tgz), md5 tgz = pin.
- Nie zdazy do 22:00 (stream sam trwa 15-40 min + ~20 min buildu). Bot CI SAM
  commituje raport z linkami po zakonczeniu: reports/mystical1-links-<runid>.md
  + odswieza release mysticalos-gsi-1. Timeout budzetu: 100 min.
- Wersja z transplantem = ten sam GSI + microG + Aurora + MiuiHome itd.
  (kompromis udokumentowany: apk MIUI budowane pod framework MIUI - na AOSP
  moga padac; Launcher3 zostaje fallbackiem).
