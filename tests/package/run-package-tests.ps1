#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$verifier = Join-Path $repository 'verify_package.ps1'
$builder = Join-Path $repository 'tools/build-release.ps1'
$powershell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$testRoot = Join-Path $repository ('.local/package-tests-' + [guid]::NewGuid().ToString('N'))
$utf8 = [Text.UTF8Encoding]::new($false)
$abcHash = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
$passed = 0
$junctions = @()
$completed = $false

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function New-Fixture {
    param([string]$Name)
    $path = Join-Path $testRoot $Name
    [void][IO.Directory]::CreateDirectory($path)
    return $path
}

function Write-FixtureFile {
    param([string]$Root, [string]$RelativePath, [string]$Text)
    $path = Join-Path $Root $RelativePath
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
    [IO.File]::WriteAllText($path, $Text, $utf8)
}

function Invoke-TestScript {
    param([string]$Path, [string[]]$Arguments)
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $oldPreference }
    return [pscustomobject]@{ Code = $code; Text = ($output -join "`n") }
}

function Assert-ScriptResult {
    param([object]$Result, [int]$ExpectedCode, [string]$Name, [string]$ExpectedText)
    Assert-True ($Result.Code -eq $ExpectedCode) "$Name returned $($Result.Code), expected $ExpectedCode. $($Result.Text)"
    if ($ExpectedText) { Assert-True ($Result.Text.Contains($ExpectedText)) "$Name did not report '$ExpectedText'. $($Result.Text)" }
    $script:passed++
    Write-Host "PASS: $Name"
}

function Test-BadManifest {
    param([string]$Name, [string]$Text, [string]$ExpectedText)
    $fixture = New-Fixture $Name
    Write-FixtureFile $fixture 'known.txt' 'abc'
    Write-FixtureFile $fixture 'SHA256SUMS.txt' $Text
    $result = Invoke-TestScript $verifier @('-PackageDir', $fixture)
    Assert-ScriptResult $result 1 $Name $ExpectedText
}

function Write-BuildManifest {
    param([string]$Fixture, [string[]]$Paths)
    $lines = @()
    foreach ($relative in $Paths) {
        $hash = (Get-FileHash -LiteralPath (Join-Path $Fixture $relative) -Algorithm SHA256).Hash.ToLowerInvariant()
        $lines += "$hash  $relative"
    }
    Write-FixtureFile $Fixture 'SHA256SUMS.txt' (($lines -join "`n") + "`n")
}

