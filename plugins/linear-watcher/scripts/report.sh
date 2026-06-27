#!/usr/bin/env bash
# report.sh — SessionStart hook. Two jobs, both as injected context:
#   1. Report the Todo lane status (user-visible).
#   2. Auto-arm directive: instruct the agent to start the background watcher
#      (watch.sh) via the run_in_background tool, so mid-session/idle Todos get
#      caught with nothing for anyone to remember.
# Always exits 0. Silent in repos with no LINEAR_PROJECT_ID / API key.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Recover the repo root from the hook payload if Claude Code didn't export it.
if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
  payload="$(cat 2>/dev/null || true)"
  cwd="$(printf '%s' "$payload" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')"
  [ -n "${cwd:-}" ] && export CLAUDE_PROJECT_DIR="$cwd"
fi
PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
# shellcheck source=/dev/null
. "$DIR/config.sh"

# Unconfigured repo -> stay completely silent.
if [ -z "${LINEAR_PROJECT_ID:-}" ] || [ -z "${LINEAR_API_KEY:-}" ]; then
  exit 0
fi

out="$("$DIR/check.sh" 2>/dev/null)"; rc=$?
case "$rc" in
  0)
    n="$(printf '%s' "$out" | head -1 | awk '{print $2}')"
    ids="$(printf '%s' "$out" | tail -n +2 | paste -sd ', ' -)"
    echo "Linear watcher: $n item(s) in the Todo lane ($ids). This IS your go signal — do NOT wait for the user to type \"$LINEAR_TRIGGER_PHRASE\". Work them now per the \"$LINEAR_TRIGGER_PHRASE\" workflow (finish what you can → Done; anything where your part is done but it needs the user's review/decision → post a recommendation comment and move it to your review/feedback status, NOT Backlog). A ticket you recently acted on reappearing here is the normal revision loop — the user re-opened it with NEW feedback, so read the newest comments and act on those rather than re-verifying it. Unless the user's first message directs you elsewhere."
    ;;
  1) echo "Linear watcher: Todo lane is empty." ;;
  *) exit 0 ;;   # transient error -> stay silent
esac

# --- Auto-arm directive (always emitted when configured) ---
cat <<EOF

[linear-watcher — auto-arm] To catch Todos that arrive mid-session (even while the user is idle), start the background watcher NOW if you have not already started it this session, using the run_in_background tool with the sandbox disabled:
  CLAUDE_PROJECT_DIR='$PROJECT' bash '$DIR/watch.sh'
It sleeps cheaply (zero tokens) and exits the instant a Todo appears, which re-invokes you. When it fires: work the lane per the "$LINEAR_TRIGGER_PHRASE" workflow, then re-arm it the same way. Never run a second copy if one is already running.
EOF
exit 0
