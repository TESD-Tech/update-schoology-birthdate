<?php

$usage = <<<HELP
Usage: php update_birthdate.php <mode>

Modes:
  --all              Update all student accounts
  --uid <school_uid> Update one specific student by school_uid
  --random           Update one randomly selected student (smoke test)

Examples:
  php update_birthdate.php --uid 100234
  php update_birthdate.php --random
  php update_birthdate.php --all
HELP;

// Parse arguments
$mode    = $argv[1] ?? null;
$modeArg = $argv[2] ?? null;

if (!$mode || in_array($mode, ['--help', '-h'])) {
    echo $usage . "\n";
    exit(0);
}

if (!in_array($mode, ['--all', '--uid', '--random'])) {
    fwrite(STDERR, "Unknown option: {$mode}\n\n");
    echo $usage . "\n";
    exit(1);
}

if ($mode === '--uid' && !$modeArg) {
    fwrite(STDERR, "--uid requires a school_uid argument\n\n");
    echo $usage . "\n";
    exit(1);
}

// Load .env
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
        foreach ($page as $user) { $students[] = $user; }
        $total  = (int) ($data['total'] ?? 0);
        $start += count($page);
        if (empty($page) || $start >= $total) break;
    }
    return $students;
}

function fetchStudentByUid(string $uid, string $key, string $secret): array
{
    $data  = apiRequest('GET', '/v1/users?school_uid=' . urlencode($uid), null, $key, $secret);
    $users = $data['user'] ?? [];
    if (empty($users)) {
        fwrite(STDERR, "No user found with school_uid: {$uid}\n");
        exit(1);
    }
    return $users[0];
}

function updateStudents(array $students, string $targetDate, string $key, string $secret): void
{
    $toUpdate = array_values(array_filter($students, fn($s) => ($s['birthday_date'] ?? '') !== $targetDate));
    $skipped  = count($students) - count($toUpdate);

    echo "Checked:  " . count($students) . "\n";
    echo "Skipped:  {$skipped} (already {$targetDate})\n";
    echo "Updating: " . count($toUpdate) . "\n";

    if (empty($toUpdate)) {
        echo "Nothing to do.\n";
        return;
    }

    $updated = 0;
    foreach (array_chunk($toUpdate, 50) as $batch) {
        $payload = [
            'users' => [
                'user' => array_map(fn($s) => ['id' => $s['id'], 'birthday_date' => $targetDate], $batch),
            ],
        ];
        apiRequest('PUT', '/v1/users', $payload, $key, $secret);
        $updated += count($batch);
        echo "Updated {$updated}/" . count($toUpdate) . "\n";
        if ($updated < count($toUpdate)) {
            usleep(500000);
        }
    }

    echo "Done.\n";
}

// Main
if ($mode === '--uid') {
    echo "Fetching student with school_uid: {$modeArg}...\n";
    $student = fetchStudentByUid($modeArg, $key, $secret);
    echo "Found: id {$student['id']}\n";
    updateStudents([$student], $targetDate, $key, $secret);

} elseif ($mode === '--random') {
    echo "Fetching one page of students to pick from...\n";
    $data     = apiRequest('GET', "/v1/users?role_ids={$studentRoleId}&limit=200&start=0", null, $key, $secret);
    $students = $data['user'] ?? [];
    if (empty($students)) {
        fwrite(STDERR, "No students found.\n");
        exit(1);
    }
    $student = $students[array_rand($students)];
    echo "Randomly selected: id {$student['id']}\n";
    updateStudents([$student], $targetDate, $key, $secret);

} elseif ($mode === '--all') {
    echo "Fetching all students...\n";
    $students = fetchAllStudents($studentRoleId, $key, $secret);
    echo 'Total fetched: ' . count($students) . "\n";
    updateStudents($students, $targetDate, $key, $secret);
}
