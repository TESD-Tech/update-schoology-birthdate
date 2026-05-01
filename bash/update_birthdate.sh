#!/usr/bin/env bash
set -euo pipefail

# Load .env from parent directory if present
ENV_FILE="$(dirname "$0")/../.env"
if [ -f "$ENV_FILE" ]; then
  while IFS='=' read -r name value; do
    # Skip comments and blank lines
    [[ "$name" =~ ^#.*$ || -z "$name" ]] && continue
    export "$name"="$value"
  done < "$ENV_FILE"
fi

KEY="${SCHOOLOGY_KEY:?SCHOOLOGY_KEY is required}"
SECRET="${SCHOOLOGY_SECRET:?SCHOOLOGY_SECRET is required}"
STUDENT_ROLE_ID="${STUDENT_ROLE_ID:?STUDENT_ROLE_ID is required}"

CURRENT_YEAR=$(date +%Y)
TARGET_DATE="${CURRENT_YEAR}-01-01"
BASE_URL="https://api.schoology.com"

oauth_header() {
  local nonce timestamp
  nonce=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-f0-9' | head -c 32)
  timestamp=$(date +%s)
  printf 'OAuth realm="Schoology API",oauth_consumer_key="%s",oauth_token="",oauth_nonce="%s",oauth_timestamp="%s",oauth_signature_method="PLAINTEXT",oauth_signature="%s%%26",oauth_version="1.0"' \
    "$KEY" "$nonce" "$timestamp" "$SECRET"
}

api_get() {
  local path="$1"
  curl -sf \
    -H "Authorization: $(oauth_header)" \
    -H "Accept: application/json" \
    "${BASE_URL}${path}"
}

api_put() {
  local path="$1"
  local body="$2"
  curl -sf \
    -X PUT \
    -H "Authorization: $(oauth_header)" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$body" \
    "${BASE_URL}${path}"
}

echo "Fetching students..."

students_json="[]"
start=0
limit=200

while true; do
  page=$(api_get "/v1/users?role_ids=${STUDENT_ROLE_ID}&limit=${limit}&start=${start}")
  page_users=$(echo "$page" | jq '.user // []')
  page_count=$(echo "$page_users" | jq 'length')
  total=$(echo "$page" | jq '.total // 0 | tonumber')

  students_json=$(echo "$students_json $page_users" | jq -s 'add')
  start=$((start + page_count))

  if [ "$page_count" -eq 0 ] || [ "$start" -ge "$total" ]; then
    break
  fi
done

total_students=$(echo "$students_json" | jq 'length')
echo "Total students fetched: ${total_students}"

to_update=$(echo "$students_json" | jq --arg td "$TARGET_DATE" '[.[] | select(.birthday_date != $td)]')
skipped=$(echo "$students_json" | jq --arg td "$TARGET_DATE" '[.[] | select(.birthday_date == $td)] | length')
update_count=$(echo "$to_update" | jq 'length')

echo "Already correct: ${skipped}"
echo "To update: ${update_count}"

if [ "$update_count" -eq 0 ]; then
  echo "Nothing to do."
  exit 0
fi

batch_size=50
updated=0
batch_num=0
total_batches=$(( (update_count + batch_size - 1) / batch_size ))

while [ "$updated" -lt "$update_count" ]; do
  batch=$(echo "$to_update" | jq --argjson offset "$updated" --argjson size "$batch_size" '.[$offset:$offset+$size]')
  payload=$(echo "$batch" | jq --arg td "$TARGET_DATE" '{"users":{"user":[.[] | {"id": .id, "birthday_date": $td}]}}')

  api_put "/v1/users" "$payload" > /dev/null
  batch_num=$((batch_num + 1))
  batch_actual=$(echo "$batch" | jq 'length')
  updated=$((updated + batch_actual))

  echo "Updated batch ${batch_num}/${total_batches} (${updated}/${update_count})"
done

echo "Done. Updated ${updated} student(s)."
