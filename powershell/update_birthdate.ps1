#Requires -Version 5.1
param(
    [switch]$All,
    [string]$Uid,
    [switch]$Random
)

$Usage = @"
Usage: .\update_birthdate.ps1 <mode>

Modes:
  -All           Update all student accounts
  -Uid <id>      Update one specific student by school_uid
  -Random        Update one randomly selected student (smoke test)

Examples:
  .\update_birthdate.ps1 -Uid 100234
  .\update_birthdate.ps1 -Random
  .\update_birthdate.ps1 -All
"@

$modeCount = @($All.IsPresent, ($Uid -ne ''), $Random.IsPresent) | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count

if ($modeCount -eq 0) {
    Write-Host $Usage
    exit 0
}

if ($modeCount -gt 1) {
    Write-Error 'Specify only one mode: -All, -Uid, or -Random'
    Write-Host $Usage
    exit 1
}

# Load .env
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
    param([string]$Method, [string]$Path, [hashtable]$Body = $null)
    $params = @{
        Uri     = "$BaseUrl$Path"
        Method  = $Method
        Headers = @{ Authorization = Get-OAuthHeader; 'Content-Type' = 'application/json'; Accept = 'application/json' }
    }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress) }
    Invoke-RestMethod @params
}

function Get-AllStudents {
    $students = [System.Collections.Generic.List[object]]::new()
    $start = 0; $limit = 200
    do {
        $data  = Invoke-SchoologyRequest -Method GET -Path "/v1/users?role_ids=$StudentRoleId&limit=$limit&start=$start"
        $page  = @($data.user)
        foreach ($u in $page) { $students.Add($u) }
        $total  = [int]$data.total
        $start += $page.Count
    } while ($page.Count -gt 0 -and $start -lt $total)
    return $students
}

function Update-Students {
    param([object[]]$Students)

    $toUpdate = @($Students | Where-Object { $_.birthday_date -ne $TargetDate })
    $skipped  = $Students.Count - $toUpdate.Count

    Write-Host "Checked:  $($Students.Count)"
    Write-Host "Skipped:  $skipped (already $TargetDate)"
    Write-Host "Updating: $($toUpdate.Count)"

    if ($toUpdate.Count -eq 0) { Write-Host 'Nothing to do.'; return }

    $updated = 0
    for ($i = 0; $i -lt $toUpdate.Count; $i += 50) {
        $batch   = @($toUpdate[$i..([Math]::Min($i + 49, $toUpdate.Count - 1))])
        $payload = @{ users = @{ user = @($batch | ForEach-Object { @{ id = $_.id; birthday_date = $TargetDate } }) } }
        Invoke-SchoologyRequest -Method PUT -Path '/v1/users' -Body $payload | Out-Null
        $updated += $batch.Count
        Write-Host "Updated $updated/$($toUpdate.Count)"
        if ($updated -lt $toUpdate.Count) { Start-Sleep -Milliseconds 500 }
    }

    Write-Host 'Done.'
}

# Main
if ($Uid) {
    Write-Host "Fetching student with school_uid: $Uid..."
    $data    = Invoke-SchoologyRequest -Method GET -Path "/v1/users?school_uid=$([Uri]::EscapeDataString($Uid))"
    $student = @($data.user)[0]
    if (-not $student) { Write-Error "No user found with school_uid: $Uid"; exit 1 }
    Write-Host "Found: id $($student.id)"
    Update-Students -Students @($student)

} elseif ($Random) {
    Write-Host 'Fetching one page of students to pick from...'
    $data     = Invoke-SchoologyRequest -Method GET -Path "/v1/users?role_ids=$StudentRoleId&limit=200&start=0"
    $students = @($data.user)
    if ($students.Count -eq 0) { Write-Error 'No students found.'; exit 1 }
    $student  = $students[(Get-Random -Maximum $students.Count)]
    Write-Host "Randomly selected: id $($student.id)"
    Update-Students -Students @($student)

} elseif ($All) {
    Write-Host 'Fetching all students...'
    $students = Get-AllStudents
    Write-Host "Total fetched: $($students.Count)"
    Update-Students -Students @($students)
}
