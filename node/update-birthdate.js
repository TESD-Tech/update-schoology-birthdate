// Loads SCHOOLOGY_KEY, SCHOOLOGY_SECRET, and STUDENT_ROLE_IDS from the .env file
// one directory up. Must be configured before running.
require('dotenv').config({ path: '../.env' });

const https = require('https');
const { randomUUID } = require('crypto');

// ─── CLI argument parsing (skip to CONFIG section for the real logic) ──────────

const HELP = `
Usage: node update-birthdate.js <mode>

Modes:
  --all              Update all student accounts
  --uid <school_uid> Update one specific student by school_uid
  --random           Update one randomly selected student
  --batch            Update a small sample (5 students) to smoke test the batch PUT path

Examples:
  node update-birthdate.js --uid 100234
  node update-birthdate.js --random
  node update-birthdate.js --batch
  node update-birthdate.js --all
`.trim();

const args = process.argv.slice(2);
const mode = args[0];
const modeArg = args[1];

if (!mode || mode === '--help' || mode === '-h') {
  console.log(HELP);
  process.exit(0);
}

if (!['--all', '--uid', '--random', '--batch'].includes(mode)) {
  console.error(`Unknown option: ${mode}\n`);
  console.log(HELP);
  process.exit(1);
}

if (mode === '--uid' && !modeArg) {
  console.error('--uid requires a school_uid argument\n');
  console.log(HELP);
  process.exit(1);
}

// ─── CONFIG ───────────────────────────────────────────────────────────────────

const KEY = process.env.SCHOOLOGY_KEY;
const SECRET = process.env.SCHOOLOGY_SECRET;

// Comma-separated list of student role IDs — districts often have more than one
// (e.g. "695428,311125"). All matching roles are fetched in a single API call.
const STUDENT_ROLE_IDS = (process.env.STUDENT_ROLE_IDS || '').split(',').map((s) => s.trim()).filter(Boolean);

if (!KEY || !SECRET || STUDENT_ROLE_IDS.length === 0) {
  console.error('Missing required environment variables: SCHOOLOGY_KEY, SCHOOLOGY_SECRET, STUDENT_ROLE_IDS');
  process.exit(1);
}

// This is the date we write to every student record. January 1st of the
// current year is non-identifying but passes Schoology's date validation.
const CURRENT_YEAR = new Date().getFullYear();
const TARGET_DATE = `${CURRENT_YEAR}-01-01`;

const BASE_HOST = 'api.schoology.com';

// ─── OAUTH ────────────────────────────────────────────────────────────────────

// Builds a fresh Authorization header for each request using OAuth 1.0 PLAINTEXT
// signing. This is the authentication method Schoology's API requires.
// A new nonce (random value) and timestamp are generated every call so that
// replayed requests are rejected by the server.
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

// ─── HTTP ─────────────────────────────────────────────────────────────────────

