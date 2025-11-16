#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

# Base output dir (default: ./output, overridable via WORKSHOP_OUTPUT_DIR)
OUTPUT_DIR="${WORKSHOP_OUTPUT_DIR:-${ROOT_DIR}/output}"
mkdir -p "$OUTPUT_DIR"

INPUT_FILE="${1:-${OUTPUT_DIR}/attendees.auto.tfvars.json}"
CSV_OUTPUT="${2:-${OUTPUT_DIR}/credentials.csv}"
JSON_OUTPUT="${3:-${OUTPUT_DIR}/credentials.json}"

# Optional: load .env to get TF_VAR_vault_address, etc.
ENV_FILE="${ROOT_DIR}/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

VAULT_ADDR_RESOLVED="${TF_VAR_vault_address:-${VAULT_ADDR:-}}"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "❌ Input file '$INPUT_FILE' not found."
  echo "Usage: $0 [attendees.auto.tfvars.json] [csv_output] [json_output]"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq is required but not installed."
  exit 1
fi

# Sanity-check JSON
if ! jq . "$INPUT_FILE" >/dev/null 2>&1; then
  echo "❌ '$INPUT_FILE' is not valid JSON. Regenerate it via convert_2_tfvars.sh."
  exit 1
fi

echo "🔄 Generating workshop credentials from:"
echo "   TFVARS → $INPUT_FILE"
echo "   CSV    → $CSV_OUTPUT"
echo "   JSON   → $JSON_OUTPUT"

# CSV header
echo "first_name,last_name,email,namespace,username,password" > "$CSV_OUTPUT"

# JSON header
echo '{"credentials":[' > "$JSON_OUTPUT"
first_item=true

# We'll put env files in ROOT_DIR:
# <namespace_suffix>.env  e.g. jorg.env, raymon-e.env, raymon-b.env
entries_file="$(mktemp)"
trap 'rm -f "$entries_file"' EXIT

jq -c '.attendees | to_entries[]' "$INPUT_FILE" > "$entries_file"

while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue

  first=$(echo "$entry"  | jq -r '.value.first_name')
  last=$(echo  "$entry"  | jq -r '.value.last_name')
  email=$(echo "$entry"  | jq -r '.value.email')
  # Provided by convert_2_tfvars.sh
  ns_suffix=$(echo "$entry" | jq -r '.value.namespace_suffix // empty')

  # Username based on first name (lowercased)
  username=$(echo "$first" | tr '[:upper:]' '[:lower:]')

  # Backward compatibility: if namespace_suffix missing, fall back to username
  if [[ -z "$ns_suffix" || "$ns_suffix" == "null" ]]; then
    ns_suffix="$username"
    echo "⚠️  No namespace_suffix for ${email}, falling back to '${ns_suffix}'" >&2
  fi

  namespace="admin/team_${ns_suffix}"
  password="VaultWorkshop-${username}!"

  # CSV row
  echo "${first},${last},${email},${namespace},${username},${password}" >> "$CSV_OUTPUT"

  # JSON object
  json_entry=$(jq -n \
    --arg first "$first" \
    --arg last "$last" \
    --arg email "$email" \
    --arg namespace "$namespace" \
    --arg username "$username" \
    --arg password "$password" \
    --arg ns_suffix "$ns_suffix" \
    '{
      first_name:       $first,
      last_name:        $last,
      email:            $email,
      namespace:        $namespace,
      namespace_suffix: $ns_suffix,
      username:         $username,
      password:         $password
    }')

  if $first_item; then
    echo "  $json_entry" >> "$JSON_OUTPUT"
    first_item=false
  else
    echo "  ,$json_entry" >> "$JSON_OUTPUT"
  fi

  # Per-user .env file – use namespace_suffix to avoid collisions
  env_file="${ROOT_DIR}/${ns_suffix}.env"

  {
    echo "# Vault workshop environment for $first $last <$email>"
    if [[ -n "$VAULT_ADDR_RESOLVED" ]]; then
      echo "VAULT_ADDR=\"$VAULT_ADDR_RESOLVED\""
    else
      echo "# VAULT_ADDR not resolved from .env – set it manually:"
      echo "# VAULT_ADDR=\"https://your-hcp-vault-address:8200\""
    fi
    echo "VAULT_NAMESPACE=\"$namespace\""
    echo "VAULT_USERNAME=\"$username\""
    echo "VAULT_PASSWORD=\"$password\""
    echo
    echo "# Optional: Terraform Cloud / HCP Terraform (to be filled by attendee)"
    echo "TFE_HOST=\"app.terraform.io\""
    echo "TFE_TOKEN=\"\""
    echo
    echo "# Optional: Terraform variables if they run TF against Vault"
    echo "TF_VAR_vault_address=\"${VAULT_ADDR_RESOLVED:-}\""
    echo "# TF_VAR_vault_admin_token=\"\"  # do NOT set this to the global admin token"
  } > "$env_file"

  echo "📝 Wrote env file → $(basename "$env_file")"

done < "$entries_file"

echo ']}' >> "$JSON_OUTPUT"

echo
echo "✅ Credentials written to:"
echo "   - $CSV_OUTPUT"
echo "   - $JSON_OUTPUT"
