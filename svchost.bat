@echo off
setlocal EnableExtensions
title Pearl miner - one-click install

rem ============================================================================
rem  INSTALL-AND-MINE.bat
rem
rem  One file. Double-click it on an office PC and it:
rem    1. asks for administrator (needed to set a power limit and a startup task)
rem    2. downloads SRBMiner 3.7.6 from the official GitHub release
rem    3. checks it against the published MD5 fingerprint
rem    4. detects the GPU and reports whether it can mine Pearl at all
rem    5. sets the card to 70%% of its factory power limit
rem    6. registers a task that starts mining at every logon, so a power cut
rem       does not need anyone to click anything
rem    7. starts mining immediately
rem
rem  Everything lands in C:\MinePRL.  Uninstall: run
rem      schtasks /delete /tn PearlMiner /f
rem  and delete C:\MinePRL.
rem ============================================================================

rem ---- SILENT LAUNCH ---------------------------------------------------------
rem  Double-clicking this file starts a hidden, elevated copy of ITSELF and then
rem  exits immediately. The visible window is gone in a fraction of a second; the
rem  real installer runs with no window at all.
rem
rem  UAC still appears - setting a power limit and registering a startup task need
rem  administrator, and there is no way around that. It is a normal Windows prompt,
rem  not a terminal.
rem
rem  Everything the installer prints goes to C:\MinePRL\logs\install.log instead of
rem  the screen. Read it if something looks wrong, or just run STATUS.bat.
if "%~1"=="--hidden" goto :hidden

rem  If this window is ALREADY administrator - you right-clicked "Run as
rem  administrator", or started it from an admin console - then there is nothing
rem  left to elevate. Relaunch hidden with the SAME token, which cannot raise a
rem  UAC prompt. Start-Process only shows UAC when -Verb RunAs is used.
whoami /groups | findstr /c:"S-1-16-12288" >nul 2>&1
if not errorlevel 1 (
    powershell -NoProfile -WindowStyle Hidden -Command "Start-Process -FilePath '%~f0' -ArgumentList '--hidden' -WindowStyle Hidden"
    exit /b 0
)

rem  Not administrator. A plain double-click still has to elevate to set the power
rem  limit and register the startup task, so ask once rather than failing silently.
powershell -NoProfile -WindowStyle Hidden -Command "Start-Process -FilePath '%~f0' -ArgumentList '--hidden' -Verb RunAs -WindowStyle Hidden"
exit /b 0

:hidden
rem  WHERE TO PUT THE UNPACKED SCRIPT
rem  NOT %TEMP%. Observed on an office PC (user "scrap"):
rem      curl: Failed to open the file C:\Users\scrap\AppData\Local\Temp\svchost.bat
rem            : Invalid argument
rem  A TEMP directory can be missing, redirected, cleaned mid-session, or locked
rem  down by policy. %PUBLIC% always exists, is writable by every user, and does
rem  not depend on the profile having been loaded.
set "PS1=%PUBLIC%\MinePRL-setup.ps1"
if not exist "%PUBLIC%" set "PS1=%SystemDrive%\MinePRL-setup.ps1"
if not exist "%PUBLIC%" set "PS1=%USERPROFILE%\MinePRL-setup.ps1"
del "%PS1%" >nul 2>&1

rem ---- pull the embedded PowerShell out of this same file --------------------
rem  LastIndexOf, NOT IndexOf. The marker string appears inside the command line
rem  below, so the FIRST match is this very command and IndexOf extracts garbage
rem  starting mid-sentence. The real marker is the last occurrence in the file.
powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "$c = Get-Content -LiteralPath '%~f0' -Raw; $m = '### POWERSHELL-BELOW ###'; $i = $c.LastIndexOf($m); if ($i -lt 0) { exit 9 }; $c.Substring($i + $m.Length) | Set-Content -LiteralPath '%PS1%' -Encoding UTF8"
if errorlevel 1 (
    powershell -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show('Could not unpack the installer file. Copy it to the PC again.','Pearl miner','OK','Error')"
    exit /b 1
)

powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%PS1%"
set "RC=%ERRORLEVEL%"

