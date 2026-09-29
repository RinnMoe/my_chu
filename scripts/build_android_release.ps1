[CmdletBinding()]
param(
    [ValidatePattern('^\d{6}$')]
    [string]$Date = (Get-Date -Format 'yyMMdd'),
    [ValidateSet('official', 'preview')]
    [string]$Channel = 'official',
    [ValidatePattern('^\d+$')]
    [string]$BuildNumber,
    [string]$GitSha,
    [string]$BuildId,
    [string]$BuildTimeUtc,
    [string]$MapboxPublicAccessToken = $env:MAPBOX_PUBLIC_ACCESS_TOKEN,
    [switch]$SkipBuild,
    [switch]$Overwrite
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot

$versionLine = Get-Content -LiteralPath (Join-Path $repoRoot 'pubspec.yaml') -Encoding UTF8 |
    Where-Object { $_ -match '^version:\s*[^\s#]+' } |
    Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($versionLine)) {
    throw 'pubspec.yaml is missing a valid version field.'
}

$version = $versionLine.Substring(8).Trim().Split('#', 2)[0].Trim()
$versionName = $version.Split('+', 2)[0]
if ($versionName -notmatch '^\d+\.\d+\.\d+$') {
    throw "Unable to parse version from pubspec.yaml: $version"
}

if ($null -eq $GitSha) { $GitSha = '' }
$GitSha = $GitSha.Trim()
if ([string]::IsNullOrWhiteSpace($GitSha)) {
    try {
        $GitSha = (& git rev-parse --short=12 HEAD 2>$null | Select-Object -First 1).Trim()
    } catch {
        $GitSha = ''
    }
}
if ([string]::IsNullOrWhiteSpace($GitSha)) {
    $GitSha = 'unknown'
}
$GitSha = $GitSha -replace '[^A-Za-z0-9._-]', '_'

if ($null -eq $BuildId) { $BuildId = '' }
$BuildId = $BuildId.Trim()
if ([string]::IsNullOrWhiteSpace($BuildId)) {
    $BuildId = if ($Channel -eq 'preview') { "local-$Date" } else { "release-$Date" }
}
$BuildId = $BuildId -replace '[^A-Za-z0-9._-]', '_'

if ($null -eq $BuildTimeUtc) { $BuildTimeUtc = '' }
$BuildTimeUtc = $BuildTimeUtc.Trim()
if ([string]::IsNullOrWhiteSpace($BuildTimeUtc)) {
    $BuildTimeUtc = (Get-Date).ToUniversalTime().ToString('o')
}

function Invoke-ApkAnalyzer {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    if (-not (Get-Command apkanalyzer -ErrorAction SilentlyContinue)) {
        throw 'apkanalyzer is required to validate the release APK identity.'
    }
    $output = & apkanalyzer @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "apkanalyzer failed for '$($Arguments -join ' ')': $output"
    }
    $output.Trim()
}

$previousBuildChannel = $env:MYCHU_BUILD_CHANNEL
$previousGitSha = $env:MYCHU_GIT_SHA
$previousBuildId = $env:MYCHU_BUILD_ID
$previousBuildTimeUtc = $env:MYCHU_BUILD_TIME_UTC

