[CmdletBinding()]
param(
    [ValidateSet('All', 'Android', 'Watch')]
    [string] $Target = 'All',
    [ValidateSet('Debug', 'Release')]
    [string] $Configuration = 'Debug',
    [string] $GarminSdk = $env:GARMIN_SDK,
    [string] $GarminDeveloperKey = $env:GARMIN_DEVELOPER_KEY,
    [string] $OutputDirectory = (Join-Path $PSScriptRoot 'build\official'),
    [switch] $Official
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

$androidSettingsText = Get-Content -LiteralPath $androidSettings -Raw
function Read-AndroidSetting([string] $Name, [string] $Pattern) {
    $matches = [regex]::Matches($androidSettingsText, "(?m)^[ \t]*$Name[ \t]*=[ \t]*$Pattern[ \t]*\r?$")
    if ($matches.Count -ne 1) {
        throw "Expected exactly one Android $Name in app\build.gradle.kts."
    }
    $matches[0].Groups[1].Value
}
$androidVersion = Read-AndroidSetting 'versionName' '"([^"]+)"'

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

$release = $Configuration -eq 'Release'
if ($Official -and (-not $release -or $Target -ne 'All')) {
    throw 'An official build requires -Configuration Release -Target All.'
}
if ($Official) {
    foreach ($name in @('GITHUB_REPOSITORY', 'GITHUB_SHA', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT',
                         'GITHUB_WORKFLOW_REF', 'ANDROID_RELEASE_CERT_SHA256', 'CIQ_RELEASE_PUBLIC_KEY_SHA256')) {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
            throw "Official build environment variable is missing: $name"
        }
    }
    if ($env:GITHUB_EVENT_NAME -cne 'push' -or
        -not [string]::Equals($env:GITHUB_REF, 'refs/heads/main', [StringComparison]::Ordinal) -or
        -not $env:GITHUB_WORKFLOW_REF.StartsWith("$env:GITHUB_REPOSITORY/.github/workflows/build.yml@", [StringComparison]::Ordinal)) {
        throw 'Official builds must originate from the main-branch push build workflow.'
    }
    & git -C $PSScriptRoot diff --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Official build sources have uncommitted changes.' }
    & git -C $PSScriptRoot diff --cached --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Official build sources have staged changes.' }
    if ([string]::IsNullOrWhiteSpace($GarminDeveloperKey)) {
        throw 'An official build requires an explicit production Garmin developer key.'
    }
}
if ($release) {
    if (@($devices | Where-Object { $_ -notmatch '^[a-zA-Z0-9_]+$' }).Count -ne 0 -or
        @($devices | Select-Object -Unique).Count -ne $devices.Count) {
        throw 'Release device IDs must be unique and safe for artifact filenames.'
    }
    $OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $targets = if ($Target -eq 'All') { @('Android', 'Watch') } else { @($Target) }
    $files = @('fta-garmin-companion.apk', 'app-release.aab', 'fta-monitor-garmin-watchapp.iq')
    $files += $devices | ForEach-Object { "fta-monitor-garmin-watchapp-$_.prg" }
    $files += Get-ChildItem -LiteralPath $OutputDirectory -File -Filter 'fta-monitor-garmin-watchapp-*.prg' |
        Where-Object { $_.Name -cmatch '^fta-monitor-garmin-watchapp-[a-zA-Z0-9_]+\.prg$' } |
        ForEach-Object { $_.Name }
    foreach ($name in @($files | Select-Object -Unique) + @('build-info.json', 'SHA256SUMS')) {
        $path = Join-Path $OutputDirectory $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
        }
    }
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