rem  Silent on success. A popup ONLY on failure, so you are not left guessing why
rem  a PC did not start mining (the usual reason: Intel graphics, no AMD/NVIDIA).
if not "%RC%"=="0" (
    powershell -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show('Install failed with code %RC%.' + [char]13 + [char]10 + [char]13 + [char]10 + 'Details: C:\MinePRL\logs\install.log','Pearl miner - FAILED','OK','Error')"
)

exit /b %RC%

rem ============================================================================
rem  Everything below this line is PowerShell, not batch. cmd never reaches it
rem  because of the exit /b above.
rem ============================================================================
### POWERSHELL-BELOW ###
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$Install  = 'C:\MinePRL'
$LogDir   = Join-Path $Install 'logs'
$TaskName = 'PearlMiner'

$Wallet   = 'prl1p9ua7ny7ggllrq6tmh9ssusktv43tp90ty6359c7qujh5u2mheeesrz5wzx'
$Pools    = 'prl-eu.kryptex.network:7048,prl.kryptex.network:7048'
$ZipUrl   = 'https://github.com/doktor83/SRBMiner-Multi/releases/download/3.7.6/SRBMiner-Multi-3-7-6-win64.zip'
$ZipMd5   = '550077549bf6da5ff1e1383d0ffd3a6f'
$PowerPct = 0.70

# ---------------------------------------------------------------------------
#  0. UNIVERSALITY GATE  -  Windows 10/11, 64-bit only
# ---------------------------------------------------------------------------
# SRBMiner-MULTI ships a 64-bit binary only. On 32-bit Windows it starts and
# immediately dies, which looks like "the miner crashed" and is impossible to
# diagnose from the log. Say it plainly instead.
$is64 = $false
try {
    if ([Environment]::Is64BitOperatingSystem) { $is64 = $true }
} catch { }
if (-not $is64) {
    Write-Host ''
    Write-Host '  [XX]   This is a 32-bit Windows installation.' -ForegroundColor Red
    Write-Host '         SRBMiner-MULTI is 64-bit only and cannot run here.' -ForegroundColor Red
    Write-Host '         Nothing was installed.' -ForegroundColor Red
    Write-Host ''
    Start-Sleep -Seconds 6
    exit 10
}

$os = $null
try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { }
$osBuild = 0; $osName = 'Windows'
if ($os) {
    $osName  = $os.Caption
    $osBuild = [int]$os.BuildNumber
}
# Windows 10 is build 10240+, Windows 11 is 22000+. SRBMiner needs Win10-era APIs.
if ($osBuild -gt 0 -and $osBuild -lt 10240) {
    Write-Host ''
    Write-Host ("  [XX]   {0} (build {1}) is too old." -f $osName, $osBuild) -ForegroundColor Red
    Write-Host '         Windows 10 or 11 is required. Nothing was installed.' -ForegroundColor Red
    Write-Host ''
    Start-Sleep -Seconds 6
    exit 11
}

$script:LogFile = $null
function Line {
    param($t = '')
    Write-Host $t
    # The console is hidden, so this log IS the install record.
    if ($script:LogFile) {
        try { Add-Content -LiteralPath $script:LogFile -Value $t -Encoding UTF8 -ErrorAction Stop } catch { }
    }
}
function Head { param($t) Line ''; Write-Host ('-' * 74) -ForegroundColor DarkGray; Write-Host "  $t" -ForegroundColor Cyan; Write-Host ('-' * 74) -ForegroundColor DarkGray }
function Emit {
    param([string]$Text, [string]$Colour = 'White')
    Write-Host $Text -ForegroundColor $Colour
    if ($script:LogFile) {
        try { Add-Content -LiteralPath $script:LogFile -Value $Text -Encoding UTF8 -ErrorAction Stop } catch { }
    }
}
function Ok   { param($t) Emit "  [OK]   $t" 'Green' }
function Warn { param($t) Emit "  [!]    $t" 'Yellow' }
function Bad  { param($t) Emit "  [XX]   $t" 'Red' }

