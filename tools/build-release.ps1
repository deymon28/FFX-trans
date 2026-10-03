#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$')]
    [string]$Version = '1.0.0',
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$buildDirectory = $null
$distDirectory = $null

function Assert-FfxOutputFile {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return }
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing a directory or link at release output: $Path"
    }
    if (-not $Force) { throw "Release output already exists. Use -Force to replace it: $Path" }
}

function Publish-FfxOutput {
    param([string]$Source, [string]$Destination)
    Assert-FfxOutputFile $Destination
    if (Test-Path -LiteralPath $Destination) {
        [IO.File]::Replace($Source, $Destination, [NullString]::Value)
    } else {
        [IO.File]::Move($Source, $Destination)
    }
}

try {
    $repository = Split-Path -Parent $PSScriptRoot
    # This is the trusted source verifier, never the copy inside the built ZIP.
    . (Join-Path $repository 'verify_package.ps1') -FunctionsOnly
    $repository = Get-FfxPackageRoot $repository
    $allowlistFile = Get-FfxPackageFile $repository 'tools/package-files.txt'
    $allowlist = @()
    $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in [IO.File]::ReadAllLines($allowlistFile)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
        Assert-FfxRelativePath $line
        if ($line -ieq 'SHA256SUMS.txt') { throw 'Do not put SHA256SUMS.txt in package-files.txt; it is added separately.' }
        if (-not $expected.Add($line)) { throw "Duplicate release allowlist path: $line" }
        $allowlist += $line
    }
    if ($allowlist.Count -eq 0) { throw 'The release allowlist is empty.' }
    Write-Host 'Verifying release inputs...'
    $manifestEntries = @(Test-FfxPackage $repository)
    if ($manifestEntries.Count -ne $allowlist.Count) {
        throw 'The manifest and release allowlist must contain exactly the same file paths.'
    }
    foreach ($entry in $manifestEntries) {
        if (-not $expected.Contains($entry.RelativePath)) {
            throw "Manifest entry is absent from the release allowlist: $($entry.RelativePath)"
        }
    }
    $manifestPath = Get-FfxPackageFile $repository 'SHA256SUMS.txt'
    $manifestBytes = [IO.File]::ReadAllBytes($manifestPath)

    $distDirectory = Join-Path $repository 'dist'
    $distItem = Get-Item -LiteralPath $distDirectory -Force -ErrorAction SilentlyContinue
    if ($null -eq $distItem) { [void][IO.Directory]::CreateDirectory($distDirectory) }
    $distDirectory = Get-FfxPackageRoot $distDirectory
    $archiveName = "FFX-trans-v$Version.zip"
    $archiveOutput = Join-Path $distDirectory $archiveName
    $checksumOutput = $archiveOutput + '.sha256'
    Assert-FfxOutputFile $archiveOutput
    Assert-FfxOutputFile $checksumOutput
    $buildDirectory = Join-Path $distDirectory ('.build-' + [guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $buildDirectory) { throw 'Temporary release directory already exists.' }
    [void][IO.Directory]::CreateDirectory($buildDirectory)
    $buildDirectory = Get-FfxPackageRoot $buildDirectory
    $archiveTemporary = Join-Path $buildDirectory $archiveName

    Add-Type -AssemblyName System.IO.Compression
    $stream = $null
    $archive = $null
    try {
        $stream = [IO.File]::Open($archiveTemporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        foreach ($relative in ($allowlist + @('SHA256SUMS.txt'))) {
            $entry = $archive.CreateEntry($relative, [IO.Compression.CompressionLevel]::Optimal)
            # A fixed timestamp avoids publishing local file timestamps.
            $entry.LastWriteTime = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
            $entryInput = $null
            $entryOutput = $null
            try {
                $entryOutput = $entry.Open()
                if ($relative -eq 'SHA256SUMS.txt') {
                    $entryOutput.Write($manifestBytes, 0, $manifestBytes.Length)
                } else {
                    $path = Get-FfxPackageFile $repository $relative
                    $entryInput = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                    $entryInput.CopyTo($entryOutput)
                }
            } finally {
                if ($null -ne $entryOutput) { $entryOutput.Dispose() }
                if ($null -ne $entryInput) { $entryInput.Dispose() }
            }
        }
    } finally {
        if ($null -ne $archive) { $archive.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }

    $extractedDirectory = Join-Path $buildDirectory 'extracted'
    [void][IO.Directory]::CreateDirectory($extractedDirectory)
    $archive = $null
    $stream = $null
    try {
        $stream = [IO.File]::OpenRead($archiveTemporary)
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $true)
        $archivePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $archive.Entries) {
            $relative = $entry.FullName
            Assert-FfxRelativePath $relative
            if (-not $archivePaths.Add($relative) -or
                ($relative -cne 'SHA256SUMS.txt' -and -not $expected.Contains($relative))) {
                throw "Unexpected or duplicate ZIP entry: $relative"
            }
            $target = Join-Path $extractedDirectory $relative
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            $entryInput = $null
            $entryOutput = $null
            try {
                $entryInput = $entry.Open()
                $entryOutput = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                $entryInput.CopyTo($entryOutput)
            } finally {
                if ($null -ne $entryOutput) { $entryOutput.Dispose() }
                if ($null -ne $entryInput) { $entryInput.Dispose() }
            }
        }
        if ($archivePaths.Count -ne $allowlist.Count + 1 -or -not $archivePaths.Contains('SHA256SUMS.txt')) {
            throw 'The ZIP does not contain exactly the expected release files and manifest.'
        }
    } finally {
        if ($null -ne $archive) { $archive.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
    Write-Host 'Verifying extracted release bytes with the source verifier...'
    $extractedEntries = @(Test-FfxPackage $extractedDirectory)
    if ($extractedEntries.Count -ne $allowlist.Count) { throw 'Extracted manifest file count changed during packaging.' }
    foreach ($entry in $extractedEntries) {
        if (-not $expected.Contains($entry.RelativePath)) { throw 'Extracted manifest paths changed during packaging.' }
    }
    $archiveHash = (Get-FileHash -LiteralPath $archiveTemporary -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksumTemporary = Join-Path $buildDirectory ($archiveName + '.sha256')
    [IO.File]::WriteAllText($checksumTemporary, "$archiveHash  $archiveName`n", [Text.UTF8Encoding]::new($false))
    Publish-FfxOutput $archiveTemporary $archiveOutput
    Publish-FfxOutput $checksumTemporary $checksumOutput
    Write-Host "Release created: $archiveOutput" -ForegroundColor Green
    Write-Host "SHA-256: $archiveHash"
    Write-Host "Checksum file: $checksumOutput"
} catch {
    Write-Host ('ERROR: Release build failed. ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    if ($null -ne $buildDirectory -and (Test-Path -LiteralPath $buildDirectory)) {
        try {
            $resolved = Get-FfxPackageRoot $buildDirectory
            $prefix = $distDirectory.TrimEnd([char[]]@('\', '/')) + [IO.Path]::DirectorySeparatorChar
            if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
                [IO.Path]::GetFileName($resolved) -notmatch '^\.build-[0-9a-f]{32}$') {
                throw 'Temporary release cleanup path is outside the expected dist directory.'
            }
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Warning ('Temporary release files were preserved. ' + $_.Exception.Message)
        }
    }
}
exit 0
