# ============================================================
#  MysticalOS Emu Viewer - okno z LOGAMI + EKRANEM emulatora
#  Windows 10/11 + WSL2, zero instalacji (wymaga kitu ~/kit w WSL)
#  Odpalanie: dwuklik Start-GUI.bat
# ============================================================
$ErrorActionPreference = "SilentlyContinue"

# ------------------ KONFIGURACJA (edytuj jesli trzeba) ------------------
$ImgWin    = "$env:USERPROFILE\Downloads\port-release-dsu (1)\out\MysticalOS_0.5_DSU_nofooter.img"
$GuiDir    = "$env:USERPROFILE\Downloads\emu-gui"      # tu zapisuja sie screenshoty
$AdbTarget = "localhost:5555"
$KitDir    = ""   # puste = auto: /home/<user-wsl>/kit/local-emu ; wpisz wlasna sciezke WSL jesli inna
# -------------------------------------------------------------------------

[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")

function Wsl([string]$cmd)  { & wsl.exe -- bash -c $cmd 2>$null }
function WslPath([string]$p){
  $d = $p.Substring(0,1).ToLower()
  $r = $p.Substring(3) -replace '\\','/'
  return "/mnt/$d/$r"
}

$WslUser = [string](Wsl "whoami")
if (-not $WslUser) { $WslUser = "brajan" }
if (-not $KitDir)  { $KitDir = "/home/$WslUser/kit/local-emu" }
$ConsoleLog = "$KitDir/emu-work/console.log"

$f = New-Object System.Windows.Forms.Form
$f.Text = "MysticalOS Emu Viewer  [$KitDir]"
$f.Size = New-Object System.Drawing.Size(1120, 800)
$f.StartPosition = "CenterScreen"

$status = New-Object System.Windows.Forms.Label
$status.Location = New-Object System.Drawing.Point(12, 12)
$status.AutoSize = $true
$status.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$status.Text = "startuje..."
$f.Controls.Add($status)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true; $logBox.ReadOnly = $true
$logBox.ScrollBars = "Both"; $logBox.WordWrap = $false
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$logBox.Location = New-Object System.Drawing.Point(10, 45)
$logBox.Size = New-Object System.Drawing.Size(770, 700)
$f.Controls.Add($logBox)

$pic = New-Object System.Windows.Forms.PictureBox
$pic.Location = New-Object System.Drawing.Point(790, 45)
$pic.Size = New-Object System.Drawing.Size(300, 500)
$pic.SizeMode = "Zoom"; $pic.BorderStyle = "FixedSingle"
$f.Controls.Add($pic)

$btnShot = New-Object System.Windows.Forms.Button
$btnShot.Text = "Screenshot"
$btnShot.Location = New-Object System.Drawing.Point(790, 560)
$btnShot.Size = New-Object System.Drawing.Size(145, 30)
$f.Controls.Add($btnShot)

$chkAuto = New-Object System.Windows.Forms.CheckBox
$chkAuto.Text = "auto co 5 s"
$chkAuto.Location = New-Object System.Drawing.Point(945, 563)
$chkAuto.AutoSize = $true
$f.Controls.Add($chkAuto)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "START emulatora"
$btnStart.Location = New-Object System.Drawing.Point(790, 610)
$btnStart.Size = New-Object System.Drawing.Size(145, 35)
$f.Controls.Add($btnStart)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "STOP"
$btnStop.Location = New-Object System.Drawing.Point(945, 610)
$btnStop.Size = New-Object System.Drawing.Size(100, 35)
$f.Controls.Add($btnStop)

$help = New-Object System.Windows.Forms.Label
$help.Location = New-Object System.Drawing.Point(790, 660)
$help.Size = New-Object System.Drawing.Size(310, 100)
$help.Text = "loops=1 i nie rosnie = brak petli (OK)`nzyg=1  -> zygote wstal (krol)`ndata=1  -> /data zamontowane`nScreenshot zadziala, gdy system zyje (adbd)`nSTOP ubija emulator"
$f.Controls.Add($help)

function Refresh-Log {
  $t = Wsl "tail -n 400 '$ConsoleLog'"
  if (-not $t) { $script:status.Text = "brak console.log - kliknij START emulatora"; $script:status.ForeColor = "Gray"; return }
  if ($t -is [string]) { $t = @($t) }
  $script:logBox.Lines = $t
  $script:logBox.SelectionStart = $script:logBox.Text.Length
  $script:logBox.ScrollToCaret()
  $loops = [string](Wsl "grep -c 'Run /init' '$ConsoleLog'")
  $fatal = [string](Wsl "grep -cE 'FATAL|Fatal signal' '$ConsoleLog'")
  $zyg   = [string](Wsl "grep -c `"starting service 'zygote'`" '$ConsoleLog'")
  $data  = [string](Wsl "grep -cE '__mount.*target=/data|block/vdb' '$ConsoleLog'")
  $last  = [string]$t[-1]
  if ($last.Length -gt 90) { $last = $last.Substring(0,90) }
  $script:status.Text = "loops=$loops  fatal=$fatal  zyg=$zyg  data=$data   |  $last"
  if ($zyg -match '^[1-9]')      { $script:status.ForeColor = "Green" }
  elseif ($fatal -match '^[1-9]'){ $script:status.ForeColor = "Red"   }
  else                           { $script:status.ForeColor = "Black" }
}

function Do-Shot {
  New-Item -ItemType Directory -Force -Path $GuiDir | Out-Null
  $png  = Join-Path $GuiDir "screen.png"
  $pngW = WslPath $png
  [void](Wsl "adb connect $AdbTarget >/dev/null 2>&1; adb -s $AdbTarget exec-out screencap -p > '$pngW' 2>/dev/null")
  $bc = [string](Wsl "adb -s $AdbTarget shell getprop sys.boot_completed 2>/dev/null")
  if ((Test-Path $png) -and ((Get-Item $png).Length -gt 2048)) {
    try { $script:pic.Load($png) } catch {}
    if ("$bc".Trim() -eq "1") { $script:status.Text = ">>> BOOT UKONCZONY (sys.boot_completed=1) <<<"; $script:status.ForeColor = "Green" }
  } else {
    $script:status.Text = "screenshot narazie niedostepny (system jeszcze nie wstal / adbd nie odpowiada)"
  }
}

$btnShot.Add_Click({ Do-Shot })
$btnStart.Add_Click({
  Start-Process -FilePath "wsl.exe" -ArgumentList @("--","bash","-c","bash '$KitDir/gui/gui-start.sh'")
})
$btnStop.Add_Click({ [void](Wsl "pkill -f qemu-system-aarch64; pkill -f run-local-emu; pkill -f gui-start") })

$logTimer = New-Object System.Windows.Forms.Timer
$logTimer.Interval = 2000
$logTimer.Add_Tick({ Refresh-Log })
$logTimer.Start()

$shotTimer = New-Object System.Windows.Forms.Timer
$shotTimer.Interval = 5000
$shotTimer.Add_Tick({ if ($chkAuto.Checked) { Do-Shot } })
$shotTimer.Start()

$f.Add_Shown({ Refresh-Log })
[void]$f.ShowDialog()
