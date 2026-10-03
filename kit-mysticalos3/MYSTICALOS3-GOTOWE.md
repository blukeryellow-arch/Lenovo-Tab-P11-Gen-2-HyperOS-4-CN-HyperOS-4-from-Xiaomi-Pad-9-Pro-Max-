# MYSTICALOS 3 - OBRAZ GOTOWY (2 pazdziernika 2026, 06:50)

## SKAD POBRAC (GitHub release — jestes wlascicielem, pobierasz zalogowany):
https://github.com/blukeryellow-arch/Lenovo-Tab-P11-Gen-2-HyperOS-4-CN-HyperOS-4-from-Xiaomi-Pad-9-Pro-Max-/releases/tag/mysticalos-3-super

Pobierz WSZYSTKIE pliki z release:
- super_mystical3.part.00 ... .31  (32 czastki, ~5,7 GB razem)
- vbmeta_disable.img + vbmeta_system_disable.img + vbmeta_vendor_disable.img
- boot_TB350FU_S230982_251013_ROW.img (bezpiecznik rollback)
- FLASH-M3.md + SHA256SUMS.txt + sprawdz.sh + simg2img.py + super.manifest

## CO MASZ W OBRAZIE (zgodnie z wymaganiami):
- PURGE Google/GMS (zostaje TYLKO WebView; zero YouTube/Maps/Gmail)
- microG v0.3.17.252432 + FakeStore (logowanie Google + push dzialaja)
- Aurora Store vc=76 swieza z F-Droid = jedyny sklep
- Magisk v30.7 (manager w systemie; root: apka -> Install -> Patch boot.img)
- 25 fontow Mi (transplant TIER C z HyperOS)
- stockowe aplikacje Lenova (aparat, kalkulator itd.) + geometria fabryczna
- vbmeta flags=3 (weryfikacja AVB wylaczona), slot B = rollback

## WGRANIE (5 krokow, ~30 min + 15 min pierwszy boot):
1. cat super_mystical3.part.* > super_mystical3.img
2. sha256sum -c SHA256SUMS.txt
3. fastboot flash vbmeta vbmeta_disable.img
   fastboot flash vbmeta_system vbmeta_system_disable.img
   fastboot flash vbmeta_vendor vbmeta_vendor_disable.img
4. fastboot reboot fastboot    (fastbootd!)
   fastboot flash super super_mystical3.img
   fastboot --set-active=a
   fastboot reboot
5. pierwszy boot 10-15 min NIE dotykaj; potem microG Settings -> Sign in
   (pelna instrukcja: PO-FLASHIE.md i PO-SZKOLE-START.md w tym folderze)

## AWARYJNIE:
- bootloop: fastboot flash boot boot_TB350FU_S230982_251013_ROW.img
- powrot do stock: fastboot --set-active=b && fastboot reboot

## ZOSTALO DO ZROBIENIA (opcje):
- repo GitHub jest nadal PUBLICZNE - wroc na private:
  Settings -> General -> Danger Zone -> Change visibility -> private
  (moj token nie ma uprawnien; pobieranie z release dziala Ci zalogowanemu)
- pelny transplant HyperOS 4 (MiuiCalculator/Camera/Notes itd.) wymaga
  donor-cache: m1 do pobrania product.img (10,3 GB z Drive) nie doszedl
  2x z powodu throttlingu Drive - moge sprobowac ponownie kiedy chcesz
