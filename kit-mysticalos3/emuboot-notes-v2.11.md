# emuboot v2.11 - plan i wnioski

## Kontekst (z v2.10, run 38015844455)
- NOP-patch property FATAL-i (0x12337c/0x12339c) dziala: init przechodzi
  PropertyInit, dochodzi do post-fs, startuja uslugi (vold, atrace) -
  RDZEN PORTU DZIALA.
- vold abortuje: "DM_DEV_STATUS failed for system / could not find logical
  partition system" -> reboot,vold-failed. Przyczyna: brak super w harnessie
  (vold checkpoint szuka logicznej partycji system), NIE property.
- Kontrola natywna pada wczesniej: realpath /dev/block/by-name/super -
  top-level by-name pod surowym qemu jest racy (TCG). Kontrola w tej formie
  porzucona.

## v2.11
- mksuper.py (format liblp): super.img z logiczna partycja 'system'
  linear-mappingujaca caly nasz obraz. Zwiazane checksumi SHA256, geometry
  x2, metadata slot x2, extent linear, grupa default, blockdevice super.
- Uklad dyskow: vda=metadata(raw), vdb=vendor-mod(GPT by-name), vdc=data,
  vdd=GPT super (nazwa partycji super, OSTATNI dysk - jak vendor-vdc kiedy
  by-name dzialal niezawodnie).
- fstab: system LOGICAL (jak natywnie); vendor by-name platform; metadata
  vda; data vdc.
- Faza 1: BOOT 1:1 bez patchy (z super!). Faza 2 (gdy 1:1 padlo): NOP-patch
  property FATAL-i + przebudowa super + drugi boot - vold teraz ma logical
  system, wiec lancuch pojedzie dalej (zygote?).

## v2.12 (run 38027234483) - WNIOSKI
- boot_devices=a003c00 NIE wystarczyl: nadal realpath /dev/block/by-name/super.
- Dowod analizy: brak linii "partition(s) not found: super" = urzadzenie super
  (vdd1) ZOSTALO znalezione przez BlockDevInitializer (match po PARTNAME),
  ale symlink top-level by-name/super nie powstal bo is_boot_device=false.
- PRAWDA: qemu virt przydziela transporty virtio-mmio TOP-DOWN:
  1.=-a003e00, 2.=a003c00, 3.=a003a00, 4.=a003800, 5.(net)=a003600.
  Dowod wlasny: w ukladzie v2.6-v2.10 vendor byl 2. dyskiem i fstab
  platform/a003c00.virtio_mmio/by-name/vendor DZIALAL. W v2.12 super jest
  4. dyskiem = a003800.virtio_mmio.
  (To samo tlumaczy pad kontroli natywnej v2.9/v2.10 - by-name/super.)

## v2.13
- cmdline: androidboot.boot_devices=a003e00,c00,a00,800 (wszystkie 4 transporty
  dyskow; GetBootDevices robi Split po przecinku). Niezawodne niezaleznie od
  kolejnosci dyskow.
- raport: sekcja "wczesna konsola" (Kernel command line + by-name/mapper)
  jako dowod dzialania fixu.

## v2.13 (run 38031846094) - WNIOSKI
- boot_devices (4 transporty) DZIALA: by-name/super powstal, realpath OK,
  init przeszedl InitDevices (kolejny kamien milowy).
- PADA PONIZEJ: "Invalid ext4 superblock on /dev/block/vda" + "[liblp]
  incompatible version" + "invalid magic" + "Could not read logical
  partition metadata from /dev/block/vda1".
- ROZSZYFROWANE (liblp utility.cpp + reader.cpp):
  1) LITERY DYSKOW: kernel probuje virtio-mmio ASC (a003800,c00,a00,e00) =
     ODWROTNIE do kolejnosci qemu. Dowod: vda=super (4. dysk qemu) przy
     fstab metadata=/dev/block/vda -> fs_mgr probowal ext4 na GPT super.
     (To samo bylo zawsze: system=vdd=1. dysk qemu, meta=vda=4. dysk.)
  2) MKSUPER MIAL 2 BUGI vs liblp: (a) major_version musi byc 10
     (LP_METADATA_MAJOR_VERSION), nie 1 -> "incompatible version";
     (b) layout: [0..4095]=RESERVED, geometry@4096 i @8192, metadata@12288
     i backup@16384, content@20480 - mksuper pisal geometry@0, meta@8192,
     content@16384. Stad dokladnie ta pare bledow: primary@12288 trafil w
     moj backup blob (v1), backup@16384 trafil w POCZATEK system.img
     (ext4 magic) -> "invalid magic value". Bajt w bajt.

