[CmdletBinding()]
param(
  [switch]$RunTests,
  [switch]$SyncOnly,
  [switch]$Offline
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$flutterOverrideSource = Join-Path $PSScriptRoot 'pubspec_overrides.ohos.yaml'
$flutterOverrideTarget = Join-Path $repoRoot 'pubspec_overrides.yaml'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "mychu-harmony-pub-$([guid]::NewGuid().ToString('N'))"
$relativeStatePaths = @(
  'pubspec.lock',
  '.dart_tool/package_config.json',
  '.dart_tool/package_graph.json',
  '.dart_tool/version',
  '.packages',
  '.flutter-plugins',
  '.flutter-plugins-dependencies',
  'android/local.properties'
)
$previouslyPresent = @{}
$overlayWasPresent = Test-Path -LiteralPath $flutterOverrideTarget
$success = $false

if (!(Test-Path -LiteralPath $flutterOverrideSource)) {
  throw "Harmony pubspec override source is missing: $flutterOverrideSource"
}

Push-Location $repoRoot
try {
  New-Item -ItemType Directory -Path $tempRoot | Out-Null

  foreach ($relativePath in $relativeStatePaths) {
    $sourcePath = Join-Path $repoRoot $relativePath
    $backupPath = Join-Path $tempRoot ($relativePath -replace '[\\/.]', '_')
    $exists = Test-Path -LiteralPath $sourcePath -PathType Leaf
    $previouslyPresent[$relativePath] = $exists
    if ($exists) {
      Copy-Item -LiteralPath $sourcePath -Destination $backupPath
    }
  }
  if ($overlayWasPresent) {
    Copy-Item -LiteralPath $flutterOverrideTarget -Destination (Join-Path $tempRoot 'pubspec_overrides.yaml')
  }

  $flutterCommand = Get-Command flutter -ErrorAction Stop
  $flutterPath = $flutterCommand.Source
  if ($flutterPath -notmatch 'flutter-oh') {
    throw "Flutter OH is not first on PATH. Initialize the Flutter OH and DevEco environment first; found $flutterPath"
  }
  $versionOutput = (& flutter --version 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0 -or $versionOutput -notmatch '3\.41\.10-ohos-1\.0\.0') {
    throw "Expected Flutter OH 3.41.10-ohos-1.0.0; got:`n$versionOutput"
  }

  $hmosSdkHome = $env:HOS_SDK_HOME
  if ($env:DEVECO_SDK_HOME) {
    $devecoDefaultSdk = Join-Path $env:DEVECO_SDK_HOME 'default'
    if (Test-Path -LiteralPath (Join-Path $devecoDefaultSdk 'openharmony')) {
      $hmosSdkHome = $devecoDefaultSdk
    } elseif (Test-Path -LiteralPath (Join-Path $env:DEVECO_SDK_HOME 'openharmony')) {
      $hmosSdkHome = $env:DEVECO_SDK_HOME
    }
  }
  if ($hmosSdkHome -and (Test-Path -LiteralPath (Join-Path $hmosSdkHome 'default\openharmony'))) {
    $hmosSdkHome = Join-Path $hmosSdkHome 'default'
  }
  if (!$hmosSdkHome -or !(Test-Path -LiteralPath (Join-Path $hmosSdkHome 'openharmony'))) {
    throw 'Harmony SDK was not found. Load the Flutter OH environment and set HOS_SDK_HOME or DEVECO_SDK_HOME.'
  }
  $env:HOS_SDK_HOME = $hmosSdkHome
  Write-Host "HOS_SDK_HOME: $env:HOS_SDK_HOME"
  Copy-Item -LiteralPath $flutterOverrideSource -Destination $flutterOverrideTarget -Force

  if ($SyncOnly -and $RunTests) {
    throw 'RunTests cannot be combined with SyncOnly.'
  }

  $pubArguments = @('pub', 'get')
  if ($Offline) {
    $pubArguments += '--offline'
  }
  $commands = @(
    [pscustomobject]@{ Tool = 'flutter'; Arguments = $pubArguments }
  )
  if ($SyncOnly) {
    $commands += [pscustomobject]@{
      Tool = 'hvigorw'
      Arguments = @('--sync', '-p', 'product=default', '--analyze=normal', '--parallel', '--incremental', '--daemon', '--stacktrace')
    }
  } else {
    $commands += [pscustomobject]@{ Tool = 'flutter'; Arguments = @('analyze', '--no-fatal-warnings', '--no-fatal-infos') }
    if ($RunTests) {
      $commands += [pscustomobject]@{ Tool = 'flutter'; Arguments = @('test') }
    }
    $commands += [pscustomobject]@{
      Tool = 'flutter'
      Arguments = @('build', 'hap', '--debug', '--no-codesign', '--target-platform', 'ohos-x64')
    }
  }
  foreach ($command in $commands) {
    $arguments = $command.Arguments
    Write-Host ($command.Tool + ' ' + ($arguments -join ' '))
    if ($command.Tool -eq 'hvigorw') {
      $hvigorCommand = Get-Command hvigorw -ErrorAction Stop
      Push-Location (Join-Path $repoRoot 'ohos')
      try {
        & $hvigorCommand.Source @arguments
        $commandExitCode = $LASTEXITCODE
      } finally {
        Pop-Location
      }
    } else {
      & flutter @arguments
      $commandExitCode = $LASTEXITCODE
    }
    if ($commandExitCode -ne 0) {
      throw "Command failed (exit $commandExitCode): $($command.Tool) $($arguments -join ' ')"
    }
  }
  $success = $true
}
finally {
  foreach ($relativePath in $relativeStatePaths) {
    $targetPath = Join-Path $repoRoot $relativePath
    if ($previouslyPresent.ContainsKey($relativePath) -and $previouslyPresent[$relativePath]) {
      $backupPath = Join-Path $tempRoot ($relativePath -replace '[\\/.]', '_')
      Copy-Item -LiteralPath $backupPath -Destination $targetPath -Force
    } elseif (Test-Path -LiteralPath $targetPath -PathType Leaf) {
      Remove-Item -LiteralPath $targetPath -Force
    }
  }
  if ($overlayWasPresent) {
    Copy-Item -LiteralPath (Join-Path $tempRoot 'pubspec_overrides.yaml') -Destination $flutterOverrideTarget -Force
  } elseif (Test-Path -LiteralPath $flutterOverrideTarget) {
    Remove-Item -LiteralPath $flutterOverrideTarget -Force
  }
  Pop-Location
  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
}

if ($success) {
  if ($SyncOnly) {
    Write-Host 'Harmony sync complete; pubspec.lock, Pub resolver state, and android/local.properties were restored.'
  } else {
    Write-Host 'Harmony build complete; pubspec.lock, Pub resolver state, and android/local.properties were restored.'
  }
}
