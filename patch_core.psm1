#Requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Definitions = @(
    [pscustomobject]@{
        Name = 'FFX_Data.vbf'
        Patch = 'FFX Patch.vcdiff'
        SourceMD5 = 'DBB4ADAF14FBC80D631266A876D00892'
        PatchSHA256 = 'F325560DAA5766D849BED22B4B8A45F590343CA327DB32D17B3C91345806414C'
        TargetLength = [long]20799140005
    },
    [pscustomobject]@{
        Name = 'metamenu.vbf'
        Patch = 'metamenu patch.vcdiff'
        SourceMD5 = '535BBD83176480ABCA1D1AAF33DF0091'
        PatchSHA256 = '513D9F96CAD2288C781022AE0C7BB1B6F9BCF8C3DCA30348629FBA3272001CE4'
        TargetLength = [long]21768300
    }
)
. (Join-Path $PSScriptRoot 'decoder.ps1')

function Assert-RegularFile {
    param([string]$Path, [switch]$Optional)
    if (-not (Test-Path -LiteralPath $Path)) {
        if ($Optional) { return }
        throw "File not found: $Path"
    }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Expected a regular file, not a directory or link: $Path"
    }
}

function Get-CheckedHash {
    param([string]$Path, [string]$Algorithm = 'SHA256')
    Assert-RegularFile $Path
    return (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm -ErrorAction Stop).Hash
}

function Resolve-DataDirectory {
    param([string]$GameDir)
    if ([string]::IsNullOrWhiteSpace($GameDir)) { throw 'The game folder is required.' }
    $item = Get-Item -LiteralPath $GameDir.Trim().Trim('"') -Force -ErrorAction Stop
    if (-not $item.PSIsContainer -or $item.PSProvider.Name -ne 'FileSystem') {
        throw 'The game path must be a filesystem directory.'
    }
    $path = $item.FullName
    $hasData = $false
    foreach ($definition in $script:Definitions) {
        foreach ($suffix in @('', '.alchemistlab_original', '.alchemistlab_pending')) {
            if (Test-Path -LiteralPath (Join-Path $path ($definition.Name + $suffix))) { $hasData = $true }
        }
    }
    if (-not $hasData) { $path = Join-Path $path 'data' }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Game data folder not found: $path" }
    # Reject directory links so the free-space check describes the actual volume.
    $directory = [IO.DirectoryInfo]::new($path)
    while ($null -ne $directory) {
        if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Directory links are not supported: $($directory.FullName)"
        }
        $directory = $directory.Parent
    }
    $root = [IO.Path]::GetPathRoot($path)
    if ($root.StartsWith('\\')) { throw 'Use a local drive, not a network share.' }
    return [IO.Path]::GetFullPath($path)
}

function Get-Plan {
    param([string]$DataDir, [string]$PackageDir)
    foreach ($definition in $script:Definitions) {
        [pscustomobject]@{
            Name = $definition.Name
            Active = Join-Path $DataDir $definition.Name
            Backup = Join-Path $DataDir ($definition.Name + '.alchemistlab_original')
            Pending = Join-Path $DataDir ($definition.Name + '.alchemistlab_pending')
            Patch = Join-Path $PackageDir $definition.Patch
            SourceMD5 = $definition.SourceMD5
            PatchSHA256 = $definition.PatchSHA256
            TargetLength = $definition.TargetLength
        }
    }
}

function Assert-Package {
    param([string]$PackageDir, [object[]]$Plan)
    Assert-DecoderRuntime
    $xdelta = Join-Path $PackageDir $script:XdeltaZipName
    Test-DecoderArchive $xdelta
    foreach ($entry in $Plan) {
        if ((Get-CheckedHash $entry.Patch) -ne $entry.PatchSHA256) {
            throw "Patch SHA-256 mismatch: $($entry.Patch)"
        }
    }
    return $xdelta
}

function Assert-Original {
    param([string]$Path, [string]$ExpectedMD5)
    Write-Host "Checking original: $Path"
    if ((Get-CheckedHash $Path 'MD5') -ne $ExpectedMD5) {
        throw "Original MD5 mismatch: $Path. Do not bypass this check. Verify the game files in Steam."
    }
}

