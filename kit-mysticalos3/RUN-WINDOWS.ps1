# ============================================================================
#  MysticalOS 3 - JEDNOKLIKOWY BUILDER dla Windows (WSL2)
# ----------------------------------------------------------------------------
#  Ten skrypt robi WSZYSTKO: sprawdza WSL2, doklada brakujace pakiety,
#  pobiera kit z Google Drive, odpala pelny build (30-60 min) i wydaje
#  wyniki do folderu WYNIKI-mysticalos3 obok skryptu.
#
#  Wymagania: Windows 10 2004+ / Windows 11, ~25 GB wolnego na dysku C:.
#  Nie trzeba nic instalowac recznie - skrypt poprowadzi.
#
#  Uruchomienie:  podwojne klikniecie START-MYSTICALOS3.bat  (lub:
#                 powershell -ExecutionPolicy Bypass -File RUN-WINDOWS.ps1)
# ============================================================================
# vim: ft=powershell

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$env:WSL_UTF8 = "1"

# --- linki (Drive, publiczne, auto-pobierajace) -----------------------------
$KIT_URL     = "https://drive.google.com/uc?id=1rREQK84nCLj98povMjyQsKL9cdchWF8u&export=download"
$KIT_NAME    = "mysticalos3-local-kit.tar.gz"
$KIT_SHA256  = "0dd8d5d4604b88e1126d5493a5dc3fa98de1ed330fb7ccd8f1394d8696e1b56d"

function Say($m) { Write-Host "[MysticalOS3] $m" -ForegroundColor Cyan }
function Ok($m)  { Write-Host "[MysticalOS3] $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[MysticalOS3] $m" -ForegroundColor Yellow }
function Die($m) { Write-Host "[MysticalOS3] BLAD: $m" -ForegroundColor Red; Read-Host "Enter = zamknij"; exit 1 }

$BaseDir = $PSScriptRoot
if (-not $BaseDir) { $BaseDir = (Get-Location).Path }
$OutWin = Join-Path $BaseDir "WYNIKI-mysticalos3"

Write-Host ""
Say "MysticalOS 3 - lokalny build super.img (TB350FU S230982 -> HyperOS 4)"
Write-Host ""

# --- 1. dysk ----------------------------------------------------------------
$drive = Get-PSDrive -Name ($BaseDir.Substring(0,1))
$freeGB = [math]::Round($drive.Free / 1GB, 1)
Say "Dysk $($drive.Name): wolne $freeGB GB"
if ($freeGB -lt 25) { Die "Potrzeba min. 25 GB wolnego miejsca (build potrzebuje ~20 GB + zapas)." }

# --- 2. WSL2 ----------------------------------------------------------------
$wslOut = ""
try { $wslOut = (& wsl.exe --status 2>&1 | Out-String) -replace "`0","" } catch {}
$distros = @()
try {
    $raw = (& wsl.exe -l -q 2>&1 | Out-String) -replace "`0",""
    $distros = @($raw -split "`r?`n" | Where-Object { $_ -and $_.Trim() -ne "" -and $_ -notmatch "docker" } | ForEach-Object { $_.Trim() })
} catch {}

if (-not $distros -or $distros.Count -eq 0) {
    Warn "Brak dystrybucji Linux w WSL2."
    Warn "Zainstaluje ja teraz jako Administrator (jednorazowo; moze byc potrzebny restart)."
    $ans = Read-Host "Kontynuowac? [T/n]"
    if ($ans -ne "" -and $ans -notmatch "^[tT]") { Die "Przerwano." }
    try {
        Start-Process -Verb RunAs -Wait -FilePath "wsl.exe" -ArgumentList "--install","--no-launch","-d","Ubuntu"
    } catch { Die "Nie udalo sie podniesc uprawnien administratora: $_" }
    Write-Host ""
    Warn "Jesli instalator zazadal RESTARTU - zrestartuj, uruchom Ubuntu raz (utworz uzytkownika),"
    Warn "a potem uruchom TEN skrypt ponownie. Nie zamykaj tego okna, jesli restart nie byl potrzebny."
    Read-Host "Po instalacji nacisnij Enter, aby kontynuowac"
    # odswiez liste
    try {
        $raw = (& wsl.exe -l -q 2>&1 | Out-String) -replace "`0",""
        $distros = @($raw -split "`r?`n" | Where-Object { $_ -and $_.Trim() -ne "" -and $_ -notmatch "docker" } | ForEach-Object { $_.Trim() })
    } catch {}
    if (-not $distros -or $distros.Count -eq 0) { Die "Nadal brak dystrybucji WSL. Uruchom skrypt ponownie po restarcie." }
}

$D = $distros[0]
Ok "Dystrybucja WSL: $D"

