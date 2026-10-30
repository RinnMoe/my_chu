[CmdletBinding()]
param(
    [string]$Device,
    [switch]$BuildOnly,
    [string]$UpgradeLinkConfigFile,
    [string]$SupabaseConfigFile,
    [string]$PrivacyBaseUrl = $env:MYCHU_PRIVACY_BASE_URL
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($PrivacyBaseUrl)) {
    $PrivacyBaseUrl = 'https://mychu-policy.rinn.moe/'
}
. (Join-Path $PSScriptRoot 'upgradelink_build_config.ps1')
. (Join-Path $PSScriptRoot 'supabase_build_config.ps1')
$nativeConfig = Get-UpgradeLinkBuildConfig -Path $UpgradeLinkConfigFile -Required
$supabaseConfig = Get-SupabaseBuildConfig -Path $SupabaseConfigFile
$flutterArgs = if ($BuildOnly) { @('build', 'apk', '--debug') } else { @('run', '--debug') }
$flutterArgs += "--dart-define-from-file=$nativeConfig"
if ($supabaseConfig) { $flutterArgs += "--dart-define-from-file=$supabaseConfig" }
if (-not [string]::IsNullOrWhiteSpace($env:MAPBOX_PUBLIC_ACCESS_TOKEN)) {
    $flutterArgs += "--dart-define=MAPBOX_PUBLIC_ACCESS_TOKEN=$env:MAPBOX_PUBLIC_ACCESS_TOKEN"
}
$flutterArgs += "--dart-define=MYCHU_PRIVACY_BASE_URL=$PrivacyBaseUrl"
if ($Device -and -not $BuildOnly) { $flutterArgs += @('-d', $Device) }
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Debug build/run failed.' }
} finally {
    Pop-Location
}
