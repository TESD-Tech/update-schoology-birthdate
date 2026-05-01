<?php

// Load .env file from parent directory if present
$envFile = __DIR__ . '/../.env';
if (file_exists($envFile)) {
    foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        if (strpos(trim($line), '#') === 0) continue;
        [$name, $value] = array_map('trim', explode('=', $line, 2));
        putenv("$name=$value");
        $_ENV[$name] = $value;
    }
}

$key           = getenv('SCHOOLOGY_KEY');
$secret        = getenv('SCHOOLOGY_SECRET');
$studentRoleId = getenv('STUDENT_ROLE_ID');

if (!$key || !$secret || !$studentRoleId) {
    fwrite(STDERR, "Missing required environment variables: SCHOOLOGY_KEY, SCHOOLOGY_SECRET, STUDENT_ROLE_ID\n");
    exit(1);
}

$currentYear = (int) date('Y');
$targetDate  = "{$currentYear}-01-01";
$baseUrl     = 'https://api.schoology.com';

function oauthHeader(string $key, string $secret): string
{
    $nonce     = bin2hex(random_bytes(16));
    $timestamp = time();
    return implode(',', [
        'OAuth realm="Schoology API"',
        "oauth_consumer_key=\"{$key}\"",
        'oauth_token=""',
        "oauth_nonce=\"{$nonce}\"",
        "oauth_timestamp=\"{$timestamp}\"",
        'oauth_signature_method="PLAINTEXT"',
        "oauth_signature=\"{$secret}%26\"",
        'oauth_version="1.0"',
    ]);
}

function apiRequest(string $method, string $path, ?array $body, string $key, string $secret): array
{
    global $baseUrl;

    $url = $baseUrl . $path;
    $ch  = curl_init($url);

    $headers = [
        'Authorization: ' . oauthHeader($key, $secret),
        'Content-Type: application/json',
        'Accept: application/json',
    ];

    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);

    if ($body !== null) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
    }

    $response = curl_exec($ch);
    $status   = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($status < 200 || $status >= 300) {
        throw new RuntimeException("HTTP {$status}: {$response}");
    }

    return $response ? json_decode($response, true) : [];
}

function fetchAllStudents(string $roleId, string $key, string $secret): array
{
    $students = [];
    $start    = 0;
    $limit    = 200;

    while (true) {
        $path = "/v1/users?role_ids={$roleId}&limit={$limit}&start={$start}";
        $data = apiRequest('GET', $path, null, $key, $secret);

        $page = $data['user'] ?? [];
        foreach ($page as $user) {
            $students[] = $user;
        }

        $total = (int) ($data['total'] ?? 0);
        $start += count($page);

        if (empty($page) || $start >= $total) break;
    }

    return $students;
}

function chunkArray(array $arr, int $size): array
{
    return array_chunk($arr, $size);
}

// Main
echo "Fetching students...\n";
$students = fetchAllStudents($studentRoleId, $key, $secret);
echo 'Total students fetched: ' . count($students) . "\n";

$toUpdate = array_filter($students, fn($s) => ($s['birthday_date'] ?? '') !== $targetDate);
$toUpdate = array_values($toUpdate);
$skipped  = count($students) - count($toUpdate);
echo "Already correct: {$skipped}\n";
echo 'To update: ' . count($toUpdate) . "\n";

if (empty($toUpdate)) {
    echo "Nothing to do.\n";
    exit(0);
}

$batches = chunkArray($toUpdate, 50);
$updated = 0;
$total   = count($toUpdate);

foreach ($batches as $i => $batch) {
    $payload = [
        'users' => [
            'user' => array_map(fn($s) => ['id' => $s['id'], 'birthday_date' => $targetDate], $batch),
        ],
    ];
    apiRequest('PUT', '/v1/users', $payload, $key, $secret);
    $updated += count($batch);
    $batchNum = $i + 1;
    $batchTotal = count($batches);
    echo "Updated batch {$batchNum}/{$batchTotal} ({$updated}/{$total})\n";
}

echo "Done. Updated {$updated} student(s).\n";
