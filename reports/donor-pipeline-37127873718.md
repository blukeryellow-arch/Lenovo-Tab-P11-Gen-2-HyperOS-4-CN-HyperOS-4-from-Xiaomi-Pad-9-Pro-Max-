# donor-pipeline run 37127873718 (2026-10-03T14:04:56Z)

## probe
```
cache: md5=cfc5e04e1b7cb17a8bcd556b324f91fa (oczek. cfc5e04e1b7cb17a8bcd556b324f91fa), size=6445187072 (oczek. 6445187072)
product.img z cache donor-cache (GitHub CDN) - Drive pominiety
```
## ekstrakcja (tail 100)
```
```
## release (krok 7, tail 120)
```
https://github.com/blukeryellow-arch/Lenovo-Tab-P11-Gen-2-HyperOS-4-CN-HyperOS-4-from-Xiaomi-Pad-9-Pro-Max-/releases/tag/donor-cache
https://github.com/blukeryellow-arch/Lenovo-Tab-P11-Gen-2-HyperOS-4-CN-HyperOS-4-from-Xiaomi-Pad-9-Pro-Max-/releases/tag/donor-cache
donor-harvest.manifest 938B [uploaded]
donor-harvest.part.000 521141094B [uploaded]
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
## framework-podsumowanie (bez set -x trace)
```
== mirrory wg szybkosci ==
== ekstrakcja system z https://cdnorg.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip (timeout 45 min) ==
== ekstrakcja system_ext z https://cdnorg.d.miui.com/OS4.0.11.0.XBMCNXM/yingtian-ota_full-OS4.0.11.0.XBMCNXM-user-17.0-a12ac31de7.zip (timeout 45 min) ==
/tmp/donor/system.img: EROFS OK (937791488 B)
/tmp/donor/system_ext.img: EROFS OK (632840192 B)
  deklaracja: com.android.settingslib.search.xml [z se]
++ L91: stat -c%s /tmp/donor/smnt/se/framework/MiuiSettingsSearchLib.jar
++ L95: basename /system_ext/framework/MiuiSettingsSearchLib.jar
  lib: MiuiSettingsSearchLib.jar (122790 B) [z se]
  deklaracja: com.miui.wm.shell.xml [z se]
++ L91: stat -c%s /tmp/donor/smnt/se/framework/Miui-WindowManager-Shell.jar
++ L95: basename /system_ext/framework/Miui-WindowManager-Shell.jar
  lib: Miui-WindowManager-Shell.jar (8964399 B) [z se]
  deklaracja: miui-cameraopt.xml [z se]
++ L91: stat -c%s /tmp/donor/smnt/se/framework/miui-cameraopt.jar
++ L95: basename /system_ext/framework/miui-cameraopt.jar
  lib: miui-cameraopt.jar (354310 B) [z se]
  deklaracja: platform-miui.xml [z se]
  UWAGA: /system/framework/cloud-common-runtime.jar wskazany w deklaracji, nie ma go w system/system_ext
  UWAGA: /system/framework/MiCloudLibShared.jar wskazany w deklaracji, nie ma go w system/system_ext
  UWAGA: /system/framework/yellowpage-common.jar wskazany w deklaracji, nie ma go w system/system_ext
  UWAGA: /system/framework/miui-update.jar wskazany w deklaracji, nie ma go w system/system_ext
  UWAGA: /system/framework/activation.jar wskazany w deklaracji, nie ma go w system/system_ext
++ L91: stat -c%s /tmp/donor/smnt/se/framework/gson.jar
++ L95: basename /system_ext/framework/gson.jar
  lib: gson.jar (194273 B) [z se]
  UWAGA: /system/framework/protobuf.jar wskazany w deklaracji, nie ma go w system/system_ext
  UWAGA: /system_ext/framework/android-support-v13.jar wskazany w deklaracji, nie ma go w system/system_ext
  UWAGA: /system/framework/android-support-v7-recyclerview.jar wskazany w deklaracji, nie ma go w system/system_ext
  UWAGA: /system_ext/framework/android-support-v13.jar wskazany w deklaracji, nie ma go w system/system_ext
  UWAGA: /system/framework/volley.jar wskazany w deklaracji, nie ma go w system/system_ext
  UWAGA: /system/framework/picasso.jar wskazany w deklaracji, nie ma go w system/system_ext
  UWAGA: /system/framework/miuipushsdkshared.jar wskazany w deklaracji, nie ma go w system/system_ext
  UWAGA: /system/framework/miuistatssdkshared.jar wskazany w deklaracji, nie ma go w system/system_ext
  UWAGA: /system/framework/miuistatssdksharedv3.jar wskazany w deklaracji, nie ma go w system/system_ext
  UWAGA: /system/framework/eventbus.jar wskazany w deklaracji, nie ma go w system/system_ext
++ L91: stat -c%s /tmp/donor/smnt/se/framework/security-device-credential-sdk.jar
++ L95: basename /system_ext/framework/security-device-credential-sdk.jar
  lib: security-device-credential-sdk.jar (18766 B) [z se]
  UWAGA: /system/framework/global-miui11-empty.jar wskazany w deklaracji, nie ma go w system/system_ext
  UWAGA: /system/framework/global-miui12-empty.jar wskazany w deklaracji, nie ma go w system/system_ext