## v2.14
- mksuper.py przepisany wg liblp (reserved+geometry@4096+meta v10.0@12288+
  content@20480); lokalna walidacja per reader.cpp (offsety, checksumi,
  wersja, deskryptory, zawartosc, backupy) - PASS.
- kolejnosc qemu: super,vendor,userdata,meta -> litery: vda=meta, vdb=data,
  vdc=vendor, vdd=super. fstab: data=/dev/block/vdb (bylo vdc), metadata
  /dev/block/vda bez zmian, vendor by-name a003c00 bez zmian (nadal 2. dysk).
- oczekiwanie: FirstStage czyta metadata v10 z super, zaklada dm-linear
  system, montuje /system -> po raz pierwszy obraz z PRAWDZIWEGO super;
  potem PropertyInit (spodziewamy sie FATAL property = punktu wyjscia v2.10).

## v2.14 (run 38044076369) - WNIOSKI
- KOLEJNY KAMIEN MILowy: /metadata zamontowany na vda (litery potwierdzone:
  vda=meta, vdb=data, vdc=vendor, vdd=super), liblp czyta super, magic+wersja
  OK -> pada na "Logical partition metadata has invalid checksum" (x2).
- PRZYCZYNA (reader.cpp ReadMetadataHeader): header_checksum = SHA256(header
  z wyzerowanym TYLKO header_checksum; tables_checksum zostaje WPISANY).
  Mksuper liczyl z oboma wyzerowanymi -> zla checksuma. (Lokalny test mial
  ten sam blad logiczny, wiec przechodzil - fix testu tez.)

## v2.15
- mksuper.py: poprawna kolejnosc - najpierw wpisz tables_checksum, potem
  header_checksum = SHA256(header z header_checksum=0). Lokalna walidacja
  w stylu readera (zero tylko header_checksum) - PASS.
- Oczekiwanie: ParseMetadata przejdzie -> CreateLogicalPartitions (dm-linear
  system) -> mount /system z PRAWDZIWEGO super -> PropertyInit.

## v2.15 (run 38048370740) - PRZELOM
- mksuper checksum OK: "Created logical partition system on device /dev/block/dm-0"
  + "__mount(dm-0 -> /system) = 0: Success" - NASZ OBRAZ Z PRAWDZIWEGO SUPER!
