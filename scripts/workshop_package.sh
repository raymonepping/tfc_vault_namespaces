#!/usr/bin/env bash
set -euo pipefail

# workshop_package.sh
# Create a distributable archive for a workshop:
# - env/*.env        (per-attendee environments)
# - meta/*.csv       (credentials + wrapped tokens)
# - tfvars/*.json    (Terraform attendees.auto.tfvars.json)
# - input/tickets.csv (original attendee CSV, if present)
#
# Usage:
#   ./workshop_package.sh
#
# Output:
#   ./workshop_package_YYYYMMDD_HHMMSS.zip   (or .tar.gz fallback)

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

usage() {
  cat <<EOF
${BOLD}Workshop packaging helper${RESET}  ${DIM}(v${VERSION})${RESET}
Create a zip/tar.gz bundle with all attendee-facing artifacts.

It collects (if present):
  ${BLUE}env/${RESET}
    • output/*.env                      ${DIM}# per-attendee Vault env files${RESET}

  ${BLUE}meta/${RESET}
    • output/credentials.csv
    • output/wrapped_story_tokens.csv

  ${BLUE}tfvars/${RESET}
    • output/attendees.auto.tfvars.json

  ${BLUE}input/${RESET}
    • input/tickets.csv                 ${DIM}# original attendee CSV${RESET}

Usage:
  ${GREEN}$0${RESET}

The archive will be created in:
  ${BLUE}${ROOT_DIR}${RESET}
as:
  ${DIM}workshop_package_YYYYMMDD_HHMMSS.zip${RESET}
(or .tar.gz if zip is not available).
EOF
}

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

echo "${BOLD}📦 Workshop package builder${RESET}"

# ────────────────────────────────────────────────────────────────
# Collect env files
# ────────────────────────────────────────────────────────────────
if [[ ! -d "$OUTPUT_DIR" ]]; then
  error "Output directory not found: ${OUTPUT_DIR}"
  echo "Run ./workshop.sh prepare or ./generate_credentials.sh first."
  exit 1
fi

mapfile -t ENV_FILES < <(find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.env' 2>/dev/null | sort || true)

if ((${#ENV_FILES[@]} == 0)); then
  warn "No .env files found in ${OUTPUT_DIR}."
  warn "Run ./generate_credentials.sh before packaging."
  exit 1
fi

ok "Found ${#ENV_FILES[@]} attendee .env files to include."

# Optional companions
CREDENTIALS_CSV="${OUTPUT_DIR}/credentials.csv"
TOKENS_CSV="${OUTPUT_DIR}/wrapped_story_tokens.csv"
TFVARS_JSON="${OUTPUT_DIR}/attendees.auto.tfvars.json"
TICKETS_CSV="${INPUT_DIR}/tickets.csv"

# ────────────────────────────────────────────────────────────────
# Create staging directory
# ────────────────────────────────────────────────────────────────
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/workshop_pkg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

mkdir -p \
  "${STAGING_DIR}/env" \
  "${STAGING_DIR}/meta" \
  "${STAGING_DIR}/tfvars" \
  "${STAGING_DIR}/input"

info "Staging files in: ${STAGING_DIR}"

# env/*.env
for f in "${ENV_FILES[@]}"; do
  cp "$f" "${STAGING_DIR}/env/"
done
ok "Copied .env files → env/"

# meta/*.csv
if [[ -f "$CREDENTIALS_CSV" ]]; then
  cp "$CREDENTIALS_CSV" "${STAGING_DIR}/meta/"
  ok "Included credentials.csv → meta/"
else
  warn "credentials.csv not found – skipping."
fi

if [[ -f "$TOKENS_CSV" ]]; then
  cp "$TOKENS_CSV" "${STAGING_DIR}/meta/"
  ok "Included wrapped_story_tokens.csv → meta/"
else
  warn "wrapped_story_tokens.csv not found – skipping."
fi

# tfvars/*.json
if [[ -f "$TFVARS_JSON" ]]; then
  cp "$TFVARS_JSON" "${STAGING_DIR}/tfvars/"
  ok "Included attendees.auto.tfvars.json → tfvars/"
else
  warn "attendees.auto.tfvars.json not found – skipping."
fi

# input/tickets.csv
if [[ -f "$TICKETS_CSV" ]]; then
  cp "$TICKETS_CSV" "${STAGING_DIR}/input/"
  ok "Included tickets.csv → input/"
else
  warn "input/tickets.csv not found – skipping."
fi

# ────────────────────────────────────────────────────────────────
# Create archive
# ────────────────────────────────────────────────────────────────
timestamp="$(date +%Y%m%d_%H%M%S)"
ARCHIVE_BASE="workshop_package_${timestamp}"
ARCHIVE_PATH=""

if command -v zip >/dev/null 2>&1; then
  ARCHIVE_PATH="${ROOT_DIR}/${ARCHIVE_BASE}.zip"
  info "Creating zip archive: ${ARCHIVE_PATH}"
  (
    cd "$STAGING_DIR"
    # zip contents as env/, meta/, tfvars/, input/
    zip -r "$ARCHIVE_PATH" . >/dev/null
  )
  ok "Zip archive created."
else
  ARCHIVE_PATH="${ROOT_DIR}/${ARCHIVE_BASE}.tar.gz"
  info "zip not found, falling back to tar.gz: ${ARCHIVE_PATH}"
  (
    cd "$STAGING_DIR"
    tar czf "$ARCHIVE_PATH" .
  )
  ok "tar.gz archive created."
fi

echo
ok "Workshop package ready:"
echo "   ${BLUE}${ARCHIVE_PATH}${RESET}"
echo
info "Contents:"
echo "   env/   → per-attendee .env files"
echo "   meta/  → credentials.csv, wrapped_story_tokens.csv (if present)"
echo "   tfvars/→ attendees.auto.tfvars.json (if present)"
echo "   input/ → tickets.csv (if present)"
echo
echo "${DIM}You can now share this archive with attendees or instructors.${RESET}"