++ L91: stat -c%s /tmp/donor/smnt/se/framework/camerax-vendor-extensions.jar
++ L95: basename /system_ext/framework/camerax-vendor-extensions.jar
  lib: camerax-vendor-extensions.jar (71945 B) [z se]
++ L91: stat -c%s /tmp/donor/smnt/se/framework/livephoto-lite.jar
++ L95: basename /system_ext/framework/livephoto-lite.jar
  lib: livephoto-lite.jar (321933 B) [z se]
++ L91: stat -c%s /tmp/donor/smnt/se/framework/global-cleaner-empty.jar
++ L95: basename /system_ext/framework/global-cleaner-empty.jar
  lib: global-cleaner-empty.jar (1333 B) [z se]
== framework harvest: 30 jar, 4 deklaracji, 66 MB ==
-rw-r--r-- 1 runner runner  8964399 Jan  1  2009 Miui-WindowManager-Shell.jar
-rw-r--r-- 1 runner runner    78182 Jan  1  2009 MiuiBooster.jar
-rw-r--r-- 1 runner runner   122790 Jan  1  2009 MiuiSettingsSearchLib.jar
-rw-r--r-- 1 runner runner    71945 Jan  1  2009 camerax-vendor-extensions.jar
-rw-r--r-- 1 runner runner     1333 Jan  1  2009 global-cleaner-empty.jar
-rw-r--r-- 1 runner runner   194273 Jan  1  2009 gson.jar
-rw-r--r-- 1 runner runner   321933 Jan  1  2009 livephoto-lite.jar
-rw-r--r-- 1 runner runner   196098 Jan  1  2009 miui-appcompat.appcontinuity.jar
-rw-r--r-- 1 runner runner    71598 Jan  1  2009 miui-appcompat.jar
-rw-r--r-- 1 runner runner   354310 Jan  1  2009 miui-cameraopt.jar
-rw-r--r-- 1 runner runner   338694 Jan  1  2009 miui-connectivity-service.jar
-rw-r--r-- 1 runner runner  2679446 Jan  1  2009 miui-embedding-window.jar
-rw-r--r-- 1 runner runner   247649 Jan  1  2009 miui-enterprise-sdk.jar
-rw-r--r-- 1 runner runner    47989 Jan  1  2009 miui-framework-pointer-pad.jar
-rw-r--r-- 1 runner runner   274102 Jan  1  2009 miui-framework.autoui.jar
-rw-r--r-- 1 runner runner    51482 Jan  1  2009 miui-framework.hovermode.jar
-rw-r--r-- 1 runner runner 12558164 Jan  1  2009 miui-framework.hyperviewscale.jar
-rw-r--r-- 1 runner runner  7173722 Jan  1  2009 miui-framework.jar
-rw-r--r-- 1 runner runner    67018 Jan  1  2009 miui-framework.thirdappopt.jar
-rw-r--r-- 1 runner runner   105234 Jan  1  2009 miui-services-pointer-pad.jar
-rw-r--r-- 1 runner runner    51254 Jan  1  2009 miui-services.autoui.jar
-rw-r--r-- 1 runner runner    87806 Jan  1  2009 miui-services.hovermode.jar
-rw-r--r-- 1 runner runner    17754 Jan  1  2009 miui-services.hyperviewscale.jar
-rw-r--r-- 1 runner runner 19632637 Jan  1  2009 miui-services.jar
-rw-r--r-- 1 runner runner    51722 Jan  1  2009 miui-services.thirdappopt.jar
-rw-r--r-- 1 runner runner   764861 Jan  1  2009 miui-telephony-common.jar
-rw-r--r-- 1 runner runner  4431234 Jan  1  2009 miui-wifi-service.jar
-rw-r--r-- 1 runner runner   146246 Jan  1  2009 miui.car.server.jar
-rw-r--r-- 1 runner runner  9390577 Jan  1  2009 miuix.jar
-rw-r--r-- 1 runner runner    18766 Jan  1  2009 security-device-credential-sdk.jar
```
## framework (krok 5.5, tail 500 z trace L$LINENO)
```
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/android.software.credentials.xml
+ L79: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/androidx.window.extensions.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/androidx.window.extensions.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/androidx.window.extensions.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/androidx.window.sidecar.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/androidx.window.sidecar.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/androidx.window.sidecar.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.android.carrierconfig.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.android.carrierconfig.xml
+ L79: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.android.emergency.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.android.emergency.xml
+ L79: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.android.provision.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.android.provision.xml
+ L79: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.android.settings.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.android.settings.xml
+ L79: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.android.settingslib.search.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.android.settingslib.search.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/com.android.settingslib.search.xml
+ L81: cp -aL /tmp/donor/smnt/se/etc/permissions/com.android.settingslib.search.xml /tmp/donor/keep/permissions/
++ L83: basename /tmp/donor/smnt/se/etc/permissions/com.android.settingslib.search.xml
+ L83: echo '  deklaracja: com.android.settingslib.search.xml [z se]'
  deklaracja: com.android.settingslib.search.xml [z se]
