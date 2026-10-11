### MysticalOS 3 (super.img TB350FU) links (run 36941869814)
release: mysticalos-3-super
transplant: OK (TIER C; fonty z assets.tar.gz product.img Xiaomi: 25)
purge product/system_ext: PURGED_product=1 PURGED_system_ext=1 

--- gofile (2 tary: kit-A czastki+flash, kit-B czastki+vbmeta) ---
(brak)
--- manifest stream_lpunpack (baza) ---
# liblp v10.2; slots=3; bdev=super (9663676416 B); grupy=['default', 'main_a', 'main_b']
# glowy=1310720 B; segmenty: [('odm_dlkm', 1048576, 1396736), ('product', 2097152, 2794594304), ('system', 2795503616, 6474297344), ('system_ext', 6659506176, 7416504320), ('vendor', 7416578048, 8333131776), ('vendor_dlkm', 8334082048, 8365445120)]; only=['system_ext']
P	odm_dlkm	348160
P	product	2792497152
P	system	3678793728
P	system_ext	756998144
P	vendor	916553728
P	vendor_dlkm	31363072
W	odm_dlkm	0	348160	SKIP
W	product	0	2792497152	SKIP
W	system	0	3678793728	SKIP
W	system_ext	756998144	756998144	OK
W	vendor	0	916553728	SKIP
W	vendor_dlkm	0	31363072	SKIP
--- sondy URL ---
(brak)
--- manifest ---
parts=32
chunk=179306496
size_sparse=5727894460
sha256_sparse_zlozony=260fdc8fe0df5e7844d53af8d2a818673a73f4351fb3d975a10e01998915d634
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
== PARTITIONS ==
  system_a: group=main_a attrs=0x1 extents=1
  system_ext_a: group=main_a attrs=0x1 extents=1
  product_a: group=main_a attrs=0x1 extents=1
  vendor_a: group=main_a attrs=0x1 extents=1
  vendor_dlkm_a: group=main_a attrs=0x1 extents=1
  odm_dlkm_a: group=main_a attrs=0x1 extents=1
== EXTENTS (sumy sektorow na partycje) ==
  system_a: 2955898880 B (2.956 GB)
  system_ext_a: 447930368 B (0.448 GB)
  product_a: 1380327424 B (1.380 GB)
  vendor_a: 916553728 B (0.917 GB)
  vendor_dlkm_a: 31363072 B (0.031 GB)
  odm_dlkm_a: 348160 B (0.000 GB)
--- purge GMS ---
/tmp/m3/tree/system/app/CaptivePortalLoginGoogle
/tmp/m3/tree/system/app/GooglePrintRecommendationService
/tmp/m3/tree/system/app/GoogleExtShared
/tmp/m3/tree/system/priv-app/ZUISetupWizardExtROW
/tmp/m3/tree/system/priv-app/GooglePackageInstaller
/tmp/m3/tree/system/priv-app/DocumentsUIGoogle
/tmp/m3/tree/system/priv-app/TagGoogle
/tmp/m3/tree/system/priv-app/NetworkStackGoogle
/tmp/m3/tree/product/app/GoogleLocationHistory
/tmp/m3/tree/product/app/CalendarGoogle
/tmp/m3/tree/product/app/CalculatorGoogle
/tmp/m3/tree/product/app/LatinImeGoogle
/tmp/m3/tree/product/app/SpeechServicesByGoogle
/tmp/m3/tree/product/app/com.google.mainline.adservices
/tmp/m3/tree/product/app/com.google.android.modulemetadata
/tmp/m3/tree/product/app/YTMSetupWizard
/tmp/m3/tree/product/app/DeskClockGoogle
/tmp/m3/tree/product/app/com.google.mainline.telemetry
/tmp/m3/tree/product/app/WebViewGoogle
/tmp/m3/tree/product/app/GoogleContacts
/tmp/m3/tree/product/priv-app/ConfigUpdater
/tmp/m3/tree/product/priv-app/GoogleOneTimeInitializer
/tmp/m3/tree/product/priv-app/Phonesky
/tmp/m3/tree/product/priv-app/GooglePartnerSetup
/tmp/m3/tree/product/priv-app/HotwordEnrollmentOKGoogleRISCV
/tmp/m3/tree/product/priv-app/GoogleRestore
/tmp/m3/tree/product/priv-app/GoogleKidsSpace
/tmp/m3/tree/product/priv-app/FilesGoogle
/tmp/m3/tree/product/priv-app/HotwordEnrollmentXGoogleRISCV
/tmp/m3/tree/product/priv-app/GmsCore
/tmp/m3/tree/system_ext/priv-app/GoogleFeedback
/tmp/m3/tree/system_ext/priv-app/EmergencyInfoGms
/tmp/m3/tree/system_ext/priv-app/SetupWizard
/tmp/m3/tree/system_ext/priv-app/GoogleServicesFramework
