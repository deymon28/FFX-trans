#Requires -Version 5.1
param([string]$GameDir)
$ErrorActionPreference = 'Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'patch_core.psm1') -Force -ErrorAction Stop
    Write-Host 'Final Fantasy X - restore original files' -ForegroundColor Cyan
    if ([string]::IsNullOrWhiteSpace($GameDir)) { $GameDir = Read-Host 'Game folder (or its data folder)' }
    Invoke-RuRestore -GameDir $GameDir
    exit 0
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
