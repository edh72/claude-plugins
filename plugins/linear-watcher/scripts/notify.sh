#!/usr/bin/env bash
# notify.sh — UserPromptSubmit hook. Runs on every message you send and, if the
# Todo lane has items, prints a one-line notice. UserPromptSubmit stdout is
# injected into the model's context, so a mid-session Todo surfaces automatically
# with NO background loop and NO action required.
#
# Zero model tokens. Throttled so it hits the Linear API at most once per
# THROTTLE seconds; in between it replays the last result (so a pending Todo
# keeps surfacing every turn until it's worked out of the lane).
#
# Always exits 0; stays silent in repos with no LINEAR_PROJECT_ID / no API key.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THROTTLE=30

# Recover the repo root from the hook payload if Claude Code didn't export it.
if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
  payload="$(cat 2>/dev/null || true)"
  cwd="$(printf '%s' "$payload" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')"
  [ -n "${cwd:-}" ] && export CLAUDE_PROJECT_DIR="$cwd"
fi
PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"

key="$(printf '%s' "$PROJECT" | tr -c 'A-Za-z0-9' '_')"
cache="${TMPDIR:-/tmp}/linear-watcher-$key"
now="$(date +%s)"

# Within the throttle window: replay the cached notice (line 2+) and stop.
if [ -f "$cache" ]; then
  ts="$(head -1 "$cache" 2>/dev/null || true)"
  if [ -n "$ts" ] && [ "$((now - ts))" -lt "$THROTTLE" ]; then
    tail -n +2 "$cache"
    exit 0
  fi
fi

out="$("$DIR/check.sh" 2>/dev/null)"; rc=$?
msg=""
if [ "$rc" = "0" ]; then
  n="$(printf '%s' "$out" | head -1 | awk '{print $2}')"
  ids="$(printf '%s' "$out" | tail -n +2 | paste -sd ', ' -)"
  # shellcheck source=/dev/null
  phrase="$(. "$DIR/config.sh"; printf '%s' "$LINEAR_TRIGGER_PHRASE")"
  msg="[linear-watcher] $n item(s) waiting in the Linear Todo lane ($ids). When it fits, work them per the \"$phrase\" workflow."
fi

{ echo "$now"; printf '%s' "$msg"; } > "$cache" 2>/dev/null || true
printf '%s' "$msg"
exit 0
