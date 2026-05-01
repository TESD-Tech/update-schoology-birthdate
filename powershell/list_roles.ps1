#Requires -Version 5.1

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

$Key    = $env:SCHOOLOGY_KEY
$Secret = $env:SCHOOLOGY_SECRET

if (-not $Key -or -not $Secret) {
    Write-Error 'Missing required environment variables: SCHOOLOGY_KEY, SCHOOLOGY_SECRET'
    exit 1
}

$nonce     = [System.Guid]::NewGuid().ToString('N')
$timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$auth = (
    'OAuth realm="Schoology API",' +
    "oauth_consumer_key=`"$Key`"," +
    'oauth_token="",' +
    "oauth_nonce=`"$nonce`"," +
    "oauth_timestamp=`"$timestamp`"," +
    'oauth_signature_method="PLAINTEXT",' +
    "oauth_signature=`"$Secret%26`"," +
    'oauth_version="1.0"'
)

$response = Invoke-RestMethod -Uri 'https://api.schoology.com/v1/roles' -Headers @{
    Authorization = $auth
    Accept        = 'application/json'
}

$roles = @($response.role)
Write-Host ''
Write-Host 'Available roles:'
Write-Host ''
Write-Host ('  {0,-10}  {1}' -f 'ID', 'Title')
Write-Host ('  {0,-10}  {1}' -f '----------', '--------------------')
foreach ($r in $roles) {
    Write-Host ('  {0,-10}  {1}' -f $r.id, $r.title)
}
Write-Host ''
Write-Host 'Set STUDENT_ROLE_ID in your .env to the ID of the student role above.'
Write-Host ''