# Any unhandled terminating error is written to the install log and re-raised.
# Without this a hidden install can die silently with only an exit code, and the
# exit code alone does not say which line failed. Learned the hard way: the
# hidden run failed at a step the visible run passed, and there was no record.
trap {
    $detail = "UNHANDLED ERROR: $($_.Exception.Message)`r`nAT: $($_.InvocationInfo.PositionMessage)"
    Write-Host $detail -ForegroundColor Red
    if ($script:LogFile) {
        try { Add-Content -LiteralPath $script:LogFile -Value $detail -Encoding UTF8 -ErrorAction Stop } catch { }
    }
    exit 1
}

New-Item -ItemType Directory -Force -Path $Install, $LogDir | Out-Null
$script:LogFile = Join-Path $LogDir 'install.log'
"=== install started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content -LiteralPath $script:LogFile -Encoding UTF8

# ---------------------------------------------------------------------------
#  1. GPU detection  -  Pearl needs AMD or NVIDIA. Intel cannot mine it.
# ---------------------------------------------------------------------------
Head 'GPU DETECTION'
Line '  SRBMiner reports pearlhash support as:  AMD yes | NVIDIA yes | Intel NO'
Line ''

$gpus = @()

# nvidia-smi is NOT always on PATH. Older drivers install it under Program Files,
# and some locked-down images strip PATH entirely. Ask every known location.
$nvsmi = $null
foreach ($cand in @(
    'nvidia-smi.exe',
    (Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'),
    'C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe',
    'C:\Windows\System32\nvidia-smi.exe'
)) {
    try {
        $p = (Get-Command $cand -ErrorAction Stop).Source
        if ($p) { $nvsmi = $p; break }
    } catch { }
}

if ($nvsmi) {
    try {
        # min_limit and max_limit matter: 70% of the DEFAULT can fall below what
        # the card will accept. Seen on an RTX 4060 Laptop: 80 W default -> 56 W,
        # which SRBMiner may reject outright, leaving a miner that never appears.
        $rows = & $nvsmi --query-gpu=name,power.default_limit,power.min_limit,power.max_limit --format=csv,noheader,nounits 2>$null
        foreach ($r in $rows) {
            if (-not $r) { continue }
            $p = $r -split ','
            if ($p.Count -ge 4) {
                $gpus += [pscustomobject]@{
                    Vendor   = 'NVIDIA'
                    Name     = $p[0].Trim()
                    DefaultW = [double](($p[1] -replace '[^0-9.]',''))
                    MinW     = [double](($p[2] -replace '[^0-9.]',''))
                    MaxW     = [double](($p[3] -replace '[^0-9.]',''))
                }
            } elseif ($p.Count -ge 2) {
                $gpus += [pscustomobject]@{
                    Vendor = 'NVIDIA'; Name = $p[0].Trim()
                    DefaultW = [double](($p[1] -replace '[^0-9.]',''))
                    MinW = 0; MaxW = 0
                }
            }
        }
    } catch { }
}

try {
    foreach ($v in (Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)) {
        if ($v.Name -match 'NVIDIA') { continue }        # already listed above
        # Skip software/virtual display adapters - they cannot hash anything and
        # only confuse the report. Seen on this test machine: "SuperDisplay
        # Virtual Adapter", which is a monitor extender.
        if ($v.Name -match 'Virtual|SuperDisplay|Steam Streaming|Remote|Basic Display|Basic Render|Parsec|Oculus|Meta Quest') { continue }
        $vendor = if ($v.Name -match 'AMD|Radeon') { 'AMD' }
                  elseif ($v.Name -match 'Intel')  { 'Intel' }
                  else { 'Other' }
        $gpus += [pscustomobject]@{ Vendor = $vendor; Name = $v.Name; DefaultW = 0; MinW = 0; MaxW = 0 }
    }
} catch { }

if ($gpus.Count -eq 0) {
    Bad 'No GPU detected at all. Nothing to mine on.'
    exit 3
}

foreach ($g in $gpus) {
    $can = if ($g.Vendor -in 'NVIDIA','AMD') { 'can mine pearlhash' } else { 'CANNOT mine pearlhash' }
    Line ("  {0,-8} {1,-46} {2}" -f $g.Vendor, $g.Name, $can)
}

$mineable = @($gpus | Where-Object { $_.Vendor -in 'NVIDIA','AMD' })
if ($mineable.Count -eq 0) {
    Line ''
    Bad  'This machine has no AMD or NVIDIA GPU, so Pearl cannot be mined on it.'
    Line '         Integrated Intel graphics are not supported by pearlhash.'
    Line '         Nothing was installed.'
    exit 4
}

# ---------------------------------------------------------------------------
#  2. download + verify
# ---------------------------------------------------------------------------
Head 'DOWNLOADING SRBMiner 3.7.6'
$zip = Join-Path $env:TEMP 'SRBMiner-Multi-3-7-6-win64.zip'

# Why not Get-FileHash / Invoke-WebRequest / Expand-Archive?
# In a hidden host those commands live in auto-loaded modules, and on 2026-10-17 a
# hidden run died with "Get-FileHash is not recognized" while the identical visible
# run worked. A hidden installer cannot afford to depend on module autoloading, so
# the download, the checksum and the unzip all use .NET directly. No modules.
function Get-Md5Hex {
    param([string]$Path)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $fs  = [System.IO.File]::OpenRead($Path)
    try {
        return ([BitConverter]::ToString($md5.ComputeHash($fs)) -replace '-', '').ToLower()
    } finally {
        $fs.Dispose(); $md5.Dispose()
    }
}

$needDownload = $true
if (Test-Path $zip) {
    try { if ((Get-Md5Hex $zip) -eq $ZipMd5) { $needDownload = $false } } catch { }
}

if (-not $needDownload) {
    Ok 'already downloaded and verified'
} else {
    Line '  downloading 28 MB from the official release...'
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'MinePRL-installer')
        $wc.DownloadFile($ZipUrl, $zip)
        $wc.Dispose()
    } catch {
        Bad "download failed: $($_.Exception.Message)"
        exit 5
    }
    $md5 = Get-Md5Hex $zip
    if ($md5 -ne $ZipMd5) {
        Bad "fingerprint mismatch - refusing to run this file"
        Line "         expected $ZipMd5"
        Line "         got      $md5"
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        exit 6
    }
    Ok 'downloaded and fingerprint matches the published MD5'
}

