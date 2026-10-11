# donor-pipeline run 37056299450 (2026-10-02T20:10:25Z)

## probe
```
brak donor-product w cache - bedzie Drive
probe [drive.usercontent.google.com] -> 206 CR='bytes 0-0/10340028849' body0=b'P'
speed 1-watkowo (32 MiB): 0.00 MB/s
Filesystem      Size  Used Avail Use% Mounted on
/dev/root       145G   59G   86G  41% /
=== TIER CDN-R: Recovery OTA yingtian 4.0.11.0 (payload.bin, range-extraction) ===
CDN mirrory z HTML (yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip):
https://bigota.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
https://bkt-sgp-miui-ota-update-alisgp.oss-ap-southeast-1.aliyuncs.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
https://bn.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
https://cdnorg.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
https://hugeota.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
CDN speed 247630 B/s: https://bigota.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
CDN speed 2922394 B/s: https://bkt-sgp-miui-ota-update-alisgp.oss-ap-southeast-1.aliyuncs.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
CDN speed 6652527 B/s: https://bn.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
CDN speed 11997313 B/s: https://cdnorg.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
CDN speed 247650 B/s: https://hugeota.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
CDN-R proba 1/2: https://cdnorg.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
CDN-R OK: product.img 6445187072 B z https://cdnorg.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip (zip md5 wg strony: a12ac31de7165776806e8252cbb8628a)
source=Xiaomi CDN Recovery OTA yingtian 4.0.11.0.XBMCNXM zip (yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip; payload.bin range-extraction, per-op sha256 OK, 12 watkow; Drive quota - receipt 37026854069)
```
## ekstrakcja (tail 100)
```
# probe: status=206 CR='bytes 0-0/10313202368' CL='1' AR='bytes' CT='application/zip' body0=b'P'
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
#   partycja odm            new_size=3096117248   ops=1477  (pole 8, sha256 na 1477)
#   partycja odm_dlkm       new_size=348160       ops=1     (pole 8, sha256 na 1)
#   partycja product        new_size=6445187072   ops=3074  (pole 8, sha256 na 3074)
#     pola len-delim w product: [(8, 3074), (17, 1)]
#   partycja pvmfw          new_size=1048576      ops=1     (pole 8, sha256 na 1)
#   partycja sec_dtbo       new_size=139264       ops=1     (pole 8, sha256 na 1)
#   partycja sensorhub      new_size=3948544      ops=2     (pole 8, sha256 na 2)
#   partycja system         new_size=937791488    ops=448   (pole 8, sha256 na 448)
#     pola len-delim w system: [(8, 448), (3, 1), (17, 1)]
#   partycja system_dlkm    new_size=27078656     ops=13    (pole 8, sha256 na 13)
#   partycja system_ext     new_size=632840192    ops=302   (pole 8, sha256 na 302)
#   partycja tee            new_size=5148672      ops=3     (pole 8, sha256 na 3)
#   partycja uefi           new_size=2101248      ops=2     (pole 8, sha256 na 2)
#   partycja vbmeta         new_size=12288        ops=1     (pole 8, sha256 na 1)
#   partycja vbmeta_system  new_size=4096         ops=1     (pole 8, sha256 na 1)
#   partycja vbmeta_vendor  new_size=8192         ops=1     (pole 8, sha256 na 1)
#   partycja vendor         new_size=677728256    ops=324   (pole 8, sha256 na 324)
#     pola len-delim w vendor: [(8, 324), (17, 1)]
#   partycja vendor_boot    new_size=205520896    ops=98    (pole 8, sha256 na 98)
#   partycja vendor_dlkm    new_size=40054784     ops=20    (pole 8, sha256 na 20)
#   partycja xctrl_cpu      new_size=204800       ops=1     (pole 8, sha256 na 1)
#   partycja xctrl_ddr      new_size=86016        ops=1     (pole 8, sha256 na 1)
#   partycja xloader        new_size=733184       ops=1     (pole 8, sha256 na 1)
#   partycja xrse           new_size=421888       ops=1     (pole 8, sha256 na 1)
#   partycja xspm           new_size=995328       ops=1     (pole 8, sha256 na 1)
#   partycja xsps           new_size=1007616      ops=1     (pole 8, sha256 na 1)
#   partycja mi_product     new_size=348160       ops=1     (pole 8, sha256 na 1)
#   partycja mi_ext         new_size=528691200    ops=253   (pole 8, sha256 na 253)
zrodlo: HTTP https://cdnorg.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
  size=10313202368 accept-ranges=bytes
  zip64: cd_off=10313200061 cd_size=551
  wpis payload.bin: STORED, 10313193325 B @+5370
naglowek payload (hex, 32B): 43724155000000000000000200000000000574a60000010b1880202099c1c5b5
payload: version=2 manifest=357542B meta_sig=267B, bloby od 357833
partycja product: 3074 op (REPLACE x518, REPLACE_BZ x107, REPLACE_XZ x2449), do pobrania 5573222120 B (5.19 GiB), new_size=6445187072
pokrycie partycji: 1573532 / 1573532 blokow (100.0%)
  [  0.1%] op 1/3074, 5 MiB / 5315 MiB, 39.55 MB/s, ETA 2.2 min
  [  9.9%] op 348/3074, 528 MiB / 5315 MiB, 16.48 MB/s, ETA 4.8 min
  [ 18.8%] op 652/3074, 1001 MiB / 5315 MiB, 16.12 MB/s, ETA 4.5 min
  [ 30.6%] op 981/3074, 1628 MiB / 5315 MiB, 17.66 MB/s, ETA 3.5 min
  [ 41.3%] op 1320/3074, 2196 MiB / 5315 MiB, 17.97 MB/s, ETA 2.9 min
  [ 52.5%] op 1649/3074, 2791 MiB / 5315 MiB, 18.33 MB/s, ETA 2.3 min
  [ 64.7%] op 1982/3074, 3439 MiB / 5315 MiB, 18.78 MB/s, ETA 1.7 min
  [ 75.0%] op 2278/3074, 3985 MiB / 5315 MiB, 18.55 MB/s, ETA 1.2 min
  [ 84.8%] op 2580/3074, 4505 MiB / 5315 MiB, 18.40 MB/s, ETA 0.7 min
  [ 95.2%] op 2926/3074, 5062 MiB / 5315 MiB, 18.42 MB/s, ETA 0.2 min
  [100.0%] op 3074/3074, 5316 MiB / 5315 MiB, 18.55 MB/s, ETA -0.0 min
gotowe: /tmp/donor/product.img = 6445187072 B (oczek. 6445187072) w 4.8 min; requestow HTTP: 3080
new_partition_info.hash (do weryfikacji zewnetrznej): 743a28088080a781181220384396ce94ae8620b51eca9b5daa3cb436fba380b6
erofs-check: magic e2e1f5e0 @1024 OK
```
## release (krok 7, tail 120)
```
https://github.com/blukeryellow-arch/Lenovo-Tab-P11-Gen-2-HyperOS-4-CN-HyperOS-4-from-Xiaomi-Pad-9-Pro-Max-/releases/tag/donor-cache
https://github.com/blukeryellow-arch/Lenovo-Tab-P11-Gen-2-HyperOS-4-CN-HyperOS-4-from-Xiaomi-Pad-9-Pro-Max-/releases/tag/donor-cache
donor-harvest.manifest 386B [uploaded]
donor-harvest.part.000 494384330B [uploaded]
donor-product.manifest 146B [uploaded]
donor-product.part.000 1800000000B [uploaded]
donor-product.part.001 1800000000B [uploaded]
donor-product.part.002 1800000000B [uploaded]
donor-product.part.003 1045187072B [uploaded]
```
## harvest (tail 120)
```
opcust
overlay
pangu
prebuilts
priv-app
usr
== app ==
AiasstVision
AnalyticsCore
CatchLog
ContentCatcherOS4
DeviceInfoQR
EidService
FidoAuthen2
GoogleExtShared
GoogleLocationHistory
GooglePrintRecommendationService
HybridPlatform
IFAAService
LyraSdkSpp
MIS
MIUICloudService
MIUIFileExplorer
MIUIFrequentPhrase
MIUIGuardProvider
MIUIMiCloudSync
MIUINotificationCenter
MIUIReporter
MIUIScreenshot
MIUISecurityAdd
MIUISecurityInputMethod
MIUISuperMarketPad
MIUISystemUIPlugin
MIUIThemeManagerPad
MIUIXiaomiAccount
MIUIgreenguard
MSA
MSLgRdp
MediaViewer
MiAONServiceX
MiBugReportOS4
MiDevAuthService
MiLinkOS4Cn
MiPCExpend
MiSound
MiTrustService
MiType
MiWallpaper
MiuiCit
MiuiCredentialManager
MiuiPasswords
MiuixEditor
ModuleMetadata
PaymentService
SecurityCoreAdd
SecurityOnetrackService
SogouIME
SoterService
SwitchAccess
ThirdAppAssistant
Updater
VoiceTrigger
WMService
WebViewGoogle64
WinPlay
XMSFKeeperCN
XmsCore
== priv-app ==
AIService
Backup
ConfigUpdater
GmsCore
GooglePlayServicesUpdater
ImsServiceEntitlement
InCallUI
MISettings
MIShare
MIUIAICR
MIUIAccessibility
MIUIAod
MIUIBrowserPad
MIUICloudBackup
MIUIContactsPad
MIUIFindDeviceCN
MIUIPackageInstallerVariants
MIUIPersonalAssistantPadOS4
MIUISecurityCenterPad
MIUIYellowPagePad
MetokNLP
MiGameCenterSDKService
MiniGameService
MirrorOS4
MiuiBarrage
MiuiCamera
MiuiHome
MiuiLocationTimeZoneProviderService
QuickSearchBoxPadMIUI15
SettingsIntelligence
Toolbox
VoiceAssistAndroidT
kidspace
  apk: MiuiHome <- /tmp/donor/mnt/priv-app/MiuiHome (61 MB)
  apk: MiuiGallery <- /tmp/donor/mnt/data-app/MIUIGallery (107 MB)
  brak: MiuiGalleryNew
  brak: MiuiMusic
  brak: MiuiFileManager
  apk: MiuiCalculator <- /tmp/donor/mnt/data-app/MIUICalculator (10 MB)
  apk: MiuiCamera <- /tmp/donor/mnt/priv-app/MiuiCamera (184 MB)
  brak: MiuiVideo
  apk: MiuiNotes <- /tmp/donor/mnt/data-app/MIUINotes (170 MB)
  brak: NewMiuiNotes
  brak: MiuiWeather2
  brak: MiuiClock
  brak: MiuiSecurityCenter
kluczowe apki (kalkulator/aparat/notatki): 3/3
fonty Mi: 25
  motywy: /tmp/donor/mnt/media/theme (176 MB)
Filesystem      Size  Used Avail Use% Mounted on
/dev/root       145G   66G   79G  46% /
== harvest: 5 apk, 780 MB ==
```
## manifesty
```
md5=7d7ecbb911cc01aa9ddca06877793505
size=494384330
parts=1
apps=MIUICalculator,MIUIGallery,MIUINotes,MiuiCamera,MiuiHome
fonts=25
source=source=Xiaomi CDN Recovery OTA yingtian 4.0.11.0.XBMCNXM zip (yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip; payload.bin range-extraction, per-op sha256 OK, 12 watkow; Drive quota - receipt 37026854069)
created=2026-10-02T20:06:59Z
md5=cfc5e04e1b7cb17a8bcd556b324f91fa
size=6445187072
parts=4
sha256(product.img)=384396ce94ae8620b51eca9b5daa3cb436fba380b644bed9a932e186356f9870
```
## dysk
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/root       145G   73G   72G  51% /
```
