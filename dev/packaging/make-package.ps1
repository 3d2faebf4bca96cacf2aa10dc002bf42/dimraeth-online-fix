<#
.SYNOPSIS
    Builds the distributable zip from package\.

.DESCRIPTION
    Produces Dimraeth-OnlineFix.zip containing the same payload as package\ plus a
    short player-facing README. Anyone extracts it into their Dimraeth folder and
    presses Play.

    The zip deliberately contains NO SteamID. Every machine generates its own on
    first run; shipping one would make all players share an identity and be
    unable to connect.

.PARAMETER OutputPath
    Where to write the zip. Defaults to the repository root.

.EXAMPLE
    pwsh -File .\dev\packaging\make-package.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Dist     = Join-Path $RepoRoot 'package'
$OutZip   = if ($OutputPath) { $OutputPath } else { Join-Path $RepoRoot 'Dimraeth-OnlineFix.zip' }

function Ok($m)    { Write-Host "  [ok] $m" -ForegroundColor Green }
function Bad($m)   { Write-Host "  [XX] $m" -ForegroundColor Red; exit 1 }

Write-Host ''
Write-Host 'Packaging the online fix' -ForegroundColor White
Write-Host ''

if (-not (Test-Path $Dist)) { Bad "package\ not found at $Dist" }

$dll = Join-Path $Dist 'Dimraeth_Data\Plugins\x86_64\steam_api64.dll'
if (-not (Test-Path $dll)) { Bad "package\ is missing steam_api64.dll" }
Ok "payload present ($((Get-Item $dll).Length) bytes)"

# Refuse to ship a fixed SteamID
$sidFile = Join-Path $Dist 'Dimraeth_Data\Plugins\x86_64\steam_settings\force_steamid.txt'
if (Test-Path $sidFile) {
    Bad 'force_steamid.txt is present in package\. Every player must generate their own SteamID - remove it.'
}
Ok 'no fixed SteamID in the payload'

# Stage
$stage = Join-Path $env:TEMP ('dimraeth-package-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $stage | Out-Null
try {
    Copy-Item (Join-Path $Dist 'Dimraeth_Data') $stage -Recurse -Force

    $readme = Join-Path $PSScriptRoot 'PLAYER-README.txt'
    if (Test-Path $readme) {
        Copy-Item $readme (Join-Path $stage 'README.txt') -Force
        Ok 'player README included'
    } else {
        Write-Host '  [!!] dev\packaging\PLAYER-README.txt not found, shipping without it' -ForegroundColor Yellow
    }

    Remove-Item $OutZip -Force -ErrorAction SilentlyContinue
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $OutZip -CompressionLevel Optimal -Force
    Ok "wrote $OutZip ($([int]((Get-Item $OutZip).Length / 1KB)) KB)"
} finally {
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'Contents:' -ForegroundColor White
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($OutZip)
$zip.Entries | Sort-Object FullName | ForEach-Object { Write-Host "  $($_.FullName)" }
$zip.Dispose()
Write-Host ''
