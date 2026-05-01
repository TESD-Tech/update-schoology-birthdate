#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="$(dirname "$0")/../.env"
if [ -f "$ENV_FILE" ]; then
  while IFS='=' read -r name value; do
    [[ "$name" =~ ^#.*$ || -z "$name" ]] && continue
    export "$name"="$value"
  done < "$ENV_FILE"
fi

KEY="${SCHOOLOGY_KEY:?SCHOOLOGY_KEY is required}"
SECRET="${SCHOOLOGY_SECRET:?SCHOOLOGY_SECRET is required}"

nonce=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-f0-9' | head -c 32)
timestamp=$(date +%s)
auth=$(printf 'OAuth realm="Schoology API",oauth_consumer_key="%s",oauth_token="",oauth_nonce="%s",oauth_timestamp="%s",oauth_signature_method="PLAINTEXT",oauth_signature="%s%%26",oauth_version="1.0"' \
  "$KEY" "$nonce" "$timestamp" "$SECRET")

response=$(curl -sf -H "Authorization: $auth" -H "Accept: application/json" \
  "https://api.schoology.com/v1/roles")

echo ""
echo "Available roles:"
echo ""
printf "  %-10s  %s\n" "ID" "Title"
printf "  %-10s  %s\n" "----------" "--------------------"
echo "$response" | jq -r '.role[] | [.id, .title] | @tsv' | while IFS=$'\t' read -r id title; do
  printf "  %-10s  %s\n" "$id" "$title"
done
echo ""
echo "Set STUDENT_ROLE_ID in your .env to the ID of the student role above."
echo ""
