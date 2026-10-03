#Requires -Version 5.1
[CmdletBinding()]
param([switch]$NativeDecoder)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# All game-like data is generated below .local. No game path is accepted.
$script:ProjectRoot = (Get-Item -LiteralPath (Split-Path -Parent $PSScriptRoot)).FullName
$script:LocalRoot = Join-Path $script:ProjectRoot '.local'
$script:TestRoot = Join-Path $script:LocalRoot ('test-run-' + [guid]::NewGuid().ToString('N'))
$script:Passed = 0
$script:Failed = 0
$script:FixtureNumber = 0
$script:OldTemp = [Environment]::GetEnvironmentVariable('TEMP', 'Process')
$script:OldTmp = [Environment]::GetEnvironmentVariable('TMP', 'Process')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -cne $Actual) {
        throw ('{0} Expected: {1}; actual: {2}.' -f $Message, $Expected, $Actual)
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$MessagePart)
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
    if ($null -eq $caught) { throw ('Expected a failure containing: ' + $MessagePart) }
    if ($caught.IndexOf($MessagePart, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw ('Unexpected failure: ' + $caught)
    }
}

function Get-TestHash {
    param([string]$Path, [string]$Algorithm = 'SHA256')
    return (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash
}

function Assert-FileHash {
    param([string]$Path, [string]$Expected, [string]$Algorithm = 'SHA256')
    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) ('Missing fixture file: ' + $Path)
    Assert-Equal $Expected (Get-TestHash $Path $Algorithm) ('Unexpected content: ' + [IO.Path]::GetFileName($Path))
}

