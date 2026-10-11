### MysticalOS 3 (super.img TB350FU) links (run 36642400344)
release: mysticalos-3-super
transplant: OK (TIER C; fonty z assets.tar.gz: 26)
purge product/system_ext: 

--- gofile (3 tary) ---
(brak)
--- manifest stream_lpunpack (baza) ---
# liblp v10.2; slots=3; bdev=super (9663676416 B); grupy=['default', 'main_a', 'main_b']
# glowy=1310720 B; segmenty: [('odm_dlkm', 1048576, 1396736)]
P	odm_dlkm	348160
# stop po offset 1396736 (tryb --only)
W	odm_dlkm	348160	348160	OK
# liblp v10.2; slots=3; bdev=super (9663676416 B); grupy=['default', 'main_a', 'main_b']
# glowy=1310720 B; segmenty: [('system', 2795503616, 6474297344)]
P	system	3678793728
# stop po offset 6474297344 (tryb --only)
W	system	3678793728	3678793728	OK
--- manifest super_patch ---
(brak)
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
  odm_dlkm_a: group=main_a attrs=0x1 extents=1
  odm_dlkm_b: group=main_b attrs=0x1 extents=0
  product_a: group=main_a attrs=0x1 extents=1
  product_b: group=main_b attrs=0x1 extents=0
  system_a: group=main_a attrs=0x1 extents=1
  system_b: group=main_b attrs=0x1 extents=1
  system_ext_a: group=main_a attrs=0x1 extents=1
  system_ext_b: group=main_b attrs=0x1 extents=0
  vendor_a: group=main_a attrs=0x1 extents=1
  vendor_b: group=main_b attrs=0x1 extents=0
  vendor_dlkm_a: group=main_a attrs=0x1 extents=1
  vendor_dlkm_b: group=main_b attrs=0x1 extents=0
== EXTENTS (sumy sektorow na partycje) ==
  odm_dlkm_a: 348160 B (0.000 GB)
  odm_dlkm_b: 0 B (0.000 GB)
  product_a: 2792497152 B (2.792 GB)
  product_b: 0 B (0.000 GB)
  system_a: 3678793728 B (3.679 GB)
  system_b: 184356864 B (0.184 GB)
  system_ext_a: 756998144 B (0.757 GB)
  system_ext_b: 0 B (0.000 GB)
  vendor_a: 916553728 B (0.917 GB)
  vendor_b: 0 B (0.000 GB)
  vendor_dlkm_a: 31363072 B (0.031 GB)
  vendor_dlkm_b: 0 B (0.000 GB)
--- geometria zbudowana ---
(brak)
--- purge GMS ---
(brak)
