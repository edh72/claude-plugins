# dev-loop

A Claude Code plugin that builds an approved spec task by task, with a developer, a QA checker
and a verdict on every task, until there is a working version for review. It replaces the old
dev-agents Laravel app (queue job, database, UI, API) with skills, two subagents and files in
the repo. The prompts are the old ones, trimmed of the parts that only made sense for the
Laravel engine.

## Use

```
/dev-loop:spec          # interview or convert -> SPEC.md
/dev-loop:plan-tasks    # SPEC.md -> .dev-loop/tasks.json (files, acceptance criteria, dependencies)
/dev-loop:build-loop    # run until there is a working version, or a question for Ed
```

`build-loop` takes optional words: `max rework 2`, `stop after TASK-005`, `answer: <text>`
(the answer to a question the run stopped on).

Headless:

```
claude -p "/dev-loop:build-loop" --plugin-dir <path>/plugins/dev-loop --max-budget-usd 5 \
  --permission-mode acceptEdits --allowedTools "Bash(git:*)" "Bash(node:*)" "Bash(bash:*)" "Bash(jq:*)" Read Write Edit Glob Grep Agent Skill
```

## How a task runs

The main session is the architect and coordinator. For each task, in the order of the task list:

1. **developer** subagent implements it, commits, writes `.dev-loop/handoffs/<task>.md`.
2. **qa** subagent checks it against the acceptance criteria on its own (it is given only the
   task ID: it reads the criteria, the handoff and the code) and writes `.dev-loop/qa/<task>.md`.
3. **verdict** by the coordinator: approve, rework (back to 1, at most 3 times by default; an
   unclear QA result counts as rework), block, or stop with a question for Ed.

`scripts/loop.sh` decides everything that must not depend on the model: which task and step
come next, whether the step's file was written, the rework limit, tasks blocked by a blocked
dependency, and the per-task usage log. It writes `.dev-loop/state.json` after every step, so a
new or compacted session resumes at the exact step.

## Files in the repo

| Path | What |
|---|---|
| `SPEC.md` | the spec |
| `.dev-loop/tasks.json` | the task list (optional `test_command`) |
| `.dev-loop/state.json` | done / blocked / remaining, and the current task's step and attempt |
| `.dev-loop/handoffs/`, `.dev-loop/qa/` | the developer's handoff and the QA report per task |
| `.dev-loop/usage-log.md` (+ `usage.jsonl`) | per task: coordinator context size and growth, estimated cost |
| `.dev-loop/question.md`, `answers.md` | an open question for Ed, and his answers |
| `.dev-loop/summary.md` | written at the end: what was built, how to try it, what is blocked |

## Guardrails

- Works on a branch: if the repo is on main/master, `init` creates `dev-loop/<date-time>`.
- Never pushes or deploys: the prompts say so, and a PreToolUse hook refuses `git push` and
  common deploy commands while a run is in progress (only in repos with a running
  `.dev-loop/state.json`; it does nothing anywhere else).

## Models

`agents/developer.md` and `agents/qa.md` set `model: haiku`, which is what the stamina test
used. For real work, change it to `sonnet` (or remove the line to use the session's model).
