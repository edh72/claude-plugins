#!/usr/bin/env bash
# config.sh — resolve the linear-watcher tokenized values.
# Sourced by check.sh and report.sh. Do NOT `set -e` here (it would leak
# into the caller). Resolution order for each value:
#   1. environment variable (e.g. a repo's .claude/settings.json "env" block)
#   2. repo-local file        $PROJECT_DIR/.claude/linear-watcher.json
#   3. repo settings.json     $PROJECT_DIR/.claude/settings.json
#   4. built-in default
#
# PROJECT_DIR is the repo root: CLAUDE_PROJECT_DIR (set for hooks) or $PWD.

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

# Grep a flat "key":"value" out of a JSON file, anywhere (handles nesting in
# the settings.json "env" block since LINEAR_* keys are unambiguous). No jq dep.
_lw_grepkey(){
  [ -f "$2" ] || return 1
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$2" 2>/dev/null \
    | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//'
}

_lw_cfg(){            # _lw_cfg NAME DEFAULT
  local name="$1" def="$2" val
  val="$(printenv "$name" 2>/dev/null || true)"
  [ -z "$val" ] && val="$(_lw_grepkey "$name" "$PROJECT_DIR/.claude/linear-watcher.json" || true)"
  [ -z "$val" ] && val="$(_lw_grepkey "$name" "$PROJECT_DIR/.claude/settings.json" || true)"
  [ -z "$val" ] && val="$def"
  printf '%s' "$val"
}

LINEAR_PROJECT_ID="$(_lw_cfg LINEAR_PROJECT_ID '')"
LINEAR_STATE_TYPE="$(_lw_cfg LINEAR_STATE_TYPE 'unstarted')"
LINEAR_TRIGGER_PHRASE="$(_lw_cfg LINEAR_TRIGGER_PHRASE 'to-dos')"
LINEAR_POLL_SECONDS="$(_lw_cfg LINEAR_POLL_SECONDS '120')"

# API key — global secret. Never read from the repo. env var or a key file.
if [ -z "${LINEAR_API_KEY:-}" ]; then
  for _lw_kf in \
    "${LINEAR_API_KEY_FILE:-}" \
    "$HOME/.config/linear-watcher/key" \
    "$HOME/.config/wristy/linear-api-key"; do
    if [ -n "$_lw_kf" ] && [ -f "$_lw_kf" ]; then
      LINEAR_API_KEY="$(tr -d '[:space:]' < "$_lw_kf")"
      break
    fi
  done
fi
