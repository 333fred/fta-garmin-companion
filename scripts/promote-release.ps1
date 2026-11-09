[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[1-9][0-9]*$')]
    [string] $RunId,
    [Parameter(Mandatory)]
    [ValidateRange(1, 2147483647)]
    [int] $RunAttempt,
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string] $Commit,
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string] $Repository = $env:GITHUB_REPOSITORY,
    [string] $Path,
    [string] $ReleaseTitle = $env:RELEASE_TITLE,
    [string] $ReleaseNotes = $env:RELEASE_NOTES,
    [switch] $Publish
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'github-api.ps1')

function Read-GitHub([string] $Endpoint) {
    return ,(Invoke-GitHubApi $Endpoint)
}

function Get-TagCommit {
    Get-GitHubTagCommit $Repository $Tag
}

function Assert-TagCommit([string] $ExpectedCommit) {
    if ((Get-TagCommit) -ne $ExpectedCommit) {
        throw 'The release tag must point to the selected candidate commit.'
    }
}

function Ensure-Tag([string] $ExpectedCommit) {
    $existing = Get-TagCommit
    if ($null -eq $existing) {
        $null = Invoke-GitHubApi "repos/$Repository/git/refs" -Method POST -Body @{
            ref = "refs/tags/$Tag"
            sha = $ExpectedCommit
        }
    } elseif ($existing -ne $ExpectedCommit) {
        throw 'The existing release tag points to a different commit.'
    }
    Assert-TagCommit $ExpectedCommit
}

function Write-ReleaseOutput {
    if ($env:GITHUB_OUTPUT) {
        "version=$($info.android.versionName)" | Out-File -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8 -Append
        "version-code=$($info.android.versionCode)" | Out-File -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8 -Append
        "tag=$Tag" | Out-File -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8 -Append
    }
}

function Find-Release {
    $found = $null
    $page = 1
    do {
        $releases = Read-GitHub "repos/$Repository/releases?per_page=100&page=$page"
        $matching = @($releases | Where-Object { Test-ExactString $_.tag_name $Tag })
        if ($matching.Count -gt 1 -or ($matching.Count -eq 1 -and $null -ne $found)) {
            throw 'There are ambiguous releases for the selected tag.'
        }
        if ($matching.Count -eq 1) { $found = $matching[0] }
        $page++
    } while ($releases.Count -eq 100)
    return $found
}

function Assert-CompatibleRelease($Release) {
    if ($Release.prerelease -or -not (Test-ExactString $Release.name $ReleaseTitle) -or
        -not (Test-ExactString $Release.body $ReleaseNotes)) {
        throw 'The tag already has a conflicting release.'
    }
}

if ([string]::IsNullOrWhiteSpace($Repository)) { throw 'Specify the candidate repository.' }
if ($Publish -and ($env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or
    -not (Test-ExactString $env:GITHUB_REF 'refs/heads/main') -or $Repository -ne $env:GITHUB_REPOSITORY)) {
    throw 'Publication requires the manually dispatched main-branch release workflow.'
}
$Commit = $Commit.ToLowerInvariant()
$run = Read-GitHub "repos/$Repository/actions/runs/$RunId/attempts/$RunAttempt"
$workflow = Read-GitHub "repos/$Repository/actions/workflows/build.yml"
if ($run.id -ne [long] $RunId -or $run.run_attempt -ne $RunAttempt -or
    $run.workflow_id -ne $workflow.id -or $run.event -ne 'push' -or -not (Test-ExactString $run.head_branch 'main') -or
    $run.head_repository.full_name -ne $Repository -or $run.repository.full_name -ne $Repository -or
    $run.status -ne 'completed' -or $run.conclusion -ne 'success' -or $run.head_sha -ne $Commit) {
    throw 'Select a successful main-push attempt of this repository''s Build workflow.'
}
$artifactName = "official-$RunId-$RunAttempt-$($run.head_sha)"
$artifacts = @()
$page = 1
do {
    $result = Read-GitHub "repos/$Repository/actions/runs/$RunId/artifacts?per_page=100&page=$page"
    $artifacts += @($result.artifacts | Where-Object { Test-ExactString $_.name $artifactName })
    $page++
} while (@($result.artifacts).Count -eq 100)
if ($artifacts.Count -ne 1 -or $artifacts[0].expired -or $artifacts[0].size_in_bytes -le 0) {
    throw 'The exact official candidate is missing, ambiguous, or expired.'
}
if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Specify the downloaded candidate directory.' }
$Path = [IO.Path]::GetFullPath($Path)
& (Join-Path $PSScriptRoot 'official-artifacts.ps1') -Mode Verify -Path $Path
$info = Get-Content -LiteralPath (Join-Path $Path 'build-info.json') -Raw | ConvertFrom-Json -AsHashtable
if (-not $info.official -or $info.repository -ne $Repository -or $info.workflow -ne '.github/workflows/build.yml' -or
    $info.commit -ne $Commit -or $info.runId -ne $RunId -or $info.runAttempt -ne $RunAttempt) {
    throw 'The candidate provenance does not match the requested commit and build.'
}
$Tag = "v$($info.android.versionName)"
if ($Tag -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+$') {
    throw 'Release promotion requires a three-part numeric application version.'
}
if (-not $Publish) {
    Write-Host "Validated $Tag from $artifactName; no tag or release was written."
    return
}
if ([string]::IsNullOrWhiteSpace($ReleaseTitle) -or [string]::IsNullOrWhiteSpace($ReleaseNotes)) {
    throw 'Publication requires the exact owner-reviewed release title and notes.'
}