try {
    $env:MYCHU_BUILD_CHANNEL = $Channel
    $env:MYCHU_GIT_SHA = $GitSha
    $env:MYCHU_BUILD_ID = $BuildId
    $env:MYCHU_BUILD_TIME_UTC = $BuildTimeUtc

    $buildArguments = @(
        'build',
        'apk',
        '--release',
        '--target-platform=android-arm64',
        '--no-pub',
        "--dart-define=MYCHU_BUILD_CHANNEL=$Channel",
        "--dart-define=MYCHU_GIT_SHA=$GitSha",
        "--dart-define=MYCHU_BUILD_ID=$BuildId",
        "--dart-define=MYCHU_BUILD_TIME_UTC=$BuildTimeUtc"
    )
    if (-not $SkipBuild) {
        $MapboxPublicAccessToken = if ($null -eq $MapboxPublicAccessToken) {
            ''
        } else {
            $MapboxPublicAccessToken.Trim()
        }
        if (-not $MapboxPublicAccessToken.StartsWith('pk.') -or $MapboxPublicAccessToken.Length -le 3) {
            throw 'Set MAPBOX_PUBLIC_ACCESS_TOKEN to a Mapbox public pk.* token before building.'
        }
        $buildArguments += "--dart-define=MAPBOX_PUBLIC_ACCESS_TOKEN=$MapboxPublicAccessToken"
    }
    if (-not [string]::IsNullOrWhiteSpace($BuildNumber)) {
        $buildArguments += "--build-number=$BuildNumber"
    }

    if (-not $SkipBuild) {
        & flutter @buildArguments
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter Release build failed with exit code $LASTEXITCODE"
        }
    }

    $source = Join-Path $repoRoot 'build/app/outputs/flutter-apk/app-release.apk'
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Release APK was not found: $source"
    }

    $apkEntries = Invoke-ApkAnalyzer @('files', 'list', '--files-only', $source)
    $apkAbis = @(
        $apkEntries -split "`r?`n" |
            ForEach-Object { $_.Trim().TrimStart('/') } |
            Where-Object { $_ -match '^lib/([^/]+)/' } |
            ForEach-Object { [regex]::Match($_, '^lib/([^/]+)/').Groups[1].Value } |
            Sort-Object -Unique
    )
    if ($apkAbis.Count -ne 1 -or $apkAbis[0] -ne 'arm64-v8a') {
        $actualAbis = if ($apkAbis.Count -eq 0) { 'none' } else { $apkAbis -join ', ' }
        throw "Release APK must contain native libraries for arm64-v8a only; found: $actualAbis."
    }

    $expectedApplicationId = if ($Channel -eq 'preview') {
        'moe.rinn.mychu.preview'
    } else {
        'moe.rinn.mychu'
    }
    $actualApplicationId = Invoke-ApkAnalyzer @('manifest', 'application-id', $source)
    if ($actualApplicationId -ne $expectedApplicationId) {
        throw "APK applicationId mismatch for $Channel`: expected '$expectedApplicationId', got '$actualApplicationId'."
    }

    $expectedLabel = if ($Channel -eq 'preview') { 'MyCHU Preview' } else { 'MyCHU' }
    $actualLabel = Invoke-ApkAnalyzer @(
        'resources',
        'value',
        '--config',
        'default',
        '--type',
        'string',
        '--name',
        'app_name',
        $source
    )
    if ($actualLabel -ne $expectedLabel) {
        throw "APK label mismatch for $Channel`: expected '$expectedLabel', got '$actualLabel'."
    }

    $actualVersionCode = Invoke-ApkAnalyzer @('manifest', 'version-code', $source)
    if ($actualVersionCode -notmatch '^\d+$' -or [int64]$actualVersionCode -le 0) {
        throw "APK versionCode is invalid: '$actualVersionCode'."
    }

    $outputDirectory = Join-Path $repoRoot 'output/releases'
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    $outputName = if ($Channel -eq 'preview') {
        "MyCHU-$versionName-$Date-arm64-v8a-preview-$BuildId-$GitSha.apk"
    } else {
        "MyCHU-$versionName-$Date-arm64-v8a-release.apk"
    }
    $destination = Join-Path $outputDirectory $outputName
    if ((Test-Path -LiteralPath $destination) -and -not $Overwrite) {
        throw "Release artifact already exists: ${destination}. Use -Overwrite to replace it."
    }

    Copy-Item -LiteralPath $source -Destination $destination -Force:$Overwrite
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash

    [pscustomobject]@{
        Version = $version
        Channel = $Channel
        BuildId = $BuildId
        GitSha = $GitSha
        Artifact = $destination
        Bytes = (Get-Item -LiteralPath $destination).Length
        SHA256 = $hash
    } | Format-List
} finally {
    $env:MYCHU_BUILD_CHANNEL = $previousBuildChannel
    $env:MYCHU_GIT_SHA = $previousGitSha
    $env:MYCHU_BUILD_ID = $previousBuildId
    $env:MYCHU_BUILD_TIME_UTC = $previousBuildTimeUtc
}
