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
