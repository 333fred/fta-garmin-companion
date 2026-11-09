function Test-ExactString([string] $Left, [string] $Right) {
    [string]::Equals($Left, $Right, [StringComparison]::Ordinal)
}

function Invoke-GitHubApi {
    param(
        [Parameter(Mandatory)]
        [string] $Endpoint,
        [ValidateSet('GET', 'POST', 'DELETE')]
        [string] $Method = 'GET',
        $Body
    )

    if ($Method -eq 'GET') {
        $output = (& gh api $Endpoint 2>&1 | Out-String)
    } elseif ($Method -eq 'POST') {
        $json = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
        $output = ($json | & gh api --method POST $Endpoint --input - 2>&1 | Out-String)
    } else {
        $output = (& gh api --method DELETE $Endpoint 2>&1 | Out-String)
    }
    if ($LASTEXITCODE -ne 0) { throw "GitHub API $Method failed: $Endpoint`n$output" }
    if ($Method -eq 'DELETE') { return }
    return ,($output | ConvertFrom-Json -AsHashtable -NoEnumerate)
}

function Get-GitHubTagCommit([string] $Repository, [string] $Tag) {
    $references = Invoke-GitHubApi "repos/$Repository/git/matching-refs/tags/$Tag"
    $matches = @($references | Where-Object { Test-ExactString $_.ref "refs/tags/$Tag" })
    if ($matches.Count -eq 0) { return $null }
    if ($matches.Count -ne 1) { throw 'The release tag is ambiguous.' }
    $tagObject = $matches[0].object
    $seenTags = @{}
    while ($tagObject.type -eq 'tag') {
        if ($seenTags.ContainsKey($tagObject.sha)) { throw 'The release tag contains a reference cycle.' }
        $seenTags[$tagObject.sha] = $true
        $tagObject = (Invoke-GitHubApi "repos/$Repository/git/tags/$($tagObject.sha)").object
    }
    if ($tagObject.type -ne 'commit') { throw 'The release tag does not point to a commit.' }
    $tagObject.sha
}