+ L84: IFS=
+ L84: read -r F
++ L77: grep -oE 'file="[^"]+"' /tmp/donor/smnt/se/etc/permissions/com.android.settingslib.search.xml
++ L77: sed 's/file="//;s/"$//'
+ L85: case "$F" in
+ L87: SRC=/tmp/donor/smnt/se/framework/MiuiSettingsSearchLib.jar
+ L90: '[' -f /tmp/donor/smnt/se/framework/MiuiSettingsSearchLib.jar ']'
++ L91: stat -c%s /tmp/donor/smnt/se/framework/MiuiSettingsSearchLib.jar
+ L91: SZX=122790
+ L92: '[' 122790 -le 157286400 ']'
+ L93: cp -aL /tmp/donor/smnt/se/framework/MiuiSettingsSearchLib.jar /tmp/donor/keep/framework/
++ L95: basename /system_ext/framework/MiuiSettingsSearchLib.jar
+ L95: echo '  lib: MiuiSettingsSearchLib.jar (122790 B) [z se]'
  lib: MiuiSettingsSearchLib.jar (122790 B) [z se]
+ L84: IFS=
+ L84: read -r F
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.android.storagemanager.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.android.storagemanager.xml
+ L79: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.android.systemui.libpag.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.android.systemui.libpag.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/com.android.systemui.libpag.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.android.systemui.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.android.systemui.xml
+ L79: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.miui.wm.shell.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.miui.wm.shell.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/com.miui.wm.shell.xml
+ L81: cp -aL /tmp/donor/smnt/se/etc/permissions/com.miui.wm.shell.xml /tmp/donor/keep/permissions/
++ L83: basename /tmp/donor/smnt/se/etc/permissions/com.miui.wm.shell.xml
+ L83: echo '  deklaracja: com.miui.wm.shell.xml [z se]'
  deklaracja: com.miui.wm.shell.xml [z se]
+ L84: IFS=
+ L84: read -r F
++ L77: grep -oE 'file="[^"]+"' /tmp/donor/smnt/se/etc/permissions/com.miui.wm.shell.xml
++ L77: sed 's/file="//;s/"$//'
+ L85: case "$F" in
+ L87: SRC=/tmp/donor/smnt/se/framework/Miui-WindowManager-Shell.jar
+ L90: '[' -f /tmp/donor/smnt/se/framework/Miui-WindowManager-Shell.jar ']'
++ L91: stat -c%s /tmp/donor/smnt/se/framework/Miui-WindowManager-Shell.jar
+ L91: SZX=8964399
+ L92: '[' 8964399 -le 157286400 ']'
+ L93: cp -aL /tmp/donor/smnt/se/framework/Miui-WindowManager-Shell.jar /tmp/donor/keep/framework/
++ L95: basename /system_ext/framework/Miui-WindowManager-Shell.jar
+ L95: echo '  lib: Miui-WindowManager-Shell.jar (8964399 B) [z se]'
  lib: Miui-WindowManager-Shell.jar (8964399 B) [z se]
+ L84: IFS=
+ L84: read -r F
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.xiaomi.NetworkBoost.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.xiaomi.NetworkBoost.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/com.xiaomi.NetworkBoost.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.xiaomi.hardware.camera.companion.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.xiaomi.hardware.camera.companion.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/com.xiaomi.hardware.camera.companion.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.xiaomi.hypercomm.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.xiaomi.hypercomm.xml
+ L79: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.xiaomi.phone.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.xiaomi.phone.xml
+ L79: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.xiaomi.pms.common-V1-java-permission.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.xiaomi.pms.common-V1-java-permission.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/com.xiaomi.pms.common-V1-java-permission.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.xiaomi.pms.deferredcameraservice-V1-java-permission.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.xiaomi.pms.deferredcameraservice-V1-java-permission.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/com.xiaomi.pms.deferredcameraservice-V1-java-permission.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.xiaomi.pms.videoplayprocservice-V1-java-permission.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.xiaomi.pms.videoplayprocservice-V1-java-permission.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/com.xiaomi.pms.videoplayprocservice-V1-java-permission.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.xiaomi.radio.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.xiaomi.radio.xml
+ L79: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.xiaomi.slalib.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.xiaomi.slalib.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/com.xiaomi.slalib.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.xiaomi.uniperf.UniperfClient.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.xiaomi.uniperf.UniperfClient.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/com.xiaomi.uniperf.UniperfClient.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.xring.perf.PerfFlingerClient.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.xring.perf.PerfFlingerClient.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/com.xring.perf.PerfFlingerClient.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/com.xring.perf.SchedGeniusClient.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/com.xring.perf.SchedGeniusClient.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/com.xring.perf.SchedGeniusClient.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/extphonelib.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/extphonelib.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/extphonelib.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/miui-cameraopt.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/miui-cameraopt.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/miui-cameraopt.xml
+ L81: cp -aL /tmp/donor/smnt/se/etc/permissions/miui-cameraopt.xml /tmp/donor/keep/permissions/
++ L83: basename /tmp/donor/smnt/se/etc/permissions/miui-cameraopt.xml
+ L83: echo '  deklaracja: miui-cameraopt.xml [z se]'
  deklaracja: miui-cameraopt.xml [z se]
