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
