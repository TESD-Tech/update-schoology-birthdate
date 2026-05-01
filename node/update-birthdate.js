require('dotenv').config({ path: '../.env' });

const https = require('https');
const { randomUUID } = require('crypto');

const KEY = process.env.SCHOOLOGY_KEY;
const SECRET = process.env.SCHOOLOGY_SECRET;
const STUDENT_ROLE_ID = process.env.STUDENT_ROLE_ID;

if (!KEY || !SECRET || !STUDENT_ROLE_ID) {
  console.error('Missing required environment variables: SCHOOLOGY_KEY, SCHOOLOGY_SECRET, STUDENT_ROLE_ID');
  process.exit(1);
}

const CURRENT_YEAR = new Date().getFullYear();
const TARGET_DATE = `${CURRENT_YEAR}-01-01`;
const BASE_HOST = 'api.schoology.com';

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

function apiRequest(method, path, body = null) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: BASE_HOST,
      path,
      method,
      headers: {
        Authorization: oauthHeader(),
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            resolve(data ? JSON.parse(data) : {});
          } catch {
            resolve({});
          }
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${data}`));
        }
      });
    });

    req.on('error', reject);

    if (body) {
      req.write(JSON.stringify(body));
    }
    req.end();
  });
}

async function fetchAllStudents() {
  const students = [];
  let start = 0;
  const limit = 200;

  while (true) {
    const path = `/v1/users?role_ids=${STUDENT_ROLE_ID}&limit=${limit}&start=${start}`;
    const data = await apiRequest('GET', path);

    const page = data.user || [];
    students.push(...page);

    const total = parseInt(data.total, 10) || 0;
    start += page.length;

    if (page.length === 0 || start >= total) break;
  }

  return students;
}

function chunkArray(arr, size) {
  const chunks = [];
  for (let i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size));
  }
  return chunks;
}

async function main() {
  console.log('Fetching students...');
  const students = await fetchAllStudents();
  console.log(`Total students fetched: ${students.length}`);

  const toUpdate = students.filter((s) => s.birthday_date !== TARGET_DATE);
  const skipped = students.length - toUpdate.length;
  console.log(`Already correct: ${skipped}`);
  console.log(`To update: ${toUpdate.length}`);

  if (toUpdate.length === 0) {
    console.log('Nothing to do.');
    return;
  }

  const batches = chunkArray(toUpdate, 50);
  let updated = 0;

  for (let i = 0; i < batches.length; i++) {
    const batch = batches[i];
    const payload = {
      users: {
        user: batch.map((s) => ({ id: s.id, birthday_date: TARGET_DATE })),
      },
    };

    await apiRequest('PUT', '/v1/users', payload);
    updated += batch.length;
    console.log(`Updated batch ${i + 1}/${batches.length} (${updated}/${toUpdate.length})`);
  }

  console.log(`Done. Updated ${updated} student(s).`);
}

main().catch((err) => {
  console.error('Fatal error:', err.message);
  process.exit(1);
});
