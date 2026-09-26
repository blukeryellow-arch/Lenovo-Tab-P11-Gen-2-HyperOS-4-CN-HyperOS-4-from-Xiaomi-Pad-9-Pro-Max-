# Full Xiaomi yingtian HyperOS recovery audit

- requested source: Xiaomi Pad 9 Pro Max (yingtian), China Recovery, OS4.0.11.0.XBMCNXM
- source class: third-party catalogue link supplied by the user; the archive is independently inspected before use
- scope: extract and audit only the Xiaomi `system` payload; no Lenovo image is overwritten or copied

## Archive identity
```
input/miui_YINGTIAN_OS4.0.11.0.XBMCNXM_recovery.zip 10313202368 B
7b8c7f002abfeebae302961b73030984e5a065ec9f9e73976c0cc818349c8cce  input/miui_YINGTIAN_OS4.0.11.0.XBMCNXM_recovery.zip
input/miui_YINGTIAN_OS4.0.11.0.XBMCNXM_recovery.zip: Java archive data (JAR)
```

## Recovery metadata and payload inventory
```
--- META-INF/com/android/metadata ---
ota-property-files=payload_metadata.bin:5370:357833,payload.bin:5370:10313193325,payload_properties.txt:10313198753:157,apex_info.pb:2476:1640,care_map.pb:4163:1140,metadata:69:733,metadata.pb:870:1558                          
ota-required-cache=0
ota-streaming-property-files=payload.bin:5370:10313193325,payload_properties.txt:10313198753:157,apex_info.pb:2476:1640,care_map.pb:4163:1140,metadata:69:733,metadata.pb:870:1558                            
ota-type=AB
post-build=Xiaomi/yingtian/yingtian:17/CP2A.260605.016/17OS4.0.260916.103155210.XRPDCN.S:user/release-keys
post-build-incremental=17OS4.0.260916.103155210.XRPDCN.S
post-sdk-level=37
post-security-patch-level=2026-08-01
post-timestamp=1789532207
pre-device=yingtian
--- payload_properties.txt ---
FILE_HASH=MP5jF21QGrPwhY01AgU3BLFc+7Ip0FrPyZwH/1NptNM=
FILE_SIZE=10313193325
METADATA_HASH=05QmF5Ca0Nv+DbumRtuRPZJsG4Yu3m8noyN6WY67j1w=
METADATA_SIZE=357566
--- selected archive members ---
META-INF/com/android/metadata
META-INF/com/android/metadata.pb
payload.bin
```

## Extracted exact system payload
```
work/recovery/extracted/system.img 937791488 B
4d3c61fe358f78102f5cae7bdaacc9f7a5d5d3c726d881dbc0ee3dcc697ee462  work/recovery/extracted/system.img
work/recovery/extracted/system.img: EROFS filesystem, compat: SB_CHKSUM MTIME, blocksize=12, exslots=0, uuid=02926FD9-7A7A-4453-91DC-8B6A86C28C1D, incompat: LZ4_0PADDING
```