+ L84: IFS=
+ L84: read -r F
++ L77: sed 's/file="//;s/"$//'
++ L77: grep -oE 'file="[^"]+"' /tmp/donor/smnt/se/etc/permissions/miui-cameraopt.xml
+ L85: case "$F" in
+ L87: SRC=/tmp/donor/smnt/se/framework/miui-cameraopt.jar
+ L90: '[' -f /tmp/donor/smnt/se/framework/miui-cameraopt.jar ']'
++ L91: stat -c%s /tmp/donor/smnt/se/framework/miui-cameraopt.jar
+ L91: SZX=354310
+ L92: '[' 354310 -le 157286400 ']'
+ L93: cp -aL /tmp/donor/smnt/se/framework/miui-cameraopt.jar /tmp/donor/keep/framework/
++ L95: basename /system_ext/framework/miui-cameraopt.jar
+ L95: echo '  lib: miui-cameraopt.jar (354310 B) [z se]'
  lib: miui-cameraopt.jar (354310 B) [z se]
+ L84: IFS=
+ L84: read -r F
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/package-shareduid-allowlist-miui-system-ext.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/package-shareduid-allowlist-miui-system-ext.xml
+ L79: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/platform-miui.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/platform-miui.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/platform-miui.xml
+ L81: cp -aL /tmp/donor/smnt/se/etc/permissions/platform-miui.xml /tmp/donor/keep/permissions/
++ L83: basename /tmp/donor/smnt/se/etc/permissions/platform-miui.xml
+ L83: echo '  deklaracja: platform-miui.xml [z se]'
  deklaracja: platform-miui.xml [z se]
