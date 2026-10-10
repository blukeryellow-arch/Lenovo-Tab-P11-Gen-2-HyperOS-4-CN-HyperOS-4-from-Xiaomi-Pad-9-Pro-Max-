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
