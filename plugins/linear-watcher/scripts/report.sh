#!/usr/bin/env bash
# report.sh — SessionStart reporter. Wraps check.sh in a friendly one-liner.
# Always exits 0 so it can never block a session from starting.
#
# Stays SILENT in repos that haven't configured a LINEAR_PROJECT_ID (exit 3)
# or have no API key (exit 2), so a global install is harmless everywhere.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Recover the repo root from the hook payload if Claude Code didn't export it.
if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
  payload="$(cat 2>/dev/null || true)"
  cwd="$(printf '%s' "$payload" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')"
  [ -n "${cwd:-}" ] && export CLAUDE_PROJECT_DIR="$cwd"
fi

out="$("$DIR/check.sh" 2>/dev/null)"; rc=$?

case "$rc" in
  0)
    n="$(printf '%s' "$out" | head -1 | awk '{print $2}')"
    ids="$(printf '%s' "$out" | tail -n +2 | paste -sd ', ' -)"
    # shellcheck source=/dev/null
    phrase="$(. "$DIR/config.sh"; printf '%s' "$LINEAR_TRIGGER_PHRASE")"
    echo "Linear watcher: $n item(s) waiting in the Todo lane ($ids). Say \"$phrase\" to work them."
    ;;
  1)
    echo "Linear watcher: Todo lane is empty."
    ;;
  *)
    : # 2 = no key, 3 = repo not configured -> stay silent
    ;;
esac
exit 0
