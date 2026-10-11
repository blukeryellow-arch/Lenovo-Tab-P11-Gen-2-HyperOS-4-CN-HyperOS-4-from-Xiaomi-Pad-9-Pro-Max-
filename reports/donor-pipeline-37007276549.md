# donor-pipeline run 37007276549 (2026-10-02T12:34:14Z)

## probe
```
probe [drive.usercontent.google.com] -> 206 Content-Range=bytes 0-0/10340028849 (1.0s)
speed 1-watkowo (32 MiB): 18.07 MB/s
Filesystem      Size  Used Avail Use% Mounted on
/dev/root       145G   59G   86G  41% /
```
## ekstrakcja (tail 100)
```
zrodlo: HTTP https://drive.usercontent.google.com/download?id=1wkAkQyd-68oPB_x35BGvqIlzQ0BLffdd&export=download&confirm=t
  size=10340028849 accept-ranges=bytes
  zip64: cd_off=10340026542 cd_size=551
  wpis payload.bin: STORED, 10340019806 B @+5370
payload: version=0 manifest=8589934592B meta_sig=0B, bloby od 8589934608
Traceback (most recent call last):
  File "/home/runner/work/Lenovo-Tab-P11-Gen-2-HyperOS-4-CN-HyperOS-4-from-Xiaomi-Pad-9-Pro-Max-/Lenovo-Tab-P11-Gen-2-HyperOS-4-CN-HyperOS-4-from-Xiaomi-Pad-9-Pro-Max-/tools/payload_extract.py", line 631, in <module>
    main()
  File "/home/runner/work/Lenovo-Tab-P11-Gen-2-HyperOS-4-CN-HyperOS-4-from-Xiaomi-Pad-9-Pro-Max-/Lenovo-Tab-P11-Gen-2-HyperOS-4-CN-HyperOS-4-from-Xiaomi-Pad-9-Pro-Max-/tools/payload_extract.py", line 487, in main
    block_size, partitions = parse_manifest(manifest)
                             ^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/runner/work/Lenovo-Tab-P11-Gen-2-HyperOS-4-CN-HyperOS-4-from-Xiaomi-Pad-9-Pro-Max-/Lenovo-Tab-P11-Gen-2-HyperOS-4-CN-HyperOS-4-from-Xiaomi-Pad-9-Pro-Max-/tools/payload_extract.py", line 203, in parse_manifest
    for f, wt, v in iter_fields(buf):
  File "/home/runner/work/Lenovo-Tab-P11-Gen-2-HyperOS-4-CN-HyperOS-4-from-Xiaomi-Pad-9-Pro-Max-/Lenovo-Tab-P11-Gen-2-HyperOS-4-CN-HyperOS-4-from-Xiaomi-Pad-9-Pro-Max-/tools/payload_extract.py", line 110, in iter_fields
    raise ValueError("wire_type %d nieobslugiwany" % wt)
ValueError: wire_type 7 nieobslugiwany
```
## harvest (tail 100)
```
```
## manifest
```
```
## dysk
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/root       145G   59G   86G  41% /
```