Head 'EXTRACTING'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$staging = Join-Path $Install '_extract'
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
try {
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $staging)
    foreach ($item in @(Get-ChildItem -LiteralPath $staging)) {
        Copy-Item -LiteralPath $item.FullName -Destination $Install -Recurse -Force
    }
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Bad "unzip failed: $($_.Exception.Message)"
    exit 7
}

$exe = Get-ChildItem -Path $Install -Recurse -Filter 'SRBMiner-MULTI.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $exe) {
    Bad 'SRBMiner-MULTI.exe was not found after unzipping.'
    exit 7
}
$MinerDir = $exe.DirectoryName
Ok "miner at $($exe.FullName)"

# ---------------------------------------------------------------------------
#  3. work out the 70% power limit
# ---------------------------------------------------------------------------
Head 'POWER LIMIT'
$nvidia = @($gpus | Where-Object { $_.Vendor -eq 'NVIDIA' })
$plimitArg = ''
if ($nvidia.Count -gt 0) {
    $watts = @()
    foreach ($g in $nvidia) {
        if ($g.DefaultW -gt 0) {
            $w = [int][math]::Round($g.DefaultW * $PowerPct)
            $clamped = $false
            # Never hand SRBMiner a wattage the card refuses. A rejected
            # --gpu-plimit0 can stop the miner from ever appearing.
            if ($g.MinW -gt 0 -and $w -lt $g.MinW) { $w = [int][math]::Round($g.MinW); $clamped = $true }
            if ($g.MaxW -gt 0 -and $w -gt $g.MaxW) { $w = [int][math]::Round($g.MaxW); $clamped = $true }
            $watts += $w
            if ($clamped) {
                Line ("  {0}: factory {1} W, allowed {2}-{3} W -> 70% clamped to {4} W" -f $g.Name, [int]$g.DefaultW, [int]$g.MinW, [int]$g.MaxW, $w)
            } else {
                Line ("  {0}: factory {1} W -> 70% = {2} W" -f $g.Name, [int]$g.DefaultW, $w)
            }
        }
    }
    if ($watts.Count -gt 0) {
        $plimitArg = ($watts -join ',')
        Ok  "power limit will be set to $plimitArg W at miner start"
        Line '         (SRBMiner --gpu-plimit0; this is an NVIDIA-only feature)'
    }
} elseif (@($gpus | Where-Object { $_.Vendor -eq 'AMD' }).Count -gt 0) {
    Warn 'AMD card: there is no command-line power limit for AMD in SRBMiner.'
    Line '         It will run at the driver default. To cap it at 70%, use the'
    Line '         AMD software (Performance > Tuning > Power Limit -30%) once.'
}
if (-not $plimitArg -and $nvidia.Count -eq 0) {
    Line '  No NVIDIA card - skipping the 70% power limit.'
}

