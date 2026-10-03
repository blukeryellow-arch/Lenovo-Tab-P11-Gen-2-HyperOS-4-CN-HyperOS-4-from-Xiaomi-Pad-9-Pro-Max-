@echo off
REM ================================================================
REM FLASH-ALL.bat - JEDEN DWUKLIK = caly flash MysticalOS 3 (TB350FU)
REM
REM DZIALA W DWUCH SYTUACJACH:
REM  A) w folderze jest JUZ super_mystical3.img (np. z zipa CALOSC) ->
REM     pomija sklejanie, tylko weryfikuje i flashuje,
REM  B) w folderze sa 32 czesci .part.00-.31 -> sam skleja je w img.
REM
REM Co robi: [1] img gotowy? (sklej jesli brak)  [2] SHA256
REM          [3] vbmeta x3  [4] fastbootd  [5] super  [6] slot A + reboot
REM
REM W FOLDERZE MUSZA BYC: super_mystical3.img LUB 32 czesci .part.*,
REM   vbmeta_disable.img + vbmeta_system_disable.img + vbmeta_vendor_disable.img,
REM   fastboot.exe (platform-tools) w folderze lub PATH.
REM Tablet: wylaczony -> trzymaj Vol- + Power -> ekran fastboot -> kabel USB.
REM ================================================================
cd /d "%~dp0"
setlocal EnableDelayedExpansion
set WANT_SHA=1d5f480922e5db47455915c822705ab749025f0004c776203b9d21ee1985b16e
set WANT_SZ=6313495592

set FB=fastboot
where fastboot >nul 2>nul
if errorlevel 1 (
  if exist fastboot.exe (set FB=fastboot.exe) else (
    echo [BLAD] Brak fastboot.exe - pobierz platform-tools i wrzuc fastboot.exe do folderu.
    pause & exit /b 1
  )
)

set MODE=OK
if exist super_mystical3.img (
  for %%A in (super_mystical3.img) do set SZ=%%~zA
  if "%SZ%"=="%WANT_SZ%" (
    echo [1/6] super_mystical3.img JUZ GOTOWY (%SZ% B) - nie sklejam.
  ) else (
    echo [1/6] super_mystical3.img ma zly rozmiar (%SZ% B) - kasuje i sklejam z czesci...
    del super_mystical3.img
    set MODE=JOIN
  )
) else (
  echo [1/6] Brak gotowego img - bede sklejal z czesci...
  set MODE=JOIN
)
if "%MODE%"=="JOIN" (
  dir /b super_mystical3.part.* 2>nul | find /c "super_mystical3.part" > "%TEMP%\m3np.txt"
  set /p NP=<"%TEMP%\m3np.txt"
  if not "!NP!"=="32" (
    echo [BLAD] Czesci: !NP!/32 - pobierz WSZYSTKIE z release albo rozpakuj zip CALOSC.
    pause & exit /b 1
  )
  echo        Sklejam 32 czesci (5-15 min, nie zamykaj okna)...
  copy /b super_mystical3.part.* super_mystical3.img >nul
  if errorlevel 1 ( echo [BLAD] Sklejanie nie wyszlo. & pause & exit /b 1 )
)

echo [2/6] Rozmiar + SHA256...
for %%A in (super_mystical3.img) do set SZ=%%~zA
if not "%SZ%"=="%WANT_SZ%" (
  echo [BLAD] Rozmiar %SZ% B ^!= %WANT_SZ% B - plik uszkodzony, pobierz ponownie.
  pause & exit /b 1
)
set H=
for /f "skip=1 delims=" %%H in ('certutil -hashfile super_mystical3.img SHA256') do if not defined H set H=%%H
set HC=%H: =%
if /i not "%HC%"=="%WANT_SHA%" (
  echo [BLAD] SHA256 nie zgadza sie (%HC%) - pobierz ponownie.
  pause & exit /b 1
)
echo        OK - plik zweryfikowany.

echo [3/6] Szukam tabletu w fastboot...
%FB% devices 2>nul | findstr /r "fastboot" >nul
if errorlevel 1 (
  echo [BLAD] Nie widze tabletu. Wylacz tablet, trzymaj Vol- + Power az pojawi sie fastboot, podlacz kabel.
  pause & exit /b 1
)
echo        OK. Flashuje vbmeta x3...
%FB% flash vbmeta vbmeta_disable.img
if errorlevel 1 goto :bladflash
%FB% flash vbmeta_system vbmeta_system_disable.img
if errorlevel 1 goto :bladflash
%FB% flash vbmeta_vendor vbmeta_vendor_disable.img
if errorlevel 1 goto :bladflash

echo [4/6] Restartuje tablet do fastbootd (do 60 s)...
%FB% reboot fastboot
set TRY=0
:czekajfd
timeout /t 5 /nobreak >nul
set /a TRY+=1
%FB% devices 2>nul | findstr /r "fastboot" >nul
if not errorlevel 1 goto :fdok
if %TRY% GTR 12 ( echo [BLAD] Tablet nie wrocil do trybu fastboot(d). & goto :bladflash )
goto :czekajfd
:fdok
echo [5/6] Flashuje super (10-20 min, NIE ODLACZAJ KABLA!)...
%FB% flash super super_mystical3.img
if errorlevel 1 goto :bladflash

echo [6/6] Ustawiam slot A i restartuje...
%FB% --set-active=a
echo.
echo ==============================================================
echo  GOTOWE! Tablet sie restartuje.
echo  Pierwszy boot: 10-15 min CZARNEGO EKRANU - normalne, nie dotykaj.
echo  Potem: microG Settings -^> Google Account -^> Sign in
echo  Launcher MIUI: Ustawienia -^> Aplikacje -^> Aplikacje domyslne -^> MiuiHome
echo  Awaryjnie (bootloop): %FB% flash boot boot_TB350FU_S230982_251013_ROW.img
echo  Rollback (stock):     %FB% --set-active=b
echo ==============================================================
%FB% reboot
pause
exit /b 0

:bladflash
echo.
echo [BLAD] Flash nie wyszedl - nic nie zginelo (slot B = stock).
echo Napisz agentowi KTORY krok sie zepsul, naprawimy.
pause
exit /b 1
