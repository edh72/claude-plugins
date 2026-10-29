#!/usr/bin/env bash
# PreToolUse guard for Bash. While a dev-loop run is in progress in this repo (.dev-loop/state.json
# with status "running"), refuse pushes and deploys, for the coordinator and its subagents alike.
# Anywhere else it does nothing, so installing the plugin never gets in the way of normal work.
INPUT="$(cat)"
CWD="$(jq -r '.cwd // empty' <<<"$INPUT")"
CMD="$(jq -r '.tool_input.command // empty' <<<"$INPUT")"
[ -n "$CMD" ] || exit 0
ROOT="$(cd "${CWD:-.}" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "${CWD:-.}")"
STATE="$ROOT/.dev-loop/state.json"
[ -f "$STATE" ] || exit 0
[ "$(jq -r .status "$STATE" 2>/dev/null)" = running ] || exit 0
if grep -Eq '(^|[;&|(`[:space:]])git([[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+|--?[^[:space:]]+))*[[:space:]]+push([[:space:]]|$)' <<<"$CMD" \
   || grep -Eiq '((npm|pnpm|yarn|bun|composer)[[:space:]]+(run[[:space:]]+)?deploy|(^|[[:space:]])(vercel|netlify|fly|flyctl|forge|envoy|vapor|serverless|sls|cdk|firebase)[[:space:]].*deploy|kubectl[[:space:]]+apply|terraform[[:space:]]+apply)' <<<"$CMD"; then
    echo "dev-loop: pushing and deploying are not allowed during a build run. Commit locally on the run's branch; Ed reviews and pushes." >&2
    exit 2
fi
exit 0
