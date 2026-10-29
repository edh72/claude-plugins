#!/usr/bin/env bash
# dev-loop state keeper. The build-loop skill calls this for every decision that must not
# be left to the model: which task comes next, which step of it, the rework limit, and the
# usage log. All state lives in .dev-loop/ in the repo, so a fresh session (or one that was
# compacted) picks up at the exact step.
#
#   loop.sh init [--max-rework N] [--stop-after TASK-ID|none]   start or continue a run (puts the work on a branch)
#   loop.sh next                      print the one next step, as JSON
#   loop.sh show TASK-ID              print one task from the task list
#   loop.sh phase TASK-ID qa|verdict  record that the previous step finished (checks its file exists)
#   loop.sh verdict-input TASK-ID     short summary of the handoff and QA report, plus the rule-based verdict
#   loop.sh approve TASK-ID           task done
#   loop.sh rework TASK-ID "issues"   send back to the developer (blocks the task past the limit)
#   loop.sh block TASK-ID "reason"    give up on this task, carry on with the rest
#   loop.sh escalate TASK-ID "question"   stop the run with a question for Ed
#   loop.sh answer "text"             record Ed's answer and let the run continue
#   loop.sh finish                    mark the run finished
#   loop.sh status                    short human summary
#
# Needs bash 3.2+ and jq.
set -euo pipefail

DIR="${DEV_LOOP_DIR:-.dev-loop}"
TASKS="$DIR/tasks.json"
STATE="$DIR/state.json"
LOG_JSONL="$DIR/usage.jsonl"
LOG_MD="$DIR/usage-log.md"

