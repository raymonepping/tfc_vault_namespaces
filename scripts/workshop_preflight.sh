#!/usr/bin/env bash
set -euo pipefail

echo "🧪 Workshop preflight check"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
MISSING=0

########################################
# 1) Check .env
########################################
if [[ -f "$ENV_FILE" ]]; then
  echo "✅ Found .env → $ENV_FILE"
  # shellcheck disable=SC1090
  set -a; . "$ENV_FILE"; set +a
else
  echo "❌ .env not found at $ENV_FILE" >&2
  MISSING=1
fi

########################################
# 2) Check required binaries
########################################
for cmd in terraform vault jq; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "✅ $cmd is installed: $(command -v "$cmd")"
  else
    echo "❌ $cmd is NOT installed or not in PATH" >&2
    MISSING=1
  fi
done

########################################
# 3) Check required env vars (from .env)
########################################
REQUIRED_VARS=(
  "TF_VAR_vault_address"
  "TF_VAR_vault_admin_token"
)

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "❌ Missing required env var: $var" >&2
    MISSING=1
  else
    echo "✅ $var is set"
  fi
done

if (( MISSING > 0 )); then
  echo
  echo "🚫 Preflight failed. Fix the above issues and re-run ./workshop_preflight.sh"
  exit 1
fi

########################################
# 4) Check Vault status
########################################
export VAULT_ADDR="${TF_VAR_vault_address}"
echo
echo "🌐 Checking Vault at: $VAULT_ADDR"

if ! vault status >/dev/null 2>&1; then
  echo "❌ Could not reach Vault or 'vault status' failed" >&2
  exit 1
fi

vault status

########################################
# 5) Verify admin token can list namespaces
########################################
echo
echo "🔐 Verifying admin token capabilities (listing namespaces)..."

export VAULT_TOKEN="${TF_VAR_vault_admin_token}"

if ! vault list sys/namespaces >/dev/null 2>&1; then
  echo "❌ Admin token cannot list namespaces (sys/namespaces)" >&2
  echo "   Make sure TF_VAR_vault_admin_token is an admin-scoped token for HCP Vault." >&2
  exit 1
fi

echo "✅ Admin token can list namespaces"

echo
echo "🎉 Preflight successful. You are ready to run:"
echo "   terraform init && terraform apply -auto-approve"
