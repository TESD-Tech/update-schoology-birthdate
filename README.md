# update-schoology-birthdate

> **ALPHA** — Scripts are untested against a live Schoology environment. See the [To-Do](#to-do) section for current status.

---

## Background

A Schoology update exposed student birthdates to all authenticated users via the UI. While PowerSchool's engineering team works on a permanent fix, this repository provides a workaround: anonymize all student `birthday_date` fields via the Schoology REST API by setting them to `01/01/{current_year}` — a date that is non-identifying but still passes Schoology's validation.

Scripts are provided in five languages. **Node.js is the primary implementation** — it is the language this district uses day-to-day and will be the first script validated against production. The PHP, Python, PowerShell, and Bash scripts are provided as alternatives for districts or staff without a Node environment; they follow identical logic but are pending testing.

---

## To-Do

- [ ] Test Node.js script against a single test student account
- [ ] Test Node.js script against full district student population
- [ ] Test Python script against a single test student account
- [ ] Test PHP script against a single test student account
- [ ] Test PowerShell script against a single test student account
- [ ] Test Bash script against a single test student account
- [ ] Spot-check student profiles in Schoology UI after each run
- [ ] Confirm idempotency: second run reports 0 updates for all scripts

---

## Quick Setup

### Prerequisites

- Schoology API credentials (OAuth consumer key and secret) — available in your district's Schoology system settings under **API**
- Your district's `STUDENT_ROLE_ID` (see below)

### Finding Your `STUDENT_ROLE_ID`

A `list-roles` helper is included for every language. Once your `.env` has `SCHOOLOGY_KEY` and `SCHOOLOGY_SECRET`, run whichever matches your environment:

```bash
# Node.js (primary)
cd node && node list-roles.js

# Python
cd python && python list_roles.py

# PHP
cd php && php list_roles.php

# Bash
cd bash && ./list_roles.sh

# PowerShell
cd powershell && .\list_roles.ps1
```

All five print the same table:

```text
  ID          Title
  ----------  --------------------
  12345       Student
  12346       Teacher
  12347       Administrator
```

Copy the ID(s) next to your student role(s) and set them as a comma-separated list in `STUDENT_ROLE_IDS` in your `.env`. Districts often have more than one student role — include all of them.

### Configuration

Copy `.env.example` to `.env` and fill in your credentials:

```dotenv
SCHOOLOGY_KEY=your_consumer_key_here
SCHOOLOGY_SECRET=your_consumer_secret_here
STUDENT_ROLE_IDS=695428,311125
```

---

## Running the Scripts

All scripts require one of three modes. Running without arguments prints help and exits.

| Mode               | What it does                                          |
| ------------------ | ----------------------------------------------------- |
| `--all`            | Update every student account                          |
| `--uid <school_uid>` | Update one specific student (safe for initial testing) |
| `--random`         | Pick one student at random (quick smoke test)         |

### Node.js (primary)

```bash
cd node
npm install
node update-birthdate.js --random
node update-birthdate.js --uid 100234
node update-birthdate.js --all
```

Requires Node.js 18+.

### Python

```bash
cd python
pip install -r requirements.txt
python update_birthdate.py --random
python update_birthdate.py --uid 100234
python update_birthdate.py --all
```

Requires Python 3.7+.

### PHP

```bash
cd php
php update_birthdate.php --random
php update_birthdate.php --uid 100234
php update_birthdate.php --all
```

Requires PHP 7.4+ with cURL extension enabled. No Composer needed.

### Bash

```bash
cd bash
chmod +x update_birthdate.sh
./update_birthdate.sh --random
./update_birthdate.sh --uid 100234
./update_birthdate.sh --all
```

Requires `curl` and `jq`. Works on macOS and Linux.

### PowerShell

```powershell
cd powershell
.\update_birthdate.ps1 -Random
.\update_birthdate.ps1 -Uid 100234
.\update_birthdate.ps1 -All
```

Works on Windows PowerShell 5.1+ and PowerShell 7+.

---

## Warning

**This is a batch operation that modifies student records.** Before running against your full district:

1. Test against a single student account first (modify the script to filter by `school_uid`)
2. Confirm the change looks correct in the Schoology UI
3. The operation is idempotent — running a second time will report 0 updates

After running, spot-check a few student profiles in the Schoology UI to confirm birthdates show as `01/01/{year}`.

---

## Schoology API Reference

- [Schoology REST API Documentation](https://developers.schoology.com/api-documentation/rest-api-v1)
- Users endpoint: `GET/PUT /v1/users`
- Roles endpoint: `GET /v1/roles`
