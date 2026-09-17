<#
.SYNOPSIS
    Builds the helper executables in tools\bin\ from the sources in dev\src\.

.DESCRIPTION
    The helper tools are plain C# console programs that load the emulator DLL
    directly. They are compiled with the classic .NET Framework csc.exe, because
    the .NET 10 Roslyn compiler refuses to run on Windows builds that do not
    fully support CET ("Your Windows doesn't fully support CET").

    Produces:
      tools\bin\JoinTest.exe     - lobby discovery / join test
      tools\bin\LobbyHarness.exe - two-instance lobby propagation harness
      tools\bin\PacketSniffer.exe- announce packet decoder

.PARAMETER Configuration
    Release (default) or Debug.

.EXAMPLE
    pwsh -File .\dev\packaging\build.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$SrcDir   = Join-Path $RepoRoot 'dev\src'
$OutDir   = Join-Path $RepoRoot 'tools\bin'

function Ok($m)    { Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn2($m) { Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Bad($m)   { Write-Host "  [XX] $m" -ForegroundColor Red }

Write-Host ''
Write-Host 'Building helper tools' -ForegroundColor White
Write-Host ''

# ---------------------------------------------------------------- compiler
$csc = @(
    "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:SystemRoot\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $csc) {
    Bad 'Could not find csc.exe. Install the .NET Framework 4.x, or build the'
    Bad 'C# sources in src\ with any C# compiler targeting .NET Framework 4.x.'
    exit 1
}
Ok "compiler: $csc"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$flags = @('/nologo', '/target:exe', '/platform:anycpu')
if ($Configuration -eq 'Release') { $flags += '/optimize+' } else { $flags += '/optimize-' }

$targets = @(
    @{ Name = 'JoinTest';      Source = 'JoinTest\JoinTest.cs' }
    @{ Name = 'LobbyHarness';  Source = 'LobbyHarness\LobbyHarness.cs' }
    @{ Name = 'PacketSniffer'; Source = 'PacketSniffer\PacketSniffer.cs' }
)

$built = 0
$failed = 0
foreach ($t in $targets) {
    $source = Join-Path $SrcDir $t.Source
    $output = Join-Path $OutDir "$($t.Name).exe"

    if (-not (Test-Path $source)) { Warn2 "skipped $($t.Name): $source not found"; continue }

    Write-Host ''
    Write-Host "  compiling $($t.Name)..." -ForegroundColor Cyan
    $result = & $csc @flags "/out:$output" $source 2>&1
    if ($LASTEXITCODE -eq 0 -and (Test-Path $output)) {
        Ok "$($t.Name).exe  ($((Get-Item $output).Length) bytes)"
        $built++
    } else {
        $result | Select-Object -First 8 | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        Bad "$($t.Name) failed to build"
        $failed++
    }
}

Write-Host ''
if ($failed -eq 0) {
    Write-Host "Build finished: $built tool(s)." -ForegroundColor Green
} else {
    Write-Host "Build finished with $failed failure(s)." -ForegroundColor Red
    exit 1
}
Write-Host ''
Write-Host 'Next:  pwsh -File .\dev\packaging\make-package.ps1' -ForegroundColor White
Write-Host ''
