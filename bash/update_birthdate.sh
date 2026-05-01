#!/usr/bin/env bash
set -euo pipefail

USAGE="Usage: $(basename "$0") <mode>

Modes:
  --all              Update all student accounts
  --uid <school_uid> Update one specific student by school_uid
  --random           Update one randomly selected student (smoke test)

Examples:
  $(basename "$0") --uid 100234
  $(basename "$0") --random
  $(basename "$0") --all"

MODE="${1:-}"
MODE_ARG="${2:-}"

if [[ -z "$MODE" || "$MODE" == "--help" || "$MODE" == "-h" ]]; then
  echo "$USAGE"
  exit 0
fi

if [[ "$MODE" != "--all" && "$MODE" != "--uid" && "$MODE" != "--random" ]]; then
  echo "Unknown option: $MODE" >&2
  echo ""
  echo "$USAGE"
  exit 1
fi

if [[ "$MODE" == "--uid" && -z "$MODE_ARG" ]]; then
  echo "--uid requires a school_uid argument" >&2
  echo ""
  echo "$USAGE"
  exit 1
fi

# Load .env
ENV_FILE="$(dirname "$0")/../.env"
if [ -f "$ENV_FILE" ]; then
  while IFS='=' read -r name value; do
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
  curl -sf \
    -H "Authorization: $(oauth_header)" \
    -H "Accept: application/json" \
    "${BASE_URL}${1}"
}

api_put() {
  curl -sf -X PUT \
    -H "Authorization: $(oauth_header)" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$2" \
    "${BASE_URL}${1}"
}

fetch_all_students() {
  local all="[]"
  local start=0 limit=200

  while true; do
    page=$(api_get "/v1/users?role_ids=${STUDENT_ROLE_ID}&limit=${limit}&start=${start}")
    page_users=$(echo "$page" | jq '.user // []')
    page_count=$(echo "$page_users" | jq 'length')
    total=$(echo "$page" | jq '.total // 0 | tonumber')

    all=$(echo "$all $page_users" | jq -s 'add')
    start=$((start + page_count))

    if [ "$page_count" -eq 0 ] || [ "$start" -ge "$total" ]; then
      break
    fi
  done

  echo "$all"
}

update_students() {
  local students="$1"
  local total_checked update_count skipped

  to_update=$(echo "$students" | jq --arg td "$TARGET_DATE" '[.[] | select(.birthday_date != $td)]')
  total_checked=$(echo "$students" | jq 'length')
  update_count=$(echo "$to_update" | jq 'length')
  skipped=$((total_checked - update_count))

  echo "Checked:  ${total_checked}"
  echo "Skipped:  ${skipped} (already ${TARGET_DATE})"
  echo "Updating: ${update_count}"

  if [ "$update_count" -eq 0 ]; then
    echo "Nothing to do."
    return
  fi

  local updated=0 batch_size=50
  while [ "$updated" -lt "$update_count" ]; do
    batch=$(echo "$to_update" | jq --argjson offset "$updated" --argjson size "$batch_size" '.[$offset:$offset+$size]')
    payload=$(echo "$batch" | jq --arg td "$TARGET_DATE" '{"users":{"user":[.[] | {"id": .id, "birthday_date": $td}]}}')
    api_put "/v1/users" "$payload" > /dev/null
    batch_actual=$(echo "$batch" | jq 'length')
    updated=$((updated + batch_actual))
    echo "Updated ${updated}/${update_count}"
    if [ "$updated" -lt "$update_count" ]; then
      sleep 0.5
    fi
  done

  echo "Done."
}

# Main
if [[ "$MODE" == "--uid" ]]; then
  echo "Fetching student with school_uid: ${MODE_ARG}..."
  result=$(api_get "/v1/users?school_uid=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$MODE_ARG" 2>/dev/null || printf '%s' "$MODE_ARG")")
  student=$(echo "$result" | jq '.user[0] // empty')
  if [ -z "$student" ]; then
    echo "No user found with school_uid: ${MODE_ARG}" >&2
    exit 1
  fi
  id=$(echo "$student" | jq -r '.id')
  echo "Found: id ${id}"
  update_students "$(echo "$student" | jq -s '.')"

elif [[ "$MODE" == "--random" ]]; then
  echo "Fetching one page of students to pick from..."
  data=$(api_get "/v1/users?role_ids=${STUDENT_ROLE_ID}&limit=200&start=0")
  students=$(echo "$data" | jq '.user // []')
  count=$(echo "$students" | jq 'length')
  if [ "$count" -eq 0 ]; then
    echo "No students found." >&2
    exit 1
  fi
  idx=$((RANDOM % count))
  student=$(echo "$students" | jq ".[$idx]")
  id=$(echo "$student" | jq -r '.id')
  echo "Randomly selected: id ${id}"
  update_students "$(echo "$student" | jq -s '.')"

elif [[ "$MODE" == "--all" ]]; then
  echo "Fetching all students..."
  students=$(fetch_all_students)
  total=$(echo "$students" | jq 'length')
  echo "Total fetched: ${total}"
  update_students "$students"
fi
