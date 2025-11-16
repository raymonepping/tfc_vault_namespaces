#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

INPUT_DIR="${ROOT_DIR}/input"
OUTPUT_DIR="${ROOT_DIR}/output"
VERSION="1.0.0"

# ────────────────────────────────────────────────────────────────
# Colors & formatting
# ────────────────────────────────────────────────────────────────
BOLD=$'\e[1m'
DIM=$'\e[2m'
RED=$'\e[31m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
BLUE=$'\e[34m'
RESET=$'\e[0m'

error() {
  echo "${RED}❌ $*${RESET}" >&2
}

info() {
  echo "${BLUE}ℹ️  $*${RESET}"
}

ok() {
  echo "${GREEN}✅ $*${RESET}"
}

warn() {
  echo "${YELLOW}⚠️  $*${RESET}"
}

step() {
  # Usage: step "1/7" "CSV → JSON (extended) into output/"
  local idx="$1"
  shift
  echo
  echo "${YELLOW}▶ [${idx}]${RESET} $*"
}

usage() {
  cat <<EOF
${BOLD}Workshop orchestration helper${RESET}  ${DIM}(v${VERSION})${RESET}
${DIM}Glue from CSV → JSON → Terraform → Vault → Credentials → Wrapped stories${RESET}

${BOLD}📂 Directory layout (expected)${RESET}

  ${BLUE}./input/${RESET}
    └── tickets.csv          ${DIM}# Source CSV (you can have more files here)${RESET}

  ${BLUE}./output/${RESET}
    ├── tickets.json
    ├── tickets_extended.json
    ├── attendees.auto.tfvars.json
    ├── credentials.csv
    ├── credentials.json
    ├── wrapped_story_tokens.csv
    └── wrapped_story_tokens.json

${BOLD}🛠 Commands${RESET}

  ${GREEN}$0 prepare <tickets.csv>${RESET}
    ${DIM}Prepare Terraform inputs only (no Vault changes).${RESET}
      • convert_2_json.sh --extended <tickets.csv>
        → writes ${BLUE}output/tickets.json${RESET} and ${BLUE}output/tickets_extended.json${RESET}
      • convert_2_tfvars.sh
        → reads ${BLUE}output/tickets_extended.json${RESET}
          and writes ${BLUE}output/attendees.auto.tfvars.json${RESET}

  ${GREEN}$0 full <tickets.csv> [--skip-tf] [--skip-creds] [--skip-wrap]${RESET}
    ${DIM}End-to-end instructor pipeline.${RESET}
      1) CSV → JSON (extended)
      2) JSON → attendees.auto.tfvars.json
      3) workshop_preflight.sh
      4) terraform init -upgrade
      5) terraform apply -auto-approve -var-file=${BLUE}output/attendees.auto.tfvars.json${RESET}
      6) generate_credentials.sh   ${DIM}# CSV + JSON + per-attendee .env${RESET}
      7) issue_wrapped_story.sh    ${DIM}# one-time wrapped story tokens${RESET}

      ${DIM}Flags:${RESET}
        • ${GREEN}--skip-tf${RESET}     ${DIM}Skip preflight + terraform init/apply${RESET}
        • ${GREEN}--skip-creds${RESET}  ${DIM}Skip credential generation${RESET}
        • ${GREEN}--skip-wrap${RESET}   ${DIM}Skip wrapped story token issuance${RESET}

  ${GREEN}$0 preflight${RESET}
    ${DIM}Only run workshop_preflight.sh (Vault reachability, token, tools).${RESET}

  ${GREEN}$0 status${RESET}
    ${DIM}Show a quick status overview (input, outputs, Vault namespaces).${RESET}

  ${GREEN}$0 nuke [--dry-run] [--include-orphans]${RESET}
    ${DIM}Call workshop_nuke_namespaces.sh with the same flags.${RESET}
    ${YELLOW}⚠️  Instructor-only safety net. Respects NUKE_ALLOWED=true in .env.${RESET}