function Assert-GameStopped {
    $running = @(Get-Process -ErrorAction Stop | Where-Object {
        $_.ProcessName -in @('FFX', 'FFX_EN', 'FFX_JP', 'FFX-2', 'FFX2', 'FFX&X-2_LAUNCHER', 'FFX&X-2_LAUNCHER_RU')
    })
    if ($running.Count -gt 0) { throw 'Close the game and its launcher before proceeding.' }
}

function Get-AvailableBytes {
    param([string]$DataDir)
    $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($DataDir))
    if (-not $drive.IsReady -or $drive.DriveFormat -notin @('NTFS', 'ReFS')) {
        throw 'A ready local NTFS or ReFS volume is required for atomic replacement.'
    }
    return $drive.AvailableFreeSpace
}

function Assert-FreeSpace {
    param([string]$DataDir, [object[]]$Plan)
    [long]$required = 256MB
    foreach ($entry in $Plan) { $required += $entry.TargetLength }
    [long]$available = Get-AvailableBytes $DataDir
    Write-Host ('Free space: {0:N2} GiB; required: {1:N2} GiB.' -f ($available / 1GB), ($required / 1GB))
    if ($available -lt $required) { throw 'Insufficient free space. No game files have been changed.' }
}

function Open-PatchLock {
    param([string]$DataDir)
    $path = Join-Path $DataDir '.alchemistlab.lock'
    Assert-RegularFile $path -Optional
    try {
        return [IO.FileStream]::new($path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None, 4096, [IO.FileOptions]::DeleteOnClose)
    } catch {
        throw "Cannot lock the game folder. Another patch operation may be running, or write access is denied: $path"
    }
}

function Switch-PatchFile {
    param([string]$Source, [string]$Destination, [AllowNull()][string]$Backup)
    # All callers use adjacent files on the same volume.
    if ([string]::IsNullOrEmpty($Backup)) {
        # Windows PowerShell 5.1 converts $null to an empty string at this .NET boundary.
        [IO.File]::Replace($Source, $Destination, [NullString]::Value)
    } else {
        [IO.File]::Replace($Source, $Destination, $Backup)
    }
}

function Restore-OneOriginal {
    param([object]$Entry)
    Assert-Original $Entry.Backup $Entry.SourceMD5
    Assert-RegularFile $Entry.Active -Optional
    if (Test-Path -LiteralPath $Entry.Active) {
        Switch-PatchFile $Entry.Backup $Entry.Active $null
    } else {
        [IO.File]::Move($Entry.Backup, $Entry.Active)
    }
}

function Invoke-DeltaDecode {
    param([string]$Xdelta, [object]$Entry)
    # XDELTA can inject flags; use only the explicit arguments below.
    $oldOptions = [Environment]::GetEnvironmentVariable('XDELTA', 'Process')
    $oldPreference = $ErrorActionPreference
    try {
        [Environment]::SetEnvironmentVariable('XDELTA', $null, 'Process')
        $ErrorActionPreference = 'Continue'
        $code = Invoke-XdeltaCommand $Xdelta $Entry
    } finally {
        $ErrorActionPreference = $oldPreference
        [Environment]::SetEnvironmentVariable('XDELTA', $oldOptions, 'Process')
    }
    if ($code -ne 0) { throw "xdelta3 failed for $($Entry.Name), exit code $code." }
}

function Remove-OwnedPending {
    param([object[]]$Plan)
    foreach ($entry in $Plan) {
        try {
            Assert-RegularFile $entry.Pending -Optional
            if (Test-Path -LiteralPath $entry.Pending) { Remove-Item -LiteralPath $entry.Pending -Force -ErrorAction Stop }
        } catch {
            Write-Warning "Temporary output was preserved: $($entry.Pending). $($_.Exception.Message)"
        }
    }
}

