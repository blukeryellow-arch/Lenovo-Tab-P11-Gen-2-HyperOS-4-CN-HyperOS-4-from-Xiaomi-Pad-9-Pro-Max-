@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ============================================================================
echo   Redmi 9C (angelica / angelican / blossom) - HyperOS 4 Debloated Port
echo ============================================================================
echo.
echo WYMAGANIA PRZED WGRANIEM:
echo   1. Odblokowany bootloader.
echo   2. Telefon uruchomiony w trybie FASTBOOT (Power + Vol Down).
echo   3. Zainstalowane sterowniki MediaTek / Android Fastboot oraz fastboot.exe w PATH
echo      (lub skopiuj fastboot.exe + AdbWinApi.dll obok tego skryptu).
echo   4. Zrobiony backup (np. MTKClient / Recovery) przed zmiana systemu!
echo.

where fastboot >nul 2>nul
if errorlevel 1 (
    if exist "%~dp0fastboot.exe" (
        set "FASTBOOT=%~dp0fastboot.exe"
    ) else (
        echo [BLAD] Nie znaleziono fastboot.exe! Pobierz Android Platform Tools i wrzuc do PATH lub obok skryptu.
        pause
        exit /b 1
    )
) else (
    set "FASTBOOT=fastboot"
)

if not exist "super.img" (
    echo [BLAD] Brak pliku super.img obok skryptu! Upewnij sie, ze wypakowales .7z.001 z wszystkimi 5 czesciami.
    pause
    exit /b 1
)

echo Sprawdzam polaczenie z telefonem w trybie fastboot...
"%FASTBOOT%" devices
echo.
set /p CONF="Wpisz TAK i nacisnij Enter, aby wgrac ROM (lub zamknij okno, aby anulowac): "
if /i not "%CONF%"=="TAK" exit /b 0

echo.
echo [1/5] Wgrywam vbmeta (AVB verification disabled)...
"%FASTBOOT%" flash vbmeta vbmeta.img || goto :fail
if exist "vbmeta_system.img" "%FASTBOOT%" flash vbmeta_system vbmeta_system.img || goto :fail
if exist "vbmeta_vendor.img" "%FASTBOOT%" flash vbmeta_vendor vbmeta_vendor.img || goto :fail

echo [2/5] Wgrywam dtbo.img...
if exist "dtbo.img" "%FASTBOOT%" flash dtbo dtbo.img || goto :fail

echo [3/5] Wgrywam boot.img (kernel 4.19 OSS blossom)...
"%FASTBOOT%" flash boot boot.img || goto :fail

echo [4/5] Wgrywam super.img (HyperOS 4 Debloated + blossom OSS vendor)...
"%FASTBOOT%" flash super super.img || goto :fail

echo.
set /p WIPE="Czy wyczyscic dane (fastboot -w) - WYMAGANE przy pierwszej instalacji? (T/N): "
if /i "%WIPE%"=="T" (
    echo [5/5] Czyszczenie userdata i cache...
    "%FASTBOOT%" -w
)

echo.
echo ============================================================================
echo   WGRAINE ZAKONCZONE! Restartuje telefon...
echo   Pierwszy start moze potrwac 3-8 minut.
echo ============================================================================
"%FASTBOOT%" reboot
pause
exit /b 0

:fail
echo.
echo [BLAD] Ktorys z etapow fastboot zakonczyl sie bledem! Nie restartuj na slepo - sprawdz komunikaty powyzej.
pause
exit /b 1
