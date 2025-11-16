#!/usr/bin/env bash
set -euo pipefail

# workshop_nuke_namespaces.sh
#
# Hard reset for workshop namespaces.
#
# - Uses output/attendees.auto.tfvars.json to determine expected namespaces (team_<suffix>)
# - Optionally also nukes "orphan" namespaces in admin/ that start with "team_"
# - Deletes namespaces via Vault API (sys/namespaces), not Terraform
# - Protected by NUKE_ALLOWED=true in .env + explicit confirmation
#
# Usage:
#   ./workshop_nuke_namespaces.sh                       # nukes only namespaces from tfvars
#   ./workshop_nuke_namespaces.sh --dry-run             # preview only
#   ./workshop_nuke_namespaces.sh --include-orphans
#   ./workshop_nuke_namespaces.sh --include-orphans --dry-run

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

OUTPUT_DIR="${ROOT_DIR}/output"
INPUT_FILE="${OUTPUT_DIR}/attendees.auto.tfvars.json"
INCLUDE_ORPHANS=false
DRY_RUN=false

# Parse flags (correctly handles "no args")
for arg in "$@"; do
  case "$arg" in
    --include-orphans)
      INCLUDE_ORPHANS=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    *)
      echo "❌ Unknown argument: $arg" >&2
      echo "Usage: $0 [--include-orphans] [--dry-run]" >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "❌ $INPUT_FILE not found. Run ./convert_2_tfvars.sh (or ./workshop.sh prepare/full) first." >&2
  exit 1
fi

if [[ ! -f ".env" ]]; then
  echo "❌ .env not found. Need TF_VAR_vault_address and TF_VAR_vault_admin_token." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq is required." >&2
  exit 1
fi

if ! command -v vault >/dev/null 2>&1; then
  echo "❌ vault CLI is required." >&2
  exit 1
fi

# Load admin context + nuke flag from .env
set -a
# shellcheck disable=SC1091
. ./.env
set +a

VAULT_ADDR="${TF_VAR_vault_address:?TF_VAR_vault_address must be set in .env}"
ADMIN_TOKEN="${TF_VAR_vault_admin_token:?TF_VAR_vault_admin_token must be set in .env}"
PARENT_NAMESPACE="admin"
NUKE_ALLOWED="${NUKE_ALLOWED:-false}"

echo "🧨 Workshop namespace nuke"
echo "   VAULT_ADDR       = $VAULT_ADDR"
echo "   PARENT_NAMESPACE = $PARENT_NAMESPACE"
echo "   DRY_RUN          = $DRY_RUN"
echo "   INCLUDE_ORPHANS  = $INCLUDE_ORPHANS"
echo "   NUKE_ALLOWED     = $NUKE_ALLOWED"
echo

# Instructor-only guardrail
if [[ "$NUKE_ALLOWED" != "true" ]]; then
  echo "🚫 Nuke is not allowed. NUKE_ALLOWED is not set to 'true' in .env."
  echo "   To enable, add this line to your instructor .env (NEVER to student envs):"
  echo "     NUKE_ALLOWED=true"
  echo
  echo "   Then re-run: ./workshop_nuke_namespaces.sh"
  exit 1
fi

############################################
# 1) Namespaces from attendees.auto.tfvars.json
############################################

mapfile -t NS_FROM_TFVARS < <(
  jq -r '
    .attendees
    | to_entries[]
    | .value.namespace_suffix
      // (.value.first_name | ascii_downcase)
    | "team_" + .
  ' "$INPUT_FILE"
)

declare -A SEEN=()
for ns in "${NS_FROM_TFVARS[@]}"; do
  SEEN["$ns"]=1
done

############################################
# 2) Optional: detect orphans in admin/ that start with team_
############################################

NS_ORPHANS=()
if $INCLUDE_ORPHANS; then
  echo "🔍 Checking Vault for existing team_* namespaces under admin/ ..."

  tmp_ns_json="$(mktemp)"
  if VAULT_NAMESPACE="$PARENT_NAMESPACE" VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$ADMIN_TOKEN" \
       vault namespace list -format=json >"$tmp_ns_json" 2>/dev/null; then

    mapfile -t EXISTING < <(
      jq -r '.[]' "$tmp_ns_json" 2>/dev/null \
        | sed 's:/$::' \
        | grep '^team_' || true
    )

    for ns in "${EXISTING[@]}"; do
      if [[ -z "${SEEN[$ns]:-}" ]]; then
        NS_ORPHANS+=("$ns")
      fi
    done
  else
    echo "⚠️ Could not list namespaces under admin/. Skipping orphans detection." >&2
  fi
  rm -f "$tmp_ns_json"
fi

############################################
# 3) Build final list to delete
############################################

FINAL_NS=()
FINAL_NS+=("${NS_FROM_TFVARS[@]}")
FINAL_NS+=("${NS_ORPHANS[@]}")

# Remove duplicates
declare -A DEDUP=()
NS_UNIQ=()
for ns in "${FINAL_NS[@]}"; do
  [[ -z "$ns" ]] && continue
  if [[ -z "${DEDUP[$ns]:-}" ]]; then
    DEDUP["$ns"]=1
    NS_UNIQ+=("$ns")
  fi
done

if ((${#NS_UNIQ[@]} == 0)); then
  echo "✅ No namespaces found to delete. Nothing to do."
  exit 0
fi

############################################
# 4) Show plan
############################################

echo "🧹 The following namespaces will be deleted from Vault (child of admin/):"
for ns in "${NS_UNIQ[@]}"; do
  fq="admin/${ns}"
  if [[ " ${NS_FROM_TFVARS[*]} " == *" $ns "* ]]; then
    echo "   - $fq  (from tfvars)"
  else
    echo "   - $fq  (orphan in Vault)"
  fi
done
echo

if $DRY_RUN; then
  echo "📝 Dry-run mode enabled. No changes will be made."
  exit 0
fi

############################################
# 5) Final confirmation
############################################

echo "⚠️ This will irreversibly delete the namespaces above from Vault."
echo "   It will NOT touch your Terraform state file, only Vault itself."
echo
read -rp "Type YES_NUKE_WORKSHOP to continue: " confirm

if [[ "$confirm" != "YES_NUKE_WORKSHOP" ]]; then
  echo "❌ Cancelled. No namespaces were deleted."
  exit 1
fi

############################################
# 6) Delete via Vault API
############################################

echo
echo "🔥 Deleting namespaces from Vault..."

for ns in "${NS_UNIQ[@]}"; do
  fq="admin/${ns}"
  echo "   → Deleting $fq ..."
  if VAULT_NAMESPACE="$PARENT_NAMESPACE" VAULT_ADDR="$VAULT_ADDR" VAULT_TOKEN="$ADMIN_TOKEN" \
      vault delete "sys/namespaces/${ns}" >/dev/null 2>&1; then
    echo "     ✅ Deleted $fq"
  else
    echo "     ⚠️ Failed to delete $fq (check permissions or spelling)" >&2
  fi
done

echo
echo "🎉 Nuke complete. You can now safely re-run:"
echo "   terraform init && terraform apply -auto-approve"
