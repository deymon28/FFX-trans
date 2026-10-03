#Requires -Version 5.1
# Only the full official decoder supports the DJW-compressed translation patches.
$script:XdeltaZipName = 'xdelta3-3.2.0-windows-x86_64.zip'
$script:XdeltaZipSHA256 = '8ACA331C3D49EC4465EE8F3F7E3AFB92E06D36E32FDEC422C3252AAA813A7D2A'
$script:XdeltaSHA256 = '6E812B38484D0C764291779FADEE83FFBE2ECEACCB4E3A21F8A043A02654A01E'
$script:XdeltaEntry = 'xdelta3-3.2.0-windows-x86_64/xdelta3.exe'

function Get-StreamSHA256 {
    param([IO.Stream]$Stream)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($Stream))).Replace('-', '') }
    finally { $algorithm.Dispose() }
}

function Read-DecoderArchive {
    param([string]$Path, [AllowNull()][string]$Destination)
    Assert-RegularFile $Path
    Add-Type -AssemblyName System.IO.Compression
    $file = $null
    $zip = $null
    $inputStream = $null
    $outputStream = $null
    try {
        # Hash and read the same handle; deny writers and replacement throughout.
        $file = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        if ((Get-StreamSHA256 $file) -ne $script:XdeltaZipSHA256) { throw 'Xdelta ZIP SHA-256 mismatch.' }
        $file.Position = 0
        $zip = [IO.Compression.ZipArchive]::new($file, [IO.Compression.ZipArchiveMode]::Read, $true)
        $entries = @($zip.Entries | Where-Object { $_.FullName -ceq $script:XdeltaEntry })
        if ($entries.Count -ne 1 -or $entries[0].Length -ne 336896) { throw 'Unexpected Xdelta ZIP contents.' }
        $inputStream = $entries[0].Open()
        if ((Get-StreamSHA256 $inputStream) -ne $script:XdeltaSHA256) { throw 'xdelta3.exe SHA-256 mismatch.' }
        $inputStream.Dispose()
        $inputStream = $null
        if (-not [string]::IsNullOrEmpty($Destination)) {
            # Fixed entry and fixed destination: no archive path can escape this directory.
            $inputStream = $entries[0].Open()
            $outputStream = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $inputStream.CopyTo($outputStream)
        }
    } finally {
        if ($null -ne $outputStream) { $outputStream.Dispose() }
        if ($null -ne $inputStream) { $inputStream.Dispose() }
        if ($null -ne $zip) { $zip.Dispose() }
        if ($null -ne $file) { $file.Dispose() }
    }
}

function Test-DecoderArchive {
    param([string]$Path)
    Read-DecoderArchive $Path $null
}

function Assert-DecoderRuntime {
    if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) {
        throw 'Use 64-bit Windows PowerShell on Windows x64.'
    }
    foreach ($name in @('vcruntime140.dll', 'ucrtbase.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path ([Environment]::SystemDirectory) $name) -PathType Leaf)) {
            throw 'Microsoft Visual C++ x64 runtime is missing. Install it from https://aka.ms/vc14/vc_redist.x64.exe and retry.'
        }
    }
}

function Open-Decoder {
    param([string]$Archive)
    Assert-DecoderRuntime
    $directory = Join-Path ([IO.Path]::GetTempPath()) ('ffx-trans-' + [guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $directory) { throw 'Temporary decoder directory already exists.' }
    [void][IO.Directory]::CreateDirectory($directory)
    $context = [pscustomobject]@{ Directory = $directory; Path = (Join-Path $directory 'xdelta3.exe'); Handle = $null }
    try {
        Read-DecoderArchive $Archive $context.Path
        $context.Handle = [IO.File]::Open($context.Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        if ((Get-StreamSHA256 $context.Handle) -ne $script:XdeltaSHA256) { throw 'Extracted xdelta3.exe SHA-256 mismatch.' }
        return $context
    } catch {
        Close-Decoder $context
        throw
    }
}

function Close-Decoder {
    param($Context)
    if ($null -eq $Context) { return }
    if ($null -ne $Context.Handle) { $Context.Handle.Dispose() }
    try {
        # Only the exact file we created is deleted. Never recursively remove TEMP.
        if (Test-Path -LiteralPath $Context.Path) { Remove-Item -LiteralPath $Context.Path -Force -ErrorAction Stop }
        if (Test-Path -LiteralPath $Context.Directory) { [IO.Directory]::Delete($Context.Directory, $false) }
    } catch { Write-Warning "Temporary decoder could not be removed: $($Context.Directory). $($_.Exception.Message)" }
}

function Invoke-XdeltaCommand {
    param([string]$Xdelta, [object]$Entry)
    # A private test double replaces only this native execution boundary in wrapper tests.
    Push-Location -LiteralPath ([IO.Path]::GetDirectoryName($Xdelta))
    try {
        $global:LASTEXITCODE = $null
        try {
            & $Xdelta -d -D -R -s $Entry.Active $Entry.Patch $Entry.Pending | Out-Host
        } catch { throw ('Unable to start xdelta3.exe. ' + $_.Exception.Message) }
        if ($null -eq $global:LASTEXITCODE) { throw 'Unable to start xdelta3.exe. Check runtime, antivirus messages, and file permissions.' }
        return $global:LASTEXITCODE
    } finally { Pop-Location }
}
