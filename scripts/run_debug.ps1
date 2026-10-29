[CmdletBinding()]
param(
    [string]$Device,
    [switch]$BuildOnly,
    [string]$UpgradeLinkConfigFile,
    [string]$SupabaseConfigFile
)

$ErrorActionPreference = 'Stop'
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
if ($Device -and -not $BuildOnly) { $flutterArgs += @('-d', $Device) }
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Debug build/run failed.' }
} finally {
    Pop-Location
}
