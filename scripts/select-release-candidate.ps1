[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string] $Commit,
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string] $Repository = $env:GITHUB_REPOSITORY
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'github-api.ps1')

if ([string]::IsNullOrWhiteSpace($Repository)) { throw 'Specify the candidate repository.' }
$Commit = $Commit.ToLowerInvariant()
$workflow = Invoke-GitHubApi "repos/$Repository/actions/workflows/build.yml"
$runs = @()
$page = 1
do {
    $result = Invoke-GitHubApi "repos/$Repository/actions/workflows/build.yml/runs?event=push&branch=main&head_sha=$Commit&per_page=100&page=$page"
    $runs += @($result.workflow_runs)
    $page++
} while (@($result.workflow_runs).Count -eq 100)

$candidates = @()
foreach ($run in $runs) {
    if ($run.workflow_id -ne $workflow.id -or $run.event -ne 'push' -or
        -not (Test-ExactString $run.head_branch 'main') -or $run.head_sha -ne $Commit -or
        $run.repository.full_name -ne $Repository -or $run.head_repository.full_name -ne $Repository) {
        throw 'GitHub returned a workflow run outside the requested main-branch commit.'
    }
    $artifacts = @()
    $page = 1
    do {
        $result = Invoke-GitHubApi "repos/$Repository/actions/runs/$($run.id)/artifacts?per_page=100&page=$page"
        $artifacts += @($result.artifacts)
        $page++
    } while (@($result.artifacts).Count -eq 100)
    for ($attempt = $run.run_attempt; $attempt -ge 1; $attempt--) {
        $name = "official-$($run.id)-$attempt-$Commit"
        $matching = @($artifacts | Where-Object { (Test-ExactString $_.name $name) -and -not $_.expired -and $_.size_in_bytes -gt 0 })
        if ($matching.Count -gt 1) { throw "Multiple official artifacts match $name." }
        if ($matching.Count -eq 0) { continue }
        $details = Invoke-GitHubApi "repos/$Repository/actions/runs/$($run.id)/attempts/$attempt"
        if ($details.id -ne $run.id -or $details.run_attempt -ne $attempt -or
            $details.workflow_id -ne $workflow.id -or $details.event -ne 'push' -or
            -not (Test-ExactString $details.head_branch 'main') -or $details.head_sha -ne $Commit -or
            $details.repository.full_name -ne $Repository -or $details.head_repository.full_name -ne $Repository) {
            throw 'The candidate attempt does not match the requested main-branch commit.'
        }
        if ($details.status -eq 'completed' -and $details.conclusion -eq 'success') {
            $candidates += [pscustomobject]@{
                RunId = [long] $run.id
                Attempt = $attempt
                ArtifactId = [long] $matching[0].id
                StartedAt = [DateTimeOffset]::Parse($details.run_started_at)
            }
        }
    }
}
$candidate = $candidates | Sort-Object StartedAt, RunId, Attempt -Descending | Select-Object -First 1
if ($null -eq $candidate) { throw "No successful main build with an available official artifact exists for $Commit." }
if ($env:GITHUB_OUTPUT) {
    "artifact-id=$($candidate.ArtifactId)" | Out-File -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8 -Append
    "run-id=$($candidate.RunId)" | Out-File -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8 -Append
    "run-attempt=$($candidate.Attempt)" | Out-File -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8 -Append
    "commit=$Commit" | Out-File -LiteralPath $env:GITHUB_OUTPUT -Encoding utf8 -Append
}
Write-Host "Selected official-$($candidate.RunId)-$($candidate.Attempt)-$Commit (artifact $($candidate.ArtifactId))."
