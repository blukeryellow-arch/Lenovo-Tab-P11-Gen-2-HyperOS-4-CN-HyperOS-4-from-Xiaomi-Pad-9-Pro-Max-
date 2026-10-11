# Dwa zestawy sum — to nie przypadek

- `SHA256SUMS.runner.txt` — sumy policzone na runnerze w biegu `35897100768`; opisują
  zawartość `images/rom-kit.tar.gz`. W tym zestawie `flash.sh` ma 25 linii, bo bieg
  startował z `fcf056d`, a wersja ze slotami weszła w `52f06bd` — czyli **po** starcie.
- `SHA256SUMS.git.txt` — sumy tego, co realnie leży w gicie (zregenerowana kopia
  `flash.sh` 84 linie, vbmeta, MISMATCH).

Różnica nie jest kosmetyczna: wersja 25-liniowa wbijała `vbmeta` tylko na slot `a`; przy
`current-slot: b` urządzenie weryfikuje `vbmeta_b`, więc flashowanie kończy się „OK", a
tablet nie wstaje i nie mówi dlaczego.

Sekwencję sprawdzałem na atrapie `fastboot` (loguje argumenty, udaje `current-slot: b`):

    fetch vbmeta_a vbmeta_obecna_a.img
    fetch vbmeta_b vbmeta_obecna_b.img
    getvar is-userspace            # -> yes, więc partycje w super są dostępne
    flash vbmeta_a / flash vbmeta_b
    flash system_a / flash system_b
    reboot

rc skryptu 0. To dowód na poprawność **sekwencji i slotów**, nie na bootalność.

Własny błąd tej sesji, żeby się nie powtórzył: po podmianie `flash.sh` nie przeliczyłem
`SHA256SUMS.git.txt` i `sha256sum -c` mówiło FAILED na pliku będącym w porządku — czyli
sama zasada „sumy liczone na końcu", którą opisałem dla `build_rom_on_runner.sh`, złamana
godzinę później gdzie indziej. Reguła: liczenie sum jest ostatnią operacją pakowania.
