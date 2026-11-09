[CmdletBinding()]
param(
    [ValidateSet('Prepare', 'Verify')]
    [string] $Mode = 'Verify',
    [Parameter(Mandatory)]
    [string] $Path,
    [string] $AndroidCertificate = $env:ANDROID_RELEASE_CERT_SHA256,
    [string] $GarminPublicKey = $env:CIQ_RELEASE_PUBLIC_KEY_SHA256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Normalize-Fingerprint([string] $Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { throw 'Expected a SHA-256 signing fingerprint.' }
    $normalized = $Value.Replace(':', '').Replace(' ', '').ToUpperInvariant()
    if ($normalized -notmatch '^[A-F0-9]{64}$') { throw 'Expected a SHA-256 signing fingerprint.' }
    $normalized
}

function Find-AndroidTool([string] $Name) {
    $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
    if ([string]::IsNullOrWhiteSpace($sdk)) { throw 'Set ANDROID_HOME or ANDROID_SDK_ROOT for signature verification.' }
    $tools = Join-Path $sdk 'build-tools'
    $versions = @(Get-ChildItem -LiteralPath $tools -Directory |
        Where-Object { $_.Name -match '^[0-9]+\.[0-9]+\.[0-9]+$' } |
        Sort-Object { [version] $_.Name } -Descending)
    foreach ($directory in $versions) {
        $tool = Join-Path $directory.FullName $Name
        if (Test-Path -LiteralPath $tool -PathType Leaf) { return $tool }
    }
    throw "Android build tool was not found: $Name"
}

$Path = [IO.Path]::GetFullPath($Path)
$metadataPath = Join-Path $Path 'build-info.json'
$info = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json -AsHashtable
if ($info.schemaVersion -ne 1 -or $info.configuration -ne 'Release' -or
    $info.official -isnot [bool] -or $info.commit -notmatch '^[a-f0-9]{40}$' -or
    $info.android.versionName -ne $info.watch.version -or
    $info.android.versionName -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:[A-Za-z0-9.+-]*)?$' -or
    ($info.android.versionCode -isnot [long] -and $info.android.versionCode -isnot [int]) -or
    $info.android.versionCode -lt 1 -or
    $info.android.applicationId -notmatch '^[a-zA-Z0-9_.]+$' -or
    $info.watch.applicationId -notmatch '^[a-fA-F0-9]{32}$') {
    throw 'Release metadata has invalid identity, version, or build fields.'
}
$targets = @($info.targets)
$devices = @($info.watch.devices)
if ($targets.Count -eq 0 -or @($targets | Select-Object -Unique).Count -ne $targets.Count -or
    @($targets | Where-Object { $_ -notin @('Android', 'Watch') }).Count -ne 0 -or
    $devices.Count -eq 0 -or @($devices | Select-Object -Unique).Count -ne $devices.Count -or
    @($devices | Where-Object { $_ -notmatch '^[a-zA-Z0-9_]+$' }).Count -ne 0) {
    throw 'Release metadata has invalid targets or devices.'
}
if ($info.official -and ($targets.Count -ne 2 -or $info.repository -notmatch '^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$' -or
    $info.workflow -ne '.github/workflows/build.yml' -or $info.runId -notmatch '^[1-9][0-9]*$' -or
    $info.runAttempt -lt 1)) {
    throw 'Official candidate provenance is incomplete.'
}

$expected = @()
if ('Android' -in $targets) { $expected += 'fta-garmin-companion.apk', 'app-release.aab' }
if ('Watch' -in $targets) {
    $expected += $devices | ForEach-Object { "fta-monitor-garmin-watchapp-$_.prg" }
    $expected += 'fta-monitor-garmin-watchapp.iq'
}
foreach ($name in $expected) {
    $file = Get-Item -LiteralPath (Join-Path $Path $name)
    if ($file.PSIsContainer -or $file.Length -eq 0 -or $file.LinkType) { throw "Invalid release file: $name" }
}

