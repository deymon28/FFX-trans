#Requires -Version 5.1
param([string]$GameDir, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'patch_core.psm1') -Force -ErrorAction Stop
    Write-Host 'Final Fantasy X HD Remaster - Russian text patch' -ForegroundColor Cyan
    if ([string]::IsNullOrWhiteSpace($GameDir)) { $GameDir = Read-Host 'Game folder (or its data folder)' }
    Invoke-RuInstall -GameDir $GameDir -CheckOnly:$CheckOnly
    if (-not $CheckOnly) {
        Write-Host 'Use the original launcher and select English text. Verify Russian text in the game.'
        Write-Host 'This package affects FFX and the selection menu; it does not translate FFX-2.'
    }
    exit 0
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