${BOLD}🧷 Global flags${RESET}
  ${GREEN}-h, --help${RESET}      Show this help
  ${GREEN}-V, --version${RESET}   Show script version

${BOLD}📝 Notes${RESET}
  • When you pass just ${DIM}tickets.csv${RESET}, the script first looks in: ${BLUE}input/tickets.csv${RESET}
    If not found, it falls back to a file named ${DIM}tickets.csv${RESET} in the current directory.
  • All generated files are written to ${BLUE}./output${RESET} for easy cleanup and sharing.
  • Use ${GREEN}full${RESET} once per workshop; use ${GREEN}prepare${RESET} when you only want to regenerate tfvars.

${BOLD}📎 Examples${RESET}
  ${GREEN}$0 prepare tickets.csv${RESET}
  ${GREEN}$0 full tickets.csv${RESET}
  ${GREEN}$0 full tickets.csv --skip-tf --skip-wrap${RESET}
  ${GREEN}$0 preflight${RESET}
  ${GREEN}$0 status${RESET}
  ${GREEN}$0 nuke --dry-run --include-orphans${RESET}
EOF
}

require_script() {
  local s="$1"
  if [[ ! -x "$ROOT_DIR/$s" ]]; then
    if [[ -f "$ROOT_DIR/$s" ]]; then
      error "Script '$s' exists but is not executable. Run: chmod +x $s"
    else
      error "Required script '$s' not found in $ROOT_DIR"
    fi
    exit 1
  fi
}

resolve_csv_path() {
  local csv_arg="$1"
  local candidate

  # Prefer input/<file> if it exists
  candidate="${INPUT_DIR}/${csv_arg}"
  if [[ -f "$candidate" ]]; then
    echo "$candidate"
    return 0
  fi

  # Fall back to path as given (relative or absolute)
  if [[ -f "$csv_arg" ]]; then
    echo "$csv_arg"
    return 0
  fi

  error "CSV file not found as '${INPUT_DIR}/${csv_arg}' or '${csv_arg}'"
  exit 1
}

# ────────────────────────────────────────────────────────────────
# Argument dispatch
# ────────────────────────────────────────────────────────────────

CMD="${1:-}"

case "$CMD" in
  ""|-h|--help|help)
    usage
    exit 0
    ;;
  -V|--version|version)
    echo "workshop.sh v${VERSION}"
    exit 0
    ;;
esac