if ($Mode -eq 'Prepare') {
    if ($info.official -and (
        [string]::IsNullOrWhiteSpace($AndroidCertificate) -or [string]::IsNullOrWhiteSpace($GarminPublicKey))) {
        throw 'Official artifacts require expected Android and Garmin signing fingerprints.'
    }
    if ('Android' -in $targets) {
        $apk = Join-Path $Path 'fta-garmin-companion.apk'
        $verification = (& (Find-AndroidTool 'apksigner.bat') verify --verbose --print-certs $apk 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { throw 'Release APK signature verification failed.' }
        $certificates = [regex]::Matches($verification, 'Signer #[0-9]+ certificate SHA-256 digest: ([a-fA-F0-9]+)')
        if ($certificates.Count -ne 1) { throw 'Expected exactly one APK signing certificate.' }
        $fingerprint = Normalize-Fingerprint $certificates[0].Groups[1].Value
        if ($AndroidCertificate -and $fingerprint -ne (Normalize-Fingerprint $AndroidCertificate)) {
            throw 'The APK signing certificate differs from the expected release certificate.'
        }
        $badging = (& (Find-AndroidTool 'aapt2.exe') dump badging $apk 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the release APK identity.' }
        $package = [regex]::Match($badging, "package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'")
        if (-not $package.Success -or $package.Groups[1].Value -ne $info.android.applicationId -or
            $package.Groups[2].Value -ne [string] $info.android.versionCode -or
            $package.Groups[3].Value -ne $info.android.versionName -or $badging -match 'application-debuggable') {
            throw 'APK identity/version differs from release metadata, or the APK is debuggable.'
        }
        $aab = Join-Path $Path 'app-release.aab'
        $bundleVerification = (& jarsigner '-J-Duser.language=en' '-J-Duser.country=US' -verify -verbose -certs $aab 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0 -or $bundleVerification -notmatch 'jar verified\.' -or
            $bundleVerification -match 'unsigned entries|jar is unsigned') {
            throw 'Release AAB has an invalid signature or unsigned content.'
        }
        $bundleCertificate = (& keytool '-J-Duser.language=en' '-J-Duser.country=US' -printcert -jarfile $aab 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the AAB signing certificate.' }
        $bundleFingerprint = [regex]::Match($bundleCertificate, 'SHA256:\s*([a-fA-F0-9:]+)')
        if (-not $bundleFingerprint.Success -or
            (Normalize-Fingerprint $bundleFingerprint.Groups[1].Value) -ne $fingerprint) {
            throw 'The AAB and APK signing certificates differ.'
        }
        $info.signers.android = $fingerprint
    }
    if ('Watch' -in $targets) {
        $fingerprint = Normalize-Fingerprint $info.signers.garmin
        if ($GarminPublicKey -and $fingerprint -ne (Normalize-Fingerprint $GarminPublicKey)) {
            throw 'The Garmin signing identity differs from the expected production key.'
        }
        $iq = Join-Path $Path 'fta-monitor-garmin-watchapp.iq'
        $entries = @(& tar.exe -tf $iq)
        if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the IQ archive.' }
        foreach ($name in @('manifest.xml', 'manifest.sig2', 'dev_key.pub')) {
            if (@($entries | Where-Object { [string]::Equals($_, $name, [StringComparison]::Ordinal) }).Count -ne 1) {
                throw "The IQ archive has a missing or duplicate $name."
            }
        }
        $temporary = Join-Path ([IO.Path]::GetTempPath()) ('fta-iq-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $temporary | Out-Null
        $rsa = [Security.Cryptography.RSA]::Create()
        try {
            & tar.exe -xf $iq -C $temporary manifest.xml manifest.sig2 dev_key.pub
            if ($LASTEXITCODE -ne 0) { throw 'Unable to read the IQ signing manifest.' }
            foreach ($name in @('manifest.xml', 'manifest.sig2', 'dev_key.pub')) {
                if ((Get-Item -LiteralPath (Join-Path $temporary $name)).LinkType) {
                    throw 'IQ signing files must not be links.'
                }
            }
            $read = 0
            $rsa.ImportSubjectPublicKeyInfo([IO.File]::ReadAllBytes((Join-Path $temporary 'dev_key.pub')), [ref] $read)
            $iqFingerprint = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($rsa.ExportSubjectPublicKeyInfo()))
            if ($iqFingerprint -ne $fingerprint -or -not $rsa.VerifyData(
                    [IO.File]::ReadAllBytes((Join-Path $temporary 'manifest.xml')),
                    [IO.File]::ReadAllBytes((Join-Path $temporary 'manifest.sig2')),
                    [Security.Cryptography.HashAlgorithmName]::SHA256,
                    [Security.Cryptography.RSASignaturePadding]::Pkcs1)) {
                throw 'The IQ manifest signature or signing identity is invalid.'
            }
            $exported = [Xml.XmlDocument]::new()
            $exported.XmlResolver = $null
            $exported.Load((Join-Path $temporary 'manifest.xml'))
            $namespace = [Xml.XmlNamespaceManager]::new($exported.NameTable)
            $namespace.AddNamespace('iq', 'http://www.garmin.com/xml/connectiq')
            $app = $exported.SelectSingleNode('/iq:manifest/iq:application', $namespace)
            if ($null -eq $app -or $app.GetAttribute('id') -ne $info.watch.applicationId -or
                $app.GetAttribute('version') -ne $info.watch.version) {
                throw 'The IQ application identity or version differs from release metadata.'
            }
            $products = @($app.SelectNodes('iq:products/iq:product', $namespace))
            $expectedParts = @()
            foreach ($device in $devices) {
                $parts = @($info.watch.deviceParts[$device])
                if ($parts.Count -eq 0) { throw "Missing SDK product definitions for $device." }
                foreach ($part in $parts) {
                    if ($part -notmatch '^[0-9]{3}-[A-Z][0-9]{4}-[0-9]{2}$') { throw 'Invalid SDK product part number.' }
                    $expectedParts += $part
                    $product = @($products | Where-Object {
                        [string]::Equals($_.GetAttribute('partNumber'), $part, [StringComparison]::Ordinal)
                    })
                    if ($product.Count -ne 1 -or $product[0].GetAttribute('filename') -notmatch "^$part/[a-zA-Z0-9_.-]+[.]prg$" -or
                        @($entries | Where-Object {
                            [string]::Equals($_, $product[0].GetAttribute('filename'), [StringComparison]::Ordinal)
                        }).Count -ne 1) {
                        throw "The IQ export is missing or has ambiguous executables for $device ($part)."
                    }
                }
            }
            $actualParts = @($products | ForEach-Object { $_.GetAttribute('partNumber') })
            $partSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($part in $expectedParts) { $null = $partSet.Add($part) }
            if ($actualParts.Count -ne $partSet.Count -or
                @($actualParts | Where-Object { -not $partSet.Contains($_) }).Count -ne 0) {
                throw 'The IQ export contains unexpected or missing device products.'
            }
        } finally {
            $rsa.Dispose()
            foreach ($name in @('manifest.xml', 'manifest.sig2', 'dev_key.pub')) {
                $file = Join-Path $temporary $name
                if (Test-Path -LiteralPath $file -PathType Leaf) { Remove-Item -LiteralPath $file -Force }
            }
            Remove-Item -LiteralPath $temporary -Force
        }
    }
    $info.files = @($expected | ForEach-Object {
        @{ name = $_; sha256 = (Get-FileHash -LiteralPath (Join-Path $Path $_) -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    $info | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding utf8NoBOM
    $checksums = @($info.files | ForEach-Object { "$($_.sha256)  $($_.name)" })
    $checksums += "$((Get-FileHash -LiteralPath $metadataPath -Algorithm SHA256).Hash.ToLowerInvariant())  build-info.json"
    $checksums | Set-Content -LiteralPath (Join-Path $Path 'SHA256SUMS') -Encoding utf8NoBOM
}

$actualNames = @(Get-ChildItem -LiteralPath $Path -Force | ForEach-Object {
    if ($_.PSIsContainer -or $_.LinkType) { throw "Unexpected release directory or link: $($_.Name)" }
    $_.Name
})
$allowed = @($expected) + @('build-info.json', 'SHA256SUMS')
$allowedSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($name in $allowed) {
    if (-not $allowedSet.Add($name)) { throw "Duplicate expected release filename: $name" }
}
if ($actualNames.Count -ne $allowed.Count -or
    @($actualNames | Where-Object { -not $allowedSet.Contains($_) }).Count -ne 0) {
    throw 'The candidate contains missing or unexpected files.'
}
if (@($info.files).Count -ne $expected.Count) { throw 'Release metadata has an incomplete artifact list.' }
foreach ($name in $expected) {
    $records = @($info.files | Where-Object { [string]::Equals($_.name, $name, [StringComparison]::Ordinal) })
    if ($records.Count -ne 1 -or $records[0].sha256 -notmatch '^[a-f0-9]{64}$' -or
        (Get-FileHash -LiteralPath (Join-Path $Path $name) -Algorithm SHA256).Hash -ne $records[0].sha256) {
        throw "Artifact metadata checksum mismatch: $name"
    }
}
$lines = @(Get-Content -LiteralPath (Join-Path $Path 'SHA256SUMS'))
if ($lines.Count -ne $expected.Count + 1) { throw 'The checksum manifest has an invalid file count.' }
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($line in $lines) {
    $match = [regex]::Match($line, '^([a-f0-9]{64})  ([a-zA-Z0-9_.-]+)$')
    if (-not $match.Success) { throw 'The checksum manifest has an invalid entry.' }
    $name = $match.Groups[2].Value
    if (-not $allowedSet.Contains($name) -or $name -ceq 'SHA256SUMS' -or -not $seen.Add($name)) {
        throw 'The checksum manifest has an unexpected or duplicate filename.'
    }
    if ((Get-FileHash -LiteralPath (Join-Path $Path $name) -Algorithm SHA256).Hash -ne $match.Groups[1].Value) {
        throw "Checksum mismatch: $name"
    }
}
if ('Android' -in $targets) { $null = Normalize-Fingerprint $info.signers.android }
if ('Watch' -in $targets) { $null = Normalize-Fingerprint $info.signers.garmin }
Write-Host "Verified $($expected.Count) release binaries and their provenance."