- FAZA 1 (1:1, BEZ PATCHY): PropertyInit PRZESZED (init.cpp:887 PropertyInit
  przed SelabelInitialize/LoadPolicy; konsola pokazuje juz "Opening SELinux
  policy" = property OK; zero "Failed to initialize property area").
  Czyli FATAL property z v2.10 byl ARTEFAKTEM starego harnessu (raw vdd).
- Init utkal na "Compiling SELinux policy" (plat_sepolicy nabu vs precompiled
  vendor emulatora -> mismatch -> secilc w locie; pod TCG > 30 min; system
  zywy - ext4lazyinit w tle).
- FAZA 2 (NOP): petle rebootu (bez property area uslugi padaja) - zgodne z
  teoria; NOP juz niepotrzebny.

## v2.16
- faza 1: selinux=0 w cmdline (kernel wylacza SELinux -> init pomija kompilacje
  polityki; harness-only, obraz 1:1) -> szybka droga do uslug/zygote/adb.
- faza 2: naturalny boot (androidboot.selinux=permissive, bez selinux=0),
  100 min na secilc - tablet-realistyczny (na tablecie tez kompiluje w locie
  po wymianie systemu: precompiled vendora Lenovo pasuje do plat Lenova).
- NOP-patch usuniety z workflow (po co skoro property dziala 1:1).

## v2.16 (run 38053021041) - WNIOSKI
- FAZA 2 (naturalna, bez patchy): polityka SELinux skompilowana w ~9 s pod
  TCG (nie 100 min!), ZALADOWANA, "init second stage started!" ->
  "Failed to initialize property area" (PropertyInit+1968 w /system/bin/init)
  -> InitFatalReboot -> petla. CZYSTY REPRO root cause 1:1 z super/dm-linear.
- selinux=0 (faza 1) = ZLY pomysl: wisil load bez selinuxfs.
- Odczyt v2.15 "PropertyInit przeszedl" byl ARTEFAKTEM tail-200 (FATAL lecial
  w kazdej petli). Nalezy zawsze liczyc counts z PELNEJ konsoli.

## v2.17 - FORENSYKA + FIX-TEST (hipoteza property_contexts)
- Mechanizm (bionic): area_init tworzy plik dla kazdego kontekstu i robi
  fsetxattr(security.selinux, u:object_r:TYP:s0); TYP nieobecny w polityce
  -> EINVAL -> area_init -1 -> FATAL. Polityka w harness = nasz plat (nabu/
  Lenovo) + vendor ranchu -> typy z transplantu moga byc nieznane.
- Nowy tool tools/propctx.py (stdlib; check/fix): porownuje typy z
  *_property_contexts z deklaracjami (type ...) w plat_sepolicy.cil +
  vendor_sepolicy.cil; fix przepisuje nieznane na default_prop.
- Workflow: forensyka check na zywych obrazach -> raport; faza 1 naturalna
  (30 min, counts z pelnej konsoli); faza 2 = fix + przebudowa super +
  naturalny boot (45 min, counts). Run_qemu/build_super jako funkcje
  (limit 21k znakow kroku).

## v2.19 (run 38075295558) - KOLEJNY PRZELOM
- System ZYWY 49 min, BOOTLOOPS_F2=1, PROPERTY_FATAL_F2=0: vold OK, core OK,
  surfaceflinger/audioserver/camera startuja (crash-loop updatable_crashing -
  expected: nasz system + HAL ranchu). init czysto przechodzi caly boot.
- BRAK ZYGOTE: obraz nie ma /system/etc/init/hw/init.zygote64.rc
  (v2.15: 'Unable to read config file'; v2.19: 'service zygote not found' x N
  + onrestart surfaceflingera). Bez zygote nie ma frameworku/SystemUI/
  boot_completed. To brak W OBRZIE (port/DSU build), nie harness!
- Bug debugfs: 'write ... fstab.ranchu' zapisal do /fstab.ranchu (root
  partycji) zamiast /etc/fstab.ranchu; przy okazji vold bez fstab
  'continuing anyways' (LineageOS main.cpp:122) - dlatego przezyl.
- restorecon 'Could not read default fstab' = nieszkodliwy szum (init/
  builtins.cpp) - zniknie z fstabem na miejscu.

## v2.20
- fix sciezki: debugfs write ... etc/fstab.ranchu (przetestowane lokalnie).
- ZYGOTE FIX: tools/init.zygote64.rc (kanoniczny AOSP A13) kopiowany do
  obrazu w fazie 2 + ro.zygote=zygote64 w build.prop (grep -q || append).
- raport: grep zygot/apexd/Unable/class_start z PELNEJ konsoli fazy 2.

## v2.20 (run 38081844818) - WNIOSKI
- Property OK w OBU fazach (FATAL=0) - fix contexts dziala; nieznane dlaczego
  F1 tez przeszlo (moze wiazac z fstab vendora; do wyjasnienia).
- NOWY REBOOT REASON: 'reboot,bootloader,bootstrap-apexd-failed':
  apexd --bootstrap exit 1 po 'Failed to collect APEX keys : Can't open
  /system_ext/apex for reading : Permission denied' (+ pre-allocate loop
  devices EACCES).
- v2.19 (bez /etc/fstab.ranchu w vendorze): apexd przechodzil, system zywy
  49 min. v2.20 (fstab vendora obecny, nasza treść): apexd pada.
  => fstab vendora wycofany w v2.21 (rm bez write).
- ciekawostka: first stage tworzy logical product (dm-2)/system_ext (dm-3)
  z super w OBU runach (zrodlo: multi-cpio ramdisk emulatora ma 2. fstab z
  logical product/system_ext - wylapany przy unpack; nasz fstab-mod to
  pierwszy cpio).

## v2.21 = v2.19 + ZYGOTE FIX
- vendor: tylko rm fstab.ranchu (bez nadpisywania)
- obraz: init.zygote64.rc (kanoniczny AOSP) + ro.zygote=zygote64 (faza 2)
- oczekiwanie: apexd OK (jak v2.19) + zygote startuje -> app_process ->
  system_server -> framework -> adb/boot_completed
