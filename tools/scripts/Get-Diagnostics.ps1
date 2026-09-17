<#
.SYNOPSIS
    Collects everything observable about the online fix into a single log.

.DESCRIPTION
    The Goldberg release build writes NO log at all - the debug packages it
    ships contain only a Readme. So diagnostics have to come from outside:
    observing the process, the sockets and the network traffic.

    This script captures:
      1. Game process - PID, memory, threads, and whether Steam launched it
      2. Fix state   - emulator DLL, AppID, port, persona, generated SteamID
      3. Sockets     - proof the emulator owns UDP+TCP 47584
      4. Game logs   - multiplayer state from Player.log and Player-prev.log
      5. ZeroTier    - network, IP, peers, MTU
      6. Packets     - decodes the emulator's announce traffic on the wire
      7. Verdict     - OK / WARNING per item

    The output lands in Dimraeth-OnlineFix-logs\ in the game folder.

    IMPORTANT about item 6 - the emulator only announces AFTER you enter
    multiplayer. Sitting in the main menu there is no listen socket, so it stays
    quiet on purpose. "not announcing" while in the menu is expected, not a bug.

.PARAMETER GameDir
    Path to the Dimraeth folder. Auto-detected when omitted.

.PARAMETER Seconds
    How long to listen for announce packets. Default 30.

.PARAMETER LaunchGame
    Start the game through Steam if it is not already running.

.PARAMETER SkipPackets
    Skip the packet capture step.

.EXAMPLE
    pwsh -File .\tools\scripts\Get-Diagnostics.ps1 -Seconds 30
#>
[CmdletBinding()]
param(
    [string]$GameDir,
    [int]$Seconds = 30,
    [int]$Port = 47584,
    [string]$SteamAppId = '2402680',
    [string]$NetworkId,
    [switch]$LaunchGame,
    [switch]$SkipPackets
)

$ErrorActionPreference = 'Continue'

$RepoRoot  = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$DllRel    = 'Dimraeth_Data\Plugins\x86_64\steam_api64.dll'
$DllDirRel = 'Dimraeth_Data\Plugins\x86_64'
$EmulatorDllSize = 1958912

function Find-GameDir {
    param([string]$Explicit)
    if ($Explicit -and (Test-Path (Join-Path $Explicit $DllRel))) { return (Resolve-Path $Explicit).Path }
    $roots = @()
    foreach ($steamRoot in @("${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam")) {
        $vdf = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            $roots += $steamRoot
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s*"([^"]+)"')) {
                $roots += ($m.Groups[1].Value -replace '\\\\', '\')
            }
        }
    }
    foreach ($r in ($roots | Select-Object -Unique)) {
        $c = Join-Path $r 'steamapps\common\Dimraeth'
        if (Test-Path (Join-Path $c $DllRel)) { return (Resolve-Path $c).Path }
    }
    return $null
}

$Game = Find-GameDir -Explicit $GameDir
if (-not $Game) { Write-Host 'Could not locate the Dimraeth folder.' -ForegroundColor Red; Read-Host 'Enter'; exit 1 }

$LogDir = Join-Path $Game 'Dimraeth-OnlineFix-logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log = Join-Path $LogDir ("diagnostic-" + (Get-Date -Format 'yyyy-MM-dd_HHmmss') + ".txt")

$script:Lines = New-Object System.Collections.Generic.List[string]
function W($m)    { $script:Lines.Add([string]$m); Write-Host $m }
function Head($t){ W ''; W ('=' * 66); W "  $t"; W ('=' * 66) }
function Good($m) { W "  [OK]      $m" }
function Warn2($m){ W "  [WARNING] $m" }
function Bad($m)  { W "  [MISSING] $m" }

W 'DIMRAETH ONLINE FIX - DIAGNOSTICS'
W "generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "game      : $Game"
W "log       : $Log"

# ---------------------------------------------------------------- 1. process
Head '1. GAME PROCESS'
$procs = @(Get-Process Dimraeth -ErrorAction SilentlyContinue)
if ($procs.Count -eq 0) {
    Warn2 'The game is not running.'
    if ($LaunchGame) {
        W '  launching via Steam...'
        Start-Process "steam://run/$SteamAppId" | Out-Null
        $deadline = (Get-Date).AddSeconds(45)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 3
            $procs = @(Get-Process Dimraeth -ErrorAction SilentlyContinue)
            if ($procs.Count -gt 0) { break }
        }
    }
}
if ($procs.Count -gt 0) {
    foreach ($pr in $procs) {
        W "  PID $($pr.Id)  memory $([int]($pr.WorkingSet64/1MB)) MB  threads $($pr.Threads.Count)"
        W "  started $($pr.StartTime.ToString('HH:mm:ss'))  path: $($pr.Path)"
        try {
            $parent = (Get-CimInstance Win32_Process -Filter "ProcessId=$($pr.Id)" -ErrorAction SilentlyContinue).ParentProcessId
            if ($parent) {
                $pname = (Get-Process -Id $parent -ErrorAction SilentlyContinue).ProcessName
                W "  parent process: $pname (PID $parent)"
                if ($pname -eq 'steam') { Good 'launched THROUGH STEAM (fix stays active)' }
                else { W '  (launched directly, not through Steam)' }
            }
        } catch { }
    }
} else { Bad 'game is not running' }

