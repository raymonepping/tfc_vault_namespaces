#!/usr/bin/env bash
set -euo pipefail

# Base dirs – kept in sync with convert_2_json.sh / workshop.sh
OUTPUT_DIR="${WORKSHOP_OUTPUT_DIR:-output}"

mkdir -p "$OUTPUT_DIR"

# Defaults:
#   input:  output/tickets_extended.json
#   output: output/attendees.auto.tfvars.json
INPUT_FILE="${OUTPUT_DIR}/tickets_extended.json"
OUTPUT_FILE="${OUTPUT_DIR}/attendees.auto.tfvars.json"

# Parse args:
#  - 1st positional: input file (optional)
#  - 2nd positional: output file (optional)
if [[ $# -ge 1 ]]; then
  if [[ "$1" == */* ]]; then
    # Explicit path
    INPUT_FILE="$1"
  else
    # Relative to OUTPUT_DIR by default
    INPUT_FILE="${OUTPUT_DIR}/$1"
  fi
fi

if [[ $# -ge 2 ]]; then
  if [[ "$2" == */* ]]; then
    OUTPUT_FILE="$2"
  else
    OUTPUT_FILE="${OUTPUT_DIR}/$2"
  fi
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "❌ Input file '$INPUT_FILE' not found."
  echo "Usage: $0 [tickets_extended.json] [attendees.auto.tfvars.json]"
  echo "       (default input:  ${OUTPUT_DIR}/tickets_extended.json)"
  echo "       (default output: ${OUTPUT_DIR}/attendees.auto.tfvars.json)"
  exit 1
fi

for cmd in jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Required command '$cmd' not found" >&2
    exit 1
  fi
done

echo "🔄 Converting $INPUT_FILE → $OUTPUT_FILE ..."

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

############################################
# STEP 1 — Normalize attendees
############################################
# Input (array):
# [
#   {
#     "first_name": "Raymon",
#     "last_name": "Epping",
#     "email": "raymon.epping@ibm.com",
#     "company": "HashiCorp an IBM company"
#   },
#   ...
# ]
#
# Normalized:
# [
#   {
#     "first_name": "...",
#     "last_name": "...",
#     "email": "...",
#     "company": "...",
#     "first_lower": "raymon",
#     "last_initial": "e",
#     "id": "raymon-epping-at-ibm-com"
#   },
#   ...
# ]

jq '
  map(
    . + {
      first_lower:  (.first_name | ascii_downcase),
      last_initial: (.last_name  | ascii_downcase | .[0:1]),
      id: (
        .email
        | ascii_downcase
        | gsub("@"; "-at-")
        | gsub("[^a-z0-9-]"; "-")
      )
    }
  )
' "$INPUT_FILE" > "$TMP"

############################################
# STEP 2 — Log duplicate first names
############################################

echo
jq -r '
  group_by(.first_lower)[]
  | select(length > 1)
  | (
      "⚠️ Duplicate first name detected: \"" + .[0].first_lower + "\" (" + (length|tostring) + " attendees)\n"
      +
      ( .[]
        | "   - \(.email) → \(.first_lower)-\(.last_initial)\n"
      )
    )
' "$TMP" || true
echo

############################################
# STEP 3 — Generate attendees.auto.tfvars.json
############################################
# If a first name is unique:
#   namespace_suffix = "raymon"
# If duplicated:
#   namespace_suffix = "raymon-e" / "raymon-b" (first + "-" + last_initial)

jq '
  . as $all
  | {
      attendees:
        (
          reduce $all[] as $a ({}; . + {
            ($a.id): {
              email:      $a.email,
              first_name: $a.first_name,
              last_name:  $a.last_name,
              company:    $a.company,
              namespace_suffix:
                (
                  if ( $all
                      | map(select(.first_lower == $a.first_lower))
                      | length
                    ) > 1
                  then ($a.first_lower + "-" + $a.last_initial)
                  else $a.first_lower
                  end
                )
            }
          })
        )
    }
' "$TMP" > "$OUTPUT_FILE"

echo "✅ Wrote Terraform tfvars JSON → $OUTPUT_FILE"
