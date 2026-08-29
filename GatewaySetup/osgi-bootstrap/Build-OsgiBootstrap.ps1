[CmdletBinding()]
param(
    [string]$FelixJar = (Join-Path $env:TEMP 'fiberhome-felix.jar'),
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\gateway\lj2600d-print\osgi\io.github.sleepyhead.lj2600d.bootstrap_1.0.1.jar')
)

$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'src\io\github\sleepyhead\lj2600d\bootstrap\Activator.java'
$manifest = Join-Path $PSScriptRoot 'MANIFEST.MF'
$output = [IO.Path]::GetFullPath($OutputPath)
$buildRoot = Join-Path ([IO.Path]::GetTempPath()) ('lj2600d-osgi-' + [Guid]::NewGuid().ToString('N'))
$classes = Join-Path $buildRoot 'classes'

if (-not (Test-Path -LiteralPath $FelixJar)) { throw "Felix API JAR not found: $FelixJar" }
if (-not (Get-Command javac -ErrorAction SilentlyContinue)) { throw 'javac is required.' }
if (-not (Get-Command jar -ErrorAction SilentlyContinue)) { throw 'jar is required.' }

try {
    New-Item -ItemType Directory -Force -Path $classes | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output) | Out-Null
    & javac -source 7 -target 7 -encoding UTF-8 -classpath $FelixJar -d $classes $source
    if ($LASTEXITCODE -ne 0) { throw 'javac failed.' }
    & jar cfm $output $manifest -C $classes .
    if ($LASTEXITCODE -ne 0) { throw 'jar failed.' }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $output).Hash.ToLowerInvariant()
    Write-Host "Built $output" -ForegroundColor Green
    Write-Host "SHA-256 $hash" -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
}