try {
    . $verifier -FunctionsOnly
    $repository = Get-FfxPackageRoot $repository
    $local = Join-Path $repository '.local'
    if (-not (Test-Path -LiteralPath $local)) { [void][IO.Directory]::CreateDirectory($local) }
    [void](Get-FfxPackageRoot $local)
    [void][IO.Directory]::CreateDirectory($testRoot)
    [void](Get-FfxPackageRoot $testRoot)

    $valid = New-Fixture 'valid'
    Write-FixtureFile $valid 'docs/known file.txt' 'abc'
    Write-FixtureFile $valid 'SHA256SUMS.txt' "$abcHash  docs/known file.txt`n"
    $before = (Get-FileHash -LiteralPath (Join-Path $valid 'docs/known file.txt') -Algorithm SHA256).Hash
    $result = Invoke-TestScript $verifier @('-PackageDir', $valid)
    Assert-ScriptResult $result 0 'known SHA-256 and nested filename with spaces' 'Package verification passed: 1 files.'
    $after = (Get-FileHash -LiteralPath (Join-Path $valid 'docs/known file.txt') -Algorithm SHA256).Hash
    Assert-True ($before -eq $after) 'Verification modified a package file.'
    Assert-True (@(Get-ChildItem -LiteralPath $valid -Recurse -File).Count -eq 2) 'Verification created a file.'

    $corrupt = New-Fixture 'corrupt'
    Write-FixtureFile $corrupt 'known.txt' 'abd'
    Write-FixtureFile $corrupt 'SHA256SUMS.txt' "$abcHash  known.txt`n"
    Assert-ScriptResult (Invoke-TestScript $verifier @('-PackageDir', $corrupt)) 1 'same-length corruption' 'SHA-256 mismatch'

    Test-BadManifest 'missing' "$abcHash  missing.txt`n" 'verification failed'
    Test-BadManifest 'traversal' "$abcHash  ../known.txt`n" 'Unsafe package-relative path'
    Test-BadManifest 'absolute' "$abcHash  C:/known.txt`n" 'Invalid package-relative path'
    Test-BadManifest 'backslash' "$abcHash  docs\known.txt`n" 'Invalid package-relative path'
    Test-BadManifest 'duplicate' "$abcHash  known.txt`n$abcHash  known.txt`n" 'Duplicate manifest path'
    Test-BadManifest 'case-duplicate' "$abcHash  known.txt`n$abcHash  KNOWN.TXT`n" 'Duplicate manifest path'
    Test-BadManifest 'bad-format' "$abcHash known.txt`n" 'Invalid SHA256SUMS.txt format'
    Test-BadManifest 'self-entry' "$abcHash  SHA256SUMS.txt`n" 'cannot include its own checksum'
    Test-BadManifest 'empty' '' 'contains no file entries'
    Test-BadManifest 'alternate-stream' "$abcHash  known.txt:stream`n" 'Invalid package-relative path'
    Test-BadManifest 'device-name' "$abcHash  NUL.txt`n" 'Unsafe package-relative path'
    Test-BadManifest 'trailing-dot' "$abcHash  known.txt.`n" 'Unsafe package-relative path'
    Test-BadManifest 'empty-component' "$abcHash  docs//known.txt`n" 'Unsafe package-relative path'

    $directoryFile = New-Fixture 'directory-file'
    [void][IO.Directory]::CreateDirectory((Join-Path $directoryFile 'known.txt'))
    Write-FixtureFile $directoryFile 'SHA256SUMS.txt' "$abcHash  known.txt`n"
    Assert-ScriptResult (Invoke-TestScript $verifier @('-PackageDir', $directoryFile)) 1 'directory cannot be a manifest file' 'Expected a regular package file'

    $linked = New-Fixture 'linked'
    $linkTarget = New-Fixture 'link-target'
    Write-FixtureFile $linkTarget 'known.txt' 'abc'
    $junction = Join-Path $linked 'docs'
    [void](New-Item -ItemType Junction -Path $junction -Target $linkTarget)
    $junctions += $junction
    Write-FixtureFile $linked 'SHA256SUMS.txt' "$abcHash  docs/known.txt`n"
    Assert-ScriptResult (Invoke-TestScript $verifier @('-PackageDir', $linked)) 1 'manifest parent junction' 'Package links are not allowed'
    Assert-ScriptResult (Invoke-TestScript $verifier @('-PackageDir', $junction)) 1 'package root junction' 'directory links or junctions'

    $fixture = New-Fixture 'build'
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'tools'))
    Copy-Item -LiteralPath $verifier -Destination (Join-Path $fixture 'verify_package.ps1')
    Copy-Item -LiteralPath $builder -Destination (Join-Path $fixture 'tools/build-release.ps1')
    Write-FixtureFile $fixture 'known.txt' 'abc'
    Write-FixtureFile $fixture 'docs/guide.md' 'Synthetic package fixture.'
    Write-FixtureFile $fixture 'payload.ps1' "throw 'A release payload was executed unexpectedly.'"
    Write-FixtureFile $fixture '.env' 'EXCLUDED_SYNTHETIC_SENTINEL=not-a-secret'
    $paths = @('verify_package.ps1', 'known.txt', 'docs/guide.md', 'payload.ps1')
    Write-FixtureFile $fixture 'tools/package-files.txt' (($paths -join "`n") + "`n")
    Write-BuildManifest $fixture $paths
    $fixtureBuilder = Join-Path $fixture 'tools/build-release.ps1'
    Assert-ScriptResult (Invoke-TestScript $fixtureBuilder @()) 0 'build allowlisted synthetic release' 'Release created:'
    $zipPath = Join-Path $fixture 'dist/FFX-trans-v1.0.0.zip'
    $sumPath = $zipPath + '.sha256'
    $zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-True (([IO.File]::ReadAllText($sumPath)).Trim() -ceq "$zipHash  FFX-trans-v1.0.0.zip") 'The outer checksum does not describe the archive.'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $names = @($zip.Entries | ForEach-Object { $_.FullName })
        Assert-True ($names.Count -eq 5) 'Unexpected release file count.'
        foreach ($relative in ($paths + @('SHA256SUMS.txt'))) {
            Assert-True ($names -ccontains $relative) "Missing expected release entry: $relative"
        }
        Assert-True ($names -notcontains '.env') 'The builder included an unlisted local file.'
    } finally { $zip.Dispose() }
    Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $fixture 'dist') -Force).Count -eq 2) 'The builder did not clean temporary build files.'
    $passed++
    Write-Host 'PASS: archive layout, excluded local file, checksum, and temporary cleanup'

    Assert-ScriptResult (Invoke-TestScript $fixtureBuilder @()) 1 'existing outputs require explicit overwrite' 'Use -Force'
    Assert-True ((Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $zipHash) 'A rejected build replaced the existing archive.'
    Assert-ScriptResult (Invoke-TestScript $fixtureBuilder @('-Force')) 0 'explicit overwrite succeeds' 'Release created:'
    Assert-ScriptResult (Invoke-TestScript $fixtureBuilder @('-Version', '../escape')) 1 'unsafe version is rejected' "parameter 'Version'"

    Write-FixtureFile $fixture 'unlisted.txt' 'Unlisted synthetic input.'
    Write-BuildManifest $fixture ($paths + @('unlisted.txt'))
    Assert-ScriptResult (Invoke-TestScript $fixtureBuilder @('-Version', '1.0.1')) 1 'manifest cannot add unallowlisted files' 'exactly the same file paths'
    Write-BuildManifest $fixture $paths
    Write-FixtureFile $fixture 'tools/package-files.txt' (($paths + @('../outside.txt') -join "`n") + "`n")
    Assert-ScriptResult (Invoke-TestScript $fixtureBuilder @('-Version', '1.0.1')) 1 'allowlist traversal is rejected' 'Unsafe package-relative path'
    Write-FixtureFile $fixture 'tools/package-files.txt' (($paths + @('KNOWN.TXT') -join "`n") + "`n")
    Assert-ScriptResult (Invoke-TestScript $fixtureBuilder @('-Version', '1.0.1')) 1 'allowlist case duplicate is rejected' 'Duplicate release allowlist path'
    Write-FixtureFile $fixture 'tools/package-files.txt' (($paths -join "`n") + "`n")
    Write-FixtureFile $fixture 'known.txt' 'abd'
    Assert-ScriptResult (Invoke-TestScript $fixtureBuilder @('-Version', '1.0.1')) 1 'build refuses corrupt source inputs' 'SHA-256 mismatch'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixture 'dist/FFX-trans-v1.0.1.zip'))) 'A failed build published an archive.'

    $linkedBuild = New-Fixture 'build-linked-dist'
    [void][IO.Directory]::CreateDirectory((Join-Path $linkedBuild 'tools'))
    Copy-Item -LiteralPath $verifier -Destination (Join-Path $linkedBuild 'verify_package.ps1')
    Copy-Item -LiteralPath $builder -Destination (Join-Path $linkedBuild 'tools/build-release.ps1')
    Write-FixtureFile $linkedBuild 'tools/package-files.txt' "verify_package.ps1`n"
    Write-BuildManifest $linkedBuild @('verify_package.ps1')
    $outsideDist = New-Fixture 'outside-dist'
    $distLink = Join-Path $linkedBuild 'dist'
    [void](New-Item -ItemType Junction -Path $distLink -Target $outsideDist)
    $junctions += $distLink
    Assert-ScriptResult (Invoke-TestScript (Join-Path $linkedBuild 'tools/build-release.ps1') @()) 1 'release output directory junction is rejected' 'directory links or junctions'
    Assert-True (@(Get-ChildItem -LiteralPath $outsideDist -Force).Count -eq 0) 'The builder wrote through an output junction.'

    Write-FixtureFile $fixture 'known.txt' 'abc'
    Assert-ScriptResult (Invoke-TestScript (Join-Path $fixture 'verify_package.ps1') @()) 0 'verifier defaults to its own package directory' 'Package verification passed'
    $completed = $true
    Write-Host "Package tests passed: $passed. Synthetic files only; no decoder or game files were executed." -ForegroundColor Green
} catch {
    Write-Host ('ERROR: Package tests failed. ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host "Fixture location: $testRoot"
    exit 1
} finally {
    # Remove junction entries themselves before any recursive fixture cleanup.
    foreach ($junction in $junctions) {
        if (Test-Path -LiteralPath $junction) { [IO.Directory]::Delete($junction, $false) }
    }
    if ($completed -and (Test-Path -LiteralPath $testRoot)) {
        $resolved = Get-FfxPackageRoot $testRoot
        $prefix = ([IO.Path]::GetFullPath((Join-Path $repository '.local'))).TrimEnd([char[]]@('\', '/')) + [IO.Path]::DirectorySeparatorChar
        if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($resolved) -notmatch '^package-tests-[0-9a-f]{32}$') {
            throw 'Test fixture cleanup path is outside the expected .local directory.'
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
    }
}
exit 0
