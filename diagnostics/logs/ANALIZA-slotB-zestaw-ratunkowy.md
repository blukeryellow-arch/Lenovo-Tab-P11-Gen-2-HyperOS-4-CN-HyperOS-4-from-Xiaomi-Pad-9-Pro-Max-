# ANALIZA: slot _b nieaktualny - dowod z zestawu ratunkowego usera (28 IX)

Zrodlo: Drive, folder TB350FU_USER_S231044_2601050946_MP_ROW/image/ (stock ROW S231044 =
dokladnie firmware hosta z bugreportow). Pobrane do google_drive/ (niecommitowane, .gitignore):
boot.img (64 MB, header v4, kernel gzip 19 652 970 B), vendor_boot.img, lk.img, vbmeta.img,
super_empty.img, MT6789_Android_scatter.x.

## RECEIPT 1 (decydujacy): kernel fabryczny vs kernel paniki
- boot.img (stock, rozpakowany gzip): Linux version 5.10.233-android12-9-00062-g49c66df526b8-ab13101360
  (SDK ab13101360; identyczny z kernelem, na ktorym host zdrowieje na slocie _a - bugreporty
  27 IX + docs/04).
- pstore (2x, bugreport 17:36 i 19:24): paniki biegly na 5.10.177-android12-9-00002-g593c61caffd9-ab10731447
  (starszy SDK ab10731447) = slot _b.
=> JEDYNY fabryczny kernel tego firmware'u to 5.10.233. Kernel 5.10.177 na _b = pozostalosc
   po starszej OTA. SLOT _b = NIEAKTUALNY: stary boot + stary vendor (stary wlan driver z
   bugiem suspend = sygnatura panik). Stock na _b zamiera; gość DSU na _b dostaje stary
   vendor -> biale ekrany. Teoria usera POTWIERDZONA i doprecyzowana do poziomu bajtow.

## RECEIPT 2: wybór slotu zyje w bootloaderze LK, przed kernelem
strings lk.img: "[LK_AB] Get slot-retry-count:a/b fail", "[LK_AB] set to slot %d",
"[LK_AB] open misc fail", "[LK_AB] unknown slot suffix", AVB_SLOT_VERIFY_* (LK robi
AVB slot verify). => Decyzja o slocie + fallback + retry-count = LK + partycja misc,
DWIE WARSTWY ponizej system.img. Zadny patch w obrazie goscia tego nie zmieni
(androidboot.slot_suffix przychodzi z cmdline; fstab z slotselect zyje w vendor_boot
hosta - 4 trafienia "slotselect" w vendor_boot.img).

## RECEIPT 3: geometria A/B
super_empty.img (liblp): main_a/main_b, system_a/b, vendor_a/b, product_a/b,
system_ext_a/b, vendor_dlkm_a/b, odm_dlkm_a/b - pelny uklad A/B.
vbmeta stock: algo=1 (SHA256_RSA), rollback=4960, flags=0 (weryfikacja wlaczona
w stocku - logiczne, nasz wydaniowy vbmeta ma Flags=3).

## WNIOSKI OPERACYJNE
1. "Hard-code SLOT A w servicemanager/init/binder" - BRAK SUBSTRATU (decyzja w LK+misc,
   przed kernelem; binder bez routingu slotowego; fstab w vendor_boot hosta).
2. REALNE pinowanie _a: fastboot --set-active=a (metoda usera, dziala) albo host-side
   bootctl; opcja ostateczna: SPFT flash pelnego zestawu (user go MA) przywraca spojnosc
   obu slotow.
3. v12 (wifi-guard) usuwa zrodlo panik wlan na starym slocie = zrodlo rotacji slotow;
   markery arena_v12 zaloguja slot_suffix w kazdym logu.
4. v13 NIE jest budowany: brak realnej zmiany obrazu = rotacja kodu (zakaz usera).