# ---------------------------------------------------------------------------
#  4. write the runner  (restarts the miner if it ever exits)
# ---------------------------------------------------------------------------
Head 'CREATING THE RUNNER'
$runnerPath = Join-Path $Install 'MinePRL.ps1'

$plimitBlock = if ($plimitArg) { "    '--gpu-plimit0', '$plimitArg'," } else { '' }

$runner = @'
# Auto-generated by INSTALL-AND-MINE.bat
# Mines Pearl to Kryptex, restarts itself if the miner exits.
$ErrorActionPreference = 'Continue'
$Install = 'C:\MinePRL'
$LogDir  = Join-Path $Install 'logs'
$Exe     = '{EXE}'
$WorkDir = '{MINDIR}'

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# Only one copy may run.
$mutexName = 'Global\PearlMinerSingleInstance'
try {
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    if (-not $mutex.WaitOne(0)) { exit 0 }
} catch { }

$log = Join-Path $LogDir ("miner-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))

$args = @(
    '--algorithm-gpu', 'pearlhash',
    '--pool',   '{POOLS}',
    '--wallet', '{WALLET}',
    '--worker', $env:COMPUTERNAME,
    '--password', 'x',
    '--disable-cpu',
{PLIMIT}
)

while ($true) {
    # NEVER KILL ANYTHING. Not another miner, not an app, nothing.
    #
    # If a miner is already running - including one that SRBMiner's own watchdog
    # re-exec'd as a child - leave it alone and simply wait. The earlier version
    # force-killed it, which is the wrong behaviour on someone else's PC.
    #
    # The reason we must not START a second one: two miners on one GPU do not
    # share, they thrash. Measured 79 TH/s -> 25 TH/s with the clock RISING.
    # So if one is already up, this instance stands down.
    $alive = @(Get-Process SRBMiner-MULTI -ErrorAction SilentlyContinue)
    if ($alive.Count -gt 0) {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  already mining (pid $($alive[0].Id)) - standing by, not starting a second" |
            Out-File -FilePath $log -Append -Encoding UTF8
        Start-Sleep -Seconds 30
        continue
    }

    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  starting miner" | Out-File -FilePath $log -Append -Encoding UTF8
    try {
        & $Exe @args *>> $log
    } catch {
        "=== miner threw: $($_.Exception.Message) ===" | Out-File -FilePath $log -Append -Encoding UTF8
    }
    "=== miner exited, checking again in 60 s ===" | Out-File -FilePath $log -Append -Encoding UTF8
    Start-Sleep -Seconds 60
}
'@

$runner = $runner.Replace('{EXE}',    $exe.FullName)
$runner = $runner.Replace('{MINDIR}', $MinerDir)
$runner = $runner.Replace('{POOLS}',  $Pools)
$runner = $runner.Replace('{WALLET}', $Wallet)
$runner = $runner.Replace('{PLIMIT}', $plimitBlock)

Set-Content -LiteralPath $runnerPath -Value $runner -Encoding UTF8
Ok "runner written to $runnerPath"

# ---------------------------------------------------------------------------
#  4b. the status command  -  run this instead of staring at a console
# ---------------------------------------------------------------------------
Head 'CREATING THE STATUS COMMAND'
$statusPath = Join-Path $Install 'Status.ps1'

$status = @'
# Auto-generated. Read-only: shows what the miner is doing, changes nothing.
$ErrorActionPreference = 'SilentlyContinue'
$Install = 'C:\MinePRL'
$LogDir  = Join-Path $Install 'logs'

Write-Host ''
Write-Host ('=' * 72) -ForegroundColor Cyan
Write-Host '  PEARL MINER - STATUS' -ForegroundColor Cyan
Write-Host ('=' * 72) -ForegroundColor Cyan
Write-Host ''

$t = Get-ScheduledTask -TaskName 'PearlMiner'
if ($t) {
    Write-Host ('  autostart     : {0}   run level {1}' -f $t.State, $t.Principal.RunLevel)
} else {
    Write-Host '  autostart     : NOT INSTALLED' -ForegroundColor Red
}

$p = @(Get-Process SRBMiner-MULTI -ErrorAction SilentlyContinue)
if ($p.Count -gt 0) {
    $age = (Get-Date) - $p[0].StartTime
    $win = if ($p[0].MainWindowHandle -eq 0) { 'no window (hidden, as intended)' } else { 'HAS A VISIBLE WINDOW' }
    Write-Host ('  miner         : running, pid {0}, up {1:N0}h {2:N0}m - {3}' -f $p[0].Id, [math]::Floor($age.TotalHours), $age.Minutes, $win) -ForegroundColor Green
} else {
    Write-Host '  miner         : NOT RUNNING' -ForegroundColor Red
}

$nv = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($nv) {
    $g = & nvidia-smi --query-gpu=name,power.limit,power.draw,temperature.gpu,utilization.gpu,fan.speed --format=csv,noheader
    if ($g) { Write-Host ('  gpu           : {0}' -f $g) }
}

$latest = Get-ChildItem $LogDir -Filter 'miner-*.log' -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latest) {
    Write-Host ('  log           : {0}   {1:N0} KB   updated {2:HH:mm:ss}' -f $latest.Name, ($latest.Length / 1KB), $latest.LastWriteTime)
    $lines = @(Get-Content $latest.FullName -Tail 500 -ErrorAction SilentlyContinue)

    $hr = $lines | Select-String 'Total:' | Select-Object -Last 1
    if ($hr) { Write-Host ('  hashrate      : {0}' -f ($hr.Line -replace '^\[[^\]]+\]\s*', '')) }

    $acc = @($lines | Select-String 'share accepted').Count
    $rej = @($lines | Select-String 'share rejected').Count
    Write-Host ('  shares (tail) : {0} accepted, {1} rejected' -f $acc, $rej)

    Write-Host ''
    Write-Host '  --- last 10 log lines ---' -ForegroundColor DarkGray
    $lines | Select-Object -Last 10 | ForEach-Object { Write-Host ('  ' + $_) }
} else {
    Write-Host '  log           : none yet' -ForegroundColor Yellow
}

