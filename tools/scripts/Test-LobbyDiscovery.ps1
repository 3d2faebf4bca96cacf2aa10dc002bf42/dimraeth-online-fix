<#
.SYNOPSIS
    Tests whether the host's lobby is visible on the network.

.DESCRIPTION
    IMPORTANT - WHAT THIS DOES AND DOES NOT PROVE

    Entering a Steam lobby (matchmaking) is NOT the same as joining the game
    session. The game additionally has to open its P2P data channel
    (ConnectP2P) and have Unity Netcode approve the connection before the player
    appears in the in-game PARTY list.

    This script only exercises the FIRST layer. It proves the lobby is
    discoverable and accepts a join request. It does NOT prove a player will
    show up in the party. That can only be confirmed by a real second player
    looking at the party list.

    What it does: spins up a second emulator instance with its own SteamID and
    runs the real client flow - RequestLobbyList -> GetLobbyByIndex ->
    JoinLobby -> GetNumLobbyMembers - against the lobby you are hosting.

    Requires: the game running and HOSTING a world, and the compiled
    tools/bin/JoinTest.exe.

.PARAMETER GameDir
    Path to the Dimraeth folder. Auto-detected when omitted.

.PARAMETER Seconds
    How long to search for the lobby. Default 60.

.EXAMPLE
    pwsh -File .\tools\scripts\Test-LobbyDiscovery.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir,
    [int]$Seconds = 60
)

$ErrorActionPreference = 'Continue'

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$DllRel   = 'Dimraeth_Data\Plugins\x86_64\steam_api64.dll'

function Ok($m)    { Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn2($m) { Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Bad($m)   { Write-Host "  [XX] $m" -ForegroundColor Red }

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

Write-Host ''
Write-Host '================================================================' -ForegroundColor White
Write-Host '  LOBBY DISCOVERY TEST  (matchmaking layer only)' -ForegroundColor White
Write-Host '================================================================' -ForegroundColor White
Write-Host '  This does NOT prove a player appears in the party list.' -ForegroundColor DarkGray
Write-Host ''

# ---------------------------------------------------------------- 1. host
$game = @(Get-Process Dimraeth -ErrorAction SilentlyContinue)
if ($game.Count -eq 0) {
    Bad 'The game is not running.'
    Write-Host '     Open Dimraeth, go to Multiplayer and HOST a world first.'
    Read-Host 'Enter'; exit 1
}
Ok "game running (PID $(($game | ForEach-Object Id) -join ','))"

$onPort = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue |
            Where-Object { $_.OwningProcess -in $game.Id -and $_.LocalPort -ge 40000 -and $_.LocalPort -le 48100 })
if ($onPort.Count -gt 0) { Ok "emulator on port $(($onPort | ForEach-Object LocalPort) -join ',')" }
else { Warn2 'emulator port not seen yet - the game may still be loading' }

$playerLog = Join-Path $env:USERPROFILE 'AppData\LocalLow\Mudtek\Dimraeth\Player.log'
$hosting = $false
if (Test-Path $playerLog) {
    $hosting = @(Select-String -Path $playerLog -Pattern 'OnNetworkSpawn|SpawnManager' -ErrorAction SilentlyContinue).Count -gt 0
}
if ($hosting) { Ok 'the game is HOSTING (Netcode active)' }
else { Bad 'the game does not look like it is hosting. Create a world first.'; Read-Host 'Enter'; exit 1 }
Write-Host ''

# ---------------------------------------------------------------- 2. client
$GameDirResolved = Find-GameDir -Explicit $GameDir
$exe = Join-Path $RepoRoot 'tools\bin\JoinTest.exe'
if (-not (Test-Path $exe)) { Bad "JoinTest.exe not found at $exe"; Write-Host '     Run .\dev\packaging\build.ps1 first.'; Read-Host 'Enter'; exit 1 }
if (-not $GameDirResolved) { Bad 'Could not locate the game folder.'; Read-Host 'Enter'; exit 1 }

$dllSrc = Join-Path $GameDirResolved $DllRel
if (-not (Test-Path $dllSrc)) { Bad "emulator DLL not found at $dllSrc"; Read-Host 'Enter'; exit 1 }

$clientDir = Join-Path $env:TEMP 'dimraeth-client-test'
Remove-Item $clientDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $clientDir 'steam_settings') | Out-Null
Copy-Item $dllSrc (Join-Path $clientDir 'steam_api64.dll') -Force
Set-Content (Join-Path $clientDir 'steam_appid.txt') '480' -Encoding ascii -NoNewline
Set-Content (Join-Path $clientDir 'steam_settings\steam_appid.txt') '480' -Encoding ascii -NoNewline
Set-Content (Join-Path $clientDir 'steam_settings\force_account_name.txt') 'TEST-CLIENT' -Encoding ascii
Set-Content (Join-Path $clientDir 'local_save.txt') 'test-client' -Encoding ascii -NoNewline
Ok 'test client instance prepared (own SteamID)'

Write-Host ''
Write-Host "Searching the network for your lobby (up to $Seconds s)..." -ForegroundColor Cyan
Write-Host ''

$logPath = Join-Path $GameDirResolved 'Dimraeth-OnlineFix-logs\lobby-test.txt'
New-Item -ItemType Directory -Force -Path (Split-Path $logPath -Parent) | Out-Null
& $exe --dir $clientDir --seconds $Seconds --log $logPath 2>&1 | ForEach-Object { "  $_" }
$code = $LASTEXITCODE

Write-Host ''
if ($code -eq 0) {
    Write-Host '================================================================' -ForegroundColor Green
    Write-Host '  LOBBY VISIBLE - found on the network and join accepted' -ForegroundColor Green
    Write-Host '================================================================' -ForegroundColor Green
    Write-Host ''
    Write-Host '  This covers layer 1 (matchmaking). It does NOT prove a player'
    Write-Host '  appears in the PARTY list - that needs the P2P channel and Netcode.'
    Write-Host '  The real test is another player joining and showing up in your party.'
} elseif ($code -eq 10) {
    Write-Host '================================================================' -ForegroundColor Yellow
    Write-Host '  LOBBY NOT FOUND' -ForegroundColor Yellow
    Write-Host '================================================================' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Check, in order:'
    Write-Host '   1. Is the game actually HOSTING (not just in the menu)?'
    Write-Host '   2. Is ZeroTier connected on both machines?'
    Write-Host '   3. If it persists, use the fallback: put the other player''s'
    Write-Host '      ZeroTier IP in steam_settings\custom_broadcasts.txt'
} else {
    Write-Host '================================================================' -ForegroundColor Yellow
    Write-Host "  Lobby found, but the join was not confirmed (exit code $code)" -ForegroundColor Yellow
    Write-Host '================================================================' -ForegroundColor Yellow
}
Write-Host ''
Write-Host "Log: $logPath" -ForegroundColor White
Write-Host ''
