#Requires -Version 5.1

# Load .env file from parent directory if present
$envFile = Join-Path $PSScriptRoot '..' '.env'
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
        $parts = $_ -split '=', 2
        if ($parts.Count -eq 2) {
            [System.Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim(), 'Process')
        }
    }
}

$Key           = $env:SCHOOLOGY_KEY
$Secret        = $env:SCHOOLOGY_SECRET
$StudentRoleId = $env:STUDENT_ROLE_ID

if (-not $Key -or -not $Secret -or -not $StudentRoleId) {
    Write-Error 'Missing required environment variables: SCHOOLOGY_KEY, SCHOOLOGY_SECRET, STUDENT_ROLE_ID'
    exit 1
}

$CurrentYear = (Get-Date).Year
$TargetDate  = "$CurrentYear-01-01"
$BaseUrl     = 'https://api.schoology.com'

function Get-OAuthHeader {
    $nonce     = [System.Guid]::NewGuid().ToString('N')
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    return (
        'OAuth realm="Schoology API",' +
        "oauth_consumer_key=`"$Key`"," +
        'oauth_token="",' +
        "oauth_nonce=`"$nonce`"," +
        "oauth_timestamp=`"$timestamp`"," +
        'oauth_signature_method="PLAINTEXT",' +
        "oauth_signature=`"$Secret%26`"," +
        'oauth_version="1.0"'
    )
}

function Invoke-SchoologyRequest {
    param(
        [string]$Method,
        [string]$Path,
        [hashtable]$Body = $null
    )

    $url     = "$BaseUrl$Path"
    $headers = @{
        Authorization  = Get-OAuthHeader
        'Content-Type' = 'application/json'
        Accept         = 'application/json'
    }

    $params = @{
        Uri     = $url
        Method  = $Method
        Headers = $headers
    }

    if ($Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress)
    }

    Invoke-RestMethod @params
}

function Get-AllStudents {
    $students = [System.Collections.Generic.List[object]]::new()
    $start    = 0
    $limit    = 200

    do {
        $path = "/v1/users?role_ids=$StudentRoleId&limit=$limit&start=$start"
        $data = Invoke-SchoologyRequest -Method GET -Path $path

        $page = @($data.user)
        foreach ($user in $page) {
            $students.Add($user)
        }

        $total  = [int]$data.total
        $start += $page.Count

    } while ($page.Count -gt 0 -and $start -lt $total)

    return $students
}

function Split-Chunks {
    param([object[]]$Array, [int]$Size)
    for ($i = 0; $i -lt $Array.Count; $i += $Size) {
        , ($Array[$i..([Math]::Min($i + $Size - 1, $Array.Count - 1))])
    }
}

# Main
Write-Host 'Fetching students...'
$students = Get-AllStudents
Write-Host "Total students fetched: $($students.Count)"

$toUpdate = @($students | Where-Object { $_.birthday_date -ne $TargetDate })
$skipped  = $students.Count - $toUpdate.Count
Write-Host "Already correct: $skipped"
Write-Host "To update: $($toUpdate.Count)"

if ($toUpdate.Count -eq 0) {
    Write-Host 'Nothing to do.'
    exit 0
}

$batches     = @(Split-Chunks -Array $toUpdate -Size 50)
$updated     = 0
$totalUpdate = $toUpdate.Count

for ($i = 0; $i -lt $batches.Count; $i++) {
    $batch   = @($batches[$i])
    $payload = @{
        users = @{
            user = @($batch | ForEach-Object { @{ id = $_.id; birthday_date = $TargetDate } })
        }
    }

    Invoke-SchoologyRequest -Method PUT -Path '/v1/users' -Body $payload | Out-Null
    $updated += $batch.Count
    Write-Host "Updated batch $($i + 1)/$($batches.Count) ($updated/$totalUpdate)"
}

Write-Host "Done. Updated $updated student(s)."
