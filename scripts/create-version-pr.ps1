[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')]
    [string] $Version,
    [Parameter(Mandatory)]
    [ValidateRange(1, 2099999999)]
    [int] $VersionCode,
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string] $Repository = $env:GITHUB_REPOSITORY
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'github-api.ps1')

if ([string]::IsNullOrWhiteSpace($Repository) -or $Repository -ne $env:GITHUB_REPOSITORY -or
    $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or -not (Test-ExactString $env:GITHUB_REF 'refs/heads/main')) {
    throw 'The version PR requires the manually dispatched main-branch release workflow.'
}
$components = $Version.Split('.')
$patch = 0
if (-not [int]::TryParse($components[2], [ref] $patch) -or $patch -eq [int]::MaxValue) {
    throw 'The released patch version cannot be incremented.'
}
$nextVersion = "$($components[0]).$($components[1]).$($patch + 1)"
$nextCode = $VersionCode + 1
$tag = "v$Version"
$branch = "automation/version-after-$tag"
$title = "Bump version to $nextVersion"
$body = "Prepare the next version after releasing $Version."
$androidPath = 'companion/app/build.gradle.kts'
$watchPath = 'watch/manifest.xml'

function Read-File([string] $Commit, [string] $Path) {
    $file = Invoke-GitHubApi "repos/$Repository/contents/${Path}?ref=$Commit"
    if ($file.type -ne 'file' -or $file.encoding -ne 'base64' -or [string]::IsNullOrWhiteSpace($file.content)) {
        throw "Unable to read $Path at $Commit."
    }
    [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String($file.content))
}

function Get-Capture([string] $Text, [string] $Pattern, [string] $Name) {
    $matches = [regex]::Matches($Text, $Pattern)
    if ($matches.Count -ne 1) { throw "Expected exactly one $Name in the version files." }
    $matches[0].Groups[1].Value
}

function Replace-Capture([string] $Text, [string] $Pattern, [string] $Value) {
    $matches = [regex]::Matches($Text, $Pattern)
    if ($matches.Count -ne 1) { throw 'A version field changed while preparing the PR.' }
    $capture = $matches[0].Groups[1]
    $Text.Substring(0, $capture.Index) + $Value + $Text.Substring($capture.Index + $capture.Length)
}

function Get-VersionFiles([string] $Commit) {
    $android = Read-File $Commit $androidPath
    $watch = Read-File $Commit $watchPath
    $namePattern = '(?m)^[ \t]*versionName[ \t]*=[ \t]*"([^"]+)"[ \t]*\r?$'
    $codePattern = '(?m)^[ \t]*versionCode[ \t]*=[ \t]*([0-9]+)[ \t]*\r?$'
    $watchPattern = '(?s)<iq:application\b[^>]*\bversion="([^"]+)"'
    $androidVersion = Get-Capture $android $namePattern 'Android versionName'
    $androidCode = Get-Capture $android $codePattern 'Android versionCode'
    $watchVersion = Get-Capture $watch $watchPattern 'watch version'
    if (-not (Test-ExactString $androidVersion $Version) -or -not (Test-ExactString $watchVersion $Version) -or
        -not (Test-ExactString $androidCode ([string] $VersionCode))) {
        throw "The version on main differs from released $Version (Android versionCode $VersionCode); no version PR was created."
    }
    $updatedAndroid = Replace-Capture $android $namePattern $nextVersion
    $updatedAndroid = Replace-Capture $updatedAndroid $codePattern ([string] $nextCode)
    $updatedWatch = Replace-Capture $watch $watchPattern $nextVersion
    return @{ android = $updatedAndroid; watch = $updatedWatch }
}

function Get-MainCommit {
    $reference = Invoke-GitHubApi "repos/$Repository/git/ref/heads/main"
    if ($reference.object.type -ne 'commit' -or $reference.object.sha -notmatch '^[a-f0-9]{40}$') {
        throw 'Unable to determine the current main commit.'
    }
    $reference.object.sha
}

