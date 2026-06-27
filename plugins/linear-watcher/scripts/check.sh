#!/usr/bin/env bash
# check.sh — the zero-token "anything in the Todo lane?" query.
# Pure curl against Linear's GraphQL API. No model tokens, no jq dependency.
#
#   exit 0  -> one or more issues exist (prints "NEW <n>" then identifiers)
#   exit 1  -> none ("NONE")
#   exit 2  -> no API key configured
#   exit 3  -> no LINEAR_PROJECT_ID for this repo (watcher inert here)

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/config.sh"

if [ -z "${LINEAR_API_KEY:-}" ]; then
  echo "NO_KEY (set LINEAR_API_KEY or ~/.config/linear-watcher/key)" >&2
  exit 2
fi
if [ -z "${LINEAR_PROJECT_ID:-}" ]; then
  echo "NO_PROJECT (set LINEAR_PROJECT_ID for this repo)" >&2
  exit 3
fi

BODY=$(cat <<JSON
{"query":"{ issues(filter:{project:{id:{eq:\\"$LINEAR_PROJECT_ID\\"}},state:{type:{eq:\\"$LINEAR_STATE_TYPE\\"}}}){nodes{identifier title}} }"}
JSON
)

RESP="$(curl -s --max-time 20 -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$BODY")"

COUNT="$(printf '%s' "$RESP" | grep -o '"identifier":"[^"]*"' | wc -l | tr -d ' ')"

if [ "${COUNT:-0}" -gt 0 ]; then
  echo "NEW $COUNT"
  printf '%s' "$RESP" | grep -o '"identifier":"[^"]*"' | sed 's/"identifier":"//; s/"$//'
  exit 0
else
  echo "NONE"
  exit 1
fi