# test czy dystrybucja zainicjalizowana (ma uzytkownika)
$probeOk = $false
try { & wsl.exe -d $D -e /bin/true 2>$null; if ($LASTEXITCODE -eq 0) { $probeOk = $true } } catch {}
if (-not $probeOk) {
    Warn "Dystrybucja $D nie zostala jeszcze uruchomiona ani razu."
    Warn "Otworz menu Start -> Ubuntu, zakoncz pierwsza konfiguracje (login + haslo),"
    Warn "a nastepnie uruchom ten skrypt ponownie."
    Die "Dystrybucja nie zainicjalizowana."
}

# --- 3. pakiety w WSL (jako root - bez pytania o haslo) ----------------------
Say "Sprawdzam/dokladam pakiety w WSL (curl, unzip, e2fsprogs, python3)..."
& wsl.exe -d $D -u root -e bash -c "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq >/dev/null 2>&1 || apt-get update -qq; apt-get install -y -qq curl unzip e2fsprogs python3 >/dev/null 2>&1 || apt-get install -y curl unzip e2fsprogs python3" | Out-Null
if ($LASTEXITCODE -ne 0) { Warn "apt-get zwrocil kod $LASTEXITCODE - sprobuje dalej, build sam sprawdzi zaleznosci." }

# --- 4. kit z Drive ----------------------------------------------------------
$kitWin = Join-Path $BaseDir $KIT_NAME
if (Test-Path $kitWin) {
    Ok "Kit juz pobrany: $KIT_NAME"
} else {
    Say "Pobieram kit z Google Drive (5,8 MB)..."
    try { Invoke-WebRequest -Uri $KIT_URL -OutFile $kitWin -UseBasicParsing }
    catch {
        Warn "Invoke-WebRequest nie dal rady ($_). Probuje curl.exe..."
        & curl.exe -L --retry 5 -o $kitWin $KIT_URL
        if ($LASTEXITCODE -ne 0) { Die "Nie udalo sie pobrac kitu. Pobierz reczenie: $KIT_URL" }
    }
    $h = (Get-FileHash -Path $kitWin -Algorithm SHA256).Hash.ToLower()
    if ($h -ne $KIT_SHA256.ToLower()) { Die "Kit ma zla sume SHA256 ($h). Pobierz kit recznie: $KIT_URL" }
    Ok "Kit pobrany, suma SHA256 zgodna."
}

# --- 5. build w WSL -----------------------------------------------------------
$kitWsl = (& wsl.exe -d $D -e wslpath -a $kitWin) -replace "`0",""
$kitWsl = ($kitWsl -split "`r?`n")[0].Trim()
if (-not $kitWsl) { Die "Nie umiem zamienic sciezki na WSL ($kitWin)." }

Say "Rozpakowuje kit i odpalam BUILD (30-60 min; NIE ZAMYKAJ OKNA)..."
Write-Host ""
& wsl.exe -d $D -e bash -lc "set -e; rm -rf ~/m3build; mkdir -p ~/m3build; cp '$kitWsl' ~/m3build/; tar xzf ~/m3build/$KIT_NAME -C ~/m3build; cd ~/m3build/kit-mysticalos3; ./build-mystical3.sh"
$rc = $LASTEXITCODE
Write-Host ""
if ($rc -ne 0) { Die "Build zakonczyl sie kodem $rc. Zobacz komunikaty powyzej (pelny log: ~/m3build/kit-mysticalos3/build/ w WSL)." }

# --- 6. wyniki do Windows ------------------------------------------------------
Say "Kopiuje wyniki do Windows..."
New-Item -ItemType Directory -Force -Path $OutWin | Out-Null
$outWinWsl = (& wsl.exe -d $D -e wslpath -a $OutWin) -replace "`0",""
$outWinWsl = ($outWinWsl -split "`r?`n")[0].Trim()
& wsl.exe -d $D -e bash -lc "cp ~/m3build/kit-mysticalos3/build/out/* '$outWinWsl'/ && cp ~/m3build/kit-mysticalos3/FLASH-M3.md '$outWinWsl'/ 2>/dev/null || true"
if ($LASTEXITCODE -ne 0) { Warn "Kopiowanie wynikow zwrocilo kod $LASTEXITCODE - sprawdz folder recznie." }

Ok "GOTOWE. Wyniki: $OutWin"
Get-ChildItem $OutWin | Format-Table Name, @{N="RozmiarMB";E={[math]::Round($_.Length/1MB,1)}} -AutoSize
Say "Instrukcja wgrania: FLASH-M3.md w folderze wynikow (fastbootd: vbmeta x3 -> super -> set-active=a)."
Start-Process explorer.exe $OutWin
Read-Host "Enter = zamknij"