die() { echo "dev-loop: $*" >&2; exit 1; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
epoch() { date +%s; }
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

need_tasks() { [ -f "$TASKS" ] || die "no task list at $TASKS (run the plan-tasks skill first)"; }
need_state() { [ -f "$STATE" ] || die "no run started (run: loop.sh init)"; }

# Write state atomically: update [jq args…] 'filter'. The filter is the last argument.
update() {
    local tmp="$STATE.tmp" filter="${!#}" args=("${@:1:$#-1}")
    jq --arg now "$(now)" ${args[@]+"${args[@]}"} "($filter) | . + {updated_at: \$now}" "$STATE" > "$tmp" || die "state update failed"
    mv "$tmp" "$STATE"
}

current_task() { jq -r '.current.task // empty' "$STATE"; }
check_current() { [ "$(current_task)" = "$1" ] || die "$1 is not the task in progress ($(current_task))"; }

# ---------- usage log ----------
# Context size and cost, read from Claude Code's own transcript of this session (the
# coordinator) and of its subagents. Prices per million tokens: [input, output, cache read];
# cache writes cost 1.25x input (5 minutes) or 2x (1 hour). The Sonnet and Haiku figures match
# what Claude Code itself reported (total_cost_usd) to the cent in the Oct 2026 test runs.
transcript() {
    local sid="${CLAUDE_CODE_SESSION_ID:-}" base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
    [ -n "$sid" ] || return 1
    ls "$base"/*/"$sid.jsonl" 2>/dev/null | head -1
}
USAGE_JQ='
  def price(m): if (m|test("haiku")) then [0.10,0.50,0.01] elif (m|test("opus")) then [4,20,0.20] else [2,10,0.10] end;
  def cost(u; m): price(m) as $p
    | (u.cache_creation.ephemeral_5m_input_tokens // (if u.cache_creation then 0 else (u.cache_creation_input_tokens // 0) end)) as $c5
    | (u.cache_creation.ephemeral_1h_input_tokens // 0) as $c1
    | ($p[0] * ((u.input_tokens // 0) + 1.25 * $c5 + 2 * $c1) + $p[2] * (u.cache_read_input_tokens // 0)
       + $p[1] * (u.output_tokens // 0)) / 1000000;
  [ .[] | select(.type == "assistant" and .message.usage != null) ]
  | (group_by(.message.id) | map(last)) as $msgs
  | { cost: ($msgs | map(cost(.message.usage; .message.model // "")) | add // 0),
      output_tokens: ($msgs | map(.message.usage.output_tokens // 0) | add // 0),
      context: (last // null | if . == null then 0 else (.message.usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)) end),
      compactions: 0 }'

log_usage() {
    local task="$1" outcome="$2" attempts="$3" t sid coord subs prev row
    t="$(transcript || true)"
    sid="${CLAUDE_CODE_SESSION_ID:-unknown}"
    if [ -z "$t" ] || [ ! -f "$t" ]; then
        row="$(jq -nc --arg task "$task" --arg outcome "$outcome" --argjson attempts "$attempts" --arg at "$(now)" \
            '{task:$task, outcome:$outcome, attempts:$attempts, at:$at, observable:false}')"
    else
        coord="$(jq -s "$USAGE_JQ" "$t")"
        coord="$(jq -c --argjson n "$(jq -c 'select(.type == "system" and .subtype == "compact_boundary")' "$t" 2>/dev/null | wc -l | tr -d ' ')" '.compactions = $n' <<<"$coord")"
        subs='{"cost":0,"output_tokens":0,"context":0}'
        if ls "${t%.jsonl}"/subagents/*.jsonl >/dev/null 2>&1; then
            subs="$(cat "${t%.jsonl}"/subagents/*.jsonl | jq -sc "$USAGE_JQ" 2>/dev/null || echo "$subs")"
        fi
        prev="$( [ -f "$LOG_JSONL" ] && jq -sc --arg sid "$sid" '[.[] | select(.session == $sid)] | last // {}' "$LOG_JSONL" || echo '{}')"
        row="$(jq -nc --arg task "$task" --arg outcome "$outcome" --argjson attempts "$attempts" --arg at "$(now)" \
            --arg sid "$sid" --argjson c "$coord" --argjson s "$subs" --argjson p "$prev" '
            { task:$task, outcome:$outcome, attempts:$attempts, at:$at, session:$sid, observable:true,
              coordinator_context: $c.context,
              coordinator_context_growth: ($c.context - ($p.coordinator_context // 0)),
              coordinator_compactions: $c.compactions,
              coordinator_cost_total: $c.cost, subagent_cost_total: $s.cost,
              coordinator_cost: ($c.cost - ($p.coordinator_cost_total // 0)),
              subagent_cost: ($s.cost - ($p.subagent_cost_total // 0)),
              new_session: ($p == {}) }
            | .task_cost = (.coordinator_cost + .subagent_cost)')"
    fi
    echo "$row" >> "$LOG_JSONL"
    if [ ! -f "$LOG_MD" ]; then
        cat > "$LOG_MD" <<'EOF'
# dev-loop usage log

One row per task, written when the task is approved or blocked. Context is the coordinator's
context size (tokens) after the task; costs are estimated from list prices. "new" in the last
column means the first task of a new session, so its growth and cost start from that session's
own start-up.

| Task | Outcome | Attempts | Coordinator context | Growth | Coordinator $ | Subagents $ | Task $ | Compactions | Session |
|---|---|---|---|---|---|---|---|---|---|
EOF
    fi
    jq -r 'if .observable then
        "| \(.task) | \(.outcome) | \(.attempts) | \(.coordinator_context) | \(.coordinator_context_growth) | \(.coordinator_cost*1000|round/1000) | \(.subagent_cost*1000|round/1000) | \(.task_cost*1000|round/1000) | \(.coordinator_compactions) | \(.session[0:8])\(if .new_session then " new" else "" end) |"
      else "| \(.task) | \(.outcome) | \(.attempts) | not observable | | | | | | |" end' <<<"$row" >> "$LOG_MD"
}

# ---------- commands ----------
cmd="${1:-}"; shift || true
case "$cmd" in
init)
    need_tasks
    jq -e '.tasks | type == "array" and length > 0' "$TASKS" >/dev/null || die "$TASKS has no tasks"
    MAX=3 STOP=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --max-rework) MAX="$2"; shift 2 ;;
            --stop-after) STOP="$2"; shift 2 ;;
            *) die "unknown option $1" ;;
        esac
    done
    mkdir -p "$DIR/handoffs" "$DIR/qa"
    git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
    BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
    case "$BRANCH" in
        main|master|HEAD|trunk|develop|production)
            NEW="dev-loop/$(date +%Y%m%d-%H%M)"
            git checkout -q -b "$NEW" 2>/dev/null || git checkout -q --orphan "$NEW"
            BRANCH="$NEW" ;;
    esac
    if [ ! -f "$STATE" ]; then
        jq -n --arg b "$BRANCH" --argjson max "$MAX" --arg stop "$STOP" --arg now "$(now)" --slurpfile t "$TASKS" '
            { status: "running", branch: $b, max_rework: $max, stop_after: (if $stop == "" or $stop == "none" then null else $stop end),
              done: [], blocked: [], remaining: [$t[0].tasks[].id], current: null, question: null,
              started_at: $now, updated_at: $now }' > "$STATE"
        echo "Started run on branch $BRANCH."
    else
        # Tasks added to the list since the run started join the end of "remaining".
        update --slurpfile t "$TASKS" --arg b "$BRANCH" --argjson max "$MAX" --arg stop "$STOP" '
            .branch = $b | .max_rework = $max
            | (if $stop == "none" then .stop_after = null elif $stop != "" then .stop_after = $stop else . end)
            | (.done + (.blocked | map(.id)) + .remaining) as $known
            | .remaining += [$t[0].tasks[].id | select(. as $id | $known | index($id) | not)]
            | if .status == "finished" and (.remaining | length) > 0 then .status = "running" else . end'
        echo "Continuing run on branch $BRANCH."
    fi
    "$0" status
    ;;
next)
    need_state; need_tasks
    STATUS="$(jq -r .status "$STATE")"
    if [ "$STATUS" = waiting_for_ed ]; then
        jq -c '{action: "wait_for_ed", task: .current.task, question: .question}' "$STATE"; exit 0
    fi
    if [ -n "$(current_task)" ]; then
        jq -c '.current as $c | {action: (if $c.phase == "developer" and $c.attempt > 1 then "rework" else $c.phase end),
            task: $c.task, attempt: $c.attempt, reworks_left: (.max_rework - ($c.attempt - 1)), issues: $c.issues}' "$STATE"
        exit 0
    fi
    STOP="$(jq -r '.stop_after // empty' "$STATE")"
    if [ -n "$STOP" ] && jq -e --arg s "$STOP" '(.done + (.blocked|map(.id))) | index($s)' "$STATE" >/dev/null; then
        jq -c --arg s "$STOP" '{action: "stop_requested", after: $s, remaining: .remaining}' "$STATE"; exit 0
    fi
    # First remaining task, in list order, whose dependencies are all done. A task that depends
    # on a blocked task is blocked too.
    for id in $(jq -r '.remaining[]' "$STATE"); do
        deps="$(jq -c --arg id "$id" '.tasks[] | select(.id == $id) | .dependencies // []' "$TASKS")"
        blocked_dep="$(jq -r --argjson d "$deps" '[.blocked[].id] as $b | $d[] | select(. as $x | $b | index($x))' "$STATE" | head -1)"
        if [ -n "$blocked_dep" ]; then
            update --arg id "$id" --arg r "depends on $blocked_dep, which is blocked" \
                '.remaining -= [$id] | .blocked += [{id: $id, reason: $r}]'
            log_usage "$id" "blocked (depends on $blocked_dep)" 0
            continue
        fi
        if jq -e --argjson d "$deps" '. as $s | all($d[]; . as $x | $s.done | index($x))' "$STATE" >/dev/null; then
            update --arg id "$id" --argjson t "$(epoch)" \
                '.current = {task: $id, phase: "developer", attempt: 1, issues: null, phase_started: $t}'
            jq -c '{action: "developer", task: .current.task, attempt: 1, reworks_left: .max_rework}' "$STATE"
            exit 0
        fi
    done
    if [ "$(jq '.remaining | length' "$STATE")" -eq 0 ]; then
        jq -c '{action: "finished", done: .done, blocked: .blocked}' "$STATE"
    else
        jq -c '{action: "stuck", reason: "remaining tasks wait on dependencies that are not done", remaining: .remaining, blocked: .blocked}' "$STATE"
    fi
    ;;
show)
    need_tasks
    jq -e --arg id "${1:?task id}" '.tasks[] | select(.id == $id)' "$TASKS" || die "no task $1"
    ;;
phase)
    need_state; TASK="${1:?task id}"; PHASE="${2:?phase}"; check_current "$TASK"
    STARTED="$(jq -r '.current.phase_started // 0' "$STATE")"
    case "$PHASE" in
        qa)
            F="$DIR/handoffs/$TASK.md"
            [ -f "$F" ] || die "no handoff at $F: the developer step did not finish (send it back with: rework $TASK \"no handoff written\")"
            [ "$(mtime "$F")" -gt "$STARTED" ] || die "$F was not rewritten in this developer step (send it back with rework)" ;;
        verdict)
            F="$DIR/qa/$TASK.md"
            [ -f "$F" ] || die "no QA report at $F: run the QA step again"
            [ "$(mtime "$F")" -gt "$STARTED" ] || die "$F was not rewritten in this QA step: run QA again" ;;
        developer) ;;
        *) die "unknown phase $PHASE (developer, qa, verdict)" ;;
    esac
    update --arg p "$PHASE" --argjson t "$(epoch)" '.current.phase = $p | .current.phase_started = $t'
    echo "$TASK: next step is $PHASE."
    ;;
verdict-input)
    need_state; TASK="${1:?task id}"
    H="$DIR/handoffs/$TASK.md"; Q="$DIR/qa/$TASK.md"
    field() { grep -m1 -i "^$1:" "$2" 2>/dev/null | sed "s/^[^:]*:[[:space:]]*//" | tr -d '\r' || true; }
    block() { awk -v k="$1" 'tolower($0) ~ "^"k":" {on=1; next} on && /^[a-z_]+:/ {on=0} on && NF {print}' "$2" 2>/dev/null || true; }
    echo "== handoff ($H)"
    echo "status: $(field status "$H")"
    echo "tests_passing: $(field tests_passing "$H")"
    echo "questions_for_architect:"; block questions_for_architect "$H"
    echo "== QA report ($Q)"
    QS="$(field status "$Q" | tr 'A-Z' 'a-z')"; REC="$(field recommendation "$Q" | tr 'A-Z' 'a-z')"
    echo "status: $QS"
    echo "recommendation: $REC"
    echo "test_suite_result: $(field test_suite_result "$Q")"
    echo "acceptance_criteria_review:"; CRIT="$(block acceptance_criteria_review "$Q")"; echo "$CRIT"
    echo "issues:"; block issues "$Q"
    # Rule-based verdict. Approve only on a clean pass; anything unclear counts as rework.
    LOWCRIT="$(echo "$CRIT" | grep -vi '(optional)' | tr 'A-Z' 'a-z')"
    if echo "$REC" | grep -q escalat; then MECH=escalate
    elif [ "$QS" = pass ] && echo "$REC" | grep -q '^approve' && [ -n "$CRIT" ] \
         && ! echo "$LOWCRIT" | grep -q -e 'not met' -e 'unable to verify' -e 'partial'; then MECH=approve
    else MECH=rework; fi
    echo "== rule-based verdict: $MECH"
    ;;
approve)
    need_state; TASK="${1:?task id}"; check_current "$TASK"
    A="$(jq -r .current.attempt "$STATE")"
    update --arg id "$TASK" '.done += [$id] | .remaining -= [$id] | .current = null'
    log_usage "$TASK" approved "$A"
    echo "$TASK approved."
    ;;
rework)
    need_state; TASK="${1:?task id}"; ISSUES="${2:?issues}"; check_current "$TASK"
    A="$(jq -r .current.attempt "$STATE")"; MAX="$(jq -r .max_rework "$STATE")"
    if [ $((A - 1)) -ge "$MAX" ]; then
        update --arg id "$TASK" --arg r "rework limit ($MAX) reached. Last issues: $ISSUES" \
            '.blocked += [{id: $id, reason: $r}] | .remaining -= [$id] | .current = null'
        log_usage "$TASK" "blocked (rework limit)" "$A"
        echo "$TASK blocked: rework limit ($MAX) reached."
    else
        update --arg i "$ISSUES" --argjson t "$(epoch)" \
            '.current.attempt += 1 | .current.phase = "developer" | .current.issues = $i | .current.phase_started = $t'
        echo "$TASK sent back for rework (attempt $((A + 1)), $((MAX - A)) reworks left after this one)."
    fi
    ;;