function Assert-OwnedDirectory {
    param([string]$Path)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $expectedPrefix = $script:LocalRoot.TrimEnd('\') + '\'
    if (-not $fullPath.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing a fixture path outside the project .local directory.'
    }
    $directory = [IO.DirectoryInfo]::new($fullPath)
    while ($null -ne $directory) {
        if ($directory.Exists -and ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Fixture directory links are not supported.'
        }
        $directory = $directory.Parent
    }
    return $fullPath
}

function Remove-TestDirectory {
    if (-not (Test-Path -LiteralPath $script:TestRoot)) { return }
    $resolved = (Get-Item -LiteralPath (Assert-OwnedDirectory $script:TestRoot) -Force).FullName
    if ($resolved -cne $script:TestRoot -or [IO.Path]::GetFileName($resolved) -notmatch '^test-run-[a-f0-9]{32}$') {
        throw 'Refusing to clean an unexpected test directory.'
    }
    $links = @(Get-ChildItem -LiteralPath $resolved -Recurse -Force | Where-Object {
        $_.Attributes -band [IO.FileAttributes]::ReparsePoint
    })
    if ($links.Count -gt 0) { throw 'Refusing recursive cleanup because a fixture contains a link.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Get-FixtureSnapshot {
    param($Fixture)
    $prefix = $Fixture.Root.TrimEnd('\') + '\'
    $records = @(Get-ChildItem -LiteralPath $Fixture.Root -Force -Recurse | Sort-Object FullName | ForEach-Object {
        $relativePath = $_.FullName.Substring($prefix.Length)
        if ($_.PSIsContainer) {
            'D|' + $relativePath
        } else {
            'F|{0}|{1}|{2}|{3}' -f $relativePath, $_.Length, $_.LastWriteTimeUtc.Ticks, (Get-TestHash $_.FullName)
        }
    })
    return ($records -join "`n")
}

function New-TestFixture {
    $script:FixtureNumber++
    $root = Join-Path $script:TestRoot ('case {0:D2}' -f $script:FixtureNumber)
    [void](Assert-OwnedDirectory $root)
    $package = Join-Path $root 'package with spaces'
    $gameRoot = Join-Path $root 'game with spaces'
    $dataDir = Join-Path $gameRoot 'data'
    [void][IO.Directory]::CreateDirectory($package)
    [void][IO.Directory]::CreateDirectory($dataDir)
    foreach ($name in @('patch_core.psm1', 'decoder.ps1', $script:DecoderInfo.ZipName)) {
        Copy-Item -LiteralPath (Join-Path $script:ProjectRoot $name) -Destination (Join-Path $package $name)
    }

    $entries = @()
    foreach ($index in 0, 1) {
        $name = @('FFX_Data.vbf', 'metamenu.vbf')[$index]
        $patchName = @('FFX Patch.vcdiff', 'metamenu patch.vcdiff')[$index]
        $sourceBytes = [Text.Encoding]::UTF8.GetBytes(('Original fixture {0}. Never a game file.' -f $index))
        $targetBytes = [Text.Encoding]::UTF8.GetBytes(('Translated fixture {0}: complete decoded output.' -f $index))
        $patchBytes = [Text.Encoding]::UTF8.GetBytes(('Mock patch fixture {0}.' -f $index))
        $active = Join-Path $dataDir $name
        $patch = Join-Path $package $patchName
        [IO.File]::WriteAllBytes($active, $sourceBytes)
        [IO.File]::WriteAllBytes($patch, $patchBytes)
        $entries += [pscustomobject]@{
            Name = $name
            Patch = $patchName
            Active = $active
            Backup = $active + '.alchemistlab_original'
            Pending = $active + '.alchemistlab_pending'
            PatchPath = $patch
            SourceBytes = $sourceBytes
            TargetBytes = $targetBytes
            SourceMD5 = (Get-TestHash $active 'MD5')
            PatchSHA256 = (Get-TestHash $patch)
            TargetLength = [long]$targetBytes.Length
        }
    }
    $module = Import-Module (Join-Path $package 'patch_core.psm1') -Force -PassThru -DisableNameChecking
    & $module {
        param([object[]]$Entries)
        $script:ProductionDefinitions = $script:Definitions
        $script:Definitions = $Entries
        $script:TestTargets = @{}
        foreach ($entry in $Entries) { $script:TestTargets[$entry.Name] = $entry.TargetBytes }
        $script:TestDecodeCalls = 0
        $script:TestDecodeMode = 'success'
        $script:TestReplacementMode = 'success'
        $script:TestOriginalNativeCommand = (Get-Command Invoke-XdeltaCommand).ScriptBlock
        $script:TestOriginalSwitch = (Get-Command Switch-PatchFile).ScriptBlock

        # Explicit script scope keeps the fault boundaries alive after this call.
        function script:Invoke-XdeltaCommand {
            param([string]$Xdelta, [object]$Entry)
            $script:TestDecodeCalls++
            if ($script:TestDecodeMode -eq 'native') {
                return (& $script:TestOriginalNativeCommand $Xdelta $Entry)
            }
            if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable('XDELTA', 'Process'))) {
                throw 'The decoder received injected XDELTA environment options.'
            }
            if ($script:TestDecodeMode -eq 'throw') { throw 'Simulated native startup failure.' }
            [byte[]]$bytes = $script:TestTargets[$Entry.Name]
            if ($Entry.Name -eq 'metamenu.vbf' -and $script:TestDecodeMode -eq 'fail-second') {
                [IO.File]::WriteAllBytes($Entry.Pending, [byte[]]@(7, 8, 9))
                return 17
            }
            if ($Entry.Name -eq 'metamenu.vbf' -and $script:TestDecodeMode -eq 'short-second') {
                [IO.File]::WriteAllBytes($Entry.Pending, [byte[]]@(7))
                return 0
            }
            [IO.File]::WriteAllBytes($Entry.Pending, $bytes)
            return 0
        }

        function script:Switch-PatchFile {
            param([string]$Source, [string]$Destination, [AllowNull()][string]$Backup)
            $second = [IO.Path]::GetFileName($Destination) -eq 'metamenu.vbf'
            if ($second -and -not [string]::IsNullOrEmpty($Backup)) {
                if ($script:TestReplacementMode -eq 'fail-second') {
                    throw 'Simulated second replacement failure.'
                }
                if ($script:TestReplacementMode -eq 'fail-after-backup') {
                    [IO.File]::Move($Destination, $Backup)
                    throw 'Simulated replacement failure after backup creation.'
                }
            }
            if ($second -and [string]::IsNullOrEmpty($Backup) -and $script:TestReplacementMode -eq 'fail-restore') {
                throw 'Simulated second restore failure.'
            }
            & $script:TestOriginalSwitch $Source $Destination $Backup
        }
    } $entries
    return [pscustomobject]@{
        Root = $root
        Package = $package
        GameRoot = $gameRoot
        DataDir = $dataDir
        Module = $module
        Entries = $entries
        Archive = (Join-Path $package $script:DecoderInfo.ZipName)
    }
}

function Invoke-FixtureInstall {
    param($Fixture, [switch]$CheckOnly, [switch]$Quoted, [switch]$UseDataDir)
    [void](Assert-OwnedDirectory $Fixture.DataDir)
    $path = $Fixture.GameRoot
    if ($UseDataDir) { $path = $Fixture.DataDir }
    if ($Quoted) { $path = '  "' + $path + '"  ' }
    & $Fixture.Module { param($Path, $Check) Invoke-RuInstall -GameDir $Path -CheckOnly:$Check } $path $CheckOnly.IsPresent
}

function Invoke-FixtureRestore {
    param($Fixture, [switch]$Prompt)
    [void](Assert-OwnedDirectory $Fixture.DataDir)
    & $Fixture.Module { param($Path, $Confirm) Invoke-RuRestore -GameDir $Path -Confirmed:$Confirm } $Fixture.DataDir (-not $Prompt.IsPresent)
}

function Assert-OriginalFixture {
    param($Fixture)
    foreach ($entry in $Fixture.Entries) {
        Assert-FileHash $entry.Active $entry.SourceMD5 'MD5'
        Assert-True (-not (Test-Path -LiteralPath $entry.Backup)) ('Unexpected backup: ' + $entry.Name)
        Assert-True (-not (Test-Path -LiteralPath $entry.Pending)) ('Unexpected pending output: ' + $entry.Name)
    }
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $Fixture.DataDir '.alchemistlab.lock'))) 'Operation lock was not released.'
}

