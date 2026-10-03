#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$PackageDir,
    [switch]$FunctionsOnly
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($PackageDir)) { $PackageDir = $PSScriptRoot }

function Get-FfxPackageRoot {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (-not $item.PSIsContainer -or $item.PSProvider.Name -ne 'FileSystem') {
        throw 'The package path must be a filesystem directory.'
    }
    $directory = [IO.DirectoryInfo]::new($item.FullName)
    while ($null -ne $directory) {
        if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Package paths must not contain directory links or junctions.'
        }
        $directory = $directory.Parent
    }
    return $item.FullName
}

function Assert-FfxRelativePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or
        $Path -match '[\\:<>"|?*\x00-\x1f]' -or $Path.Trim() -cne $Path) {
        throw "Invalid package-relative path: $Path"
    }
    foreach ($part in ($Path -split '/')) {
        if ([string]::IsNullOrEmpty($part) -or $part -in @('.', '..') -or
            $part.EndsWith('.') -or $part.Trim() -cne $part -or
            $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
            throw "Unsafe package-relative path: $Path"
        }
    }
}

function Get-FfxPackageFile {
    param([string]$Root, [string]$RelativePath)
    Assert-FfxRelativePath $RelativePath
    $path = $Root
    $parts = @($RelativePath -split '/')
    for ($index = 0; $index -lt $parts.Count; $index++) {
        $path = Join-Path $path $parts[$index]
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Package links are not allowed: $RelativePath"
        }
        if ($index -lt $parts.Count - 1) {
            if (-not $item.PSIsContainer) { throw "Expected a directory in path: $RelativePath" }
        } elseif ($item.PSIsContainer) {
            throw "Expected a regular package file: $RelativePath"
        }
    }
    return $path
}

function Read-FfxManifest {
    param([string]$Root)
    $manifest = Get-FfxPackageFile $Root 'SHA256SUMS.txt'
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $entries = @()
    $lineNumber = 0
    foreach ($line in [IO.File]::ReadAllLines($manifest)) {
        $lineNumber++
        if ($line.Length -eq 0) { continue }
        if ($line -cnotmatch '^([0-9a-fA-F]{64})  (.+)$') {
            throw "Invalid SHA256SUMS.txt format on line $lineNumber. Expected: SHA256, two spaces, relative path."
        }
        $hash = $Matches[1]
        $relative = $Matches[2]
        Assert-FfxRelativePath $relative
        if ($relative -ieq 'SHA256SUMS.txt') { throw 'The manifest cannot include its own checksum.' }
        if (-not $seen.Add($relative)) { throw "Duplicate manifest path: $relative" }
        $entries += [pscustomobject]@{ RelativePath = $relative; SHA256 = $hash }
    }
    if ($entries.Count -eq 0) { throw 'SHA256SUMS.txt contains no file entries.' }
    return $entries
}

function Test-FfxPackage {
    param([string]$Directory)
    $root = Get-FfxPackageRoot $Directory
    $entries = @(Read-FfxManifest $root)
    foreach ($entry in $entries) {
        $path = Get-FfxPackageFile $root $entry.RelativePath
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($actual -ine $entry.SHA256) { throw "SHA-256 mismatch: $($entry.RelativePath)" }
        Write-Host "Verified: $($entry.RelativePath)"
    }
    return $entries
}

# The builder loads these source helpers, then verifies extracted files as data.
# No PowerShell script from the extracted release is executed during packaging.
if ($FunctionsOnly) { return }

try {
    $verified = @(Test-FfxPackage $PackageDir)
    Write-Host "Package verification passed: $($verified.Count) files. No files were changed." -ForegroundColor Green
    exit 0
} catch {
    Write-Host ('ERROR: Package verification failed. ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
