import os
import sys
import time
import uuid
from pathlib import Path

import requests
from dotenv import load_dotenv

load_dotenv(dotenv_path=Path(__file__).parent.parent / '.env')

KEY = os.environ.get('SCHOOLOGY_KEY')
SECRET = os.environ.get('SCHOOLOGY_SECRET')

if not all([KEY, SECRET]):
    print('Missing required environment variables: SCHOOLOGY_KEY, SCHOOLOGY_SECRET')
    sys.exit(1)


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


response = requests.get(
    'https://api.schoology.com/v1/roles',
    headers={'Authorization': oauth_header(), 'Accept': 'application/json'},
)
response.raise_for_status()

roles = response.json().get('role', [])
print('\nAvailable roles:\n')
print(f'  {"ID":<10}  Title')
print(f'  {"----------":<10}  --------------------')
for r in roles:
    print(f'  {str(r["id"]):<10}  {r["title"]}')
print('\nSet STUDENT_ROLE_ID in your .env to the ID of the student role above.\n')
