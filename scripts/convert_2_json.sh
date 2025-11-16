#!/usr/bin/env bash
set -euo pipefail

# Base dirs (can be overridden by workshop.sh)
INPUT_DIR="${WORKSHOP_INPUT_DIR:-input}"
OUTPUT_DIR="${WORKSHOP_OUTPUT_DIR:-output}"

mkdir -p "$OUTPUT_DIR"

INPUT_FILE="${INPUT_DIR}/tickets.csv"
OUTPUT_FILE="${OUTPUT_DIR}/tickets.json"
EXTENDED_OUTPUT_FILE="${OUTPUT_DIR}/tickets_extended.json"
EXTENDED=false
DOMAIN_FILTER=""

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --extended)
      EXTENDED=true
      shift
      ;;
    --domain)
      DOMAIN_FILTER="${2:-}"
      shift 2
      ;;
    *)
      # Positional argument = input CSV
      # If it contains a slash, treat as explicit path
      # Otherwise, resolve relative to INPUT_DIR
      if [[ "$1" == */* ]]; then
        INPUT_FILE="$1"
      else
        INPUT_FILE="${INPUT_DIR}/$1"
      fi
      shift
      ;;
  esac
done

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "❌ Input file '$INPUT_FILE' not found."
  echo "Usage: $0 [--extended] [--domain domain1,domain2] [tickets.csv]"
  echo "       (default input: ${INPUT_DIR}/tickets.csv)"
  exit 1
fi

echo "🔄 Reading $INPUT_FILE"
echo "   Writing basic JSON     → $OUTPUT_FILE"
if [[ "$EXTENDED" == true ]]; then
  echo "   Writing extended JSON  → $EXTENDED_OUTPUT_FILE"
fi

###############################################
# Helper: filter by domain (comma-separated)
###############################################
filter_by_domain() {
  local domain_filter="$1"
  if [[ -z "$domain_filter" ]]; then
    cat
    return
  fi

  # Lowercase domains
  local lc_filter
  lc_filter="$(echo "$domain_filter" | tr '[:upper:]' '[:lower:]')"

  awk -v filter="$lc_filter" '
    BEGIN {
      n = split(filter, domains, ",")
      for (i = 1; i <= n; i++) {
        gsub(/^[ \t]+|[ \t]+$/, "", domains[i])
      }
    }
    {
      email = tolower($0)
      for (i = 1; i <= n; i++) {
        if (domains[i] != "" && index(email, domains[i]) > 0) {
          print $0
          break
        }
      }
    }
  '
}

###############################################
# Basic emails.json output
###############################################

emails_plain=$(
  tail -n +2 "$INPUT_FILE" \
    | awk -F';' '{print $3}' \
    | sed 's/^[ \t]*//;s/[ \t]*$//' \
    | grep -v '^$'
)

if [[ -n "$DOMAIN_FILTER" ]]; then
  echo "🔍 Applying domain filter: $DOMAIN_FILTER"
  emails_plain="$(printf "%s\n" "$emails_plain" | filter_by_domain "$DOMAIN_FILTER" || true)"
fi

emails_json=$(
  printf "%s\n" "$emails_plain" \
    | sort -u \
    | jq -R . \
    | jq -s .
)

jq -n --argjson emails "$emails_json" '{emails: $emails}' > "$OUTPUT_FILE"

echo "✅ Wrote basic email list → $OUTPUT_FILE"

###############################################
# Extended JSON output (if enabled)
###############################################
if [[ "$EXTENDED" == true ]]; then
  echo "🔧 Generating extended JSON..."

  extended_json=$(
    tail -n +2 "$INPUT_FILE" \
      | awk -F';' -v filter_domains="$DOMAIN_FILTER" '
        BEGIN {
          # Normalize domain filter once
          lc_filter = tolower(filter_domains)
          n = split(lc_filter, domains, ",")
          for (i = 1; i <= n; i++) {
            gsub(/^[ \t]+|[ \t]+$/, "", domains[i])
          }
        }
        {
          first_name = $1
          last_name  = $2
          email      = $3
          company    = $5

          gsub(/^[ \t]+|[ \t]+$/, "", first_name)
          gsub(/^[ \t]+|[ \t]+$/, "", last_name)
          gsub(/^[ \t]+|[ \t]+$/, "", email)
          gsub(/^[ \t]+|[ \t]+$/, "", company)

          if (email == "") next

          # Domain filter (if set)
          if (n > 0 && domains[1] != "") {
            e = tolower(email)
            allowed = 0
            for (i = 1; i <= n; i++) {
              if (domains[i] != "" && index(e, domains[i]) > 0) {
                allowed = 1
                break
              }
            }
            if (!allowed) next
          }

          printf("{\"first_name\":\"%s\", \"last_name\":\"%s\", \"email\":\"%s\", \"company\":\"%s\"}\n",
                 first_name, last_name, email, company)
      }' \
      | jq -s .
  )

  echo "$extended_json" | jq '.' > "$EXTENDED_OUTPUT_FILE"

  echo "✅ Wrote extended attendee JSON → $EXTENDED_OUTPUT_FILE"
fi

echo "🎉 All done."
