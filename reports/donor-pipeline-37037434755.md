# donor-pipeline run 37037434755 (2026-10-02T17:48:37Z)

## probe
```
brak donor-product w cache - bedzie Drive
probe [drive.usercontent.google.com] -> 206 CR='bytes 0-0/10340028849' body0=b'P'
speed 1-watkowo (32 MiB): 21.10 MB/s
Filesystem      Size  Used Avail Use% Mounted on
/dev/root       145G   59G   86G  41% /
=== TIER CDN-R: Recovery OTA yingtian 4.0.11.0 (payload.bin, range-extraction) ===
CDN mirrory z HTML (yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip):
https://bigota.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
https://bkt-sgp-miui-ota-update-alisgp.oss-ap-southeast-1.aliyuncs.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
https://bn.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
https://cdnorg.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
https://hugeota.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
CDN speed 246400 B/s: https://bigota.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
CDN speed 3882635 B/s: https://bkt-sgp-miui-ota-update-alisgp.oss-ap-southeast-1.aliyuncs.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
CDN speed 2824059 B/s: https://bn.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
CDN speed 399801 B/s: https://cdnorg.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
CDN speed 269230 B/s: https://hugeota.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
CDN-R proba 1/2: https://bkt-sgp-miui-ota-update-alisgp.oss-ap-southeast-1.aliyuncs.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
CDN-R OK: product.img 6445187072 B z https://bkt-sgp-miui-ota-update-alisgp.oss-ap-southeast-1.aliyuncs.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip (zip md5 wg strony: a12ac31de7165776806e8252cbb8628a)
source=Xiaomi CDN Recovery OTA yingtian 4.0.11.0.XBMCNXM zip (yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip; payload.bin range-extraction, per-op sha256 OK, 12 watkow; Drive quota - receipt 37026854069)
```
## ekstrakcja (tail 100)
```
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
zrodlo: HTTP https://bkt-sgp-miui-ota-update-alisgp.oss-ap-southeast-1.aliyuncs.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip
  size=10313202368 accept-ranges=bytes
  zip64: cd_off=10313200061 cd_size=551
  wpis payload.bin: STORED, 10313193325 B @+5370
naglowek payload (hex, 32B): 43724155000000000000000200000000000574a60000010b1880202099c1c5b5
payload: version=2 manifest=357542B meta_sig=267B, bloby od 357833
partycja product: 3074 op (REPLACE x518, REPLACE_BZ x107, REPLACE_XZ x2449), do pobrania 5573222120 B (5.19 GiB), new_size=6445187072
pokrycie partycji: 1573532 / 1573532 blokow (100.0%)
  [  0.1%] op 1/3074, 5 MiB / 5315 MiB, 2.54 MB/s, ETA 34.9 min
  [  1.4%] op 49/3074, 73 MiB / 5315 MiB, 2.27 MB/s, ETA 38.5 min
  [  2.9%] op 95/3074, 152 MiB / 5315 MiB, 2.43 MB/s, ETA 35.4 min
  [  4.3%] op 144/3074, 227 MiB / 5315 MiB, 2.45 MB/s, ETA 34.6 min
  [  5.6%] op 193/3074, 298 MiB / 5315 MiB, 2.42 MB/s, ETA 34.5 min
  [  6.9%] op 242/3074, 367 MiB / 5315 MiB, 2.39 MB/s, ETA 34.5 min
  [  8.2%] op 291/3074, 437 MiB / 5315 MiB, 2.38 MB/s, ETA 34.2 min
  [  9.6%] op 340/3074, 511 MiB / 5315 MiB, 2.39 MB/s, ETA 33.5 min
  [ 11.2%] op 387/3074, 596 MiB / 5315 MiB, 2.44 MB/s, ETA 32.2 min
  [ 12.7%] op 437/3074, 672 MiB / 5315 MiB, 2.45 MB/s, ETA 31.6 min
  [ 13.9%] op 487/3074, 740 MiB / 5315 MiB, 2.43 MB/s, ETA 31.4 min
  [ 15.2%] op 536/3074, 809 MiB / 5315 MiB, 2.41 MB/s, ETA 31.2 min
  [ 16.4%] op 585/3074, 873 MiB / 5315 MiB, 2.38 MB/s, ETA 31.1 min
  [ 18.2%] op 633/3074, 966 MiB / 5315 MiB, 2.43 MB/s, ETA 29.9 min
  [ 19.8%] op 681/3074, 1054 MiB / 5315 MiB, 2.46 MB/s, ETA 28.9 min
  [ 21.3%] op 730/3074, 1130 MiB / 5315 MiB, 2.46 MB/s, ETA 28.3 min
  [ 23.0%] op 777/3074, 1221 MiB / 5315 MiB, 2.50 MB/s, ETA 27.3 min
  [ 24.7%] op 822/3074, 1311 MiB / 5315 MiB, 2.52 MB/s, ETA 26.4 min
  [ 26.5%] op 870/3074, 1406 MiB / 5315 MiB, 2.55 MB/s, ETA 25.5 min
  [ 28.3%] op 918/3074, 1502 MiB / 5315 MiB, 2.58 MB/s, ETA 24.6 min
  [ 30.1%] op 966/3074, 1600 MiB / 5315 MiB, 2.61 MB/s, ETA 23.7 min
  [ 31.8%] op 1014/3074, 1691 MiB / 5315 MiB, 2.63 MB/s, ETA 23.0 min
  [ 33.3%] op 1063/3074, 1770 MiB / 5315 MiB, 2.63 MB/s, ETA 22.5 min
  [ 35.0%] op 1110/3074, 1858 MiB / 5315 MiB, 2.64 MB/s, ETA 21.8 min
  [ 36.3%] op 1159/3074, 1928 MiB / 5315 MiB, 2.62 MB/s, ETA 21.5 min
  [ 37.8%] op 1206/3074, 2012 MiB / 5315 MiB, 2.63 MB/s, ETA 20.9 min
  [ 39.5%] op 1254/3074, 2097 MiB / 5315 MiB, 2.64 MB/s, ETA 20.4 min
  [ 40.9%] op 1304/3074, 2172 MiB / 5315 MiB, 2.63 MB/s, ETA 19.9 min
  [ 42.4%] op 1352/3074, 2253 MiB / 5315 MiB, 2.63 MB/s, ETA 19.4 min
  [ 43.9%] op 1402/3074, 2333 MiB / 5315 MiB, 2.63 MB/s, ETA 18.9 min
  [ 45.6%] op 1448/3074, 2423 MiB / 5315 MiB, 2.64 MB/s, ETA 18.3 min
  [ 47.1%] op 1496/3074, 2503 MiB / 5315 MiB, 2.64 MB/s, ETA 17.7 min
  [ 48.7%] op 1540/3074, 2591 MiB / 5315 MiB, 2.65 MB/s, ETA 17.2 min
  [ 50.5%] op 1588/3074, 2686 MiB / 5315 MiB, 2.66 MB/s, ETA 16.5 min
  [ 52.0%] op 1636/3074, 2766 MiB / 5315 MiB, 2.66 MB/s, ETA 16.0 min
  [ 53.8%] op 1684/3074, 2857 MiB / 5315 MiB, 2.67 MB/s, ETA 15.4 min
  [ 55.5%] op 1731/3074, 2949 MiB / 5315 MiB, 2.68 MB/s, ETA 14.7 min
  [ 57.2%] op 1778/3074, 3040 MiB / 5315 MiB, 2.69 MB/s, ETA 14.1 min
  [ 59.0%] op 1825/3074, 3135 MiB / 5315 MiB, 2.70 MB/s, ETA 13.5 min
  [ 60.6%] op 1873/3074, 3223 MiB / 5315 MiB, 2.70 MB/s, ETA 12.9 min
  [ 62.4%] op 1921/3074, 3314 MiB / 5315 MiB, 2.71 MB/s, ETA 12.3 min
  [ 64.2%] op 1969/3074, 3410 MiB / 5315 MiB, 2.72 MB/s, ETA 11.7 min
  [ 65.9%] op 2017/3074, 3505 MiB / 5315 MiB, 2.72 MB/s, ETA 11.1 min
  [ 67.7%] op 2064/3074, 3598 MiB / 5315 MiB, 2.73 MB/s, ETA 10.5 min
  [ 69.5%] op 2112/3074, 3694 MiB / 5315 MiB, 2.74 MB/s, ETA 9.9 min
  [ 71.2%] op 2160/3074, 3784 MiB / 5315 MiB, 2.74 MB/s, ETA 9.3 min
  [ 72.6%] op 2208/3074, 3858 MiB / 5315 MiB, 2.74 MB/s, ETA 8.9 min
  [ 74.1%] op 2255/3074, 3936 MiB / 5315 MiB, 2.73 MB/s, ETA 8.4 min
  [ 75.6%] op 2302/3074, 4019 MiB / 5315 MiB, 2.73 MB/s, ETA 7.9 min
  [ 77.1%] op 2349/3074, 4098 MiB / 5315 MiB, 2.73 MB/s, ETA 7.4 min
  [ 78.8%] op 2395/3074, 4188 MiB / 5315 MiB, 2.73 MB/s, ETA 6.9 min
  [ 80.5%] op 2441/3074, 4276 MiB / 5315 MiB, 2.74 MB/s, ETA 6.3 min
  [ 82.1%] op 2489/3074, 4366 MiB / 5315 MiB, 2.74 MB/s, ETA 5.8 min
  [ 83.5%] op 2539/3074, 4440 MiB / 5315 MiB, 2.73 MB/s, ETA 5.3 min
  [ 84.9%] op 2588/3074, 4513 MiB / 5315 MiB, 2.73 MB/s, ETA 4.9 min
  [ 86.3%] op 2638/3074, 4587 MiB / 5315 MiB, 2.72 MB/s, ETA 4.5 min
  [ 87.8%] op 2687/3074, 4666 MiB / 5315 MiB, 2.72 MB/s, ETA 4.0 min
  [ 89.3%] op 2736/3074, 4746 MiB / 5315 MiB, 2.72 MB/s, ETA 3.5 min
  [ 90.9%] op 2783/3074, 4831 MiB / 5315 MiB, 2.72 MB/s, ETA 3.0 min
  [ 92.3%] op 2831/3074, 4908 MiB / 5315 MiB, 2.71 MB/s, ETA 2.5 min
  [ 93.7%] op 2881/3074, 4981 MiB / 5315 MiB, 2.71 MB/s, ETA 2.1 min
  [ 95.2%] op 2928/3074, 5062 MiB / 5315 MiB, 2.71 MB/s, ETA 1.6 min
  [ 96.9%] op 2975/3074, 5148 MiB / 5315 MiB, 2.71 MB/s, ETA 1.0 min
  [ 98.5%] op 3023/3074, 5236 MiB / 5315 MiB, 2.71 MB/s, ETA 0.5 min
  [100.0%] op 3074/3074, 5316 MiB / 5315 MiB, 2.72 MB/s, ETA -0.0 min
gotowe: /tmp/donor/product.img = 6445187072 B (oczek. 6445187072) w 32.7 min; requestow HTTP: 3080
new_partition_info.hash (do weryfikacji zewnetrznej): 743a28088080a781181220384396ce94ae8620b51eca9b5daa3cb436fba380b6
erofs-check: magic e2e1f5e0 @1024 OK
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
md5=d387dcbce8a2a61ecc08215f93709b93
size=494384389
parts=1
apps=MIUICalculator,MIUIGallery,MIUINotes,MiuiCamera,MiuiHome
fonts=25
source=source=Xiaomi CDN Recovery OTA yingtian 4.0.11.0.XBMCNXM zip (yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip; payload.bin range-extraction, per-op sha256 OK, 12 watkow; Drive quota - receipt 37026854069)
created=2026-10-02T17:45:05Z
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
