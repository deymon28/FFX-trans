#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = 'Stop'
try {
    $repository = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repository 'verify_package.ps1') -FunctionsOnly
    $repository = Get-FfxPackageRoot $repository
    $allowlist = Get-FfxPackageFile $repository 'tools/package-files.txt'
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $lines = @()
    foreach ($relative in [IO.File]::ReadAllLines($allowlist)) {
        if ([string]::IsNullOrWhiteSpace($relative) -or $relative.StartsWith('#')) { continue }
        Assert-FfxRelativePath $relative
        if ($relative -ieq 'SHA256SUMS.txt' -or -not $seen.Add($relative)) {
            throw 'The release allowlist contains a duplicate or the manifest itself.'
        }
        $path = Get-FfxPackageFile $repository $relative
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        $lines += "$hash  $relative"
    }
    if ($lines.Count -eq 0) { throw 'The release allowlist is empty.' }
    $content = ($lines -join "`n") + "`n"
    $manifest = Join-Path $repository 'SHA256SUMS.txt'
    if ($Check) {
        [void](Get-FfxPackageFile $repository 'SHA256SUMS.txt')
        if ([IO.File]::ReadAllText($manifest) -cne $content) { throw 'SHA256SUMS.txt is stale. Review changes before regenerating it.' }
        Write-Host "Manifest is current: $($lines.Count) files."
    } else {
        if (Test-Path -LiteralPath $manifest) { [void](Get-FfxPackageFile $repository 'SHA256SUMS.txt') }
        [IO.File]::WriteAllText($manifest, $content, [Text.UTF8Encoding]::new($false))
        Write-Host "Updated SHA256SUMS.txt for $($lines.Count) reviewed release files."
    }
    exit 0
} catch {
    Write-Host ('ERROR: Manifest update failed. ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