# ---------------------------------------------------------------- 2. fix
Head '2. ONLINE FIX STATE'
$dll = Join-Path $Game $DllRel
if (Test-Path $dll) {
    $len = (Get-Item $dll).Length
    if ($len -eq $EmulatorDllSize) { Good "steam_api64.dll = emulator ($len bytes)" }
    else { Bad "steam_api64.dll = $len bytes (not the emulator; Steam may have restored the original)" }
} else { Bad 'steam_api64.dll DOES NOT EXIST' }

$DllDir = Join-Path $Game $DllDirRel
foreach ($f in @('steam_appid.txt', 'steam_settings\steam_appid.txt',
                 'steam_settings\force_listen_port.txt', 'steam_settings\force_account_name.txt')) {
    $fp = Join-Path $DllDir $f
    if (Test-Path $fp) { W ("  {0,-42} = '{1}'" -f $f, (Get-Content $fp -Raw).Trim()) }
    else { W ("  {0,-42} = (absent)" -f $f) }
}

$steamId = $null
foreach ($sf in @((Join-Path $env:APPDATA 'Goldberg SteamEmu Saves\settings\user_steam_id.txt'),
                  (Join-Path $Game "$DllDirRel\Goldberg SteamEmu Saves\settings\user_steam_id.txt"))) {
    if (Test-Path $sf) {
        $steamId = (Get-Content $sf -Raw).Trim()
        W "  SteamID ($($sf -replace [regex]::Escape($env:APPDATA),'%APPDATA%')): $steamId"
    }
}
if ($steamId) {
    $base = [uint64]76561197960265728
    try {
        $v = [uint64]$steamId
        $account = $v - $base
        $type = ($v -shr 52) -band 0xF
        if ($account -ge 1 -and $account -lt 4294967296 -and $type -eq 1) { Good "SteamID is valid (account $account)" }
        else { Bad 'SteamID is invalid' }
    } catch { Bad 'SteamID is not numeric' }
} else { Warn2 'SteamID not generated yet (run the game once)' }

# ---------------------------------------------------------------- 3. sockets
Head "3. EMULATOR SOCKETS (port $Port)"
$foundPort = $false
if ($procs.Count -gt 0) {
    foreach ($pr in $procs) {
        foreach ($e in @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue |
                         Where-Object { $_.OwningProcess -eq $pr.Id -and $_.LocalPort -ge 40000 -and $_.LocalPort -le 48000 })) {
            W "  UDP $($e.LocalAddress):$($e.LocalPort)"
            if ($e.LocalPort -eq $Port) { $foundPort = $true }
        }
        foreach ($e in @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
                         Where-Object { $_.OwningProcess -eq $pr.Id -and $_.LocalPort -ge 40000 -and $_.LocalPort -le 48000 })) {
            W "  TCP $($e.LocalAddress):$($e.LocalPort) (listening)"
        }
    }
}
if ($foundPort) { Good "emulator is listening on port $Port" }
elseif ($procs.Count -gt 0) { Bad "emulator is NOT on port $Port (something else may be using it)" }
else { W '  (no game running)' }

# ---------------------------------------------------------------- 4. game logs
Head '4. GAME LOGS (multiplayer state)'
$logDir = Join-Path $env:USERPROFILE 'AppData\LocalLow\Mudtek\Dimraeth'
$sawMultiplayer = $false
foreach ($name in @('Player.log', 'Player-prev.log')) {
    $plog = Join-Path $logDir $name
    if (-not (Test-Path $plog)) { W "  $name : (does not exist)"; continue }
    W ''
    W "  --- $name  ($((Get-Item $plog).Length) bytes, $((Get-Item $plog).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))) ---"
    $hits = @(Select-String -Path $plog -Pattern 'OnNetworkSpawn|SpawnManager|NetworkObject|ServerRpc|ClientRpc|FacepunchTransport|NetworkManager|lobby' -ErrorAction SilentlyContinue)
    if ($hits.Count -gt 0) {
        $sawMultiplayer = $true
        Good "this session ENTERED MULTIPLAYER ($($hits.Count) lines)"
        $hits | Select-Object -First 12 | ForEach-Object { W "      $($_.Line.Trim())" }
    } else {
        W '      no multiplayer lines (game stayed in the main menu)'
    }
    W '      last lines:'
    Get-Content $plog | Select-Object -Last 3 | ForEach-Object { W "        $_" }
}
W ''
if ($sawMultiplayer) { Good 'a multiplayer session happened - the emulator would have been announcing during it' }
else { Warn2 'no multiplayer session in either log. The emulator only announces after you enter multiplayer.' }