block)
    need_state; TASK="${1:?task id}"; REASON="${2:?reason}"; check_current "$TASK"
    A="$(jq -r .current.attempt "$STATE")"
    update --arg id "$TASK" --arg r "$REASON" '.blocked += [{id: $id, reason: $r}] | .remaining -= [$id] | .current = null'
    log_usage "$TASK" blocked "$A"
    echo "$TASK blocked."
    ;;
escalate)
    need_state; TASK="${1:?task id}"; QUESTION="${2:?question}"
    update --arg q "$QUESTION" '.status = "waiting_for_ed" | .question = $q'
    { echo "# Question for Ed"; echo; echo "Task: $TASK"; echo; echo "$QUESTION"; echo; echo "Answer by starting build-loop again with the answer, for example: /dev-loop:build-loop answer: <your answer>"; } > "$DIR/question.md"
    echo "Run stopped. Question saved in $DIR/question.md."
    ;;
answer)
    need_state; ANSWER="${1:?answer}"
    Q="$(jq -r '.question // ""' "$STATE")"
    { echo "## $(now)"; echo; echo "Question: $Q"; echo; echo "Answer: $ANSWER"; echo; } >> "$DIR/answers.md"
    update '.status = "running" | .question = null'
    rm -f "$DIR/question.md"
    echo "Answer recorded in $DIR/answers.md. Run continues."
    ;;
