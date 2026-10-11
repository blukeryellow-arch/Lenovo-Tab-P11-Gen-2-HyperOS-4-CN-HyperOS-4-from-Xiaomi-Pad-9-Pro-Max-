# MISMATCH - co ta paczka otwiera, a czego NIE naprawia

Zmierzono na plikach z Dysku (nie z dokumentacji):
  source: HyperOS 4 / Android 17, ro.build.version.sdk=37, security_patch 2026-08-01
  w zrodlowym system.img macierze VINTF: POZIOMY 7, 8 i datowane; 4/5/6 BYLY NIEOBECNE
  - wygenerowano je tu (tools/make_level_matrix.py). Bramka init ('Failed to
    initialize VINTF') przez to OTWARTA.
  wymagania w najnizszej macierzy zrodla: 84 pozycji HAL, w tym 0 HIDL i 83 AIDL.
  Vendor targetu (Lenovo TB350FU, epoka A12) te AIDL-e (audio.core, health, power,
  thermal, dumpstate, gatekeeper, ...) NIE ISTNIEJA w jego manifestcie - po
  otwarciu bramki uslugi, ktore ich czekaja, beda crashe. ROM FLASHUJE i MONTUJE
  SI; czy dojdzie do pulpitu - tego Z TENEGO SANDBOKSA nie sprawdz (brak urzadzenia).

  vbmeta targetu opisuje hashtree: product 2 748 350 464 B, system_ext 744 968 192 B;
  zrodlowy product.img ma 6 445 187 072 B, system_ext.img 632 840 192 B. Zaden podpis
  tego nie uzupelni - stad flags=3 (wylaczona weryfikacja/verity) zamiast 'zielonego' boot.
  Klucze Lenovo (9d808b09.. boot, fa41159a.. vbmeta_system, 9577bc6c.. vbmeta_vendor)
  sa w OEM-owym HSM - nie do odtworzenia, wiec '100% flashable' ponizej oznacza
  'przejdzie fastboot i zamontuje', nie 'AVB zielony'.

## Zeby zawezic liste brakow (nalezy wykonac na urzadzeniu)
  scripts/collect_device_state.sh   - pobiera m.in. /vendor/etc/vintf; wowczas
                                      rebuild oznacza optional TYLKO realne braki
  fastboot getvar all > getvar.txt  - rozmiary partycji (czy product 6,45 GB wogole
                                      sie zmiesci na jego UFS 2.2 w tym reflashu)
