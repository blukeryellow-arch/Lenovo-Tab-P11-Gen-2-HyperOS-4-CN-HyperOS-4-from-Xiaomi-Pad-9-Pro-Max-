@echo off
rem ============================================================================
rem  MysticalOS 3 - START BUILD (Windows)
rem  Podwojne klikniecie = pobiera builder z Google Drive i odpala pelny build
rem  (WSL2 + kit MysticalOS 3; wyniki w folderze WYNIKI-mysticalos3).
rem  Nie zamykaj okna, az zobaczysz "GOTOWE".
rem ============================================================================
setlocal
cd /d "%~dp0"

set "PS1URL=https://drive.google.com/uc?id=1eZ9EtJyEbTsqfVoY4cu0OTKChv-2VBCR&export=download"

echo [MysticalOS3] Pobieram builder (RUN-WINDOWS.ps1) z Google Drive...
where curl.exe >nul 2>nul
if %errorlevel%==0 (
    curl.exe -L --retry 5 -o RUN-WINDOWS.ps1 "%PS1URL%"
) else (
    powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri '%PS1URL%' -OutFile 'RUN-WINDOWS.ps1'"
)
if not exist RUN-WINDOWS.ps1 (
    echo [MysticalOS3] BLAD: nie udalo sie pobrac builder-a.
    echo [MysticalOS3] Pobierz recznie: %PS1URL%
    pause
    exit /b 1
)

echo.
echo [MysticalOS3] Uruchamiam build (30-60 min; NIE ZAMYKAJ OKNA)...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RUN-WINDOWS.ps1"
set RC=%errorlevel%
echo.
if not "%RC%"=="0" (
    echo [MysticalOS3] Build zakonczyl sie bledem (kod %RC%). Przeczytaj komunikaty powyzej.
) else (
    echo [MysticalOS3] Wyniki w folderze: %~dp0WYNIKI-mysticalos3
)
pause
