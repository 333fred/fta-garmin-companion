[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($name in @('RUNNER_TEMP', 'GITHUB_WORKSPACE', 'GITHUB_ENV', 'GARMIN_USERNAME',
                     'GARMIN_PASSWORD', 'GARMIN_AGREEMENT_HASH')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
        throw "Garmin CI configuration is missing: $name"
    }
}
$archive = Join-Path $env:RUNNER_TEMP 'connect-iq-sdk-manager.tar.gz'
$url = 'https://github.com/lindell/connect-iq-sdk-manager-cli/releases/download/v0.8.4/connect-iq-sdk-manager-cli_0.8.4_Windows_x86_64.tar.gz'
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
    Invoke-WebRequest -Uri $url -OutFile $archive
}
$expected = '989cb7e037330213ada7d77a977adac7dc05468465998c503684e2abc9f790bf'
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expected) {
    throw 'Connect IQ SDK manager checksum mismatch.'
}
& tar.exe -xzf $archive -C $env:RUNNER_TEMP
if ($LASTEXITCODE -ne 0) { throw 'SDK manager extraction failed.' }
$manager = Join-Path $env:RUNNER_TEMP 'connect-iq-sdk-manager.exe'
& $manager agreement accept --agreement-hash $env:GARMIN_AGREEMENT_HASH --log-level error
if ($LASTEXITCODE -ne 0) { throw 'Connect IQ agreement acceptance failed.' }
& $manager login --log-level error
if ($LASTEXITCODE -ne 0) { throw 'Garmin CI login failed.' }
& $manager sdk set '=9.3.0' --log-level error
if ($LASTEXITCODE -ne 0) { throw 'Connect IQ SDK installation failed.' }
& $manager device download --manifest (Join-Path $env:GITHUB_WORKSPACE 'watch\manifest.xml') --log-level error
if ($LASTEXITCODE -ne 0) { throw 'Connect IQ device installation failed.' }
$sdk = (& $manager sdk current-path --log-level error | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $sdk 'bin\monkeyc.bat') -PathType Leaf)) {
    throw 'Installed Connect IQ compiler was not found.'
}
"GARMIN_SDK=$sdk" | Out-File -LiteralPath $env:GITHUB_ENV -Encoding utf8 -Append