function Invoke-RuInstall {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$GameDir, [switch]$CheckOnly)
    $dataDir = Resolve-DataDirectory $GameDir
    $plan = @(Get-Plan $dataDir $PSScriptRoot)
    $lock = $null
    $ownedPending = @()
    $committed = @()
    $decoder = $null
    try {
        Assert-GameStopped
        if (-not $CheckOnly) { $lock = Open-PatchLock $dataDir }
        $xdelta = Assert-Package $PSScriptRoot $plan
        foreach ($entry in $plan) {
            if ((Test-Path -LiteralPath $entry.Backup) -or (Test-Path -LiteralPath $entry.Pending)) {
                throw "Existing backup or temporary output for $($entry.Name). Run restore_original.cmd first."
            }
            Assert-Original $entry.Active $entry.SourceMD5
        }
        Assert-FreeSpace $dataDir $plan
        if ($CheckOnly) {
            Write-Host 'Preflight passed. No files were changed. Patching and in-game behavior are not tested.'
            return
        }
        $decoder = Open-Decoder $xdelta
        foreach ($entry in $plan) {
            if (Test-Path -LiteralPath $entry.Pending) { throw "Temporary path already exists: $($entry.Pending)" }
            $ownedPending += $entry
            Write-Host "Building temporary output: $($entry.Name)"
            Invoke-DeltaDecode $decoder.Path $entry
            Assert-RegularFile $entry.Pending
            if ((Get-Item -LiteralPath $entry.Pending).Length -ne $entry.TargetLength) {
                throw "Decoded size mismatch: $($entry.Name). Originals are unchanged."
            }
            Write-Host "Hashing decoded output: $($entry.Name)"
            $digest = Get-CheckedHash $entry.Pending
            Write-Host "Decoded SHA-256 (reference only): $($entry.Name) $digest"
        }
        Assert-GameStopped
        foreach ($entry in $plan) {
            Assert-Original $entry.Active $entry.SourceMD5
            if (Test-Path -LiteralPath $entry.Backup) { throw "Backup already exists: $($entry.Backup)" }
        }
        foreach ($entry in $plan) {
            Write-Host "Installing: $($entry.Name)"
            Switch-PatchFile $entry.Pending $entry.Active $entry.Backup
            $committed += $entry
        }
        Write-Host 'Installation completed. Keep the .alchemistlab_original backups.' -ForegroundColor Green
    } catch {
        $failure = $_.Exception.Message
        $rollbackErrors = @()
        # Also inspect a backup created by a failed ReplaceFile call.
        foreach ($entry in $plan) {
            if (($ownedPending.Count -gt 0) -and (Test-Path -LiteralPath $entry.Backup)) {
                try { Restore-OneOriginal $entry }
                catch { $rollbackErrors += "$($entry.Name): $($_.Exception.Message)" }
            }
        }
        if ($rollbackErrors.Count -gt 0) {
            throw ($failure + ' Recovery is incomplete. Preserve all .alchemistlab_original files and run restore_original.cmd. ' + ($rollbackErrors -join ' | '))
        }
        if ($committed.Count -gt 0) { Write-Host 'Completed replacements were rolled back.' }
        throw $failure
    } finally {
        Close-Decoder $decoder
        Remove-OwnedPending $ownedPending
        if ($null -ne $lock) { $lock.Dispose() }
    }
}

function Invoke-RuRestore {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$GameDir, [switch]$Confirmed)
    $dataDir = Resolve-DataDirectory $GameDir
    $plan = @(Get-Plan $dataDir $PSScriptRoot)
    $lock = $null
    try {
        Assert-GameStopped
        $lock = Open-PatchLock $dataDir
        [void](Get-AvailableBytes $dataDir)
        foreach ($entry in $plan) {
            Assert-RegularFile $entry.Active -Optional
            Assert-RegularFile $entry.Pending -Optional
            if (Test-Path -LiteralPath $entry.Backup) {
                Assert-Original $entry.Backup $entry.SourceMD5
            } else {
                Assert-Original $entry.Active $entry.SourceMD5
            }
        }
        if (-not $Confirmed) {
            $answer = Read-Host 'Type RESTORE to restore the verified originals and remove temporary outputs'
            if ($answer -cne 'RESTORE') { Write-Host 'Cancelled.'; return }
        }
        foreach ($entry in $plan) {
            if (Test-Path -LiteralPath $entry.Backup) {
                Write-Host "Restoring: $($entry.Name)"
                Restore-OneOriginal $entry
            }
        }
        foreach ($entry in $plan) { Assert-Original $entry.Active $entry.SourceMD5 }
        Remove-OwnedPending $plan
        Write-Host 'Both original files are restored and verified.' -ForegroundColor Green
    } catch {
        throw ($_.Exception.Message + ' Restore did not complete. Preserve all active and .alchemistlab_original files. Resolve the error and rerun restore_original.cmd.')
    } finally {
        if ($null -ne $lock) { $lock.Dispose() }
    }
}

Export-ModuleMember -Function Invoke-RuInstall, Invoke-RuRestore
