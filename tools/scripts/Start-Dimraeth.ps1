<#
.SYNOPSIS
    Starts the game through the Steam Play button with the online fix active.

.DESCRIPTION
    Dimraeth has no Steam DRM, so the Steam client only starts the executable -
    it does not replace or validate steam_api64.dll in the game folder. The
    emulator therefore stays active, and the game still shows as "Dimraeth -
    Running" in Steam, with the overlay working.

    Steam shows the game as AppID 2402680. AppID 480 (Spacewar) exists only
    inside the emulator and is never visible to the Steam client.

    This script checks the fix, reports the ZeroTier address, and then asks
    Steam to start the game.

.PARAMETER GameDir
    Path to the Dimraeth folder. Auto-detected when omitted.

.PARAMETER WaitSeconds
    How long to wait for the emulator to appear on the discovery port.

.PARAMETER WithoutSteam
    Start the executable directly instead of going through Steam.

.EXAMPLE
    pwsh -File .\tools\scripts\Start-Dimraeth.ps1
    pwsh -File .\tools\scripts\Start-Dimraeth.ps1 -WithoutSteam
#>
[CmdletBinding()]
param(
    [string]$GameDir,
    [int]$WaitSeconds = 45,
    [string]$SteamAppId = '2402680',
    [string]$NetworkId,
    [switch]$WithoutSteam
)

$ErrorActionPreference = 'Continue'

$DllRel    = 'Dimraeth_Data\Plugins\x86_64\steam_api64.dll'
$DllDirRel = 'Dimraeth_Data\Plugins\x86_64'
$EmulatorDllSize = 1958912

function Info($m)  { Write-Host "  $m" }
function Ok($m)    { Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn2($m) { Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Bad($m)   { Write-Host "  [XX] $m" -ForegroundColor Red }

function Find-GameDir {
    param([string]$Explicit)
    if ($Explicit) {
        $x = ($Explicit -replace '\\\.$', '').TrimEnd('\')
        if (Test-Path (Join-Path $x 'Dimraeth.exe')) { return (Resolve-Path $x).Path }
    }
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
        if (Test-Path (Join-Path $c 'Dimraeth.exe')) { return (Resolve-Path $c).Path }
    }
    if (Test-Path (Join-Path $PSScriptRoot 'Dimraeth.exe')) { return (Resolve-Path $PSScriptRoot).Path }
    return $null
}

Write-Host ''
Write-Host 'Dimraeth online fix - start' -ForegroundColor White
Write-Host ''

$Game = Find-GameDir -Explicit $GameDir
if (-not $Game) { Bad 'Could not locate the Dimraeth folder.'; Read-Host 'Enter'; exit 1 }
Info "Game folder: $Game"

# ---------------------------------------------------------------- fix check
$dll = Join-Path $Game $DllRel
if (-not (Test-Path $dll)) { Bad 'steam_api64.dll is missing. Reinstall the game through Steam.'; Read-Host 'Enter'; exit 1 }

$len = (Get-Item $dll).Length
if ($len -eq $EmulatorDllSize) {
    Ok "online fix active ($len bytes)"
} else {
    Warn2 "steam_api64.dll is $len bytes - the emulator is NOT installed."
    Warn2 'This happens after reinstalling the game or using Verify integrity.'
    $answer = Read-Host 'Run the installer now? (Y/n)'
    if ($answer -notmatch '^[nN]') {
        & (Join-Path $PSScriptRoot 'Install-OnlineFix.ps1') -GameDir $Game
        if ((Get-Item $dll).Length -ne $EmulatorDllSize) {
            Bad 'Install did not work. Aborting.'; Read-Host 'Enter'; exit 1
        }
    } else { Bad 'Cannot continue without the fix.'; Read-Host 'Enter'; exit 1 }
}

# ---------------------------------------------------------------- ZeroTier
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
if ($ztCli) {
    $nets = (& $ztCli listnetworks 2>&1) -join "`n"
    if (-not $NetworkId) {
        if ($nets -match '\bOK\b') { Ok 'ZeroTier has a connected network' }
        else { Warn2 'ZeroTier has no network in OK state' }
    }
    elseif ($nets -match ([regex]::Escape($NetworkId) + '[^\r\n]*\bOK\b')) { Ok "ZeroTier connected to $NetworkId" }
    else { Warn2 "not connected to $NetworkId - run: zerotier-cli join $NetworkId" }
} else { Warn2 'ZeroTier is not installed. Internet play will not work.' }
if ($ztIp) { Ok "ZeroTier IP: $ztIp - share this with the other player" }

# ---------------------------------------------------------------- launch
Write-Host ''
if ($WithoutSteam) {
    Info 'Starting the executable directly (Steam will not show it as running)...'
    $taskName = "DimraethFix-" + [guid]::NewGuid().ToString('N').Substring(0, 8)
    try {
        $action    = New-ScheduledTaskAction -Execute (Join-Path $Game 'Dimraeth.exe') -WorkingDirectory $Game
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
        $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
        Start-ScheduledTask -TaskName $taskName
        Start-Sleep -Seconds 3
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Ok 'launched as an independent process (survives this window closing)'
    } catch {
        Start-Process -FilePath (Join-Path $Game 'Dimraeth.exe') -WorkingDirectory $Game | Out-Null
        Ok 'launched'
    }
} else {
    $steam = @(Get-Process steam -ErrorAction SilentlyContinue)
    if ($steam.Count -eq 0) {
        Warn2 'Steam is not running. Starting it...'
        Start-Process 'steam://open/main' | Out-Null
        Start-Sleep -Seconds 15
    }
    Info "asking Steam to run AppID $SteamAppId..."
    Start-Process "steam://run/$SteamAppId" | Out-Null
    Ok 'request sent to Steam'
}

# ---------------------------------------------------------------- confirm
Write-Host ''
Info "waiting for the emulator to appear on port 47584 (up to $WaitSeconds s)..."
$deadline = (Get-Date).AddSeconds($WaitSeconds)
$proc = $null; $onPort = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    $proc = Get-Process Dimraeth -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) { continue }
    $u = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue |
           Where-Object { $_.OwningProcess -eq $proc.Id -and $_.LocalPort -eq 47584 })
    if ($u.Count -gt 0) { $onPort = $true; break }
}
Write-Host ''
if (-not $proc) { Bad 'the game did not start. Run the diagnostics script.' }
elseif ($onPort) {
    Ok "game running (PID $($proc.Id)) - emulator listening on UDP+TCP 47584"
    if (-not $WithoutSteam) {
        $parent = (Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)" -ErrorAction SilentlyContinue).ParentProcessId
        $pname = if ($parent) { (Get-Process -Id $parent -ErrorAction SilentlyContinue).ProcessName } else { '?' }
        Info "parent process: $pname"
    }
    Write-Host ''
    Write-Host '  Now create or join a lobby in game.' -ForegroundColor White
} else {
    Warn2 "game is running (PID $($proc.Id)) but port 47584 was not seen."
    Warn2 'Something else may be using that port. Close it and try again.'
}
Write-Host ''