# ---------------------------------------------------------------- 5. ZeroTier
Head '5. ZEROTIER'
$ztIp = $null
try {
    $ztIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
             Where-Object { $_.InterfaceAlias -match 'ZeroTier' } | Select-Object -First 1).IPAddress
} catch { }
$ztCli = $null
foreach ($c in @("${env:ProgramFiles(x86)}\ZeroTier\One\zerotier-cli.bat",
                 "$env:ProgramFiles\ZeroTier\One\zerotier-cli.bat")) {
    if (Test-Path $c) { $ztCli = $c; break }
}
if (-not $ztCli) { Bad 'ZeroTier is not installed' }
else {
    W "  cli: $ztCli"
    W "  info: $(((& $ztCli info 2>&1) -join ' '))"
    $nets = (& $ztCli listnetworks 2>&1) -join "`n"
    foreach ($l in ($nets -split "`r?`n")) { if ($l.Trim()) { W "  $l" } }
    if (-not $NetworkId) {
        W '  (no -NetworkId given, so no specific network is checked)'
        if ($nets -match '\bOK\b') { Good 'a ZeroTier network is connected' }
        else { Warn2 'no ZeroTier network reports OK' }
    }
    elseif ($nets -match ([regex]::Escape($NetworkId) + '[^\r\n]*\bOK\b')) { Good "connected to network $NetworkId" }
    elseif ($nets -match [regex]::Escape($NetworkId)) { Warn2 'network present but not OK (missing authorisation?)' }
    else { Bad "not joined to network $NetworkId" }
}
if ($ztIp) {
    Good "ZeroTier IP: $ztIp"
    try {
        $iface = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.IPAddress -eq $ztIp } | Select-Object -First 1
        if ($iface) {
            W "  MTU: $((Get-NetIPInterface -InterfaceIndex $iface.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).NlMtu)"
        }
    } catch { }
} else { Bad 'no active ZeroTier interface' }

# ---------------------------------------------------------------- 6. packets
Head '6. EMULATOR ANNOUNCE TRAFFIC'
if ($SkipPackets) { W '  skipped (-SkipPackets)' }
else {
    # Capturing without stealing the game's port:
    # the game binds 0.0.0.0:47584. Windows still allows binding a SPECIFIC
    # address on the same port, so we listen on 127.0.0.1 and each local IP.
    # The emulator broadcasts to every interface, so these sockets get a copy.
    $ips = @()
    try {
        $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.IPAddress -notmatch '^127\.' } | ForEach-Object { $_.IPAddress })
    } catch { }
    $ips = @('127.0.0.1', '127.0.0.2') + $ips
    if ($ztIp) { $ips = @($ztIp) + $ips }
    $ips = @($ips | Select-Object -Unique)

    $emitted = $null
    try {
        if (-not ('CapSpecific' -as [type])) {
            $csPath = Join-Path $RepoRoot 'dev\src\CapSpecific\CapSpecific.cs'
            if (Test-Path $csPath) { Add-Type -Path $csPath; }
        }
        $emitted = [CapSpecific]::Run([int[]]@([int]$Port, ([int]$Port + 1)), [string[]]$ips, $Seconds)
    } catch { Warn2 "packet capture failed: $($_.Exception.Message)" }

    if ($emitted) { foreach ($l in ($emitted -split "`r?`n")) { W $l } }
    else { Warn2 'CapSpecific.cs not found - copy it and try again' }
}

# ---------------------------------------------------------------- 7. verdict
Head '7. VERDICT'
$all = $script:Lines -join "`n"
function V($label, $cond, $okMsg, $badMsg) {
    if ($cond) { W ("  {0,-26}: OK       {1}" -f $label, $okMsg) }
    else       { W ("  {0,-26}: WARNING  {1}" -f $label, $badMsg) }
}
V 'fix applied'      ((Test-Path $dll) -and ((Get-Item $dll).Length -eq $EmulatorDllSize)) 'emulator in place' 'steam_api64.dll is not the emulator'
V 'AppID 480'        ($all -match "steam_appid\.txt\s+=\s+'480'") 'ok' 'AppID is not 480'
V 'port 47584'       ($all -match "force_listen_port\.txt\s+=\s+'47584'") 'ok' 'port is not 47584'
V 'SteamID generated'($null -ne $steamId) 'ok' 'not generated yet'
V 'game running'     ($procs.Count -gt 0) 'ok' 'game is closed'
V 'emulator on port' $foundPort 'listening' 'port not seen'
V 'ZeroTier'         ($null -ne $ztCli) 'installed' 'not installed'
V 'joined the network' (($all -match 'a ZeroTier network is connected') -or ($NetworkId -and ($all -match ($NetworkId + '[^\r\n]*\bOK\b')))) 'connected' 'not connected'
V 'announcing'       ($all -match 'the emulator IS announcing') 'yes' 'no (enter multiplayer)'

W ''
W '  The emulator only starts announcing once you ENTER MULTIPLAYER (create or'
W '  browse a lobby). In the main menu there is no listen socket, so it stays'
W '  quiet. That is intentional, not a fault.'
W ''
W "Log written to: $Log"
$script:Lines | Set-Content -LiteralPath $Log -Encoding UTF8
Write-Host ''
Write-Host "Log written to:" -ForegroundColor Green
Write-Host "  $Log" -ForegroundColor Green

