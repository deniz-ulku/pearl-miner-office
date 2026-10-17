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

rem ---- self-elevate ---------------------------------------------------------
rem  Test the elevation TOKEN rather than 'net session': net session also fails
rem  when the Server service is stopped, which would re-elevate forever.
whoami /groups | findstr /c:"S-1-16-12288" >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator privileges...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

set "PS1=%TEMP%\MinePRL-setup.ps1"
del "%PS1%" >nul 2>&1

rem ---- pull the embedded PowerShell out of this same file --------------------
rem  LastIndexOf, NOT IndexOf. The marker string appears inside the command line
rem  below, so the FIRST match is this very command and IndexOf extracts garbage
rem  starting mid-sentence. The real marker is the last occurrence in the file.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$c = Get-Content -LiteralPath '%~f0' -Raw; $m = '### POWERSHELL-BELOW ###'; $i = $c.LastIndexOf($m); if ($i -lt 0) { Write-Host '  [X] embedded script missing from this file'; exit 9 }; $c.Substring($i + $m.Length) | Set-Content -LiteralPath '%PS1%' -Encoding UTF8"
if errorlevel 1 (
    echo.
    echo   [X] Could not unpack the installer.
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" (
    echo   Setup finished with an error ^(code %RC%^). Read the messages above.
) else (
    echo   Done. Mining will start by itself at every logon.
)
echo.
pause
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

function Line { param($t = '') Write-Host $t }
function Head { param($t) Line ''; Write-Host ('-' * 74) -ForegroundColor DarkGray; Write-Host "  $t" -ForegroundColor Cyan; Write-Host ('-' * 74) -ForegroundColor DarkGray }
function Ok   { param($t) Write-Host "  [OK]   $t" -ForegroundColor Green }
function Warn { param($t) Write-Host "  [!!]   $t" -ForegroundColor Yellow }
function Bad  { param($t) Write-Host "  [XX]   $t" -ForegroundColor Red }

New-Item -ItemType Directory -Force -Path $Install, $LogDir | Out-Null

# ---------------------------------------------------------------------------
#  1. GPU detection  -  Pearl needs AMD or NVIDIA. Intel cannot mine it.
# ---------------------------------------------------------------------------
Head 'GPU DETECTION'
Line '  SRBMiner reports pearlhash support as:  AMD yes | NVIDIA yes | Intel NO'
Line ''

$gpus = @()

$nvsmi = $null
try { $nvsmi = (Get-Command nvidia-smi -ErrorAction Stop).Source } catch { }

if ($nvsmi) {
    try {
        $rows = & $nvsmi --query-gpu=name,power.default_limit --format=csv,noheader,nounits 2>$null
        foreach ($r in $rows) {
            if (-not $r) { continue }
            $p = $r -split ','
            if ($p.Count -ge 2) {
                $gpus += [pscustomobject]@{
                    Vendor = 'NVIDIA'; Name = $p[0].Trim(); DefaultW = [double](($p[1] -replace '[^0-9.]',''))
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
        $gpus += [pscustomobject]@{ Vendor = $vendor; Name = $v.Name; DefaultW = 0 }
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

if ((Test-Path $zip) -and ((Get-FileHash $zip -Algorithm MD5).Hash.ToLower() -eq $ZipMd5)) {
    Ok 'already downloaded and verified'
} else {
    Line '  downloading 28 MB from the official release...'
    try {
        Invoke-WebRequest -Uri $ZipUrl -OutFile $zip -UseBasicParsing -TimeoutSec 300
    } catch {
        Bad "download failed: $($_.Exception.Message)"
        exit 5
    }
    $md5 = (Get-FileHash $zip -Algorithm MD5).Hash.ToLower()
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
$exe = Get-ChildItem -Path $Install -Recurse -Filter 'SRBMiner-MULTI.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $exe) {
    Expand-Archive -Path $zip -DestinationPath $Install -Force
    $exe = Get-ChildItem -Path $Install -Recurse -Filter 'SRBMiner-MULTI.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
}
if (-not $exe) {
    Bad 'SRBMiner-MULTI.exe was not found after extracting.'
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
            $watts += $w
            Line ("  {0}: factory {1} W -> 70% = {2} W" -f $g.Name, [int]$g.DefaultW, $w)
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
    "=== starting $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -FilePath $log -Append -Encoding UTF8
    try {
        & $Exe @args *>> $log
    } catch {
        "=== miner threw: $($_.Exception.Message) ===" | Out-File -FilePath $log -Append -Encoding UTF8
    }
    "=== miner exited, restarting in 60 s ===" | Out-File -FilePath $log -Append -Encoding UTF8
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
#  5. persistence  -  runs at every logon, elevated
# ---------------------------------------------------------------------------
Head 'SETTING UP AUTOSTART'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $runnerPath)
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -RunLevel Highest -LogonType Interactive

try {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Principal $principal -Force -Description 'Pearl (PRL) mining to Kryptex' | Out-Null
    Ok "scheduled task '$TaskName' created - mining resumes at every logon"
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
foreach ($p in @(Get-Process SRBMiner-MULTI -ErrorAction SilentlyContinue)) {
    try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { }
}
Start-Sleep -Seconds 2

Start-Process -FilePath 'powershell.exe' `
    -ArgumentList ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $runnerPath) `
    -WindowStyle Hidden | Out-Null
Start-Sleep -Seconds 12

$running = @(Get-Process SRBMiner-MULTI -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    Ok "miner running (pid $($running[0].Id))"
} else {
    Warn 'the miner did not start - check the log'
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
Line "  autostart    : $TaskName  (at logon, elevated)"
Line ''
Line '  To stop:        schtasks /end /tn PearlMiner'
Line '  To uninstall:   schtasks /delete /tn PearlMiner /f   then delete C:\MinePRL'
Line ''

exit 0
