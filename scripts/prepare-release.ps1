[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string] $Commit,
    [Parameter(Mandatory)]
    [string] $Title,
    [string] $PreviousTag,
    [string] $Repository = $env:GITHUB_REPOSITORY,
    [Parameter(Mandatory, ParameterSetName = 'Preview')]
    [switch] $Preview,
    [Parameter(Mandatory, ParameterSetName = 'Approved')]
    [ValidatePattern('^[a-fA-F0-9]{64}$')]
    [string] $ApprovedPreviewHash
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'github-api.ps1')

if ([string]::IsNullOrWhiteSpace($Repository)) {
    $Repository = (& gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to determine the GitHub repository; specify -Repository.' }
}
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
    throw 'Specify a valid GitHub repository in owner/name form.'
}
if ([string]::IsNullOrWhiteSpace($Title) -or $Title -match '[\x00-\x1F\x7F]' -or
    -not (Test-ExactString $Title $Title.Trim())) {
    throw 'Specify a nonempty, single-line release title without surrounding whitespace.'
}
if ($PSBoundParameters.ContainsKey('PreviousTag') -and [string]::IsNullOrWhiteSpace($PreviousTag)) {
    throw 'Specify a nonempty previous tag or omit -PreviousTag.'
}
$Commit = $Commit.ToLowerInvariant()
$file = Invoke-GitHubApi "repos/$Repository/contents/companion/app/build.gradle.kts?ref=$Commit"
if ($file.type -ne 'file' -or $file.encoding -ne 'base64' -or [string]::IsNullOrWhiteSpace($file.content)) {
    throw 'Unable to read the Android version at the selected commit.'
}
$settings = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String($file.content))
$versions = [regex]::Matches($settings, '(?m)^[ \t]*versionName[ \t]*=[ \t]*"([^"]+)"[ \t]*\r?$')
if ($versions.Count -ne 1 -or $versions[0].Groups[1].Value -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
    throw 'The selected commit must have exactly one three-part Android versionName.'
}
$tag = "v$($versions[0].Groups[1].Value)"
$existing = Get-GitHubTagCommit $Repository $tag
if ($null -ne $existing -and -not (Test-ExactString $existing $Commit)) {
    throw 'The existing release tag points to a different commit.'
}
$request = @{ tag_name = $tag; target_commitish = $Commit }
if ($PSBoundParameters.ContainsKey('PreviousTag')) { $request.previous_tag_name = $PreviousTag }
$generated = Invoke-GitHubApi "repos/$Repository/releases/generate-notes" -Method POST -Body $request
if ([string]::IsNullOrWhiteSpace($generated.body) -or $generated.body -match '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]') {
    throw 'GitHub returned empty release notes or notes containing control characters.'
}

Write-Host "Repository: $Repository"
Write-Host "Commit: $Commit"
Write-Host "Tag: $tag"
Write-Host "Title: $Title"
Write-Host "`nGenerated release notes:`n"
Write-Host $generated.body
& (Join-Path $PSScriptRoot 'select-release-candidate.ps1') -Commit $Commit -Repository $Repository

$inputs = @{ commit = $Commit; title = $Title; notes = $generated.body }
$json = ConvertTo-Json -InputObject $inputs -Depth 4 -Compress
if ($json.Length -gt 65535) { throw 'Generated notes exceed the GitHub workflow input limit.' }
Write-Host "`nDispatching will publish this release and then open a version-bump PR."

$approvalData = [ordered]@{
    repository = $Repository
    commit = $Commit
    tag = $tag
    title = $Title
    notes = $generated.body
}
$approvalJson = ConvertTo-Json -InputObject $approvalData -Depth 4 -Compress
$previewHash = [Convert]::ToHexString(
    [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($approvalJson))
).ToLowerInvariant()

if ($PSCmdlet.ParameterSetName -eq 'Preview') {
    Write-Host "Preview SHA-256: $previewHash"
    Write-Host 'Release promotion was not dispatched.'
    return
}
if ($PSCmdlet.ParameterSetName -eq 'Approved') {
    if (-not (Test-ExactString $previewHash $ApprovedPreviewHash.ToLowerInvariant())) {
        throw 'Release details changed since the approved preview; review a new preview before dispatching.'
    }
} else {
    $approval = Read-Host 'Type PUBLISH to approve this exact title and text, or anything else to cancel'
    if (-not (Test-ExactString $approval 'PUBLISH')) {
        Write-Host 'Release promotion was not dispatched.'
        return
    }
}
$result = ($json | & gh workflow run 'release.yml' --repo $Repository --ref main --json 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw "Unable to dispatch release promotion.`n$result" }
Write-Host 'Release promotion was dispatched.'
if (-not [string]::IsNullOrWhiteSpace($result)) { Write-Host $result.Trim() }
