<#
.SYNOPSIS
Attach a generated manifest and patches to an existing Fenfa release.
.DESCRIPTION
Explicit publication command. FENFA_UPLOAD_TOKEN comes from the caller's environment;
never store it in the repository or pass it to the application. Does not upload/replace the APK.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][uri]$FenfaBaseUrl,
    [Parameter(Mandatory)][string]$ReleaseId
)
$ErrorActionPreference = 'Stop'
if ($FenfaBaseUrl.Scheme -ne 'https' -or $FenfaBaseUrl.UserInfo -or $FenfaBaseUrl.Query -or
        $ReleaseId -notmatch '^[A-Za-z0-9_-]+$') { throw 'Use an HTTPS Fenfa origin and a valid release ID.' }
if ([string]::IsNullOrWhiteSpace($env:FENFA_UPLOAD_TOKEN)) { throw 'FENFA_UPLOAD_TOKEN is required.' }
$manifestFile = (Resolve-Path -LiteralPath $ManifestPath).Path
$directory = [IO.Path]::GetDirectoryName($manifestFile)
$manifestText = [IO.File]::ReadAllText($manifestFile, [Text.Encoding]::UTF8)
$manifest = $manifestText | ConvertFrom-Json
if ($manifest.schema_version -ne 1 -or @($manifest.patches).Count -gt 8) { throw 'Unsupported delta manifest.' }
$client = [Net.Http.HttpClient]::new()
$content = [Net.Http.MultipartFormDataContent]::new()
try {
    $client.DefaultRequestHeaders.Add('X-Auth-Token', $env:FENFA_UPLOAD_TOKEN)
    $content.Add([Net.Http.StringContent]::new($manifestText, [Text.Encoding]::UTF8), 'manifest')
    foreach ($patch in $manifest.patches) {
        if ($patch.sha256 -notmatch '^[a-f0-9]{64}$' -or
                $patch.url -notmatch '^[A-Za-z0-9._-]+\.hdiff$') { throw 'Expected local generated patch filenames.' }
        $path = [IO.Path]::GetFullPath((Join-Path $directory $patch.url))
        if ([IO.Path]::GetDirectoryName($path) -ne $directory -or
            (Get-Item -LiteralPath $path).Length -ne $patch.size -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ne $patch.sha256) {
            throw 'Local patch does not match the manifest.'
        }
        $part = [Net.Http.StreamContent]::new([IO.File]::OpenRead($path))
        $part.Headers.ContentType = [Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream')
        $content.Add($part, $patch.sha256, [IO.Path]::GetFileName($path))
    }
    $endpoint = [uri]::new($FenfaBaseUrl.AbsoluteUri.TrimEnd('/') + '/releases/' + $ReleaseId + '/delta')
    $response = $client.PostAsync($endpoint, $content).GetAwaiter().GetResult()
    try {
        if (-not $response.IsSuccessStatusCode) {
            throw "Fenfa rejected delta publication (HTTP $([int]$response.StatusCode))."
        }
        [pscustomobject]@{ ReleaseId = $ReleaseId; Published = $true; PatchCount = @($manifest.patches).Count }
    } finally { $response.Dispose() }
} catch {
    # Do not propagate raw HTTP errors containing URLs, headers or credentials.
    throw 'Delta publication failed; check Fenfa release identity and upload permissions.'
} finally { $content.Dispose(); $client.Dispose() }
