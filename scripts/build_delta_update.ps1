<#
.SYNOPSIS
Build a verified HDiffPatch sidecar for an already signed Official APK.
.DESCRIPTION
Reads original distributed base APKs. Never rebuilds/re-signs them or publishes files.
Requires HDiffPatch v5.1.3 tools, apkanalyzer and apksigner on PATH or explicit paths.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TargetApk,
    [string[]]$BaseApks = @(),
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$HdiffzPath = 'hdiffz',
    [string]$HpatchzPath = 'hpatchz',
    [string]$ApkAnalyzerPath = 'apkanalyzer',
    [string]$ApkSignerPath = 'apksigner',
    [switch]$Overwrite
)

$ErrorActionPreference = 'Stop'
if ($BaseApks.Count -gt 8) { throw 'At most eight exact base APKs are supported.' }
$targetPath = (Resolve-Path -LiteralPath $TargetApk).Path
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$workDirectory = Join-Path $outputRoot ('.delta-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workDirectory | Out-Null

function Invoke-CheckedTool {
    param([string]$Tool, [string[]]$ToolArguments)
    $lines = @(& $Tool @ToolArguments 2>&1 | ForEach-Object { $_.ToString() })
    if ($LASTEXITCODE -ne 0) { throw 'APK or patch validation command failed.' }
    return ($lines -join "`n").Trim()
}

function Get-ApkIdentity {
    param([string]$Path)
    $packageName = Invoke-CheckedTool $ApkAnalyzerPath @('manifest', 'application-id', $Path)
    $version = Invoke-CheckedTool $ApkAnalyzerPath @('manifest', 'version-name', $Path)
    $versionCodeText = Invoke-CheckedTool $ApkAnalyzerPath @('manifest', 'version-code', $Path)
    if ($versionCodeText -notmatch '^\d+$') { throw 'Invalid APK version code.' }
    $signatures = Invoke-CheckedTool $ApkSignerPath @('verify', '--print-certs', $Path)
    $certificates = @([regex]::Matches($signatures, 'certificate SHA-256 digest: ([a-fA-F0-9]{64})') |
        ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() } | Sort-Object -Unique)
    if ($certificates.Count -eq 0) { throw 'APK signing certificate unavailable.' }
    $entries = Invoke-CheckedTool $ApkAnalyzerPath @('files', 'list', '--files-only', $Path)
    $abis = @([regex]::Matches($entries, '(?m)^/?lib/([^/]+)/[^\r\n]+\.so\s*$') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    if ($packageName -ne 'moe.rinn.mychu' -or $abis.Count -ne 1 -or $abis[0] -ne 'arm64-v8a') {
        throw 'Only signed Official arm64 single APKs are supported.'
    }
    return [pscustomobject]@{
        Package = $packageName; Version = $version; VersionCode = [long]$versionCodeText
        Signers = $certificates -join ','
        Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
        Size = (Get-Item -LiteralPath $Path).Length
    }
}

try {
    $target = Get-ApkIdentity $targetPath
    $sidecarPath = Join-Path $outputRoot ([IO.Path]::GetFileName($targetPath) + '.delta.json')
    if ((Test-Path -LiteralPath $sidecarPath) -and -not $Overwrite) {
        throw 'Sidecar already exists. Use -Overwrite to replace a generated artifact.'
    }
    $patches = [Collections.Generic.List[object]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new()
    foreach ($baseInput in $BaseApks) {
        $basePath = (Resolve-Path -LiteralPath $baseInput).Path
        $base = Get-ApkIdentity $basePath
        if ($base.Package -ne $target.Package -or $base.Signers -ne $target.Signers) {
            throw 'Base APK identity/signers differ from target.'
        }
        if ($base.VersionCode -ge $target.VersionCode -or -not $seen.Add($base.Hash)) { continue }
        $patchName = "MyCHU-$($base.Hash)-$($target.Hash).hdiff"
        $candidate = Join-Path $workDirectory $patchName
        $reconstructed = Join-Path $workDirectory 'reconstructed.apk'
        [void](Invoke-CheckedTool $HdiffzPath @('-f', '-c-zlib', $basePath, $targetPath, $candidate))
        [void](Invoke-CheckedTool $HpatchzPath @('-f', $basePath, $candidate, $reconstructed))
        $reconstructedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $reconstructed).Hash.ToLowerInvariant()
        if ($reconstructedHash -ne $target.Hash) { throw 'Reconstructed APK differs from signed target.' }
        $patchSize = (Get-Item -LiteralPath $candidate).Length
        if ($patchSize -ge $target.Size * 0.7) { continue }
        $patchPath = Join-Path $outputRoot $patchName
        $patchHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidate).Hash.ToLowerInvariant()
        if (Test-Path -LiteralPath $patchPath) {
            if ((Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash.ToLowerInvariant() -ne $patchHash) {
                throw 'Immutable patch filename already contains different bytes.'
            }
        } else {
            Copy-Item -LiteralPath $candidate -Destination $patchPath
        }
        $patches.Add([ordered]@{
            algorithm = 'hdiffpatch'; compression = 'zlib'
            from_version_code = $base.VersionCode; from_sha256 = $base.Hash
            size = $patchSize; sha256 = $patchHash; url = $patchName
        })
    }
    $manifest = [ordered]@{
        schema_version = 1; package_name = $target.Package; channel = 'official'; abi = 'arm64-v8a'
        target = [ordered]@{ version = $target.Version; version_code = $target.VersionCode
            size = $target.Size; sha256 = $target.Hash }
        patches = @($patches.ToArray())
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sidecarPath -Encoding utf8NoBOM
    [pscustomobject]@{ Manifest = $sidecarPath; TargetSHA256 = $target.Hash; PatchCount = $patches.Count }
} finally {
    # Only this invocation's reproducible output directory; never base/target APKs.
    $checkedWork = [IO.Path]::GetFullPath($workDirectory)
    if ($checkedWork.StartsWith($outputRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $checkedWork -Recurse -Force
    }
}
