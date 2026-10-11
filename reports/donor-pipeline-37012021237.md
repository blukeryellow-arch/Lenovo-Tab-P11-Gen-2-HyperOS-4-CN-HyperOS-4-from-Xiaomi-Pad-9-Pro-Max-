# donor-pipeline run 37012021237 (2026-10-02T13:37:38Z)

## probe
```
brak donor-product w cache - bedzie Drive
probe [drive.usercontent.google.com] -> 206 CR='bytes 0-0/10340028849' body0=b'P'
speed 1-watkowo (32 MiB): 18.15 MB/s
Filesystem      Size  Used Avail Use% Mounted on
/dev/root       145G   59G   86G  41% /
```
## ekstrakcja (tail 100)
```
#   partycja adsp           new_size=15732736     ops=8     (pole 8, sha256 na 8)
#   partycja android_esp    new_size=8388608      ops=4     (pole 8, sha256 na 4)
#   partycja bl2            new_size=217088       ops=1     (pole 8, sha256 na 1)
#   partycja bl31           new_size=282624       ops=1     (pole 8, sha256 na 1)
#   partycja boot           new_size=100663296    ops=48    (pole 8, sha256 na 48)
#   partycja boot_logo      new_size=6291456      ops=3     (pole 8, sha256 na 3)
#   partycja ddr_param0     new_size=5722112      ops=3     (pole 8, sha256 na 3)
#   partycja ddr_param1     new_size=1167360      ops=1     (pole 8, sha256 na 1)
#   partycja ddr_param3     new_size=2301952      ops=2     (pole 8, sha256 na 2)
#   partycja ddr_param5     new_size=798720       ops=1     (pole 8, sha256 na 1)
#   partycja dtbo           new_size=25165824     ops=12    (pole 8, sha256 na 12)
#   partycja exaid          new_size=157286400    ops=75    (pole 8, sha256 na 75)
#   partycja hdcp           new_size=229376       ops=1     (pole 8, sha256 na 1)
#   partycja init_boot      new_size=16777216     ops=8     (pole 8, sha256 na 8)
#   partycja isp            new_size=8712192      ops=5     (pole 8, sha256 na 5)
#   partycja lpctrl         new_size=593920       ops=1     (pole 8, sha256 na 1)
#   partycja npu            new_size=704512       ops=1     (pole 8, sha256 na 1)
#   partycja odm            new_size=3096166400   ops=1477  (pole 8, sha256 na 1477)
#   partycja odm_dlkm       new_size=348160       ops=1     (pole 8, sha256 na 1)
#   partycja product        new_size=6471729152   ops=3086  (pole 8, sha256 na 3086)
#     pola len-delim w product: [(8, 3086), (17, 1)]
#   partycja pvmfw          new_size=1048576      ops=1     (pole 8, sha256 na 1)
#   partycja sec_dtbo       new_size=139264       ops=1     (pole 8, sha256 na 1)
#   partycja sensorhub      new_size=3948544      ops=2     (pole 8, sha256 na 2)
#   partycja system         new_size=937852928    ops=448   (pole 8, sha256 na 448)
#     pola len-delim w system: [(8, 448), (3, 1), (17, 1)]
#   partycja system_dlkm    new_size=27082752     ops=13    (pole 8, sha256 na 13)
#   partycja system_ext     new_size=631791616    ops=302   (pole 8, sha256 na 302)
#   partycja tee            new_size=5148672      ops=3     (pole 8, sha256 na 3)
#   partycja uefi           new_size=2101248      ops=2     (pole 8, sha256 na 2)
#   partycja vbmeta         new_size=12288        ops=1     (pole 8, sha256 na 1)
#   partycja vbmeta_system  new_size=4096         ops=1     (pole 8, sha256 na 1)
#   partycja vbmeta_vendor  new_size=8192         ops=1     (pole 8, sha256 na 1)
#   partycja vendor         new_size=676741120    ops=323   (pole 8, sha256 na 323)
#     pola len-delim w vendor: [(8, 323), (17, 1)]
#   partycja vendor_boot    new_size=205520896    ops=98    (pole 8, sha256 na 98)
#   partycja vendor_dlkm    new_size=40067072     ops=20    (pole 8, sha256 na 20)
#   partycja xctrl_cpu      new_size=204800       ops=1     (pole 8, sha256 na 1)
#   partycja xctrl_ddr      new_size=86016        ops=1     (pole 8, sha256 na 1)
#   partycja xloader        new_size=733184       ops=1     (pole 8, sha256 na 1)
#   partycja xrse           new_size=421888       ops=1     (pole 8, sha256 na 1)
#   partycja xspm           new_size=995328       ops=1     (pole 8, sha256 na 1)
#   partycja xsps           new_size=1007616      ops=1     (pole 8, sha256 na 1)
#   partycja mi_product     new_size=348160       ops=1     (pole 8, sha256 na 1)
#   partycja mi_ext         new_size=528691200    ops=253   (pole 8, sha256 na 253)
zrodlo: HTTP https://drive.usercontent.google.com/download?id=1wkAkQyd-68oPB_x35BGvqIlzQ0BLffdd&export=download&confirm=t
  size=10340028849 accept-ranges=bytes
  zip64: cd_off=10340026542 cd_size=551
  wpis payload.bin: STORED, 10340019806 B @+5370
naglowek payload (hex, 32B): 43724155000000000000000200000000000577230000010b188020208deaaac2
payload: version=2 manifest=358179B meta_sig=267B, bloby od 358470
partycja product: 3086 op (REPLACE x525, REPLACE_BZ x103, REPLACE_XZ x2458), do pobrania 5600112314 B (5.22 GiB), new_size=6471729152
  [  0.1%] op 1/3086, 5 MiB / 5341 MiB, 5.77 MB/s, ETA 15.4 min
  [  2.5%] op 83/3086, 133 MiB / 5341 MiB, 4.26 MB/s, ETA 20.4 min
  [  4.9%] op 169/3086, 264 MiB / 5341 MiB, 4.29 MB/s, ETA 19.7 min
  [  7.1%] op 248/3086, 379 MiB / 5341 MiB, 4.13 MB/s, ETA 20.0 min
  [  9.3%] op 330/3086, 497 MiB / 5341 MiB, 4.07 MB/s, ETA 19.8 min
  [ 11.8%] op 406/3086, 628 MiB / 5341 MiB, 4.10 MB/s, ETA 19.1 min
  [ 13.9%] op 487/3086, 743 MiB / 5341 MiB, 4.04 MB/s, ETA 19.0 min
  [ 15.8%] op 564/3086, 842 MiB / 5341 MiB, 3.93 MB/s, ETA 19.1 min
# range 3402896344-3404984767 retry 1/6: HTTPError: HTTP Error 503: Service Unavailable
  [ 18.2%] op 635/3086, 970 MiB / 5341 MiB, 3.96 MB/s, ETA 18.4 min
  [ 20.8%] op 719/3086, 1111 MiB / 5341 MiB, 4.04 MB/s, ETA 17.4 min
  [ 24.0%] op 805/3086, 1281 MiB / 5341 MiB, 4.19 MB/s, ETA 16.1 min
# range 3893976412-3896073563 retry 1/6: HTTPError: HTTP Error 503: Service Unavailable
  [ 27.0%] op 888/3086, 1444 MiB / 5341 MiB, 4.30 MB/s, ETA 15.1 min
  [ 30.3%] op 977/3086, 1619 MiB / 5341 MiB, 4.42 MB/s, ETA 14.0 min
# range 4229763140-4231858643 retry 1/6: HTTPError: HTTP Error 503: Service Unavailable
  [ 32.8%] op 1052/3086, 1754 MiB / 5341 MiB, 4.43 MB/s, ETA 13.5 min
  [ 35.5%] op 1136/3086, 1895 MiB / 5341 MiB, 4.45 MB/s, ETA 12.9 min
  [ 38.1%] op 1222/3086, 2036 MiB / 5341 MiB, 4.46 MB/s, ETA 12.3 min
  [ 40.6%] op 1303/3086, 2168 MiB / 5341 MiB, 4.46 MB/s, ETA 11.9 min
# range 4778669199-4779966662 retry 1/6: HTTPError: HTTP Error 503: Service Unavailable
  [ 43.1%] op 1381/3086, 2303 MiB / 5341 MiB, 4.46 MB/s, ETA 11.4 min
  [ 46.1%] op 1470/3086, 2460 MiB / 5341 MiB, 4.50 MB/s, ETA 10.7 min
# range 5156288479-5158367254 retry 1/6: HTTPError: HTTP Error 503: Service Unavailable
  [ 48.9%] op 1551/3086, 2611 MiB / 5341 MiB, 4.52 MB/s, ETA 10.1 min
  [ 51.7%] op 1633/3086, 2760 MiB / 5341 MiB, 4.54 MB/s, ETA 9.5 min
  [ 54.8%] op 1719/3086, 2925 MiB / 5341 MiB, 4.58 MB/s, ETA 8.8 min
  [ 58.1%] op 1809/3086, 3103 MiB / 5341 MiB, 4.64 MB/s, ETA 8.0 min
  [ 61.1%] op 1894/3086, 3265 MiB / 5341 MiB, 4.67 MB/s, ETA 7.4 min
  [ 64.2%] op 1979/3086, 3430 MiB / 5341 MiB, 4.71 MB/s, ETA 6.8 min
# range 6090839050-6092878265 retry 1/6: HTTPError: HTTP Error 503: Service Unavailable
  [ 67.2%] op 2056/3086, 3587 MiB / 5341 MiB, 4.71 MB/s, ETA 6.2 min
  [ 70.2%] op 2143/3086, 3751 MiB / 5341 MiB, 4.74 MB/s, ETA 5.6 min
  [ 72.7%] op 2224/3086, 3881 MiB / 5341 MiB, 4.73 MB/s, ETA 5.1 min
  [ 75.2%] op 2298/3086, 4014 MiB / 5341 MiB, 4.71 MB/s, ETA 4.7 min
  [ 77.9%] op 2379/3086, 4160 MiB / 5341 MiB, 4.72 MB/s, ETA 4.2 min
  [ 80.9%] op 2463/3086, 4319 MiB / 5341 MiB, 4.74 MB/s, ETA 3.6 min
  [ 83.3%] op 2539/3086, 4447 MiB / 5341 MiB, 4.72 MB/s, ETA 3.2 min
  [ 85.5%] op 2625/3086, 4568 MiB / 5341 MiB, 4.70 MB/s, ETA 2.7 min
  [ 88.0%] op 2705/3086, 4702 MiB / 5341 MiB, 4.69 MB/s, ETA 2.3 min
  [ 90.8%] op 2792/3086, 4849 MiB / 5341 MiB, 4.69 MB/s, ETA 1.7 min
  [ 93.2%] op 2877/3086, 4978 MiB / 5341 MiB, 4.68 MB/s, ETA 1.3 min
  [ 95.9%] op 2960/3086, 5119 MiB / 5341 MiB, 4.68 MB/s, ETA 0.8 min
  [ 98.7%] op 3041/3086, 5272 MiB / 5341 MiB, 4.69 MB/s, ETA 0.2 min
  [100.0%] op 3086/3086, 5342 MiB / 5341 MiB, 4.69 MB/s, ETA -0.0 min
gotowe: /tmp/donor/product.img = 6471729152 B (oczek. 6471729152) w 19.1 min; requestow HTTP: 3092
new_partition_info.hash (do weryfikacji zewnetrznej): 743a28088080fb8d181220107e58d61380327ab9aa7914856d2c0cadc2511329
erofs-check: magic e2e1f5e0 @1024 OK
```
## harvest (tail 120)
```
```
## manifesty
```
```
## dysk
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/root       145G   65G   80G  45% /
```
