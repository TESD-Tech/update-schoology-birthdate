import argparse
import os
import random
import sys
import time
import uuid
from datetime import datetime
from pathlib import Path

import requests
from dotenv import load_dotenv

load_dotenv(dotenv_path=Path(__file__).parent.parent / '.env')

KEY = os.environ.get('SCHOOLOGY_KEY')
SECRET = os.environ.get('SCHOOLOGY_SECRET')
STUDENT_ROLE_ID = os.environ.get('STUDENT_ROLE_ID')

if not all([KEY, SECRET, STUDENT_ROLE_ID]):
    print('Missing required environment variables: SCHOOLOGY_KEY, SCHOOLOGY_SECRET, STUDENT_ROLE_ID')
    sys.exit(1)

CURRENT_YEAR = datetime.now().year
TARGET_DATE = f'{CURRENT_YEAR}-01-01'
BASE_URL = 'https://api.schoology.com'


def oauth_header():
    nonce = uuid.uuid4().hex
    timestamp = int(time.time())
    return (
        f'OAuth realm="Schoology API",'
        f'oauth_consumer_key="{KEY}",'
        f'oauth_token="",'
        f'oauth_nonce="{nonce}",'
        f'oauth_timestamp="{timestamp}",'
        f'oauth_signature_method="PLAINTEXT",'
        f'oauth_signature="{SECRET}%26",'
        f'oauth_version="1.0"'
    )


def api_request(method, path, json=None):
    url = f'{BASE_URL}{path}'
    headers = {
        'Authorization': oauth_header(),
        'Content-Type': 'application/json',
        'Accept': 'application/json',
    }
    response = requests.request(method, url, headers=headers, json=json)
    response.raise_for_status()
    return response.json() if response.content else {}


def fetch_all_students():
    students = []
    start = 0
    limit = 200

    while True:
        path = f'/v1/users?role_ids={STUDENT_ROLE_ID}&limit={limit}&start={start}'
        data = api_request('GET', path)
        page = data.get('user', [])
        students.extend(page)
        total = int(data.get('total', 0))
        start += len(page)
        if not page or start >= total:
            break

    return students


def fetch_student_by_uid(school_uid):
    from urllib.parse import quote
    data = api_request('GET', f'/v1/users?school_uid={quote(str(school_uid))}')
    users = data.get('user', [])
    if not users:
        print(f'No user found with school_uid: {school_uid}')
        sys.exit(1)
    return users[0]


def update_students(students):
    to_update = [s for s in students if s.get('birthday_date') != TARGET_DATE]
    skipped = len(students) - len(to_update)

    print(f'Checked:  {len(students)}')
    print(f'Skipped:  {skipped} (already {TARGET_DATE})')
    print(f'Updating: {len(to_update)}')

    if not to_update:
        print('Nothing to do.')
        return

    updated = 0
    for i in range(0, len(to_update), 50):
        batch = to_update[i:i + 50]
        payload = {
            'users': {
                'user': [{'id': s['id'], 'birthday_date': TARGET_DATE} for s in batch]
            }
        }
        api_request('PUT', '/v1/users', json=payload)
        updated += len(batch)
        print(f'Updated {updated}/{len(to_update)}')
        if updated < len(to_update):
            time.sleep(0.5)

    print('Done.')


def main():
    parser = argparse.ArgumentParser(
        prog='python update_birthdate.py',
        description='Anonymize student birthday_date fields in Schoology.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            'examples:\n'
            '  python update_birthdate.py --uid 100234\n'
            '  python update_birthdate.py --random\n'
            '  python update_birthdate.py --all'
        ),
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--all', action='store_true', help='Update all student accounts')
    group.add_argument('--uid', metavar='school_uid', help='Update one specific student by school_uid')
    group.add_argument('--random', action='store_true', help='Update one randomly selected student (smoke test)')

    args = parser.parse_args()

    if args.uid:
        print(f'Fetching student with school_uid: {args.uid}...')
        student = fetch_student_by_uid(args.uid)
        print(f'Found: id {student["id"]}')
        update_students([student])

    elif args.random:
        print('Fetching one page of students to pick from...')
        data = api_request('GET', f'/v1/users?role_ids={STUDENT_ROLE_ID}&limit=200&start=0')
        students = data.get('user', [])
        if not students:
            print('No students found.')
            sys.exit(1)
        student = random.choice(students)
        print(f'Randomly selected: id {student["id"]}')
        update_students([student])

    elif args.all:
        print('Fetching all students...')
        students = fetch_all_students()
        print(f'Total fetched: {len(students)}')
        update_students(students)


if __name__ == '__main__':
    main()