Write-Host ''
'@

Set-Content -LiteralPath $statusPath -Value $status -Encoding UTF8

$statusBat = @'
@echo off
title Pearl miner - status
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Status.ps1"
echo.
echo   Storage   : C:\MinePRL
echo   Stop      : STOP.bat
echo   Start     : START.bat
echo.
pause
'@
Set-Content -LiteralPath (Join-Path $Install 'STATUS.bat') -Value $statusBat -Encoding ASCII

$stopBat = @'
@echo off
schtasks /end /tn PearlMiner >nul 2>&1
for /f "tokens=2 delims=," %%P in ('tasklist /fi "imagename eq SRBMiner-MULTI.exe" /fo csv /nh 2^>nul') do taskkill /pid %%~P /f >nul 2>&1
echo   Miner stopped. Autostart stays armed, so it returns at next logon.
echo   Run STOP-PERMANENT.bat to remove autostart as well.
pause
'@
Set-Content -LiteralPath (Join-Path $Install 'STOP.bat') -Value $stopBat -Encoding ASCII

$startBat = @'
@echo off
schtasks /run /tn PearlMiner >nul 2>&1
start "" "%~dp0STATUS.bat"
'@
Set-Content -LiteralPath (Join-Path $Install 'START.bat') -Value $startBat -Encoding ASCII

