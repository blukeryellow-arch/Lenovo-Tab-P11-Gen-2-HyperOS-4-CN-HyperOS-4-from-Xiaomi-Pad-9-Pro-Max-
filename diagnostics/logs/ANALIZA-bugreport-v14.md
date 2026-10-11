# ANALIZA bugreport_v14 (28 IX 15:20 lokalnego) -> v15 WHITE-SCREEN FIX

Zrodlo: `bugreport_v14.zip` (Drive, id `1BAF4jsuQmhB9SA06_XdUpRiwT3ZE5yY-`,
4 547 298 B, sha256 `c664f57ed9db1d14b8f5ffebb9b68ae601928d3d2c89b168b0dbbec7e8079f11`).
Bugreport hosta: `TB350FU_EEA-UP1A.231005.007-2026-09-28-15-20-24.txt` (420 670 linii).

## 1. Oś czasu 28 IX (CEST, z shutdown-checkpoints + dropbox + boot.reason.history)

| czas | zdarzenie | dowód |
|---|---|---|
| 14:30:53 | kernel start, boot hosta (reason `cold,powerkey`) | SYSTEM_BOOT 14:31:06, 661 B |
| 14:36:28 | **reboot `dynsystem`** (start sesji DSU v14, pid 3343 `com.android.dynsystem:dynsystem`) | checkpoints-1790598988917 |
| 14:37:19 | kernel start (reason `kernel_panic` = STICKY flaga AEE po wczorajszej śmierci, patrz §2) | boot.reason.history |
| 14:37:31 | **boot GOŚCIA v14** | SYSTEM_BOOT 14:37:31, 664 B |
| 14:37–15:19 | **gość żyje 42,8 min** — ZERO tombstonów, ZERO wpisów dropbox, brak shutdown-checkpointów | sekcje DROPBOX/TOMBSTONES |
| 15:19:20 | **grzeczny revert `dynsystem`** (pid 3330, z wnętrza gościa — framework żywy!) | checkpoints-1790601560693 |
| 15:20:12 | kernel start (reason `kernel_panic` — sticky) | boot.reason.history |
| 15:20:24 | boot hosta + bugreport (fingerprint Lenovo, slot **_a**, kernel 5.10.233) | nagłówek |

`meminfo_2026-09-28-14_36_05.txt` w FS = dumpstate usera o 14:36 (przed startem DSU).

## 2. Pstore: BAJT W BAJT identyczny z bugreport_v10

`console-ramoops-0` (3099 linii, uptime okna 16516–16530 s) — diff vs
`diagnostics/logs/bugreport-v10_pstore-lastkmsg.txt` = **0 różnic treści** (różni się
tylko stopka "was the duration"). Wniosek podwójny:

1. **dzisiejsze śmierci NIE przeszły przez ścieżkę paniki kernela z konsolą** —
   `kernel_panic` w boot.reason.history obu bootów (14:37:19, 15:20:12) to sticky
   flaga AEE po wczorajszej panice wlan/bt (persist.vendor.aeev.last.boot.reason=
   kernel_panic; pierwszy boot dnia = cold,powerkey = flaga skasowana, wróciła po
   warm rebootach — timing ~50 s od reboot-request do kernel start to normalny
   czas graceful shutdown+LK, nie crash),
2. **sticky radio-off z v14 DZIAŁA**: gość v14 przeżył 42 min bez paniki wlan/bt,
   która zabijała v10-v12 (ta sama pętla, ten sam sprzęt).

## 3. Biały ekran = klasa render, nie kernel i nie crash

42 min żywego frameworku (system_server odpowiada, dynsystem obsłużył revert po 42 min,
adb działa), zero tombstonów, zero dropbox. Ekran martwy przy żywym systemie.

## 4. Mechanizm (dowody lshal hosta + readelf/strings na donorze)

**Architektura DSU: gość = system XIAOMI + product/system_ext/vendor LENOVO A14**
(wydajemy wyłącznie partycję system — patrz komentarz "product build.prop matrix"
w release-v15.yml i MISMATCH.md).

Vendor Lenovo (z bugreportu: tabela hwbinder + lshal-debug + SF dump hosta):
- composer: **HIDL 2.1 / 2.2 / 2.3** (pid 750, `composer@2.3-service`) + rozszerzenia
  `vendor.mediatek.hardware.composer_ext@1.0` (HIDL) i `.composer_ext.IComposerExt` (AIDL),
- allocator: **AIDL 4.0-mediatek** (pid 749); mapper 2.0/2.1/3.0/4.0 (libki vndk-sp),
- **ZERO composer3 AIDL**; keymint HIDL 1.0 (beanpod, pid 572) — działa na hoście,
  keystore2 hosta zyje (logi keystore2 w bugreporcie).

SF HyperOS (readelf NEEDED na `system_tree/system/bin/surfaceflinger`, 61 libek):
- linkuje klienty **composer@2.1/2.2/2.3/2.4 (HIDL)** + composer3-V5-ndk + stub
  `vendor.xring.hardware.display.composerext-V1-ndk.so` (w system/lib64 ✓) —
  czyli warstwa composera jest oszczędzona (HIDL 2.3 vendora mówi tym samym protokołem),
- ALE: **11 NEEDED nieobecnych w partycji system donora**, w tym load-bearing:
  `libsurfaceflinger.so` (10,3 MB w lib/ donora!), `libsurfaceflinger_common_shared.so`,
  `libfolme.so`, `libmisight.so`, `composer@2.1-2.4.so` — Xiaomi trzyma je w **system_ext**
  (pozostałe 3 to libc/libm/libdl z APEX runtime — nie-brak).