$mainCommit = Get-MainCommit
$updated = Get-VersionFiles $mainCommit
$references = Invoke-GitHubApi "repos/$Repository/git/matching-refs/heads/$branch"
$matching = @($references | Where-Object { Test-ExactString $_.ref "refs/heads/$branch" })
if ($matching.Count -gt 1) { throw 'The version PR branch is ambiguous.' }
if ($matching.Count -eq 0) {
    $base = Invoke-GitHubApi "repos/$Repository/git/commits/$mainCommit"
    $tree = Invoke-GitHubApi "repos/$Repository/git/trees" -Method POST -Body @{
        base_tree = $base.tree.sha
        tree = @(
            @{ path = $androidPath; mode = '100644'; type = 'blob'; content = $updated.android }
            @{ path = $watchPath; mode = '100644'; type = 'blob'; content = $updated.watch }
        )
    }
    $commit = Invoke-GitHubApi "repos/$Repository/git/commits" -Method POST -Body @{
        message = $title
        tree = $tree.sha
        parents = @($mainCommit)
    }
    $reference = Invoke-GitHubApi "repos/$Repository/git/refs" -Method POST -Body @{
        ref = "refs/heads/$branch"
        sha = $commit.sha
    }
    $branchCommit = $reference.object.sha
    if ($branchCommit -ne $commit.sha) { throw 'The created version branch points to an unexpected commit.' }
} else {
    $branchCommit = $matching[0].object.sha
    $commit = Invoke-GitHubApi "repos/$Repository/git/commits/$branchCommit"
    if (@($commit.parents).Count -ne 1) { throw 'The existing version branch has an unexpected history.' }
    $parent = $commit.parents[0].sha
    $ancestry = Invoke-GitHubApi "repos/$Repository/compare/$parent...$mainCommit"
    if ($ancestry.status -notin @('identical', 'ahead')) {
        throw 'The existing version branch is not based on the current main history.'
    }
    $change = Invoke-GitHubApi "repos/$Repository/compare/$parent...$branchCommit"
    $changedFiles = @($change.files | ForEach-Object { $_.filename })
    $expectedPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $null = $expectedPaths.Add($androidPath)
    $null = $expectedPaths.Add($watchPath)
    if ($change.ahead_by -ne 1 -or $change.behind_by -ne 0 -or $changedFiles.Count -ne 2 -or
        @($changedFiles | Where-Object { -not $expectedPaths.Contains($_) }).Count -ne 0 -or
        @($change.files | Where-Object { $_.status -ne 'modified' }).Count -ne 0) {
        throw 'The existing version branch contains unexpected changes.'
    }
    $expected = Get-VersionFiles $parent
    if (-not (Test-ExactString (Read-File $branchCommit $androidPath) $expected.android) -or
        -not (Test-ExactString (Read-File $branchCommit $watchPath) $expected.watch)) {
        throw 'The existing version branch does not contain the expected version bump.'
    }
}

$latestMain = Get-MainCommit
if ($latestMain -ne $mainCommit) { $null = Get-VersionFiles $latestMain }
$owner = $Repository.Split('/')[0]
$head = [Uri]::EscapeDataString("${owner}:$branch")
$pulls = Invoke-GitHubApi "repos/$Repository/pulls?state=open&head=$head&base=main&per_page=100"
$pulls = @($pulls)
if ($pulls.Count -gt 1) { throw 'Multiple version PRs already exist for the release.' }
if ($pulls.Count -eq 1) {
    if (-not (Test-ExactString $pulls[0].title $title) -or -not (Test-ExactString $pulls[0].body $body) -or
        $pulls[0].head.sha -ne $branchCommit -or -not (Test-ExactString $pulls[0].base.ref 'main')) {
        throw 'The existing version PR conflicts with the approved version bump.'
    }
    Write-Host "Version PR already exists: $($pulls[0].html_url)"
    return
}
$pull = Invoke-GitHubApi "repos/$Repository/pulls" -Method POST -Body @{
    title = $title
    body = $body
    head = $branch
    base = 'main'
}
Write-Host "Created version PR: $($pull.html_url)"
