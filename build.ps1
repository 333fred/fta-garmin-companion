[CmdletBinding()]
param(
    [ValidateSet('All', 'Android', 'Watch')]
    [string] $Target = 'All',
    [string] $GarminSdk = $env:GARMIN_SDK,
    [string] $GarminDeveloperKey = $env:GARMIN_DEVELOPER_KEY
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$companion = Join-Path $PSScriptRoot 'companion'
$watch = Join-Path $PSScriptRoot 'watch'
$androidSettings = Join-Path $companion 'app\build.gradle.kts'
$gradle = Join-Path $companion 'gradlew.bat'
$manifestPath = Join-Path $watch 'manifest.xml'
$jungle = Join-Path $watch 'monkey.jungle'

foreach ($file in @($androidSettings, $gradle, $manifestPath, $jungle)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Required project file not found: $file"
    }
}

$versionMatches = [regex]::Matches(
    (Get-Content -LiteralPath $androidSettings -Raw),
    '(?m)^[ \t]*versionName[ \t]*=[ \t]*"([^"]+)"[ \t]*\r?$'
)
if ($versionMatches.Count -ne 1) {
    throw 'Expected exactly one Android versionName in app\build.gradle.kts.'
}
$androidVersion = $versionMatches[0].Groups[1].Value

$manifest = [System.Xml.XmlDocument]::new()
$manifest.Load($manifestPath)
$namespaces = [System.Xml.XmlNamespaceManager]::new($manifest.NameTable)
$namespaces.AddNamespace('iq', 'http://www.garmin.com/xml/connectiq')
$application = $manifest.SelectSingleNode('/iq:manifest/iq:application', $namespaces)
if ($null -eq $application) {
    throw 'The watch manifest does not contain an application.'
}
$watchVersion = $application.GetAttribute('version')
if ([string]::IsNullOrWhiteSpace($watchVersion) -or $androidVersion -ne $watchVersion) {
    throw "Application versions differ: Android '$androidVersion', watch '$watchVersion'."
}

$devices = @(
    $application.SelectNodes('iq:products/iq:product', $namespaces) |
        ForEach-Object { $_.GetAttribute('id') }
)
if ($devices.Count -eq 0 -or @($devices | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -ne 0) {
    throw 'The watch manifest must list supported products with device IDs.'
}

if ($Target -ne 'Android') {
    if ([string]::IsNullOrWhiteSpace($GarminSdk)) {
        if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
            $selectedSdk = Join-Path $env:APPDATA 'Garmin\ConnectIQ\current-sdk.cfg'
            if (Test-Path -LiteralPath $selectedSdk -PathType Leaf) {
                $GarminSdk = ([string](Get-Content -LiteralPath $selectedSdk -Raw)).Trim()
            }
        }
        if ([string]::IsNullOrWhiteSpace($GarminSdk)) {
            throw 'Select a Connect IQ SDK in SDK Manager, or specify -GarminSdk or GARMIN_SDK.'
        }
    }
    $compiler = Join-Path $GarminSdk 'bin\monkeyc.bat'
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        throw "Connect IQ compiler not found: $compiler"
    }
    if ([string]::IsNullOrWhiteSpace($GarminDeveloperKey)) {
        foreach ($name in @('developer_key', 'developer_key.der')) {
            $localKey = Join-Path $PSScriptRoot $name
            if (Test-Path -LiteralPath $localKey -PathType Leaf) {
                $GarminDeveloperKey = $localKey
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace($GarminDeveloperKey)) {
            throw 'Place developer_key or developer_key.der in the repository root, or specify -GarminDeveloperKey or GARMIN_DEVELOPER_KEY.'
        }
    }
    if (-not (Test-Path -LiteralPath $GarminDeveloperKey -PathType Leaf)) {
        throw "Developer signing key not found: $GarminDeveloperKey"
    }
}

if ($Target -ne 'Watch') {
    & $gradle -p $companion ':app:assembleDebug' ':app:lintDebug'
    if ($LASTEXITCODE -ne 0) {
        throw "Android build failed with exit code $LASTEXITCODE."
    }
}

if ($Target -ne 'Android') {
    $outputDirectory = Join-Path $watch 'bin'
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    foreach ($device in $devices) {
        $output = Join-Path $outputDirectory "fta-monitor-garmin-watchapp-$device.prg"
        & $compiler -f $jungle -o $output -y $GarminDeveloperKey -d $device -w
        if ($LASTEXITCODE -ne 0) {
            throw "Watch build failed for $device with exit code $LASTEXITCODE."
        }
    }
}
