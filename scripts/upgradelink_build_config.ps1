# Shared by local Debug and Official Release builds; never print configuration values.
function Get-UpgradeLinkBuildConfig {
    param([string]$Path, [switch]$Required)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path (Split-Path -Parent $PSScriptRoot) '.local/upgradelink.json'
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if ($Required) { throw 'UL configuration missing. Create .local/upgradelink.json or pass -UpgradeLinkConfigFile.' }
        return $null
    }
    try { $config = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch {
        throw 'UL configuration must be a JSON object.'
    }
    if ($config -isnot [pscustomobject]) { throw 'UL configuration must be a JSON object.' }
    foreach ($key in @('MYCHU_UPGRADELINK_APK_KEY', 'MYCHU_UPGRADELINK_ACCESS_KEY', 'MYCHU_UPGRADELINK_SECRET_KEY')) {
        if ($config.$key -isnot [string] -or [string]::IsNullOrWhiteSpace($config.$key)) {
            throw 'UL configuration requires nonempty application and API keys.'
        }
    }
    $origin = $null
    if ($config.PSObject.Properties.Name -contains 'MYCHU_UPGRADELINK_BASE_URL') {
        $url = $config.MYCHU_UPGRADELINK_BASE_URL
        if ($url -isnot [string] -or -not [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$origin) -or
            $origin.Scheme -ne 'https' -or -not $origin.Host -or $origin.UserInfo -or
            $origin.Query -or $origin.Fragment -or $origin.AbsolutePath -ne '/') {
            throw 'UL configuration requires an HTTPS origin without path, credentials, query or fragment.'
        }
    }
    return (Resolve-Path -LiteralPath $Path).Path
}