Na gościu linker SF szuka ich w system_ext/**Lenovo A14** (złe ABI — A14 vs A17/Xring)
albo nic nie znajduje -> SF nie wstaje -> **biały ekran bez crashu** (zgadza się z §3:
process exit z błędu linkera nie zostawia tombstone'a).

Dlaczego AOSP 16 GSI działa (testimonium usera, niezweryfikowane u nas): czysty GSI
nie ma własnościowych zależności Xiaomi i ładuje się z libkami A14 z partycji hosta.

## 5. FIX 12 (v15): vendorowanie libek SF z system_ext donora

- zrodlo: `system_ext.img` donora (Pad 9 Pro Max) **z transfer-spool** (czesci
  `drive-13e-okLFNX3m7feTp8AlYoGME2rKFFitr.img.part.0000-0006`), oracle:
  sha256 `7340a8367d3da8e4bdcf56a0f53dd7b77d87f81389d08b2a7e9e449fc02a5385`
  + md5 Google `f879747f3f7ebb5eb026eddeb02f8d13` (te same bajty co na Dysku),
- 16 plikow (8 libek x lib64+lib) do `/system/{lib,lib64}` — default namespace
  przeszukuje /system/lib64 PRZED /system_ext, wiec nasze libki wygrywaja z A14,
- domkniecie zaleznosci (readelf, iteracyjnie): **czysto** — jedyne NEEDED spoza
  /system/{lib,lib64} to libc/libm/libdl (APEX runtime); sprawdzane offline na
  donorze i bramkowane na zywo w CI (FIX 12, krok "domkniecie"),
- manifest z sha256 w obrazie: `/system/etc/arena-v15-sflibs.txt`.

Libki (sha256 lib64 | lib):
- libsurfaceflinger.so 8fdf4dfa2a53a8cc… | ad479a98095df218…
- libsurfaceflinger_common_shared.so 38756875e40c9c4a… | 6f13bdee0e844238…
- libfolme.so e7ad8ae3faee7317… | 5dd6e747672ef637…
- libmisight.so 6526d1d9074370c2… | 3d9d019d7defa087…
- composer@2.1.so 92509be6ea43a178… | fcf9ee3b3fa50b01…
- composer@2.2.so c22b947cc0a1af51… | d5db2e58c778066f…
- composer@2.3.so f075e71cf8996ca6… | 5ee8ea488610be8c…
- composer@2.4.so 502f1d79c291e71e… | 0ae1e075a6703a78…

## 6. FIX 13 (v15): czarna skrzynka (naprawa instrumentacji v6)

Dwa receipty na to, ze obecna instrumentacja byla NOP-em:
- `ro.logd.persistent=true` / `persist.logd.persistent=true` — **nie istnieja w logd**
  (poprawny mechanizm to serwis `logcatd` wlaczany `logd.logpersistd=true`; Xiaomi
  zreszta usunal logcatd.rc z systemu — donor ma tylko logd.rc). Dowod nopu:
  LAST LOGCAT w bugreport_v14 pochodzi z **11-03** (stare events).
- `log -t arena_diag` w arena_diag.rc — `log` to nie builtin inita; w wczesnym init
  /system nie jest zamontowany -> "command not found" (to samo, co user zglosil x7
  w arena_v14_slotb.sh).

Naprawa w v15: markery przez `write /dev/kmsg` (9 faz, w tym
`init.svc.surfaceflinger=running`/`restarting` i zygote) + wlasny serwis
`arena_logcatd` (`logcat -b all -f /data/misc/logd/logcat -r 1024 -n 24`, user logd,
start na post-fs-data): /data/misc/logd to DE (zyje przed unlock), **wspolne dla
hosta i goscia DSU i przezywa revert** — po wroceniu na hosta `adb bugreport`
zawiera log goscia; rowniez `adb logcat -d` z zywego goscia.

## 7. Odmowy (receiptowe, wg zasad usera)

- **wrappery servicemanager/hwservicemanager**: framework goscia wstal i zyl 42 min
  (dynsystem obsluzyl revert) — zero dowodow na blokade binder/HAL; binarne wrappery
  bez zrodel = rotacja w ciemno. NIE robie.
- **patch keystore2 (super_key.rs/security_level.rs)**: bez zrodel; keymint HIDL 1.0
  (beanpod) zyje na vendorze; bialy ekran poprzedza jakikolwiek unlock/ECDH. NIE robie
  (do rewizji dopiero, gdy logi goscia pokaza ECDH jako blokade UI — czarna skrzynka
  v15 to rozstrzygnie).
- **binarny patch SF "ignoruj vendor extensions"**: vendoring libek (FIX 12) to
  rozwiazanie bez-zrodlowe dla rzeczywistej, udokumentowanej luki (brak libek),
  a nie dla domniemanych rozszerzen.

## 8. Test v15 (protokol dla usera)

1. DSU Sideloader -> v15 (bez `--set-active`), slot bez znaczenia (v14 pstore: sciezka
   paniki wlan/bt martwa na obu).
2. Ekran ZYJE -> raport + (radia: na _a wlaczysz recznie; na _b sa martwe celowo).
3. Ekran BIALY -> `adb wait-for-device shell getprop ro.product.brand` (Xiaomi = gosc)
   -> `adb logcat -d > ws-v15.log` -> Drive. Po revercie na hosta dodatkowo
   `adb bugreport` (zip zawiera /data/misc/logd/logcat* = log goscia) -> Drive.
4. Hard reset/panika -> bugreport hosta (pstore) jak dotychczas.