$release = Find-Release
if ($null -ne $release) { Assert-CompatibleRelease $release }
$names = @($info.files | ForEach-Object { $_.name }) + @('build-info.json', 'SHA256SUMS')
$hashes = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
foreach ($name in $names) {
    $hashes[$name] = (Get-FileHash -LiteralPath (Join-Path $Path $name) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('fta-promotion-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null

function Read-Assets([long] $ReleaseId) {
    $assets = @()
    $page = 1
    do {
        $result = Read-GitHub "repos/$Repository/releases/$ReleaseId/assets?per_page=100&page=$page"
        $assets += $result
        $page++
    } while ($result.Count -eq 100)
    return ,$assets
}

function Assert-Assets($Assets) {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($asset in $Assets) {
        $name = $asset.name
        if (-not $hashes.ContainsKey($name) -or -not $seen.Add($name) -or -not (Test-ExactString $asset.state 'uploaded') -or
            $asset.size -ne (Get-Item -LiteralPath (Join-Path $Path $name)).Length) {
            throw "Unexpected, duplicate, or incomplete release asset: $name"
        }
        if ($asset.digest) {
            if ($asset.digest -ne "sha256:$($hashes[$name])") { throw "Uploaded asset checksum mismatch: $name" }
        } else {
            & gh release download $Tag --repo $Repository --pattern $name --dir $temporary --clobber
            if ($LASTEXITCODE -ne 0) { throw "Unable to verify uploaded asset: $name" }
            if ((Get-FileHash -LiteralPath (Join-Path $temporary $name) -Algorithm SHA256).Hash -ne $hashes[$name]) {
                throw "Downloaded release asset checksum mismatch: $name"
            }
        }
    }
}

function Remove-StarterAssets($Release, $Assets) {
    $starters = @($Assets | Where-Object { Test-ExactString $_.state 'starter' })
    if ($starters.Count -eq 0) { return ,@($Assets) }
    if (-not $Release.draft) { throw 'A published release contains incomplete assets.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($asset in $Assets) {
        if (-not $hashes.ContainsKey($asset.name) -or -not $seen.Add($asset.name)) {
            throw "Unexpected or duplicate release asset: $($asset.name)"
        }
        if ((Test-ExactString $asset.state 'starter') -and ($asset.size -ne 0 -or [string] $asset.id -notmatch '^[1-9][0-9]*$')) {
            throw "Invalid starter release asset: $($asset.name)"
        }
    }
    $uploaded = @($Assets | Where-Object { -not (Test-ExactString $_.state 'starter') })
    Assert-Assets $uploaded
    if ($uploaded.Count -ne 0 -and @($uploaded | Where-Object { Test-ExactString $_.name 'build-info.json' }).Count -ne 1) {
        throw 'A nonempty draft must contain the matching build-info.json before it can be resumed.'
    }
    foreach ($asset in $starters) {
        $current = Read-GitHub "repos/$Repository/releases/$($Release.id)"
        if (-not $current.draft -or -not (Test-ExactString $current.tag_name $Tag)) {
            throw 'The release draft changed before starter asset cleanup.'
        }
        Assert-CompatibleRelease $current
        Assert-TagCommit $Commit
        $currentAsset = Read-GitHub "repos/$Repository/releases/assets/$($asset.id)"
        if ($currentAsset.id -ne $asset.id -or -not (Test-ExactString $currentAsset.name $asset.name) -or
            -not (Test-ExactString $currentAsset.state 'starter') -or $currentAsset.size -ne 0) {
            throw "The starter asset changed before cleanup: $($asset.name)"
        }
        $null = Invoke-GitHubApi "repos/$Repository/releases/assets/$($asset.id)" -Method DELETE
    }
    $remaining = Read-Assets $Release.id
    return ,$remaining
}

function Assert-PublishedRelease([long] $ReleaseId) {
    $published = Read-GitHub "repos/$Repository/releases/$ReleaseId"
    if ($published.draft -or $published.prerelease -or
        -not (Test-ExactString $published.name $ReleaseTitle) -or
        -not (Test-ExactString $published.body $ReleaseNotes) -or
        -not (Test-ExactString $published.tag_name $Tag)) {
        throw 'The published release did not retain the approved release state or text.'
    }
    Assert-TagCommit $Commit
    $publishedAssets = Read-Assets $ReleaseId
    Assert-Assets $publishedAssets
    if ($publishedAssets.Count -ne $names.Count) {
        throw 'The published release has an incomplete asset set.'
    }
}

try {
    Ensure-Tag $Commit
    if ($null -eq $release) {
        Assert-TagCommit $run.head_sha
        $release = Invoke-GitHubApi "repos/$Repository/releases" -Method POST -Body @{
            tag_name = $Tag
            name = $ReleaseTitle
            body = $ReleaseNotes
            draft = $true
            prerelease = $false
        }
        if ($null -eq $release -or -not $release.draft -or
            -not (Test-ExactString $release.tag_name $Tag) -or [string] $release.id -notmatch '^[1-9][0-9]*$') {
            throw 'The created release draft did not match the requested tag.'
        }
        Assert-CompatibleRelease $release
    }
    $assets = Read-Assets $release.id
    $assets = Remove-StarterAssets $release $assets
    Assert-Assets $assets
    if ((-not $release.draft -or $assets.Count -ne 0) -and
        @($assets | Where-Object { Test-ExactString $_.name 'build-info.json' }).Count -ne 1) {
        throw 'A nonempty draft or published release must contain the matching build-info.json before it can be resumed.'
    }
    if (-not $release.draft) {
        Assert-PublishedRelease $release.id
        Write-ReleaseOutput
        Write-Host "Verified already-published $Tag from $artifactName; continuing without changing it."
        return
    }
    $orderedNames = @('build-info.json') + @($names | Where-Object { -not (Test-ExactString $_ 'build-info.json') })
    foreach ($name in $orderedNames) {
        if (@($assets | Where-Object { Test-ExactString $_.name $name }).Count -eq 0) {
            & gh release upload $Tag (Join-Path $Path $name) --repo $Repository
            if ($LASTEXITCODE -ne 0) { throw "Release upload failed for $name; the release remains a draft." }
        }
    }
    $assets = Read-Assets $release.id
    Assert-Assets $assets
    if ($assets.Count -ne $names.Count) { throw 'The release draft has an incomplete asset set.' }
    $current = Read-GitHub "repos/$Repository/releases/$($release.id)"
    if (-not $current.draft -or -not (Test-ExactString $current.name $ReleaseTitle) -or
        -not (Test-ExactString $current.body $ReleaseNotes) -or -not (Test-ExactString $current.tag_name $Tag)) {
        throw 'The release draft changed during promotion; publication was stopped.'
    }
    Assert-TagCommit $run.head_sha
    & gh release edit $Tag --repo $Repository --draft=false --prerelease=false
    if ($LASTEXITCODE -ne 0) { throw 'Final release publication failed.' }
    Assert-PublishedRelease $release.id
    Write-ReleaseOutput
    Write-Host "Published $Tag from $artifactName without rebuilding or re-signing."
} finally {
    foreach ($file in @(Get-ChildItem -LiteralPath $temporary -File)) { Remove-Item -LiteralPath $file.FullName -Force }
    Remove-Item -LiteralPath $temporary -Force
}