+ L84: IFS=
+ L84: read -r F
++ L77: grep -oE 'file="[^"]+"' /tmp/donor/smnt/se/etc/permissions/platform-miui.xml
++ L77: sed 's/file="//;s/"$//'
+ L85: case "$F" in
+ L86: SRC=/tmp/donor/smnt/sys/framework/cloud-common-runtime.jar
+ L90: '[' -f /tmp/donor/smnt/sys/framework/cloud-common-runtime.jar ']'
+ L100: echo '  UWAGA: /system/framework/cloud-common-runtime.jar wskazany w deklaracji, nie ma go w system/system_ext'
  UWAGA: /system/framework/cloud-common-runtime.jar wskazany w deklaracji, nie ma go w system/system_ext
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L86: SRC=/tmp/donor/smnt/sys/framework/MiCloudLibShared.jar
+ L90: '[' -f /tmp/donor/smnt/sys/framework/MiCloudLibShared.jar ']'
+ L100: echo '  UWAGA: /system/framework/MiCloudLibShared.jar wskazany w deklaracji, nie ma go w system/system_ext'
  UWAGA: /system/framework/MiCloudLibShared.jar wskazany w deklaracji, nie ma go w system/system_ext
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L86: SRC=/tmp/donor/smnt/sys/framework/yellowpage-common.jar
+ L90: '[' -f /tmp/donor/smnt/sys/framework/yellowpage-common.jar ']'
+ L100: echo '  UWAGA: /system/framework/yellowpage-common.jar wskazany w deklaracji, nie ma go w system/system_ext'
  UWAGA: /system/framework/yellowpage-common.jar wskazany w deklaracji, nie ma go w system/system_ext
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L86: SRC=/tmp/donor/smnt/sys/framework/miui-update.jar
+ L90: '[' -f /tmp/donor/smnt/sys/framework/miui-update.jar ']'
+ L100: echo '  UWAGA: /system/framework/miui-update.jar wskazany w deklaracji, nie ma go w system/system_ext'
  UWAGA: /system/framework/miui-update.jar wskazany w deklaracji, nie ma go w system/system_ext
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L86: SRC=/tmp/donor/smnt/sys/framework/activation.jar
+ L90: '[' -f /tmp/donor/smnt/sys/framework/activation.jar ']'
+ L100: echo '  UWAGA: /system/framework/activation.jar wskazany w deklaracji, nie ma go w system/system_ext'
  UWAGA: /system/framework/activation.jar wskazany w deklaracji, nie ma go w system/system_ext
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L87: SRC=/tmp/donor/smnt/se/framework/gson.jar
+ L90: '[' -f /tmp/donor/smnt/se/framework/gson.jar ']'
++ L91: stat -c%s /tmp/donor/smnt/se/framework/gson.jar
+ L91: SZX=194273
+ L92: '[' 194273 -le 157286400 ']'
+ L93: cp -aL /tmp/donor/smnt/se/framework/gson.jar /tmp/donor/keep/framework/
++ L95: basename /system_ext/framework/gson.jar
+ L95: echo '  lib: gson.jar (194273 B) [z se]'
  lib: gson.jar (194273 B) [z se]
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L86: SRC=/tmp/donor/smnt/sys/framework/protobuf.jar
+ L90: '[' -f /tmp/donor/smnt/sys/framework/protobuf.jar ']'
+ L100: echo '  UWAGA: /system/framework/protobuf.jar wskazany w deklaracji, nie ma go w system/system_ext'
  UWAGA: /system/framework/protobuf.jar wskazany w deklaracji, nie ma go w system/system_ext
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L87: SRC=/tmp/donor/smnt/se/framework/android-support-v13.jar
+ L90: '[' -f /tmp/donor/smnt/se/framework/android-support-v13.jar ']'
+ L100: echo '  UWAGA: /system_ext/framework/android-support-v13.jar wskazany w deklaracji, nie ma go w system/system_ext'
  UWAGA: /system_ext/framework/android-support-v13.jar wskazany w deklaracji, nie ma go w system/system_ext
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L86: SRC=/tmp/donor/smnt/sys/framework/android-support-v7-recyclerview.jar
+ L90: '[' -f /tmp/donor/smnt/sys/framework/android-support-v7-recyclerview.jar ']'
+ L100: echo '  UWAGA: /system/framework/android-support-v7-recyclerview.jar wskazany w deklaracji, nie ma go w system/system_ext'
  UWAGA: /system/framework/android-support-v7-recyclerview.jar wskazany w deklaracji, nie ma go w system/system_ext
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L87: SRC=/tmp/donor/smnt/se/framework/android-support-v13.jar
+ L90: '[' -f /tmp/donor/smnt/se/framework/android-support-v13.jar ']'
+ L100: echo '  UWAGA: /system_ext/framework/android-support-v13.jar wskazany w deklaracji, nie ma go w system/system_ext'
  UWAGA: /system_ext/framework/android-support-v13.jar wskazany w deklaracji, nie ma go w system/system_ext
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L86: SRC=/tmp/donor/smnt/sys/framework/volley.jar
+ L90: '[' -f /tmp/donor/smnt/sys/framework/volley.jar ']'
+ L100: echo '  UWAGA: /system/framework/volley.jar wskazany w deklaracji, nie ma go w system/system_ext'
  UWAGA: /system/framework/volley.jar wskazany w deklaracji, nie ma go w system/system_ext
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L86: SRC=/tmp/donor/smnt/sys/framework/picasso.jar
+ L90: '[' -f /tmp/donor/smnt/sys/framework/picasso.jar ']'
+ L100: echo '  UWAGA: /system/framework/picasso.jar wskazany w deklaracji, nie ma go w system/system_ext'
  UWAGA: /system/framework/picasso.jar wskazany w deklaracji, nie ma go w system/system_ext
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L86: SRC=/tmp/donor/smnt/sys/framework/miuipushsdkshared.jar
+ L90: '[' -f /tmp/donor/smnt/sys/framework/miuipushsdkshared.jar ']'
+ L100: echo '  UWAGA: /system/framework/miuipushsdkshared.jar wskazany w deklaracji, nie ma go w system/system_ext'
  UWAGA: /system/framework/miuipushsdkshared.jar wskazany w deklaracji, nie ma go w system/system_ext
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L86: SRC=/tmp/donor/smnt/sys/framework/miuistatssdkshared.jar
+ L90: '[' -f /tmp/donor/smnt/sys/framework/miuistatssdkshared.jar ']'
+ L100: echo '  UWAGA: /system/framework/miuistatssdkshared.jar wskazany w deklaracji, nie ma go w system/system_ext'
  UWAGA: /system/framework/miuistatssdkshared.jar wskazany w deklaracji, nie ma go w system/system_ext
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L86: SRC=/tmp/donor/smnt/sys/framework/miuistatssdksharedv3.jar
+ L90: '[' -f /tmp/donor/smnt/sys/framework/miuistatssdksharedv3.jar ']'
+ L100: echo '  UWAGA: /system/framework/miuistatssdksharedv3.jar wskazany w deklaracji, nie ma go w system/system_ext'
  UWAGA: /system/framework/miuistatssdksharedv3.jar wskazany w deklaracji, nie ma go w system/system_ext
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L86: SRC=/tmp/donor/smnt/sys/framework/eventbus.jar
+ L90: '[' -f /tmp/donor/smnt/sys/framework/eventbus.jar ']'
+ L100: echo '  UWAGA: /system/framework/eventbus.jar wskazany w deklaracji, nie ma go w system/system_ext'
  UWAGA: /system/framework/eventbus.jar wskazany w deklaracji, nie ma go w system/system_ext
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L87: SRC=/tmp/donor/smnt/se/framework/security-device-credential-sdk.jar
+ L90: '[' -f /tmp/donor/smnt/se/framework/security-device-credential-sdk.jar ']'
++ L91: stat -c%s /tmp/donor/smnt/se/framework/security-device-credential-sdk.jar
+ L91: SZX=18766
+ L92: '[' 18766 -le 157286400 ']'
+ L93: cp -aL /tmp/donor/smnt/se/framework/security-device-credential-sdk.jar /tmp/donor/keep/framework/
++ L95: basename /system_ext/framework/security-device-credential-sdk.jar
+ L95: echo '  lib: security-device-credential-sdk.jar (18766 B) [z se]'
  lib: security-device-credential-sdk.jar (18766 B) [z se]
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L86: SRC=/tmp/donor/smnt/sys/framework/global-miui11-empty.jar
+ L90: '[' -f /tmp/donor/smnt/sys/framework/global-miui11-empty.jar ']'
+ L100: echo '  UWAGA: /system/framework/global-miui11-empty.jar wskazany w deklaracji, nie ma go w system/system_ext'
  UWAGA: /system/framework/global-miui11-empty.jar wskazany w deklaracji, nie ma go w system/system_ext
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L86: SRC=/tmp/donor/smnt/sys/framework/global-miui12-empty.jar
+ L90: '[' -f /tmp/donor/smnt/sys/framework/global-miui12-empty.jar ']'
+ L100: echo '  UWAGA: /system/framework/global-miui12-empty.jar wskazany w deklaracji, nie ma go w system/system_ext'
  UWAGA: /system/framework/global-miui12-empty.jar wskazany w deklaracji, nie ma go w system/system_ext
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L87: SRC=/tmp/donor/smnt/se/framework/camerax-vendor-extensions.jar
+ L90: '[' -f /tmp/donor/smnt/se/framework/camerax-vendor-extensions.jar ']'
++ L91: stat -c%s /tmp/donor/smnt/se/framework/camerax-vendor-extensions.jar
+ L91: SZX=71945
+ L92: '[' 71945 -le 157286400 ']'
+ L93: cp -aL /tmp/donor/smnt/se/framework/camerax-vendor-extensions.jar /tmp/donor/keep/framework/
++ L95: basename /system_ext/framework/camerax-vendor-extensions.jar
+ L95: echo '  lib: camerax-vendor-extensions.jar (71945 B) [z se]'
  lib: camerax-vendor-extensions.jar (71945 B) [z se]
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L87: SRC=/tmp/donor/smnt/se/framework/livephoto-lite.jar
+ L90: '[' -f /tmp/donor/smnt/se/framework/livephoto-lite.jar ']'
++ L91: stat -c%s /tmp/donor/smnt/se/framework/livephoto-lite.jar
+ L91: SZX=321933
+ L92: '[' 321933 -le 157286400 ']'
+ L93: cp -aL /tmp/donor/smnt/se/framework/livephoto-lite.jar /tmp/donor/keep/framework/
++ L95: basename /system_ext/framework/livephoto-lite.jar
+ L95: echo '  lib: livephoto-lite.jar (321933 B) [z se]'
  lib: livephoto-lite.jar (321933 B) [z se]