// Generic HTTPS helper used for every API call. Attaches a fresh OAuth header,
// sends an optional JSON body, and returns the parsed response.
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
          try { resolve(data ? JSON.parse(data) : {}); } catch { resolve({}); }
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${data}`));
        }
      });
    });

    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

// ─── FETCH ────────────────────────────────────────────────────────────────────

// Pages through GET /v1/users filtered to the student role. The API returns at
// most 200 records per request, so we keep incrementing `start` until we've
// collected every student. A progress bar is drawn in-place as pages arrive.
async function fetchAllStudents() {
  const students = [];
  let start = 0;
  let total = 0;
  const limit = 200;
  const BAR_WIDTH = 30;

  while (true) {
    const path = `/v1/users?role_ids=${STUDENT_ROLE_IDS.join(',')}&limit=${limit}&start=${start}`;
    const data = await apiRequest('GET', path);
    const page = data.user || [];
    students.push(...page);
    total = parseInt(data.total, 10) || 0;
    start += page.length;

    const pct = total > 0 ? Math.min(start / total, 1) : 0;
    const filled = Math.round(pct * BAR_WIDTH);
    const bar = '█'.repeat(filled) + '░'.repeat(BAR_WIDTH - filled);
    process.stdout.write(`\r  [${bar}] ${start}/${total}`);

    if (page.length === 0 || start >= total) break;
  }

  process.stdout.write('\n');
  return students;
}

// Looks up a single student by their SIS ID (school_uid) rather than fetching
// the entire roster — useful for targeted testing before a full run.
async function fetchStudentByUid(schoolUid) {
  const data = await apiRequest('GET', `/v1/users?school_uid=${encodeURIComponent(schoolUid)}`);
  const users = data.user || [];
  if (users.length === 0) throw new Error(`No user found with school_uid: ${schoolUid}`);
  return users[0];
}

// ─── VERIFY ───────────────────────────────────────────────────────────────────

// Attempts to re-fetch each updated user and confirm birthday_date.
// NOTE: As of 2026, the Schoology API does not return birthday_date in GET
// responses (confirmed against docs at /api-documentation/rest-api-v1/user).
// The PUT still works — verify results manually in the Schoology UI.
async function verifyStudents(ids) {
  console.log('\nVerifying...');
  const results = await Promise.all(
    ids.map((id) => apiRequest('GET', `/v1/users/${id}`))
  );
  for (const user of results) {
    const dob = user.birthday_date;
    if (dob !== undefined) {
      console.log(`  id ${user.id}: birthday_date = ${JSON.stringify(dob)}`);
    } else {
      console.log(`  id ${user.id}: — check /user/${user.id}/info in the Schoology UI`);
    }
  }
}

// ─── UPDATE ───────────────────────────────────────────────────────────────────

// Core update logic. Sends all students to the API in batches of 50.
// A 500ms delay between batches avoids overwhelming the server.
//
// NOTE: The Schoology API does not return birthday_date in GET responses, so
// there is no way to skip already-updated records. The PUT is idempotent in
// effect — writing Jan 1 again does nothing harmful.
//
// PUT /v1/users accepts a bulk payload — we never update students one at a time.
async function updateStudents(students) {
  console.log(`Updating: ${students.length}`);

  for (let i = 0; i < students.length; i += 50) {
    const batch = students.slice(i, i + 50);
    // Each user object only needs id and birthday_date for a partial update
    await apiRequest('PUT', '/v1/users', {
      users: { user: batch.map((s) => ({ id: s.id, birthday_date: TARGET_DATE })) },
    });
    console.log(`Updated ${Math.min(i + 50, students.length)}/${students.length}`);
    if (i + 50 < students.length) await new Promise((r) => setTimeout(r, 500));
  }

  console.log('Done.');
}

// ─── MAIN ─────────────────────────────────────────────────────────────────────

async function main() {
  if (mode === '--uid') {
    console.log(`Fetching student with school_uid: ${modeArg}...`);
    const student = await fetchStudentByUid(modeArg);
    console.log(`Found: id ${student.id}`);
    await updateStudents([student]);

  } else if (mode === '--random') {
    console.log('Fetching one page of students to pick from...');
    const data = await apiRequest('GET', `/v1/users?role_ids=${STUDENT_ROLE_IDS.join(',')}&limit=200&start=0`);
    const students = data.user || [];
    if (students.length === 0) throw new Error('No students found.');
    const student = students[Math.floor(Math.random() * students.length)];
    console.log(`Randomly selected: id ${student.id}`);
    await updateStudents([student]);
    await verifyStudents([student.id]);

  } else if (mode === '--batch') {
    // Fetches the first page and picks 5 students to run through the real
    // multi-record batch PUT — the code path that --random doesn't exercise.
    console.log('Fetching a sample of students for batch smoke test...');
    const data = await apiRequest('GET', `/v1/users?role_ids=${STUDENT_ROLE_IDS.join(',')}&limit=200&start=0`);
    const students = (data.user || []).slice(0, 5);
    if (students.length === 0) throw new Error('No students found.');
    console.log(`Sample size: ${students.length}`);
    console.log(`IDs: ${students.map((s) => s.id).join(', ')}`);
    await updateStudents(students);
    await verifyStudents(students.map((s) => s.id));

  } else if (mode === '--all') {
    console.log('Fetching all students...');
    const students = await fetchAllStudents();
    console.log(`Total fetched: ${students.length}`);
    await updateStudents(students);
  }
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