function Assert-InstalledFixture {
    param($Fixture)
    foreach ($entry in $Fixture.Entries) {
        Assert-FileHash $entry.Backup $entry.SourceMD5 'MD5'
        $expectedBytes = [Convert]::ToBase64String($entry.TargetBytes)
        Assert-Equal $expectedBytes ([Convert]::ToBase64String([IO.File]::ReadAllBytes($entry.Active))) ('Incomplete decoded output: ' + $entry.Name)
        Assert-True (-not (Test-Path -LiteralPath $entry.Pending)) ('Unexpected pending output: ' + $entry.Name)
    }
}

function Write-TestArchive {
    param([string]$Path, [switch]$DuplicateEntry)
    Add-Type -AssemblyName System.IO.Compression
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Create, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $zip = $null
    try {
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        $count = 1
        if ($DuplicateEntry) { $count = 2 }
        for ($index = 0; $index -lt $count; $index++) {
            $entryStream = $zip.CreateEntry($script:DecoderInfo.Entry).Open()
            try {
                # Preserve the real EXE length to reach its independent hash gate.
                $bytes = New-Object byte[] $script:DecoderInfo.ExeLength
                $entryStream.Write($bytes, 0, $bytes.Length)
            } finally { $entryStream.Dispose() }
        }
    } finally {
        if ($null -ne $zip) { $zip.Dispose() }
        $stream.Dispose()
    }
}

function Read-VcdiffInteger {
    param([byte[]]$Bytes, [ref]$Offset)
    [long]$value = 0
    for ($count = 0; $count -lt 10; $count++) {
        if ($Offset.Value -ge $Bytes.Length) { throw 'Truncated native VCDIFF fixture.' }
        $next = $Bytes[$Offset.Value]
        $Offset.Value++
        $value = ($value -shl 7) -bor ($next -band 127)
        if (($next -band 128) -eq 0) { return $value }
    }
    throw 'Invalid VCDIFF integer in native fixture.'
}

