### MysticalOS 3 (super.img TB350FU) links (run 37135311406)
release: mysticalos-3-super
transplant: OK (tier A2 donor-harvest; 5 apk: MIUICalculator MIUIGallery MIUINotes MiuiCamera MiuiHome ; framework: Miui-WindowManager-Shell.jar MiuiBooster.jar MiuiSettingsSearchLib.jar camerax-vendor-extensions.jar global-cleaner-empty.jar gson.jar livephoto-lite.jar miui-appcompat.appcontinuity.jar miui-appcompat.jar miui-cameraopt.jar miui-connectivity-service.jar miui-embedding-window.jar miui-enterprise-sdk.jar miui-framework-pointer-pad.jar miui-framework.autoui.jar miui-framework.hovermode.jar miui-framework.hyperviewscale.jar miui-framework.jar miui-framework.thirdappopt.jar miui-services-pointer-pad.jar miui-services.autoui.jar miui-services.hovermode.jar miui-services.hyperviewscale.jar miui-services.jar miui-services.thirdappopt.jar miui-telephony-common.jar miui-wifi-service.jar miui.car.server.jar miuix.jar security-device-credential-sdk.jar ; deklaracje: com.android.settingslib.search.xml com.miui.wm.shell.xml miui-cameraopt.xml platform-miui.xml )
purge product/system_ext: PURGED_product=1 PURGED_system_ext=1 

--- gofile (2 tary: kit-A czastki+flash, kit-B czastki+vbmeta) ---
== MysticalOS 3 super kit (gofile, 2 tary) ==
Po rozpakowaniu OBU tarow w jednym katalogu: cat super_mystical3.part.* > super_mystical3.img
### Bezposrednie linki pobierania (MysticalOS3_kit-A.tar, 3254804480 B)
## transferarch
- link: https://bunnynetassets.b-cdn.net/error.png
- probe: HTTP/2 200  | content-length: 9694 (oczekiwane 3254804480)

## gofile
- link: https://gofile.io/d/B48R7Qme
- probe: HTTP/2 200  | content-length: 3358 (oczekiwane 3254804480)

## bashupload: UPLOAD NIEUDANY
curl: (6) Could not resolve host: bashupload.com

## tempsh: UPLOAD NIEUDANY
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
<title>404 Not Found</title>
<h1>Not Found</h1>

## oshiat
- link: https://curl.se/docs/sslcerts.html
- probe: HTTP/2 200  | content-length: 12891 (oczekiwane 3254804480)

## filebin: UPLOAD NIEUDANY
{
    "bin": {
        "id": "mysticalos-1791045452",

## litterbox72
- link: https://www.bunkerweb.io/?utm_campaign=self&utm_source=bwerror
- probe: HTTP/2 200  | content-length: ? (oczekiwane 3254804480)

### Bezposrednie linki pobierania (MysticalOS3_kit-B.tar, 3169433600 B)
## transferarch
- link: https://bunnynetassets.b-cdn.net/error.png
- probe: HTTP/2 200  | content-length: 9694 (oczekiwane 3169433600)

## gofile
- link: https://gofile.io/d/vhWi8QPG
- probe: HTTP/2 200  | content-length: 3358 (oczekiwane 3169433600)

## bashupload: UPLOAD NIEUDANY
curl: (6) Could not resolve host: bashupload.com

## tempsh: UPLOAD NIEUDANY
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
<title>404 Not Found</title>
<h1>Not Found</h1>

## oshiat
- link: https://curl.se/docs/sslcerts.html
- probe: HTTP/2 200  | content-length: 12891 (oczekiwane 3169433600)

## filebin: UPLOAD NIEUDANY
{
    "bin": {
        "id": "mysticalos-1791045969",

## litterbox72
- link: https://www.bunkerweb.io/?utm_campaign=self&utm_source=bwerror
- probe: HTTP/2 200  | content-length: ? (oczekiwane 3169433600)

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
chunk=199229440
size_sparse=6357072936
sha256_sparse_zlozony=ba07d82b2f9c967148a34ed25b654a41fd3ed564045a46ab9ef1c3990a008923
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
  system_a: 3585077248 B (3.585 GB)
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
