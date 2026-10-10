# HyperOS 4 — Lenovo Tab P11 Gen 2 (TB350FU): system + vbmeta

Port z Xiaomi Pad 9 Pro Max (donor HyperOS 4.0.x CN, kod `yingtian`).
Zestaw minimalny: JEDEN plik `system` w formacie sparse (konwencja fabrycznych
paczek fastboot) + surowy `vbmeta` — bez części, bez base64.

| plik | rozmiar | sha256 |
|---|---|---|
| system_hyperos4_p11g2.img | 920 039 464 B | 8b71ea568dfb6043cfb3234372b3b672c30f9dfb2e81d11ed1bbae89e98dc14f |
| vbmeta_hyperos4_p11g2.img | 4 096 B | 9cf2e7e4e165687abe78fb0f084e2b07707c317376efd5d4ffbdea75537e6141 |

Po rozpakowaniu z sparse (unsparse) system ma sha256
`4836dcd4c8d5f6c0f9a6adbde94c65917e70ac1b054bd7acc05705ec9f66b816` —
sprawdzisz to skryptem `sprawdz.sh`.

## Flashowanie (fastboot, sloty a/b)

    sha256sum -c SHA256SUMS.txt        # najpierw sumy
    fastboot flash vbmeta_a  vbmeta_hyperos4_p11g2.img
    fastboot flash vbmeta_b  vbmeta_hyperos4_p11g2.img
    fastboot flash system_a  system_hyperos4_p11g2.img
    fastboot flash system_b  system_hyperos4_p11g2.img
    fastboot reboot

vbmeta ma Flags=3 (wyłączona weryfikacja AVB). Flashuj oba sloty.

## Uczciwe szanse

To eksperyment portowy, nie oficjalne wydanie. Init Linuxa ~85% (kernel GKI
5.10.233 android12, EROFS lz4hc, miękka macierz VINTF poziomu 5), system_server
~50–60%, pulpit ~10–25%. Realne ryzyka: apexd Androida 17, usługi `critical`
(pętla restartów). Diagnostyka po flashu: `tools/postflash_triage.sh log.txt`
(w repo).