$deviceParts = @{}
if ($release -and $Target -ne 'Android') {
    function Read-ApiVersion([string] $Value, [string] $Description) {
        [version] $parsed = $null
        if (-not [version]::TryParse($Value, [ref] $parsed)) {
            throw "Invalid Connect IQ API version for ${Description}: '$Value'."
        }
        $build = [Math]::Max(0, $parsed.Build)
        $revision = [Math]::Max(0, $parsed.Revision)
        [version]::new($parsed.Major, $parsed.Minor, $build, $revision)
    }

    $minimumApi = Read-ApiVersion $application.GetAttribute('minSdkVersion') 'watch manifest'
    $languages = @($application.SelectNodes('iq:languages/iq:language', $namespaces) |
        ForEach-Object { $_.InnerText.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    # Connect IQ exports default to English when no languages are declared.
    if ($languages.Count -eq 0) { $languages = @('eng') }
    $languageSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($language in $languages) { $null = $languageSet.Add($language) }
    foreach ($device in $devices) {
        $definition = Join-Path $env:APPDATA "Garmin\ConnectIQ\Devices\$device\compiler.json"
        $deviceInfo = Get-Content -LiteralPath $definition -Raw | ConvertFrom-Json -AsHashtable
        $eligible = @()
        foreach ($part in $deviceInfo.partNumbers) {
            $partVersion = Read-ApiVersion $part.connectIQVersion "$device $($part.number)"
            $supportedLanguages = @($part.languages | Where-Object { $languageSet.Contains([string] $_.code) })
            if ($partVersion -ge $minimumApi -and $supportedLanguages.Count -gt 0) {
                $eligible += $part.number
            }
        }
        if ($eligible.Count -eq 0) { throw "No eligible Connect IQ product variants were found for $device." }
        $deviceParts[$device] = $eligible
    }
}

if ($Target -ne 'Watch') {
    if ($release) {
        & $gradle -p $companion '--no-daemon' '-PftaReleaseSigning=true' ':app:assembleRelease' ':app:bundleRelease' ':app:lintRelease'
    } else {
        & $gradle -p $companion ':app:assembleDebug' ':app:lintDebug'
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Android build failed with exit code $LASTEXITCODE."
    }
    if ($release) {
        Copy-Item -LiteralPath (Join-Path $companion 'app\build\outputs\apk\release\app-release.apk') `
            -Destination (Join-Path $OutputDirectory 'fta-garmin-companion.apk')
        Copy-Item -LiteralPath (Join-Path $companion 'app\build\outputs\bundle\release\app-release.aab') `
            -Destination (Join-Path $OutputDirectory 'app-release.aab')
    }
}

if ($Target -ne 'Android') {
    $watchOutput = if ($release) { Join-Path $watch 'bin\release' } else { Join-Path $watch 'bin' }
    New-Item -ItemType Directory -Path $watchOutput -Force | Out-Null
    foreach ($device in $devices) {
        $output = Join-Path $watchOutput "fta-monitor-garmin-watchapp-$device.prg"
        $arguments = @('-f', $jungle, '-o', $output, '-y', $GarminDeveloperKey, '-d', $device, '-w')
        if ($release) { $arguments += '-r' }
        & $compiler @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Watch build failed for $device with exit code $LASTEXITCODE."
        }
        if ($release) {
            Copy-Item -LiteralPath $output -Destination (Join-Path $OutputDirectory ([IO.Path]::GetFileName($output)))
        }
    }
    if ($release) {
        $iq = Join-Path $watchOutput 'fta-monitor-garmin-watchapp.iq'
        & $compiler -f $jungle -o $iq -y $GarminDeveloperKey -e -r -w
        if ($LASTEXITCODE -ne 0) { throw "Watch IQ export failed with exit code $LASTEXITCODE." }
        Copy-Item -LiteralPath $iq -Destination (Join-Path $OutputDirectory 'fta-monitor-garmin-watchapp.iq')
    }
}

if ($release) {
    $commit = (& git -C $PSScriptRoot rev-parse HEAD | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to determine the build source commit.' }
    if ($Official -and $commit -ne $env:GITHUB_SHA) {
        throw 'The checked-out source commit differs from the official workflow commit.'
    }
    $javaOutput = (& java -version 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $javaOutput -notmatch 'version\s+"([^"]+)"') {
        throw 'Unable to determine the Java version.'
    }
    $javaVersion = $Matches[1]
    $wrapper = Get-Content -LiteralPath (Join-Path $companion 'gradle\wrapper\gradle-wrapper.properties') -Raw
    if ($wrapper -notmatch 'gradle-([0-9]+(?:\.[0-9]+)+)-bin\.zip') {
        throw 'Unable to determine the Gradle wrapper version.'
    }
    $gradleVersion = $Matches[1]
    $sdkVersion = $null
    $garminFingerprint = $null
    if ($Target -ne 'Android') {
        $sdkVersion = (& $compiler -v | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Unable to determine the Connect IQ compiler version.' }
        $rsa = [Security.Cryptography.RSA]::Create()
        $keyBytes = [IO.File]::ReadAllBytes($GarminDeveloperKey)
        try {
            $bytesRead = 0
            $rsa.ImportPkcs8PrivateKey($keyBytes, [ref] $bytesRead)
            if ($bytesRead -ne $keyBytes.Length -or $rsa.KeySize -ne 4096) {
                throw 'The Garmin signing key must be a PKCS8 RSA 4096-bit private key.'
            }
            $garminFingerprint = [Convert]::ToHexString(
                [Security.Cryptography.SHA256]::HashData($rsa.ExportSubjectPublicKeyInfo()))
        } finally {
            [Array]::Clear($keyBytes, 0, $keyBytes.Length)
            $rsa.Dispose()
        }
    }
    $info = [ordered]@{
        schemaVersion = 1
        official = $Official.IsPresent
        configuration = 'Release'
        repository = if ($Official) { $env:GITHUB_REPOSITORY } else { $null }
        workflow = if ($Official) { '.github/workflows/build.yml' } else { $null }
        commit = $commit
        runId = if ($Official) { $env:GITHUB_RUN_ID } else { $null }
        runAttempt = if ($Official) { [int] $env:GITHUB_RUN_ATTEMPT } else { $null }
        targets = @($targets)
        tools = @{ java = $javaVersion; gradle = $gradleVersion }
        android = [ordered]@{
            applicationId = Read-AndroidSetting 'applicationId' '"([^"]+)"'
            versionName = $androidVersion
            versionCode = [int] (Read-AndroidSetting 'versionCode' '([0-9]+)')
            compileSdk = [int] (Read-AndroidSetting 'compileSdk' '([0-9]+)')
        }
        watch = [ordered]@{
            applicationId = $application.GetAttribute('id')
            version = $watchVersion
            devices = @($devices)
            deviceParts = $deviceParts
            compiler = $sdkVersion
        }
        signers = @{ android = $null; garmin = $garminFingerprint }
        files = @()
    }
    $info | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'build-info.json') -Encoding utf8NoBOM
    & (Join-Path $PSScriptRoot 'scripts\official-artifacts.ps1') -Mode Prepare -Path $OutputDirectory
}
