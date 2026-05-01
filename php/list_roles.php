<?php

$envFile = __DIR__ . '/../.env';
if (file_exists($envFile)) {
    foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        if (strpos(trim($line), '#') === 0) continue;
        [$name, $value] = array_map('trim', explode('=', $line, 2));
        putenv("$name=$value");
    }
}

$key    = getenv('SCHOOLOGY_KEY');
$secret = getenv('SCHOOLOGY_SECRET');

if (!$key || !$secret) {
    fwrite(STDERR, "Missing required environment variables: SCHOOLOGY_KEY, SCHOOLOGY_SECRET\n");
    exit(1);
}

$nonce     = bin2hex(random_bytes(16));
$timestamp = time();
$authHeader = implode(',', [
    'OAuth realm="Schoology API"',
    "oauth_consumer_key=\"{$key}\"",
    'oauth_token=""',
    "oauth_nonce=\"{$nonce}\"",
    "oauth_timestamp=\"{$timestamp}\"",
    'oauth_signature_method="PLAINTEXT"',
    "oauth_signature=\"{$secret}%26\"",
    'oauth_version="1.0"',
]);

$ch = curl_init('https://api.schoology.com/v1/roles');
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    "Authorization: {$authHeader}",
    'Accept: application/json',
]);

$response = curl_exec($ch);
$status   = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

if ($status !== 200) {
    fwrite(STDERR, "HTTP {$status}: {$response}\n");
    exit(1);
}

$roles = json_decode($response, true)['role'] ?? [];
echo "\nAvailable roles:\n\n";
printf("  %-10s  %s\n", 'ID', 'Title');
printf("  %-10s  %s\n", '----------', '--------------------');
foreach ($roles as $r) {
    printf("  %-10s  %s\n", $r['id'], $r['title']);
}
echo "\nSet STUDENT_ROLE_ID in your .env to the ID of the student role above.\n\n";