case "$CMD" in
  prepare)
    CSV_ARG="${2:-}"

    if [[ -z "$CSV_ARG" ]]; then
      error "Missing CSV file argument."
      echo "   Usage: $0 prepare tickets.csv" >&2
      exit 1
    fi

    require_script "convert_2_json.sh"
    require_script "convert_2_tfvars.sh"

    CSV_FILE="$(resolve_csv_path "$CSV_ARG")"

    echo "${BOLD}🧩 Workshop prepare pipeline${RESET}"
    info "Using CSV: ${CSV_FILE}"

    step "1/2" "CSV → JSON (extended) into output/"
    ./convert_2_json.sh --extended "$CSV_FILE"

    step "2/2" "JSON → output/attendees.auto.tfvars.json"
    ./convert_2_tfvars.sh

    echo
    ok "prepare completed."
    ;;

  full)
    CSV_ARG="${2:-}"

    if [[ -z "$CSV_ARG" ]]; then
      error "Missing CSV file argument."
      echo "   Usage: $0 full tickets.csv [--skip-tf] [--skip-creds] [--skip-wrap]" >&2
      exit 1
    fi

    # Parse flags after CSV
    shift 2
    SKIP_TF=false
    SKIP_CREDS=false
    SKIP_WRAP=false

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --skip-tf) SKIP_TF=true ;;
        --skip-creds) SKIP_CREDS=true ;;
        --skip-wrap) SKIP_WRAP=true ;;
        *)
          error "Unknown flag for 'full': $1"
          echo "   Usage: $0 full tickets.csv [--skip-tf] [--skip-creds] [--skip-wrap]" >&2
          exit 1
          ;;
      esac
      shift
    done

    # Check all required scripts once up front
    require_script "convert_2_json.sh"
    require_script "convert_2_tfvars.sh"
    require_script "workshop_preflight.sh"
    require_script "generate_credentials.sh"
    require_script "issue_wrapped_story.sh"

    CSV_FILE="$(resolve_csv_path "$CSV_ARG")"

    echo "${BOLD}🚀 Full workshop orchestration pipeline${RESET}"
    info "Using CSV: ${CSV_FILE}"
    info "Input dir:  ${INPUT_DIR}"
    info "Output dir: ${OUTPUT_DIR}"

    step "1/7" "CSV → JSON (extended) into output/"
    ./convert_2_json.sh --extended "$CSV_FILE"

    step "2/7" "JSON → output/attendees.auto.tfvars.json"
    ./convert_2_tfvars.sh

    if [[ "$SKIP_TF" == false ]]; then
      step "3/7" "Workshop preflight check"
      ./workshop_preflight.sh

      step "4/7" "Terraform init (-upgrade)"
      terraform init -upgrade

      step "5/7" "Terraform apply (using output/attendees.auto.tfvars.json)"
      terraform apply -auto-approve -var-file="${OUTPUT_DIR}/attendees.auto.tfvars.json"
    else
      step "3-5/7" "Skipping Terraform preflight + init + apply (--skip-tf)"
    fi

    if [[ "$SKIP_CREDS" == false ]]; then
      step "6/7" "Generate per-attendee credentials + .env files"
      ./generate_credentials.sh
    else
      step "6/7" "Skipping credential generation (--skip-creds)"
    fi

    if [[ "$SKIP_WRAP" == false ]]; then
      step "7/7" "Issue wrapped story tokens"
      ./issue_wrapped_story.sh
    else
      step "7/7" "Skipping wrapped story tokens (--skip-wrap)"
    fi

    echo
    ok "full pipeline completed successfully."
    echo "${DIM}Tip: hand out the .env files + wrapped_story_tokens.csv to attendees.${RESET}"
    ;;

  preflight)
    require_script "workshop_preflight.sh"
    echo "${BOLD}🧪 Running workshop preflight only${RESET}"
    ./workshop_preflight.sh
    ;;

  status)
    echo "${BOLD}📊 Workshop status overview${RESET}"
    echo

    # Try to load .env if present (for Vault info)
    ENV_FILE="${ROOT_DIR}/.env"
    if [[ -f "$ENV_FILE" ]]; then
      set -a; . "$ENV_FILE"; set +a
      ok "Loaded .env → ${ENV_FILE}"
    else
      warn ".env not found – Vault checks will be limited."
    fi

    echo
    echo "${BOLD}📂 Input${RESET}"
    TICKETS_PATH="${INPUT_DIR}/tickets.csv"
    if [[ -f "$TICKETS_PATH" ]]; then
      # count attendees (lines - 1 header)
      line_count=$(wc -l < "$TICKETS_PATH" | tr -d '[:space:]')
      if [[ "$line_count" -gt 1 ]]; then
        attendee_count=$(( line_count - 1 ))
      else
        attendee_count=0
      fi
      ok "input/tickets.csv present (${attendee_count} attendee rows)"
    else
      warn "input/tickets.csv not found"
    fi

    echo
    echo "${BOLD}📤 Output files${RESET}"

    # helper to check output files
    check_output_file() {
      local file="$1"
      local label="$2"
      local path="${OUTPUT_DIR}/${file}"
      if [[ -f "$path" ]]; then
        ok "${label} (${file})"
      else
        warn "Missing ${label} (${file})"
      fi
    }

    check_output_file "tickets.json"              "Basic tickets JSON"
    check_output_file "tickets_extended.json"     "Extended tickets JSON"
    check_output_file "attendees.auto.tfvars.json" "Terraform tfvars"
    check_output_file "credentials.csv"           "Credentials CSV"
    check_output_file "credentials.json"          "Credentials JSON"
    check_output_file "wrapped_story_tokens.csv"  "Wrapped story tokens CSV"
    check_output_file "wrapped_story_tokens.json" "Wrapped story tokens JSON"

    # Extra counts if jq is available
    if command -v jq >/dev/null 2>&1; then
      if [[ -f "${OUTPUT_DIR}/attendees.auto.tfvars.json" ]]; then
        count_tfvars=$(jq '.attendees | length' "${OUTPUT_DIR}/attendees.auto.tfvars.json" 2>/dev/null || echo "?")
        info "attendees.auto.tfvars.json has ${count_tfvars} attendee entries"
      fi
      if [[ -f "${OUTPUT_DIR}/credentials.csv" ]]; then
        line_count=$(wc -l < "${OUTPUT_DIR}/credentials.csv" | tr -d '[:space:]')
        creds_count=$(( line_count > 0 ? line_count - 1 : 0 ))
        info "credentials.csv has ${creds_count} rows (excluding header)"
      fi
      if [[ -f "${OUTPUT_DIR}/wrapped_story_tokens.csv" ]]; then
        line_count=$(wc -l < "${OUTPUT_DIR}/wrapped_story_tokens.csv" | tr -d '[:space:]')
        tokens_count=$(( line_count > 0 ? line_count - 1 : 0 ))
        info "wrapped_story_tokens.csv has ${tokens_count} rows (excluding header)"
      fi
    else
      warn "jq not found – skipping detailed counts."
    fi

    echo
    echo "${BOLD}🔐 Vault namespaces (best effort)${RESET}"
    if command -v vault >/dev/null 2>&1 && [[ -n "${TF_VAR_vault_address:-}" && -n "${TF_VAR_vault_admin_token:-}" ]]; then
      export VAULT_ADDR="${TF_VAR_vault_address}"
      export VAULT_TOKEN="${TF_VAR_vault_admin_token}"
      if command -v jq >/dev/null 2>&1; then
        ns_json="$(vault list -format=json sys/namespaces 2>/dev/null || true)"
        if [[ -n "$ns_json" && "$ns_json" != "null" ]]; then
          ns_count=$(echo "$ns_json" | jq 'length' 2>/dev/null || echo "?")
          ok "Vault reachable at ${VAULT_ADDR} (namespaces: ${ns_count})"
          # Show names if small
          if [[ "$ns_count" != "?" && "$ns_count" -le 10 ]]; then
            ns_list=$(echo "$ns_json" | jq -r '.[]' 2>/dev/null || true)
            if [[ -n "$ns_list" ]]; then
              echo "${DIM}   Namespaces:${RESET}"
              while IFS= read -r ns; do
                echo "     • ${ns}"
              done <<< "$ns_list"
            fi
          fi
        # Post-nuke detection:
        # If no team_* namespaces exist, show a clean "freshly nuked" hint.
        if command -v jq >/dev/null 2>&1; then
            team_count=$(echo "$ns_json" | jq '[ .[] | select(startswith("team_")) ] | length')
            if [[ "$team_count" -eq 0 ]]; then
            echo
            info "🧹 No team_* namespaces found — Vault looks freshly nuked."
            fi
        fi
        else
          warn "Vault reachable but sys/namespaces returned no data (or token lacks permission)."
        fi
      else
        if vault status >/dev/null 2>&1; then
          ok "Vault reachable at ${VAULT_ADDR} (no jq, skipping namespace list)"
        else
          warn "Vault not reachable or status failed."
        fi
      fi
    else
      warn "Skipping Vault namespace checks (vault CLI or env vars missing)."
    fi

    echo
    ok "Status check complete."
    ;;

  nuke)
    require_script "workshop_nuke_namespaces.sh"
    echo "${BOLD}💣 Workshop namespace nuke helper${RESET}"
    echo "${YELLOW}⚠️  This will call workshop_nuke_namespaces.sh with your flags.${RESET}"
    shift  # pass remaining flags through
    ./workshop_nuke_namespaces.sh "$@"
    ;;

  *)
    error "Unknown command: $CMD"
    echo
    echo "Tip: run '$0 --help' for usage."
    echo
    usage
    exit 1
    ;;
esac
