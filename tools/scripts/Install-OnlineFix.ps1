<#
.SYNOPSIS
    Installs the Dimraeth online fix into the game folder.

.DESCRIPTION
    Copies the drop-in payload from ..\..\package\ into the Dimraeth installation and
    verifies the result. Safe to run more than once.

    The fix replaces steam_api64.dll with the Goldberg Steam emulator configured
    as Steam AppID 480 (Spacewar). Dimraeth has no Steam DRM, so the game can
    still be launched from the Steam Play button - Steam starts the executable
    and does not replace or validate the DLL in the game folder.

    Every player needs their own unique SteamID. This script does NOT write one:
    the emulator generates a cryptographically random ID on first run and stores
    it in %APPDATA%\Goldberg SteamEmu Saves\settings\user_steam_id.txt.
    Shipping a fixed SteamID would make every player share one identity, and the
    emulator uses the SteamID as the peer key - identical IDs cannot connect.

.PARAMETER GameDir
    Path to the Dimraeth folder. Auto-detected from Steam libraries when omitted.

.PARAMETER Remove
    Restore the original Valve steam_api64.dll and delete the fix files.

.EXAMPLE
    pwsh -File .\tools\scripts\Install-OnlineFix.ps1
    pwsh -File .\tools\scripts\Install-OnlineFix.ps1 -Remove
#>
[CmdletBinding()]
param(
    [string]$GameDir,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Payload  = Join-Path $RepoRoot 'package'

$DllRel    = 'Dimraeth_Data\Plugins\x86_64\steam_api64.dll'
$DllDirRel = 'Dimraeth_Data\Plugins\x86_64'
$EmulatorDllSize = 1958912

function Info($m) { Write-Host "  $m" }
function Ok($m)   { Write-Host "  [ok] $m"   -ForegroundColor Green }
function Warn2($m){ Write-Host "  [!!] $m"   -ForegroundColor Yellow }
function Fail($m) { Write-Host "  [XX] $m"   -ForegroundColor Red; exit 1 }

function Find-GameDir {
    param([string]$Explicit)
    if ($Explicit) {
        if (Test-Path (Join-Path $Explicit $DllRel)) { return (Resolve-Path $Explicit).Path }
        Fail "'$Explicit' does not look like the Dimraeth folder (no $DllRel)."
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
        if (Test-Path (Join-Path $c $DllRel)) { return (Resolve-Path $c).Path }
    }
    return $null
}

Write-Host ''
Write-Host 'Dimraeth online fix - install' -ForegroundColor White
Write-Host ''

$Game = Find-GameDir -Explicit $GameDir
while (-not $Game) {
    Info 'Could not locate Dimraeth automatically.'
    $answer = Read-Host 'Paste the full path to the Dimraeth folder (the one with Dimraeth.exe)'
    if ($answer) { $Game = Find-GameDir -Explicit ($answer.Trim().Trim('"')) }
}
$Game = $Game.TrimEnd('\')
Info "Game folder: $Game"

$Dll    = Join-Path $Game $DllRel
$DllDir = Join-Path $Game $DllDirRel
$Orig   = Join-Path $DllDir 'steam_api64.dll.original'
Write-Host ''

# ---------------------------------------------------------------- remove
if ($Remove) {
    Info 'Removing the fix...'
    if (-not (Test-Path $Orig)) { Fail "No backup found at $Orig. Nothing to restore." }
    Copy-Item $Orig $Dll -Force
    Ok 'original Valve steam_api64.dll restored'
    foreach ($x in @('steam_appid.txt', 'local_save.txt', 'steam_interfaces.txt', 'steam_settings')) {
        $target = "$DllDir\$x"
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force; Ok "removed $x" }
    }
    Write-Host ''
    Write-Host 'Fix removed. The game uses Steam again.' -ForegroundColor Green
    Write-Host ''
    return
}

# ---------------------------------------------------------------- install
if (-not (Test-Path (Join-Path $Payload $DllRel))) {
    Fail "Payload not found at $Payload. The repository looks incomplete."
}
Ok 'payload found'

$p = @(Get-Process Dimraeth -ErrorAction SilentlyContinue)
if ($p.Count -gt 0) {
    Info "Closing Dimraeth (PID $(($p | ForEach-Object Id) -join ',')) so the DLL can be replaced..."
    $p | Stop-Process -Force
    Start-Sleep -Seconds 4
}

# back up the original once
if (Test-Path $Orig) {
    Ok 'original DLL already backed up'
} else {
    $sig = Get-AuthenticodeSignature $Dll
    if ($sig.Status -eq 'Valid' -and $sig.SignerCertificate.Subject -match 'Valve') {
        Copy-Item $Dll $Orig -Force
        Ok "original Valve DLL backed up to $Orig"
    } else {
        Warn2 "current steam_api64.dll is not Valve-signed (status: $($sig.Status))."
        Warn2 'It may already be an emulator. Not overwriting anything.'
        Warn2 'To restore the original, use Steam > Verify integrity of game files.'
    }
}

# copy the payload
Get-ChildItem $Payload -Force | ForEach-Object {
    Copy-Item $_.FullName $Game -Recurse -Force
}
Copy-Item (Join-Path $Payload $DllRel) $Dll -Force
Ok 'emulator installed as steam_api64.dll'

# drop stale settings from older attempts
foreach ($junk in @('configs.main.ini', 'configs.app.ini', 'configs.user.ini',
                    'configs.overlay.ini', 'branches.json', 'steam_interfaces.txt')) {
    $target = Join-Path $DllDir "steam_settings\$junk"
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force; Ok "removed stale $junk" }
}

# ---------------------------------------------------------------- verify
Write-Host ''
$len = (Get-Item $Dll).Length
if ($len -ne $EmulatorDllSize) { Fail "installed steam_api64.dll is $len bytes, expected $EmulatorDllSize." }
Ok "steam_api64.dll : $len bytes (emulator)"

$settings = Join-Path $DllDir 'steam_settings'
foreach ($f in @('steam_appid.txt', 'force_listen_port.txt')) {
    $v = (Get-Content (Join-Path $settings $f) -Raw).Trim()
    Ok "$f = $v"
}
if (Test-Path (Join-Path $settings 'force_steamid.txt')) {
    Warn2 'force_steamid.txt is present. Every player must have a DIFFERENT one.'
    Warn2 'If you are copying this folder to another person, delete that file there.'
}
Ok 'no force_steamid.txt - each machine generates its own unique SteamID'

Write-Host ''
Write-Host 'Install complete.' -ForegroundColor Green
Write-Host ''
Write-Host '  Launch the game from the Steam Play button. That is all.' -ForegroundColor White
Write-Host '  To undo:  pwsh -File .\tools\scripts\Install-OnlineFix.ps1 -Remove' -ForegroundColor White
Write-Host ''