finish)
    need_state
    update '.status = "finished"'
    echo "Run marked finished."
    ;;
log-usage)
    # Write a usage row by hand (for testing, or after a failed write): log-usage TASK-ID outcome attempts
    log_usage "${1:?task id}" "${2:-manual}" "${3:-0}"
    ;;
status)
    need_state
    jq -r '"status: \(.status)   branch: \(.branch)   max reworks per task: \(.max_rework)",
        "done (\(.done|length)): \(.done|join(", "))",
        "blocked (\(.blocked|length)): \(.blocked|map("\(.id) (\(.reason))")|join("; "))",
        "remaining (\(.remaining|length)): \(.remaining|join(", "))",
        (if .current then "in progress: \(.current.task), step \(.current.phase), attempt \(.current.attempt)" else "in progress: none" end),
        (if .question then "waiting for Ed: \(.question)" else empty end)' "$STATE"
    if [ -f "$LOG_JSONL" ]; then
        jq -rs 'map(select(.observable)) | "logged cost so far: $\((map(.task_cost) | add // 0) * 100 | round / 100) over \(length) task rows; coordinator context now: \(last.coordinator_context // "?") tokens"' "$LOG_JSONL"
    fi
    ;;
*)
    sed -n '2,20p' "$0"; exit 1 ;;
esac
