#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

# Base output dir (default: ./output, overridable via WORKSHOP_OUTPUT_DIR)
OUTPUT_DIR="${WORKSHOP_OUTPUT_DIR:-${ROOT_DIR}/output}"
mkdir -p "$OUTPUT_DIR"

INPUT_FILE="${1:-${OUTPUT_DIR}/attendees.auto.tfvars.json}"
CSV_OUTPUT="${2:-${OUTPUT_DIR}/wrapped_story_tokens.csv}"
JSON_OUTPUT="${3:-${OUTPUT_DIR}/wrapped_story_tokens.json}"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "❌ Input file '$INPUT_FILE' not found."
  echo "Usage: $0 [attendees.auto.tfvars.json] [csv_output] [json_output]"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq is required but not installed."
  exit 1
fi

# ✅ Sanity check: input is valid JSON
if ! jq . "$INPUT_FILE" >/dev/null 2>&1; then
  echo "❌ '$INPUT_FILE' is not valid JSON. Regenerate it via convert_2_tfvars.sh."
  exit 1
fi

# Load admin context from .env
if [[ -f ".env" ]]; then
  set -a
  . ./.env
  set +a
else
  echo "❌ .env not found next to Terraform files."
  exit 1
fi

VAULT_ADDR="${TF_VAR_vault_address:?TF_VAR_vault_address must be set in .env}"
ADMIN_TOKEN="${TF_VAR_vault_admin_token:?TF_VAR_vault_admin_token must be set in .env}"

echo "🔄 Issuing wrapped story tokens from $INPUT_FILE"
echo "   VAULT_ADDR=$VAULT_ADDR"

# CSV header
echo "first_name,last_name,email,namespace,username,wrapped_token" > "$CSV_OUTPUT"

# JSON header
echo '{"tokens":[' > "$JSON_OUTPUT"
first_item=true

# Temp file with the entries we loop over
entries_file="$(mktemp)"
trap 'rm -f "$entries_file"' EXIT

jq -c '.attendees | to_entries[]' "$INPUT_FILE" > "$entries_file"

while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue

  first=$(echo "$entry" | jq -r '.value.first_name')
  last=$(echo  "$entry" | jq -r '.value.last_name')
  email=$(echo "$entry" | jq -r '.value.email')
  ns_suffix=$(echo "$entry" | jq -r '.value.namespace_suffix // empty')

  # Username = lowercased first name (same as generate_credentials.sh)
  username=$(echo "$first" | tr '[:upper:]' '[:lower:]')

  # Backward compat: if namespace_suffix is missing, fall back to username
  if [[ -z "$ns_suffix" || "$ns_suffix" == "null" ]]; then
    ns_suffix="$username"
    echo "⚠️  No namespace_suffix for ${email}, falling back to '${ns_suffix}'" >&2
  fi

  namespace="admin/team_${ns_suffix}"

  echo "👉 Generating wrapped token for ${first} ${last} <${email}> in ${namespace}"

  # Call Vault with admin token in the attendee namespace
  set +e
  resp=$(
    VAULT_ADDR="$VAULT_ADDR" \
    VAULT_NAMESPACE="$namespace" \
    VAULT_TOKEN="$ADMIN_TOKEN" \
    vault kv get -wrap-ttl=60m -format=json secret/story 2>&1
  )
  status=$?
  set -e

  if (( status != 0 )); then
    echo "❌ Vault kv get failed for $email in $namespace"
    echo "   Response was:"
    echo "$resp"
    echo
    continue
  fi

  if ! echo "$resp" | jq . >/dev/null 2>&1; then
    echo "❌ Vault did not return valid JSON for $email"
    echo "   Response was:"
    echo "$resp"
    echo
    continue
  fi

  wrapped_token=$(echo "$resp" | jq -r '.wrap_info.token')

  if [[ -z "$wrapped_token" || "$wrapped_token" == "null" ]]; then
    echo "❌ Failed to extract wrapped token for $email"
    echo "   Raw response:"
    echo "$resp"
    echo
    continue
  fi

  # CSV row
  echo "${first},${last},${email},${namespace},${username},${wrapped_token}" >> "$CSV_OUTPUT"

  # JSON array element (also include namespace_suffix for completeness)
  json_entry=$(jq -n \
    --arg first "$first" \
    --arg last "$last" \
    --arg email "$email" \
    --arg namespace "$namespace" \
    --arg ns_suffix "$ns_suffix" \
    --arg username "$username" \
    --arg token "$wrapped_token" \
    '{
      first_name:       $first,
      last_name:        $last,
      email:            $email,
      namespace:        $namespace,
      namespace_suffix: $ns_suffix,
      username:         $username,
      wrapped_token:    $token
    }')

  if $first_item; then
    echo "  $json_entry" >> "$JSON_OUTPUT"
    first_item=false
  else
    echo "  ,$json_entry" >> "$JSON_OUTPUT"
  fi
done < "$entries_file"

echo ']}' >> "$JSON_OUTPUT"

echo "✅ Wrapped tokens written to:"
echo "   - $CSV_OUTPUT"
echo "   - $JSON_OUTPUT"
