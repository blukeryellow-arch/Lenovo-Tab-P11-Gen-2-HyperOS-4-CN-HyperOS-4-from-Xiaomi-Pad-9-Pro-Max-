### MysticalOS 3 (super.img TB350FU) links (run 36738400196)
release: mysticalos-3-super
transplant: TIER C: brak .ttf w assets.tar.gz
purge product/system_ext: 

--- gofile (2 tary: kit-A czastki+flash, kit-B czastki+vbmeta) ---
(brak)
--- manifest stream_lpunpack (baza) ---
# liblp v10.2; slots=3; bdev=super (9663676416 B); grupy=['default', 'main_a', 'main_b']
# glowy=1310720 B; segmenty: [('odm_dlkm', 1048576, 1396736), ('product', 2097152, 2794594304), ('system', 2795503616, 6474297344), ('system_ext', 6659506176, 7416504320), ('vendor', 7416578048, 8333131776), ('vendor_dlkm', 8334082048, 8365445120)]; only=['system']
P	odm_dlkm	348160
P	product	2792497152
P	system	3678793728
P	system_ext	756998144
P	vendor	916553728
P	vendor_dlkm	31363072
W	odm_dlkm	0	348160	SKIP
W	product	0	2792497152	SKIP
W	system	3678793728	3678793728	OK
W	system_ext	0	756998144	SKIP
W	vendor	0	916553728	SKIP
W	vendor_dlkm	0	31363072	SKIP
--- sondy URL ---
(brak)
--- manifest ---
(brak)
--- geometria fabryczna ---
== GEOMETRY ==
  magic: 0x616c4467
  struct_size: 52
  metadata_max_size: 65536
  metadata_slot_count: 3
  logical_block_size: 4096
== BLOCK DEVICES ==
  super: size=9663676416 (9.664 GB) align=1048576 flags=0x0
== GROUPS ==
  default: max_size=0 (0.000 GB) flags=0x0
  main_a: max_size=9661579264 (9.662 GB) flags=0x0
  main_b: max_size=9661579264 (9.662 GB) flags=0x0
== PARTITIONS ==
  odm_dlkm_a: group=main_a attrs=0x1 extents=0
  odm_dlkm_b: group=main_b attrs=0x1 extents=0
  product_a: group=main_a attrs=0x1 extents=0
  product_b: group=main_b attrs=0x1 extents=0
  system_a: group=main_a attrs=0x1 extents=0
  system_b: group=main_b attrs=0x1 extents=0
  system_ext_a: group=main_a attrs=0x1 extents=0
  system_ext_b: group=main_b attrs=0x1 extents=0
  vendor_a: group=main_a attrs=0x1 extents=0
  vendor_b: group=main_b attrs=0x1 extents=0
  vendor_dlkm_a: group=main_a attrs=0x1 extents=0
  vendor_dlkm_b: group=main_b attrs=0x1 extents=0
--- metadane bazowego super ---
(brak)
--- geometria zbudowana ---
(brak)
--- purge GMS ---
/tmp/m3/tree/system/app/CaptivePortalLoginGoogle
/tmp/m3/tree/system/app/GooglePrintRecommendationService
/tmp/m3/tree/system/app/GoogleExtShared
/tmp/m3/tree/system/priv-app/ZUISetupWizardExtROW
/tmp/m3/tree/system/priv-app/GooglePackageInstaller
/tmp/m3/tree/system/priv-app/DocumentsUIGoogle
/tmp/m3/tree/system/priv-app/TagGoogle
/tmp/m3/tree/system/priv-app/NetworkStackGoogle