function Assert-DjwPatch {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    Assert-True ($bytes.Length -gt 10) 'Native encoder produced an empty patch.'
    Assert-Equal 'D6-C3-C4-00' ([BitConverter]::ToString($bytes[0..3])) 'Native output is not VCDIFF.'
    $header = $bytes[4]
    Assert-True (($header -band 1) -ne 0) 'Native output did not select secondary compression.'
    Assert-Equal 1 ([int]$bytes[5]) 'Native output did not select the DJW secondary compressor.'
    Assert-True (($header -band 2) -eq 0) 'Unexpected custom VCDIFF code table.'
    $offset = 6
    if (($header -band 4) -ne 0) {
        $appLength = Read-VcdiffInteger $bytes ([ref]$offset)
        $offset += [int]$appLength
    }
    $window = $bytes[$offset]
    $offset++
    if (($window -band 3) -ne 0) {
        [void](Read-VcdiffInteger $bytes ([ref]$offset))
        [void](Read-VcdiffInteger $bytes ([ref]$offset))
    }
    [void](Read-VcdiffInteger $bytes ([ref]$offset))
    [void](Read-VcdiffInteger $bytes ([ref]$offset))
    Assert-True (($bytes[$offset] -band 7) -ne 0) 'Native fixture did not actually compress a window section with DJW.'
}

function Run-TestCase {
    param([string]$Name, [scriptblock]$Body)
    $fixture = $null
    try {
        $fixture = New-TestFixture
        & $Body $fixture 6>&1 | Out-Null
        $leftovers = @(Get-ChildItem -LiteralPath $script:TestRoot -Directory -Filter 'ffx-trans-*')
        Assert-Equal 0 $leftovers.Count 'Temporary decoder directory was not removed.'
        $script:Passed++
        Write-Host ('[PASS] ' + $Name)
    } catch {
        $script:Failed++
        Write-Host ('[FAIL] {0}: {1}' -f $Name, $_.Exception.Message) -ForegroundColor Red
        Write-Host $_.ScriptStackTrace
    } finally {
        if ($null -ne $fixture) { Remove-Module $fixture.Module -Force }
    }
}

