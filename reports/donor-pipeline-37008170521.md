# donor-pipeline run 37008170521 (2026-10-02T13:04:31Z)

## probe
```
probe [drive.usercontent.google.com] -> 206 Content-Range=bytes 0-0/10340028849 (1.1s)
speed 1-watkowo (32 MiB): 14.00 MB/s
Filesystem      Size  Used Avail Use% Mounted on
/dev/root       145G   59G   86G  41% /
```
## ekstrakcja (tail 100)
```
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
  [  0.1%] op 1/3086, 7 MiB / 5341 MiB, 5.12 MB/s, ETA 17.4 min
  [  2.2%] op 73/3086, 118 MiB / 5341 MiB, 3.61 MB/s, ETA 24.1 min
  [  4.2%] op 141/3086, 223 MiB / 5341 MiB, 3.55 MB/s, ETA 24.0 min
  [  6.1%] op 212/3086, 327 MiB / 5341 MiB, 3.51 MB/s, ETA 23.8 min
  [  8.0%] op 285/3086, 428 MiB / 5341 MiB, 3.46 MB/s, ETA 23.7 min
  [ 10.0%] op 354/3086, 535 MiB / 5341 MiB, 3.47 MB/s, ETA 23.1 min
  [ 12.3%] op 425/3086, 657 MiB / 5341 MiB, 3.57 MB/s, ETA 21.9 min
  [ 14.1%] op 496/3086, 754 MiB / 5341 MiB, 3.52 MB/s, ETA 21.7 min
  [ 15.8%] op 564/3086, 842 MiB / 5341 MiB, 3.45 MB/s, ETA 21.7 min
  [ 18.1%] op 632/3086, 966 MiB / 5341 MiB, 3.52 MB/s, ETA 20.7 min
  [ 20.2%] op 697/3086, 1078 MiB / 5341 MiB, 3.53 MB/s, ETA 20.1 min
  [ 22.4%] op 765/3086, 1197 MiB / 5341 MiB, 3.57 MB/s, ETA 19.3 min
  [ 25.2%] op 838/3086, 1345 MiB / 5341 MiB, 3.68 MB/s, ETA 18.1 min
  [ 27.8%] op 908/3086, 1484 MiB / 5341 MiB, 3.75 MB/s, ETA 17.1 min
  [ 30.5%] op 981/3086, 1627 MiB / 5341 MiB, 3.82 MB/s, ETA 16.2 min
  [ 32.8%] op 1050/3086, 1752 MiB / 5341 MiB, 3.84 MB/s, ETA 15.6 min
  [ 35.2%] op 1123/3086, 1879 MiB / 5341 MiB, 3.86 MB/s, ETA 14.9 min
  [ 37.4%] op 1194/3086, 1996 MiB / 5341 MiB, 3.86 MB/s, ETA 14.4 min
  [ 39.6%] op 1267/3086, 2116 MiB / 5341 MiB, 3.86 MB/s, ETA 13.9 min
  [ 41.8%] op 1339/3086, 2230 MiB / 5341 MiB, 3.86 MB/s, ETA 13.4 min
  [ 43.6%] op 1399/3086, 2327 MiB / 5341 MiB, 3.82 MB/s, ETA 13.1 min
  [ 45.9%] op 1466/3086, 2454 MiB / 5341 MiB, 3.84 MB/s, ETA 12.5 min
  [ 47.8%] op 1520/3086, 2553 MiB / 5341 MiB, 3.81 MB/s, ETA 12.2 min
  [ 50.4%] op 1591/3086, 2690 MiB / 5341 MiB, 3.84 MB/s, ETA 11.5 min
  [ 52.5%] op 1655/3086, 2803 MiB / 5341 MiB, 3.83 MB/s, ETA 11.0 min
  [ 54.9%] op 1723/3086, 2933 MiB / 5341 MiB, 3.85 MB/s, ETA 10.4 min
  [ 57.6%] op 1795/3086, 3075 MiB / 5341 MiB, 3.88 MB/s, ETA 9.7 min
  [ 60.2%] op 1868/3086, 3216 MiB / 5341 MiB, 3.91 MB/s, ETA 9.1 min
  [ 62.8%] op 1940/3086, 3352 MiB / 5341 MiB, 3.93 MB/s, ETA 8.4 min
  [ 65.5%] op 2013/3086, 3500 MiB / 5341 MiB, 3.96 MB/s, ETA 7.7 min
# range 6197063418-6199046349 retry 1/6: HTTPError: HTTP Error 500: Internal Server Error
  [ 66.3%] op 2033/3086, 3541 MiB / 5341 MiB, 3.83 MB/s, ETA 7.8 min
  [ 68.9%] op 2105/3086, 3681 MiB / 5341 MiB, 3.85 MB/s, ETA 7.2 min
  [ 71.4%] op 2176/3086, 3811 MiB / 5341 MiB, 3.86 MB/s, ETA 6.6 min
  [ 73.4%] op 2246/3086, 3920 MiB / 5341 MiB, 3.85 MB/s, ETA 6.1 min
  [ 75.7%] op 2318/3086, 4042 MiB / 5341 MiB, 3.86 MB/s, ETA 5.6 min
  [ 78.3%] op 2388/3086, 4179 MiB / 5341 MiB, 3.88 MB/s, ETA 5.0 min
  [ 80.7%] op 2459/3086, 4311 MiB / 5341 MiB, 3.89 MB/s, ETA 4.4 min
  [ 83.0%] op 2531/3086, 4434 MiB / 5341 MiB, 3.89 MB/s, ETA 3.9 min
  [ 85.0%] op 2601/3086, 4537 MiB / 5341 MiB, 3.88 MB/s, ETA 3.5 min
  [ 87.1%] op 2674/3086, 4649 MiB / 5341 MiB, 3.87 MB/s, ETA 3.0 min
  [ 89.2%] op 2746/3086, 4766 MiB / 5341 MiB, 3.87 MB/s, ETA 2.5 min
  [ 91.6%] op 2820/3086, 4891 MiB / 5341 MiB, 3.88 MB/s, ETA 1.9 min
  [ 93.6%] op 2887/3086, 4996 MiB / 5341 MiB, 3.87 MB/s, ETA 1.5 min
  [ 95.8%] op 2957/3086, 5115 MiB / 5341 MiB, 3.87 MB/s, ETA 1.0 min
  [ 98.3%] op 3030/3086, 5250 MiB / 5341 MiB, 3.88 MB/s, ETA 0.4 min
  [100.0%] op 3086/3086, 5342 MiB / 5341 MiB, 3.89 MB/s, ETA -0.0 min
gotowe: /tmp/donor/product.img = 6471729152 B (oczek. 6471729152) w 23.0 min; requestow HTTP: 3092
new_partition_info.hash (do weryfikacji zewnetrznej): 743a28088080fb8d181220107e58d61380327ab9aa7914856d2c0cadc2511329
erofs-check: magic e2e1f5e0 @1024 OK
```
## harvest (tail 100)
```
harvest: loop-mount erofs OK (P=/tmp/donor/mnt)
== zawartosc product (ls) ==
apex
app
bin
data-app
etc
fonts
framework
lib
lib64
media
opcust
overlay
pangu
prebuilts
priv-app
usr
```
## manifest
```
```
## dysk
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/root       145G   65G   80G  45% /
```
