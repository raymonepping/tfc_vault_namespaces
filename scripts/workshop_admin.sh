#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Workshop Admin Utility
======================

Usage:
  $0 --nuke
  $0 --reset <email>
  $0 --list
  $0 --diagnostics

Commands:
  --nuke          Destroy Terraform state + all Vault namespaces created by this workshop.
                  Requires confirmation. Only for instructors.

  --reset <email> Reset a single attendee (Deletes namespace + recreates via Terraform)

  --list          List all workshop namespaces (admin/team_*)

  --diagnostics   Check Vault connection + admin token + namespace access
EOF
}

ENV_FILE=".env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ .env not found."
  exit 1
fi

set -a
. "$ENV_FILE"
set +a

VAULT_ADDR="${TF_VAR_vault_address:?Missing TF_VAR_vault_address}"
VAULT_TOKEN="${TF_VAR_vault_admin_token:?Missing TF_VAR_vault_admin_token}"

################################################################################
# Helper: List namespaces
################################################################################
list_namespaces() {
  echo "📂 Workshop namespaces:"
  VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
    vault list -format=json sys/namespaces \
    | jq -r '.[] | select(startswith("team_"))'
}

################################################################################
# Helper: Reset single namespace
################################################################################
reset_user() {
  local email="$1"
  id=$(echo "$email" | tr '[:upper:]' '[:lower:]' | tr '@.' '-')
  namespace=$(jq -r ".attendees.\"$id\".namespace_suffix" attendees.auto.tfvars.json)

  if [[ "$namespace" == "null" ]]; then
    echo "❌ User with email $email not found in attendees.auto.tfvars.json"
    exit 1
  fi

  local ns="team_${namespace}"

  echo "⚠️ Resetting attendee:"
  echo "   Email:      $email"
  echo "   Namespace:  admin/$ns"
  echo

  VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
    vault delete "sys/namespaces/$ns" || true

  echo "♻️  Namespace deleted. Reapplying Terraform..."
  terraform apply -auto-approve
}

################################################################################
# Helper: Full Nuke (state + Vault namespaces)
################################################################################
nuke_all() {
  echo "🔥 Nuke mode activated."
  echo "This will:"
  echo "  • Delete terraform.tfstate"
  echo "  • Delete all admin/team_* namespaces in Vault"
  echo "  • Fully rebuild workshop infrastructure"
  echo
  read -rp "Are you absolutely sure? Type YES_I_AM: " confirm

  if [[ "$confirm" != "YES_I_AM" ]]; then
    echo "❌ Cancelled."
    exit 1
  fi

  echo "💣 Removing Terraform state..."
  rm -f terraform.tfstate terraform.tfstate.backup

  echo "💣 Removing Vault namespaces:"
  for ns in $(VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" vault list -format=json sys/namespaces | jq -r '.[]'); do
    if [[ "$ns" == team_* ]]; then
      echo "  → Deleting: $ns"
      VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" \
        vault delete "sys/namespaces/$ns" || true
    fi
  done

  echo "♻️ Rebuilding workshop with Terraform..."
  terraform init -upgrade
  terraform apply -auto-approve

  echo "🎉 Nuke complete. Workshop reset."
}

################################################################################
# Diagnostics
################################################################################
diagnostics() {
  echo "🔍 Checking admin token..."
  VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$VAULT_TOKEN" vault status || true

  echo
  echo "🔍 Checking namespace listing..."
  list_namespaces
}

################################################################################
# Argument handling
################################################################################

case "${1:-}" in
  --list)
    list_namespaces
    ;;
  --reset)
    reset_user "${2:-}"
    ;;
  --nuke)
    nuke_all
    ;;
  --diagnostics)
    diagnostics
    ;;
  *)
    usage
    exit 1
    ;;
esac