try {
    [void](Assert-OwnedDirectory $script:TestRoot)
    [void][IO.Directory]::CreateDirectory($script:TestRoot)
    [Environment]::SetEnvironmentVariable('TEMP', $script:TestRoot, 'Process')
    [Environment]::SetEnvironmentVariable('TMP', $script:TestRoot, 'Process')
    $sourceModule = Import-Module (Join-Path $script:ProjectRoot 'patch_core.psm1') -Force -PassThru -DisableNameChecking
    try {
        $script:DecoderInfo = & $sourceModule {
            param($Package)
            Add-Type -AssemblyName System.IO.Compression
            $archive = Join-Path $Package $script:XdeltaZipName
            Test-DecoderArchive $archive
            $file = [IO.File]::OpenRead($archive)
            $zip = $null
            try {
                $zip = [IO.Compression.ZipArchive]::new($file, [IO.Compression.ZipArchiveMode]::Read)
                [pscustomobject]@{
                    ZipName = $script:XdeltaZipName
                    ZipHash = $script:XdeltaZipSHA256
                    ExeHash = $script:XdeltaSHA256
                    Entry = $script:XdeltaEntry
                    ExeLength = [int]$zip.GetEntry($script:XdeltaEntry).Length
                }
            } finally {
                if ($null -ne $zip) { $zip.Dispose() }
                $file.Dispose()
            }
        } $script:ProjectRoot
    } finally { Remove-Module $sourceModule -Force }

    Write-Host ('Windows PowerShell {0}; all fixtures stay below project .local.' -f $PSVersionTable.PSVersion)
    Write-Host 'Default cases validate real ZIP/EXE integrity and filesystem recovery; the native decode boundary is mocked.'

    Run-TestCase 'Bundled production payloads and decoder match their integrity gates' {
        param($fixture)
        & $fixture.Module {
            param($Package)
            $testDefinitions = $script:Definitions
            try {
                $script:Definitions = $script:ProductionDefinitions
                $plan = @(Get-Plan $Package $Package)
                [void](Assert-Package $Package $plan)
            } finally { $script:Definitions = $testDefinitions }
        } $script:ProjectRoot
    }

    Run-TestCase 'Preflight preserves every fixture file and never calls the decoder' {
        param($fixture)
        $before = Get-FixtureSnapshot $fixture
        Invoke-FixtureInstall $fixture -CheckOnly
        Assert-Equal $before (Get-FixtureSnapshot $fixture) 'Preflight modified the fixture.'
        Assert-Equal 0 (& $fixture.Module { $script:TestDecodeCalls }) 'Preflight invoked native decoding.'
        Assert-OriginalFixture $fixture
    }

    Run-TestCase 'Successful install keeps verified backups of both originals' {
        param($fixture)
        Invoke-FixtureInstall $fixture
        Assert-InstalledFixture $fixture
        Assert-Equal 2 (& $fixture.Module { $script:TestDecodeCalls }) 'Both outputs must be decoded.'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixture.DataDir '.alchemistlab.lock'))) 'Install lock was not released.'
    }

    Run-TestCase 'Second original MD5 mismatch refuses all changes' {
        param($fixture)
        [IO.File]::AppendAllText($fixture.Entries[1].Active, 'Wrong original.')
        $before = Get-FixtureSnapshot $fixture
        Assert-Throws { Invoke-FixtureInstall $fixture } 'Original MD5 mismatch'
        Assert-Equal $before (Get-FixtureSnapshot $fixture) 'Original mismatch changed the fixture.'
        Assert-Equal 0 (& $fixture.Module { $script:TestDecodeCalls }) 'An unverified original reached the decoder.'
    }

    Run-TestCase 'Tampered patch refuses all changes before decoding' {
        param($fixture)
        [IO.File]::AppendAllText($fixture.Entries[1].PatchPath, 'Tampered patch.')
        $before = Get-FixtureSnapshot $fixture
        Assert-Throws { Invoke-FixtureInstall $fixture } 'Patch SHA-256 mismatch'
        Assert-Equal $before (Get-FixtureSnapshot $fixture) 'A bad patch changed the fixture.'
        Assert-Equal 0 (& $fixture.Module { $script:TestDecodeCalls }) 'An unverified patch reached the decoder.'
    }

    Run-TestCase 'Tampered pinned ZIP refuses all changes before extraction' {
        param($fixture)
        [IO.File]::AppendAllText($fixture.Archive, 'Tampered ZIP.')
        $before = Get-FixtureSnapshot $fixture
        Assert-Throws { Invoke-FixtureInstall $fixture } 'Xdelta ZIP SHA-256 mismatch'
        Assert-Equal $before (Get-FixtureSnapshot $fixture) 'A bad ZIP changed the fixture.'
        Assert-Equal 0 (& $fixture.Module { $script:TestDecodeCalls }) 'An unverified ZIP reached the decoder.'
    }

    Run-TestCase 'Inner EXE hash independently rejects a ZIP with a trusted outer hash' {
        param($fixture)
        Write-TestArchive $fixture.Archive
        & $fixture.Module { param($Hash) $script:XdeltaZipSHA256 = $Hash } (Get-TestHash $fixture.Archive)
        $before = Get-FixtureSnapshot $fixture
        Assert-Throws { Invoke-FixtureInstall $fixture } 'xdelta3.exe SHA-256 mismatch'
        Assert-Equal $before (Get-FixtureSnapshot $fixture) 'A bad inner EXE changed the fixture.'
        Assert-Equal 0 (& $fixture.Module { $script:TestDecodeCalls }) 'An unverified EXE reached the decoder.'
    }

    Run-TestCase 'Duplicate executable archive entries are rejected' {
        param($fixture)
        Write-TestArchive $fixture.Archive -DuplicateEntry
        & $fixture.Module { param($Hash) $script:XdeltaZipSHA256 = $Hash } (Get-TestHash $fixture.Archive)
        $before = Get-FixtureSnapshot $fixture
        Assert-Throws { Invoke-FixtureInstall $fixture } 'Unexpected Xdelta ZIP contents'
        Assert-Equal $before (Get-FixtureSnapshot $fixture) 'An ambiguous archive changed the fixture.'
    }

    Run-TestCase 'An existing backup is refused and preserved byte for byte' {
        param($fixture)
        [IO.File]::WriteAllText($fixture.Entries[0].Backup, 'Existing user backup sentinel.')
        $before = Get-FixtureSnapshot $fixture
        Assert-Throws { Invoke-FixtureInstall $fixture } 'Existing backup or temporary output'
        Assert-Equal $before (Get-FixtureSnapshot $fixture) 'An existing backup was modified.'
    }

    Run-TestCase 'An existing pending file is refused and preserved byte for byte' {
        param($fixture)
        [IO.File]::WriteAllText($fixture.Entries[1].Pending, 'Existing pending output sentinel.')
        $before = Get-FixtureSnapshot $fixture
        Assert-Throws { Invoke-FixtureInstall $fixture } 'Existing backup or temporary output'
        Assert-Equal $before (Get-FixtureSnapshot $fixture) 'An existing pending output was modified.'
    }

    Run-TestCase 'Second decoder failure removes owned output and preserves originals' {
        param($fixture)
        & $fixture.Module { $script:TestDecodeMode = 'fail-second' }
        Assert-Throws { Invoke-FixtureInstall $fixture } 'exit code 17'
        Assert-OriginalFixture $fixture
    }

    Run-TestCase 'Wrong decoded size removes both pending outputs' {
        param($fixture)
        & $fixture.Module { $script:TestDecodeMode = 'short-second' }
        Assert-Throws { Invoke-FixtureInstall $fixture } 'Decoded size mismatch'
        Assert-OriginalFixture $fixture
    }

    Run-TestCase 'A decoder startup exception releases temporary resources' {
        param($fixture)
        & $fixture.Module { $script:TestDecodeMode = 'throw' }
        Assert-Throws { Invoke-FixtureInstall $fixture } 'Simulated native startup failure'
        Assert-OriginalFixture $fixture
    }

    Run-TestCase 'Second replacement failure rolls the first replacement back' {
        param($fixture)
        & $fixture.Module { $script:TestReplacementMode = 'fail-second' }
        Assert-Throws { Invoke-FixtureInstall $fixture } 'Simulated second replacement failure'
        Assert-OriginalFixture $fixture
    }

    Run-TestCase 'Replacement failure after backup creation recovers the missing active file' {
        param($fixture)
        & $fixture.Module { $script:TestReplacementMode = 'fail-after-backup' }
        Assert-Throws { Invoke-FixtureInstall $fixture } 'failure after backup creation'
        Assert-OriginalFixture $fixture
    }

    Run-TestCase 'Restore recovers when an active file is missing' {
        param($fixture)
        Invoke-FixtureInstall $fixture
        Remove-Item -LiteralPath $fixture.Entries[1].Active
        Invoke-FixtureRestore $fixture
        Assert-OriginalFixture $fixture
    }

    Run-TestCase 'Restore validates every backup before changing either active file' {
        param($fixture)
        Invoke-FixtureInstall $fixture
        [IO.File]::AppendAllText($fixture.Entries[1].Backup, 'Corrupt backup.')
        [IO.File]::WriteAllText($fixture.Entries[0].Pending, 'Pending output to preserve.')
        $before = Get-FixtureSnapshot $fixture
        Assert-Throws { Invoke-FixtureRestore $fixture } 'Original MD5 mismatch'
        Assert-Equal $before (Get-FixtureSnapshot $fixture) 'Failed restore changed an active file, backup, or pending file.'
    }

    Run-TestCase 'A partially completed restore is recoverable by rerunning restore' {
        param($fixture)
        Invoke-FixtureInstall $fixture
        foreach ($entry in $fixture.Entries) { [IO.File]::WriteAllText($entry.Pending, 'Pending output to preserve until verification.') }
        & $fixture.Module { $script:TestReplacementMode = 'fail-restore' }
        Assert-Throws { Invoke-FixtureRestore $fixture } 'Simulated second restore failure'
        Assert-FileHash $fixture.Entries[0].Active $fixture.Entries[0].SourceMD5 'MD5'
        Assert-True (-not (Test-Path -LiteralPath $fixture.Entries[0].Backup)) 'The completed restore kept a stale backup.'
        Assert-FileHash $fixture.Entries[1].Backup $fixture.Entries[1].SourceMD5 'MD5'
        foreach ($entry in $fixture.Entries) {
            Assert-True (Test-Path -LiteralPath $entry.Pending) 'Incomplete restore deleted pending recovery data.'
        }
        & $fixture.Module { $script:TestReplacementMode = 'success' }
        Invoke-FixtureRestore $fixture
        Assert-OriginalFixture $fixture
    }

    Run-TestCase 'Restore is repeatable with already original files and removes stale pending files' {
        param($fixture)
        foreach ($entry in $fixture.Entries) { [IO.File]::WriteAllText($entry.Pending, 'Stale pending output.') }
        Invoke-FixtureRestore $fixture
        Assert-OriginalFixture $fixture
        Invoke-FixtureRestore $fixture
        Assert-OriginalFixture $fixture
    }

    Run-TestCase 'Exclusive lock rejects concurrent install and restore without mutations' {
        param($fixture)
        $before = Get-FixtureSnapshot $fixture
        $lock = & $fixture.Module { param($Directory) Open-PatchLock $Directory } $fixture.DataDir
        try {
            Assert-Throws { Invoke-FixtureInstall $fixture } 'Cannot lock the game folder'
            Assert-Throws { Invoke-FixtureRestore $fixture } 'Cannot lock the game folder'
        } finally { $lock.Dispose() }
        Assert-Equal $before (Get-FixtureSnapshot $fixture) 'Lock contention changed the fixture.'
        Assert-OriginalFixture $fixture
    }

    Run-TestCase 'Quoted game and data paths containing spaces work' {
        param($fixture)
        Invoke-FixtureInstall $fixture -Quoted -CheckOnly
        Invoke-FixtureInstall $fixture -Quoted -UseDataDir
        Assert-InstalledFixture $fixture
        Invoke-FixtureRestore $fixture
        Assert-OriginalFixture $fixture
    }

    Run-TestCase 'Cancelled restore preserves installed files, backups, and pending files' {
        param($fixture)
        Invoke-FixtureInstall $fixture
        [IO.File]::WriteAllText($fixture.Entries[0].Pending, 'Pending recovery sentinel.')
        & $fixture.Module { function script:Read-Host { param($Prompt) return 'restore' } }
        $before = Get-FixtureSnapshot $fixture
        Invoke-FixtureRestore $fixture -Prompt
        Assert-Equal $before (Get-FixtureSnapshot $fixture) 'Cancelled restore changed the fixture.'
    }

    Run-TestCase 'Injected XDELTA options are suppressed and restored after success and failure' {
        param($fixture)
        $oldOptions = [Environment]::GetEnvironmentVariable('XDELTA', 'Process')
        $sentinel = '--invalid-test-option-do-not-execute'
        try {
            [Environment]::SetEnvironmentVariable('XDELTA', $sentinel, 'Process')
            Invoke-FixtureInstall $fixture
            Assert-Equal $sentinel ([Environment]::GetEnvironmentVariable('XDELTA', 'Process')) 'Install lost the original environment options.'
            Invoke-FixtureRestore $fixture
            & $fixture.Module { $script:TestDecodeMode = 'throw' }
            Assert-Throws { Invoke-FixtureInstall $fixture } 'Simulated native startup failure'
            Assert-Equal $sentinel ([Environment]::GetEnvironmentVariable('XDELTA', 'Process')) 'Failed install lost the original environment options.'
            Assert-OriginalFixture $fixture
        } finally { [Environment]::SetEnvironmentVariable('XDELTA', $oldOptions, 'Process') }
    }

    if ($NativeDecoder) {
        Write-Host 'Native opt-in: executing only the verified bundled decoder on generated source and target files.'
        Run-TestCase 'NATIVE: real DJW encode/decode roundtrip preserves source and matches target SHA-256' {
            param($fixture)
            $source = New-Object byte[] (192KB)
            $random = [Random]::new(72819)
            $random.NextBytes($source)
            $target = New-Object byte[] (256KB)
            [Array]::Copy($source, 0, $target, 0, 64KB)
            for ($index = 64KB; $index -lt 128KB; $index++) { $target[$index] = [byte]$random.Next(0, 8) }
            [Array]::Copy($source, 64KB, $target, 128KB, 128KB)
            $sourcePath = Join-Path $fixture.DataDir 'native source.bin'
            $targetPath = Join-Path $fixture.DataDir 'native target.bin'
            $patchPath = Join-Path $fixture.Package 'native DJW patch.vcdiff'
            $decodedPath = Join-Path $fixture.DataDir 'native decoded.bin'
            [IO.File]::WriteAllBytes($sourcePath, $source)
            [IO.File]::WriteAllBytes($targetPath, $target)
            $sourceHash = Get-TestHash $sourcePath
            $targetHash = Get-TestHash $targetPath
            & $fixture.Module {
                param($Archive, $Source, $Target, $Patch, $Decoded)
                $script:TestDecodeMode = 'native'
                $decoder = $null
                $oldOptions = [Environment]::GetEnvironmentVariable('XDELTA', 'Process')
                $oldPreference = $ErrorActionPreference
                try {
                    $decoder = Open-Decoder $Archive
                    [Environment]::SetEnvironmentVariable('XDELTA', $null, 'Process')
                    Push-Location -LiteralPath $decoder.Directory
                    try {
                        $ErrorActionPreference = 'Continue'
                        $global:LASTEXITCODE = $null
                        & $decoder.Path -e -S djw -s $Source $Target $Patch | Out-Host
                        $code = $global:LASTEXITCODE
                    } finally {
                        $ErrorActionPreference = $oldPreference
                        Pop-Location
                    }
                    if ($null -eq $code -or $code -ne 0) { throw ('Native DJW encoding failed; exit code: ' + $code) }
                    $entry = [pscustomobject]@{ Name = 'native roundtrip'; Active = $Source; Patch = $Patch; Pending = $Decoded }
                    Invoke-DeltaDecode $decoder.Path $entry
                } finally {
                    [Environment]::SetEnvironmentVariable('XDELTA', $oldOptions, 'Process')
                    $ErrorActionPreference = $oldPreference
                    Close-Decoder $decoder
                }
            } $fixture.Archive $sourcePath $targetPath $patchPath $decodedPath
            Assert-DjwPatch $patchPath
            Assert-FileHash $sourcePath $sourceHash
            Assert-FileHash $targetPath $targetHash
            Assert-FileHash $decodedPath $targetHash
        }
    } else {
        Write-Host '[SKIP] Native DJW roundtrip; opt in with -NativeDecoder after reviewing/scanning the bundled decoder.'
    }
} catch {
    $script:Failed++
    Write-Host ('[FAIL] Test setup: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
} finally {
    [Environment]::SetEnvironmentVariable('TEMP', $script:OldTemp, 'Process')
    [Environment]::SetEnvironmentVariable('TMP', $script:OldTmp, 'Process')
    try { Remove-TestDirectory } catch {
        $script:Failed++
        Write-Host ('[FAIL] Fixture cleanup: ' + $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host ('Results: {0} passed; {1} failed. Real game installation and in-game behavior are not exercised.' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
