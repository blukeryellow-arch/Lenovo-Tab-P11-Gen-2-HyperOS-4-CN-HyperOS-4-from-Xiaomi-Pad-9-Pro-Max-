# donor-pipeline run 37015010433 (2026-10-02T14:22:57Z)

## probe
```
brak donor-product w cache - bedzie Drive
probe [drive.usercontent.google.com] -> 206 CR='bytes 0-0/10340028849' body0=b'P'
speed 1-watkowo (32 MiB): 16.45 MB/s
Filesystem      Size  Used Avail Use% Mounted on
/dev/root       145G   59G   86G  41% /
```
## ekstrakcja (tail 100)
```
# probe: status=206 CR='bytes 0-0/10340028849' CL='1' AR='bytes' CT='application/octet-stream' body0=b'P'
# manifest: block_size=4096, partycji=42
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
pokrycie partycji: 1580012 / 1580012 blokow (100.0%)
  [  0.1%] op 1/3086, 7 MiB / 5341 MiB, 6.68 MB/s, ETA 13.3 min
  [  2.8%] op 92/3086, 149 MiB / 5341 MiB, 4.73 MB/s, ETA 18.3 min
# range 2679103232-2681182703 retry 1/6: krotki range: chciano 2079472, dostano 2009
# range 2683272436-2684941615 retry 1/6: krotki range: chciano 1669180, dostano 2009
# range 2681182704-2683272435 retry 1/6: krotki range: chciano 2089732, dostano 2009
# range 2679103232-2681182703 retry 2/6: krotki range: chciano 2079472, dostano 2009
# range 2681182704-2683272435 retry 2/6: krotki range: chciano 2089732, dostano 2009
# range 2683272436-2684941615 retry 2/6: krotki range: chciano 1669180, dostano 2009
# range 2679103232-2681182703 retry 3/6: krotki range: chciano 2079472, dostano 2009
# range 2681182704-2683272435 retry 3/6: krotki range: chciano 2089732, dostano 2009
# range 2683272436-2684941615 retry 3/6: krotki range: chciano 1669180, dostano 2009
# range 2679103232-2681182703 retry 4/6: krotki range: chciano 2079472, dostano 2009
# range 2681182704-2683272435 retry 4/6: krotki range: chciano 2089732, dostano 2009
# range 2683272436-2684941615 retry 4/6: krotki range: chciano 1669180, dostano 2009
# range 2679103232-2681182703 retry 5/6: krotki range: chciano 2079472, dostano 2009
# range 2681182704-2683272435 retry 5/6: krotki range: chciano 2089732, dostano 2009
# range 2683272436-2684941615 retry 5/6: krotki range: chciano 1669180, dostano 2009
# range 2679103232-2681182703 retry 6/6: krotki range: chciano 2079472, dostano 2009
# range 2681182704-2683272435 retry 6/6: krotki range: chciano 2089732, dostano 2009
# range 2683272436-2684941615 retry 6/6: krotki range: chciano 1669180, dostano 2009
range 2679103232-2681182703 padl po 6 probach: krotki range: chciano 2079472, dostano 2009
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
/dev/root       145G   59G   86G  41% /
```
