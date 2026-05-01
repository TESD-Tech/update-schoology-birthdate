import os
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
    if response.content:
        return response.json()
    return {}


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


def chunk_list(lst, size):
    for i in range(0, len(lst), size):
        yield lst[i:i + size]


def main():
    print('Fetching students...')
    students = fetch_all_students()
    print(f'Total students fetched: {len(students)}')

    to_update = [s for s in students if s.get('birthday_date') != TARGET_DATE]
    skipped = len(students) - len(to_update)
    print(f'Already correct: {skipped}')
    print(f'To update: {len(to_update)}')

    if not to_update:
        print('Nothing to do.')
        return

    batches = list(chunk_list(to_update, 50))
    updated = 0

    for i, batch in enumerate(batches):
        payload = {
            'users': {
                'user': [{'id': s['id'], 'birthday_date': TARGET_DATE} for s in batch]
            }
        }
        api_request('PUT', '/v1/users', json=payload)
        updated += len(batch)
        print(f'Updated batch {i + 1}/{len(batches)} ({updated}/{len(to_update)})')

    print(f'Done. Updated {updated} student(s).')


if __name__ == '__main__':
    main()