+ L84: IFS=
+ L84: read -r F
+ L85: case "$F" in
+ L87: SRC=/tmp/donor/smnt/se/framework/global-cleaner-empty.jar
+ L90: '[' -f /tmp/donor/smnt/se/framework/global-cleaner-empty.jar ']'
++ L91: stat -c%s /tmp/donor/smnt/se/framework/global-cleaner-empty.jar
+ L91: SZX=1333
+ L92: '[' 1333 -le 157286400 ']'
+ L93: cp -aL /tmp/donor/smnt/se/framework/global-cleaner-empty.jar /tmp/donor/keep/framework/
++ L95: basename /system_ext/framework/global-cleaner-empty.jar
+ L95: echo '  lib: global-cleaner-empty.jar (1333 B) [z se]'
  lib: global-cleaner-empty.jar (1333 B) [z se]
+ L84: IFS=
+ L84: read -r F
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/privapp-permissions-gms-cn-system-ext.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/privapp-permissions-gms-cn-system-ext.xml
+ L79: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/privapp-permissions-miui-system-ext.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/privapp-permissions-miui-system-ext.xml
+ L79: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/privapp_allowlist_com.xiaomi.bluetooth.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/privapp_allowlist_com.xiaomi.bluetooth.xml
+ L79: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/qti_telephony_utils.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/qti_telephony_utils.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/qti_telephony_utils.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/system-ext-permissions-mediatek.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/system-ext-permissions-mediatek.xml
+ L79: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/system-ext-permissions-xiaomi.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/system-ext-permissions-xiaomi.xml
+ L79: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/vendor.xiaomi.hardware.aidl.intentaware-V1-java-permission.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/vendor.xiaomi.hardware.aidl.intentaware-V1-java-permission.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/vendor.xiaomi.hardware.aidl.intentaware-V1-java-permission.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/vendor.xiaomi.hardware.misys-V1.0-java-permission.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/vendor.xiaomi.hardware.misys-V1.0-java-permission.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/vendor.xiaomi.hardware.misys-V1.0-java-permission.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/vendor.xiaomi.hardware.misys-V2.0-java-permission.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/vendor.xiaomi.hardware.misys-V2.0-java-permission.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/vendor.xiaomi.hardware.misys-V2.0-java-permission.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/vendor.xiaomi.hardware.misys-V4.0-java-permission.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/vendor.xiaomi.hardware.misys-V4.0-java-permission.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/vendor.xiaomi.hardware.misys-V4.0-java-permission.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/vendor.xiaomi.hardware.misys.V3_0-permission.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/vendor.xiaomi.hardware.misys.V3_0-permission.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/vendor.xiaomi.hardware.misys.V3_0-permission.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/vendor.xiaomi.hardware.videoservice-V9-java-permission.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/vendor.xiaomi.hardware.videoservice-V9-java-permission.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/vendor.xiaomi.hardware.videoservice-V9-java-permission.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/xiaomi-opt-ims.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/xiaomi-opt-ims.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/xiaomi-opt-ims.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/xiaomi-opt-telephony.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/xiaomi-opt-telephony.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/xiaomi-opt-telephony.xml
+ L80: continue
+ L77: for XML in "$PDIR"/*.xml
+ L78: '[' -f /tmp/donor/smnt/se/etc/permissions/xiaomi.system.hypsys.common-V2-java-permission.xml ']'
+ L79: grep -q '<library' /tmp/donor/smnt/se/etc/permissions/xiaomi.system.hypsys.common-V2-java-permission.xml
+ L80: grep -qiE '<library[^>]*(name|file)="[^"]*miui' /tmp/donor/smnt/se/etc/permissions/xiaomi.system.hypsys.common-V2-java-permission.xml
+ L80: continue
+ L74: for BASE in "$MNT/se" "$MNT/sys"
+ L75: PDIR=/tmp/donor/smnt/sys/etc/permissions
+ L76: '[' -d /tmp/donor/smnt/sys/etc/permissions ']'
+ L76: continue
+ L106: for FDIR in "$MNT/se/framework" "$MNT/sys/framework"
+ L107: '[' -d /tmp/donor/smnt/se/framework ']'
+ L108: find /tmp/donor/smnt/se/framework -maxdepth 1 -iname 'miui*.jar' -size -150M -exec cp -aLn '{}' /tmp/donor/keep/framework/ ';'
+ L106: for FDIR in "$MNT/se/framework" "$MNT/sys/framework"
+ L107: '[' -d /tmp/donor/smnt/sys/framework ']'
+ L107: continue
+ L113: sudo umount /tmp/donor/smnt/sys
+ L114: sudo umount /tmp/donor/smnt/se
+ L115: rm -rf /tmp/donor/sext /tmp/donor/system.img /tmp/donor/system_ext.img
+ L116: set +x
Filesystem      Size  Used Avail Use% Mounted on
/dev/root       145G   66G   79G  46% /
== framework harvest: 30 jar, 4 deklaracji, 66 MB ==
/tmp/donor/keep/framework:
total 66968
drwxr-xr-x 2 runner runner     4096 Oct  3 14:00 .
drwxr-xr-x 7 runner runner     4096 Oct  3 14:00 ..
-rw-r--r-- 1 runner runner  8964399 Jan  1  2009 Miui-WindowManager-Shell.jar
-rw-r--r-- 1 runner runner    78182 Jan  1  2009 MiuiBooster.jar
-rw-r--r-- 1 runner runner   122790 Jan  1  2009 MiuiSettingsSearchLib.jar
-rw-r--r-- 1 runner runner    71945 Jan  1  2009 camerax-vendor-extensions.jar
-rw-r--r-- 1 runner runner     1333 Jan  1  2009 global-cleaner-empty.jar
-rw-r--r-- 1 runner runner   194273 Jan  1  2009 gson.jar
-rw-r--r-- 1 runner runner   321933 Jan  1  2009 livephoto-lite.jar
-rw-r--r-- 1 runner runner   196098 Jan  1  2009 miui-appcompat.appcontinuity.jar
-rw-r--r-- 1 runner runner    71598 Jan  1  2009 miui-appcompat.jar
-rw-r--r-- 1 runner runner   354310 Jan  1  2009 miui-cameraopt.jar
-rw-r--r-- 1 runner runner   338694 Jan  1  2009 miui-connectivity-service.jar
-rw-r--r-- 1 runner runner  2679446 Jan  1  2009 miui-embedding-window.jar
-rw-r--r-- 1 runner runner   247649 Jan  1  2009 miui-enterprise-sdk.jar
-rw-r--r-- 1 runner runner    47989 Jan  1  2009 miui-framework-pointer-pad.jar
-rw-r--r-- 1 runner runner   274102 Jan  1  2009 miui-framework.autoui.jar
-rw-r--r-- 1 runner runner    51482 Jan  1  2009 miui-framework.hovermode.jar
-rw-r--r-- 1 runner runner 12558164 Jan  1  2009 miui-framework.hyperviewscale.jar
-rw-r--r-- 1 runner runner  7173722 Jan  1  2009 miui-framework.jar
-rw-r--r-- 1 runner runner    67018 Jan  1  2009 miui-framework.thirdappopt.jar
-rw-r--r-- 1 runner runner   105234 Jan  1  2009 miui-services-pointer-pad.jar
-rw-r--r-- 1 runner runner    51254 Jan  1  2009 miui-services.autoui.jar
-rw-r--r-- 1 runner runner    87806 Jan  1  2009 miui-services.hovermode.jar
-rw-r--r-- 1 runner runner    17754 Jan  1  2009 miui-services.hyperviewscale.jar
-rw-r--r-- 1 runner runner 19632637 Jan  1  2009 miui-services.jar
-rw-r--r-- 1 runner runner    51722 Jan  1  2009 miui-services.thirdappopt.jar
-rw-r--r-- 1 runner runner   764861 Jan  1  2009 miui-telephony-common.jar
-rw-r--r-- 1 runner runner  4431234 Jan  1  2009 miui-wifi-service.jar
-rw-r--r-- 1 runner runner   146246 Jan  1  2009 miui.car.server.jar
-rw-r--r-- 1 runner runner  9390577 Jan  1  2009 miuix.jar
-rw-r--r-- 1 runner runner    18766 Jan  1  2009 security-device-credential-sdk.jar

/tmp/donor/keep/permissions:
total 24
drwxr-xr-x 2 runner runner 4096 Oct  3 14:00 .
drwxr-xr-x 7 runner runner 4096 Oct  3 14:00 ..
-rw-r--r-- 1 runner runner  242 Jan  1  2009 com.android.settingslib.search.xml
-rw-r--r-- 1 runner runner  175 Jan  1  2009 com.miui.wm.shell.xml
-rw-r--r-- 1 runner runner  801 Jan  1  2009 miui-cameraopt.xml
-rw-r--r-- 1 runner runner 2597 Jan  1  2009 platform-miui.xml
```
## system-extract (tail 60)
```
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
partycja system: 448 op (REPLACE x12, REPLACE_BZ x2, REPLACE_XZ x434), do pobrania 698084455 B (0.65 GiB), new_size=937791488
pokrycie partycji: 228953 / 228953 blokow (100.0%)
  [  0.5%] op 1/448, 3 MiB / 666 MiB, 7.19 MB/s, ETA 1.5 min
  [ 75.1%] op 325/448, 500 MiB / 666 MiB, 16.42 MB/s, ETA 0.2 min
  [100.0%] op 448/448, 667 MiB / 666 MiB, 16.29 MB/s, ETA -0.0 min
gotowe: /tmp/donor/system.img = 937791488 B (oczek. 937791488) w 0.7 min; requestow HTTP: 454
new_partition_info.hash (do weryfikacji zewnetrznej): 10011a1b73797374656d2f62696e2f6f74617072656f70745f7363726970743a
erofs-check: magic e2e1f5e0 @1024 OK
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
partycja system_ext: 302 op (REPLACE x12, REPLACE_BZ x1, REPLACE_XZ x289), do pobrania 454947176 B (0.42 GiB), new_size=632840192
pokrycie partycji: 154502 / 154502 blokow (100.0%)
  [  1.2%] op 1/302, 5 MiB / 434 MiB, 20.38 MB/s, ETA 0.4 min
  [ 91.7%] op 279/302, 398 MiB / 434 MiB, 13.12 MB/s, ETA 0.0 min
  [100.0%] op 302/302, 435 MiB / 434 MiB, 13.30 MB/s, ETA -0.0 min
gotowe: /tmp/donor/system_ext.img = 632840192 B (oczek. 632840192) w 0.6 min; requestow HTTP: 308
new_partition_info.hash (do weryfikacji zewnetrznej): 5f6578743a280880c0e1ad0212207340a8367d3da8e4bdcf56a0f53dd7b77d87
erofs-check: magic e2e1f5e0 @1024 OK
```
## manifesty
```
md5=e4c33b162f018eaa0781d4e4bffd6776
size=521141094
parts=1
apps=MIUICalculator,MIUIGallery,MIUINotes,MiuiCamera,MiuiHome
fonts=25
framework=Miui-WindowManager-Shell.jar,MiuiBooster.jar,MiuiSettingsSearchLib.jar,camerax-vendor-extensions.jar,global-cleaner-empty.jar,gson.jar,livephoto-lite.jar,miui-appcompat.appcontinuity.jar,miui-appcompat.jar,miui-cameraopt.jar,miui-connectivity-service.jar,miui-embedding-window.jar,miui-enterprise-sdk.jar,miui-framework-pointer-pad.jar,miui-framework.autoui.jar,miui-framework.hovermode.jar,miui-framework.hyperviewscale.jar,miui-framework.jar,miui-framework.thirdappopt.jar,miui-services-pointer-pad.jar,miui-services.autoui.jar,miui-services.hovermode.jar,miui-services.hyperviewscale.jar,miui-services.jar,miui-services.thirdappopt.jar,miui-telephony-common.jar,miui-wifi-service.jar,miui.car.server.jar,miuix.jar,security-device-credential-sdk.jar
source=nieznany
created=2026-10-03T14:00:43Z
md5=cfc5e04e1b7cb17a8bcd556b324f91fa
size=6445187072
parts=4
sha256(product.img)=384396ce94ae8620b51eca9b5daa3cb436fba380b644bed9a932e186356f9870
```
## dysk
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/root       145G   67G   78G  47% /
```
