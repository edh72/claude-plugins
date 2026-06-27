#!/usr/bin/env bash
# watch.sh — the proactive watcher. Run via the agent's run_in_background tool.
# Polls the Todo lane every LINEAR_POLL_SECONDS and EXITS 0 (printing the notice)
# the moment items appear — which re-invokes the agent, even while you're idle.
# Sleeps at zero model-token cost otherwise.
#
# Exits 2 immediately if this repo isn't configured (no project / no key), so the
# agent doesn't keep a dead loop running.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$DIR/config.sh"

POLL="${LINEAR_POLL_SECONDS:-120}"

if [ -z "${LINEAR_PROJECT_ID:-}" ] || [ -z "${LINEAR_API_KEY:-}" ]; then
  echo "linear-watcher: not configured for this repo (no LINEAR_PROJECT_ID / API key) — watcher not started." >&2
  exit 2
fi

while :; do
  if out="$("$DIR/check.sh" 2>/dev/null)"; then   # check.sh exits 0 only when items exist
    echo "$out"
    exit 0
  fi
  sleep "$POLL"
done
