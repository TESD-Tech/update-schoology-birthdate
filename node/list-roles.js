require('dotenv').config({ path: '../.env' });

const https = require('https');
const { randomUUID } = require('crypto');

const KEY = process.env.SCHOOLOGY_KEY;
const SECRET = process.env.SCHOOLOGY_SECRET;

if (!KEY || !SECRET) {
  console.error('Missing required environment variables: SCHOOLOGY_KEY, SCHOOLOGY_SECRET');
  process.exit(1);
}

function oauthHeader() {
  const nonce = randomUUID().replace(/-/g, '');
  const timestamp = Math.floor(Date.now() / 1000);
  return (
    `OAuth realm="Schoology API",` +
    `oauth_consumer_key="${KEY}",` +
    `oauth_token="",` +
    `oauth_nonce="${nonce}",` +
    `oauth_timestamp="${timestamp}",` +
    `oauth_signature_method="PLAINTEXT",` +
    `oauth_signature="${SECRET}%26",` +
    `oauth_version="1.0"`
  );
}

const options = {
  hostname: 'api.schoology.com',
  path: '/v1/roles',
  method: 'GET',
  headers: {
    Authorization: oauthHeader(),
    Accept: 'application/json',
  },
};

https.get(options, (res) => {
  let data = '';
  res.on('data', (chunk) => (data += chunk));
  res.on('end', () => {
    if (res.statusCode !== 200) {
      console.error(`HTTP ${res.statusCode}: ${data}`);
      process.exit(1);
    }
    const roles = JSON.parse(data).role || [];
    console.log('\nAvailable roles:\n');
    console.log('  ID          Title');
    console.log('  ----------  --------------------');
    for (const r of roles) {
      console.log(`  ${String(r.id).padEnd(10)}  ${r.title}`);
    }
    console.log('\nSet STUDENT_ROLE_ID in your .env to the ID of the student role above.\n');
  });
}).on('error', (err) => {
  console.error('Request failed:', err.message);
  process.exit(1);
});