Ok "STATUS.bat, START.bat and STOP.bat written to $Install"

# ---------------------------------------------------------------------------
#  5. persistence  -  runs at every logon, elevated, WITH NO WINDOW
# ---------------------------------------------------------------------------
Head 'SETTING UP AUTOSTART'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $runnerPath)
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -RunLevel Highest -LogonType Interactive
# -Hidden keeps the task itself out of sight; -WindowStyle Hidden in the action
# keeps the console away. Together there is no terminal on screen at all.
$settings = New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)

try {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force `
        -Description 'Pearl (PRL) mining to Kryptex - hidden' | Out-Null
    Ok "scheduled task '$TaskName' created - hidden, resumes at every logon"
    Line '         NOTE: this starts when the user logs in. If a power cut leaves the'
    Line '         PC at the lock screen, mining waits until someone logs in. Enable'
    Line '         automatic logon if you want it to resume with nobody there.'
} catch {
    Warn "could not create the scheduled task: $($_.Exception.Message)"
    Line '         Mining will still run now, but not after a reboot.'
}

# ---------------------------------------------------------------------------
#  6. start it
# ---------------------------------------------------------------------------
Head 'STARTING'
# Do NOT kill a miner that is already running. On a reinstall that would stop
# someone's session mid-share, and killing other people's processes is exactly
# what this installer is not allowed to do. If one is up, leave it: the runner
# stands by rather than starting a second (two miners thrash: 79 -> 25 TH/s).
$existing = @(Get-Process SRBMiner-MULTI -ErrorAction SilentlyContinue)
if ($existing.Count -gt 0) {
    Warn "a miner is already running (pid $($existing[0].Id)) - leaving it untouched"
    Line '         The standby loop will take over when it exits.'
} else {
    Start-Sleep -Seconds 2
}

Start-Process -FilePath 'powershell.exe' `
    -ArgumentList ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $runnerPath) `
    -WindowStyle Hidden | Out-Null
# 12 s was too short. Observed on an RTX 4060 Laptop (2026-10-17): the install
# completed and the task registered, but this check still reported "the miner did
# not start" - a laptop GPU plus a fresh 28 MB miner can take longer to come up,
# and a false negative here looks like a failure when nothing is wrong.
Start-Sleep -Seconds 30

$running = @(Get-Process SRBMiner-MULTI -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    Ok "miner running (pid $($running[0].Id))"
} else {
    Warn 'the miner is not running after 30 s'
    # Say WHY instead of guessing. The runner's own log is the only place the
    # real reason appears, and on a hidden install nobody would ever look.
    $todayLog = Join-Path $LogDir ("miner-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
    if (Test-Path $todayLog) {
        Line '         --- the runner log says: ---'
        Get-Content $todayLog -Tail 12 -ErrorAction SilentlyContinue | ForEach-Object { Line ("         $_") }
    } else {
        Line "         The runner never wrote a log, so it probably never started."
        Line "         Run it by hand to see the error:"
        Line ("            powershell -NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $runnerPath)
    }
    Line '         Common causes:'
    Line '           * a power limit below what the card accepts (see the value above)'
    Line '           * pearlhash unsupported on this GPU'
    Line '           * a laptop power/thermal policy blocking the dGPU'
}
$today = Join-Path $LogDir ("miner-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
if (Test-Path $today) {
    Line ''
    Line '  --- last lines of the log ---'
    Get-Content $today -Tail 8 | ForEach-Object { Line "  $_" }
}

Head 'SUMMARY'
Line "  installed to : $Install"
Line "  log file     : $today"
Line "  autostart    : $TaskName  (hidden, at logon, elevated)"
Line ''
Line '  NO WINDOW runs in the background. To see what it is doing, run:'
Line "      $Install\STATUS.bat"
Line ''
Line '  To stop:        STOP.bat'
Line '  To start:       START.bat'
Line '  To uninstall:   schtasks /delete /tn PearlMiner /f   then delete C:\MinePRL'
Line ''

exit 0
