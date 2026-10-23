[CmdletBinding()]
param(
    [string]$Device,
    [switch]$BuildOnly,
    [string]$UpgradeLinkConfigFile
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'upgradelink_build_config.ps1')
$nativeConfig = Get-UpgradeLinkBuildConfig -Path $UpgradeLinkConfigFile -Required
$flutterArgs = if ($BuildOnly) { @('build', 'apk', '--debug') } else { @('run', '--debug') }
$flutterArgs += "--dart-define-from-file=$nativeConfig"
if (-not [string]::IsNullOrWhiteSpace($env:MAPBOX_PUBLIC_ACCESS_TOKEN)) {
    $flutterArgs += "--dart-define=MAPBOX_PUBLIC_ACCESS_TOKEN=$env:MAPBOX_PUBLIC_ACCESS_TOKEN"
}
if ($Device -and -not $BuildOnly) { $flutterArgs += @('-d', $Device) }
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Debug build/run failed.' }
} finally {
    Pop-Location
}
