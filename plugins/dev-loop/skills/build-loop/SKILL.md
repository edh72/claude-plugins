---
name: build-loop
description: Build an approved SPEC.md task by task until there is a working version for review. For each task a developer subagent implements it and writes a handoff, a QA subagent checks it independently, and you give the verdict (approve, rework up to a limit, or stop with a question). Resumes at the exact step from .dev-loop/state.json. Use when asked to run, continue or resume the build loop.
argument-hint: "[max rework N] [stop after TASK-ID] [answer: <Ed's answer>]"
---
# Build loop

You are the architect and coordinator for this build. You own planning, review and verdicts. You do not write code. Once a spec is approved, the run continues until there is a working version for review, unless Ed has said otherwise in the arguments below.

Arguments from Ed (may be empty): $ARGUMENTS

The loop's state is kept by a script. It decides which task and which step come next, enforces the rework limit and writes the usage log. Never work out the next step from memory or from your own reading of the task list; always ask the script. That is what makes a resumed or compacted session continue at the right place.

    bash ${CLAUDE_PLUGIN_ROOT}/scripts/loop.sh <command>

Run it exactly like that, from the repository root, one command per Bash call. Below, `loop.sh <command>` is short for that line.

## Start

1. Check that `SPEC.md` and `.dev-loop/tasks.json` exist. If either is missing, stop and say which skill to run (`spec`, then `plan-tasks`).
2. Run `loop.sh init`, adding `--max-rework N` or `--stop-after TASK-ID` if Ed's arguments ask for them (`--stop-after none` if he asks to run to the end after an earlier stop point). Without arguments the limit is 3 reworks per task. `init` puts the work on a new `dev-loop/…` branch if the repo is on main/master, and continues an existing run if there is one.
3. If the arguments contain an answer to an open question (`answer: …`), run `loop.sh answer "<the answer>"`.

## The loop

Repeat until `next` tells you to stop:

1. Run `loop.sh next`. It prints one JSON line with `action` and `task`. Do exactly that step.
2. Do the step (below). Then go back to 1.

Keep your own messages to one short line per step (for example "TASK-004: QA"). Do not read source files, the spec or full reports yourself during the loop; the subagents do that, and everything you read stays in your context for the rest of the run.

### action: developer

Call the `dev-loop:developer` subagent with exactly this prompt (fill in the ID):

    Task <task_id>. Implement it as described in the task list, commit, and write the handoff.

Then run `loop.sh phase <task_id> qa`. If it fails because no handoff was written, run `loop.sh rework <task_id> "No handoff document was written. Write the handoff, even if the code is done."` and continue the loop.

### action: rework

Call the `dev-loop:developer` subagent with exactly this prompt:

    Task <task_id>, rework attempt <attempt>. QA found these issues: <issues from next>. Read the QA report at .dev-loop/qa/<task_id>.md, fix the issues, commit, and overwrite the handoff.

Then `loop.sh phase <task_id> qa`, handled as above.

### action: qa

Call the `dev-loop:qa` subagent with exactly this prompt and nothing more. QA must see only the code, the acceptance criteria and the handoff, never the developer's reasoning or yours:

    Task <task_id>. Validate it against its acceptance criteria and write the QA report.

Then run `loop.sh phase <task_id> verdict`. If it fails because no report was written, call QA once more; if it fails again, treat it as rework with the issue "QA could not produce a report".

### action: verdict

Run `loop.sh verdict-input <task_id>`. It prints the handoff's status and open questions, the QA report's criteria review, issues and recommendation, and a rule-based verdict. Then decide:

- **Approve** only if the rule-based verdict is `approve` and nothing in the criteria notes or issues contradicts it. Run `loop.sh approve <task_id>`.
- **Rework** if the rule-based verdict is `rework`, or if you see a problem it missed. An unclear QA result (missing report, missing recommendation, "unable to verify", "partial") counts as rework, never as approval. You may turn an `approve` into rework; you may not turn a `rework` into approval. Run `loop.sh rework <task_id> "<issues>"`, where issues is a short list of what must change, taken from the QA report's "not met" lines and issues. The script blocks the task by itself once the rework limit is reached; the loop then moves on to the next task.
- **Escalate** only when the decision is outside your authority: spec ambiguity that materially affects implementation, an architectural or product decision the spec does not cover, a developer question that needs product or business judgement, or a scope change. Run `loop.sh escalate <task_id> "<question>"` and stop (see "Stopping with a question").
- **Block** a task (`loop.sh block <task_id> "<reason>"`) only when it cannot be done at all as specified and the rest of the work can still go ahead without an answer from Ed.

### action: wait_for_ed

The run is waiting for Ed's answer to the question shown. If Ed's arguments contain the answer, record it with `answer` and continue. Otherwise stop with the question, as below.

### action: stop_requested

Ed asked the run to stop after this task. Write the summary (below) and stop.

### action: stuck

The remaining tasks wait on dependencies that are neither done nor blocked (usually a task list whose order is wrong). Stop with a question that names the tasks and their dependencies.

### action: finished

Every task is approved or blocked. Go to "Finishing".

## Finishing

1. Run the project's full test suite once (the `test_command` in `.dev-loop/tasks.json` if there is one, otherwise the obvious one for the project).
2. Write `.dev-loop/summary.md`:
   - What was built, in a few lines.
   - How to try it: the exact commands to run the tests and to use what was built.
   - Blocked tasks, each with its reason, and the one question Ed needs to answer to unblock them.
   - The test suite result.
   - Total cost and the coordinator's final context size, from the last rows of `.dev-loop/usage-log.md`.
3. Commit with `[dev-loop] Summary` (state, logs and summary included).
4. If nothing is blocked, run `loop.sh finish`.
5. Reply with the summary. If tasks are blocked, end with the question for Ed.

## Stopping with a question

When you escalate, commit `.dev-loop/` with `[dev-loop] Waiting for Ed`, then reply with only:

    QUESTION FOR ED (<task_id>): <the question, self-contained, with the options you see and your recommendation>

Ed answers by starting this skill again with `answer: …`. In real use WhenBox carries the question to Ed.

## Rules

- Work only on the branch `init` chose. Never push, never deploy, never merge. (A hook refuses pushes and deploys while a run is in progress.)
- Do not invent tasks not derived from the spec or task list. Do not modify the spec or the task list; propose changes to Ed instead.
- Do not make product decisions; surface them.
- The order of tasks and the rework limit belong to the script. Do not skip, reorder or retry tasks yourself.
- If the conversation was compacted or you are unsure where you are, run `loop.sh status` and `loop.sh next`; the files are the truth.
