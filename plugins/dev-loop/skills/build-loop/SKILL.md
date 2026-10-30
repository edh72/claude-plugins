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
   Then run what was built for real, the way Ed would use it (start the command, open the app, call the endpoint), not only through the tests. Passing tests are not a working version (Oct 29: all 132 tests passed and the built command crashed on start).
   If the real run, or anything else at this point, shows the build falls short of the spec, don't stop to ask: the goal Ed approved is a working version. Append fix tasks to `.dev-loop/tasks.json` (same format, with acceptance criteria that include the real run), run `loop.sh init` to pick them up, and go back to the task loop. Small slips in SPEC.md (a leftover phrase, a typo) you fix directly. Do this at most twice; if it still doesn't work after two rounds of fixes, stop with a question. Tell Ed afterwards what you added and why, in the summary (Ed, Oct 29: "we really need the agents to just keep going and be smarter about things like this").
2. Steps only Ed could approve (`needs_ed` in the handoffs: changes to his settings, installs outside the repo). If SPEC.md's "Approved up front" section covers them, run them now, exactly as prepared, then run the built thing once more for real. If it doesn't, don't run them: they go in the reply as the one question, with the exact commands ready, so his yes finishes the job in one step.
3. Write `.dev-loop/summary.md`:
   - What was built, in a few lines.
   - How to try it: the exact commands to run the tests and to use what was built.
   - Blocked tasks, each with its reason, and the one question Ed needs to answer to unblock them.
   - The `[manual]` checks left for Ed, from the task list, each with how to do it.
   - The test suite result and the real run's result.
   - Total cost and the coordinator's context size, from the last line of `loop.sh status`.
   - Anything else worth knowing (what you fixed along the way, figures you corrected). It lives here, not in the reply.
4. If nothing is blocked, run `loop.sh finish`.
5. Commit with `[dev-loop] Summary` (state, logs and summary included).
6. Reply short enough to read on a phone: a line on what works, up to five bullets on what's left for Ed (blocked tasks, `[manual]` checks, steps that still need his yes), and at most one question. Send summary.md to Ed as a file if WhenBox is running; otherwise name it.

## Stopping with a question

When you escalate, commit `.dev-loop/` with `[dev-loop] Waiting for Ed`, then reply with only:

    QUESTION FOR ED (<task_id>): <the question, self-contained, with the options you see and your recommendation>

Keep it short enough to hear read aloud: two or three sentences, the options numbered 1, 2, 3 (never letters), and which one you suggest (Ed, Oct 29). One question per stop.

WhenBox carries the question to Ed, and his reply arrives in this session as his message: treat it as `answer: …` and carry on. In a session without WhenBox he starts this skill again with `answer: …`.

## Rules

- Work only on the branch `init` chose. Never push, never deploy, never merge. (A hook refuses pushes and deploys while a run is in progress.)
- Tasks come from the spec. The only tasks you add are the fix tasks in "Finishing", and the only changes you make to SPEC.md are the small slips described there; anything bigger is a question for Ed.
- Do not make product decisions; surface them.
- The order of tasks and the rework limit belong to the script. Do not skip, reorder or retry tasks yourself.
- If the conversation was compacted or you are unsure where you are, run `loop.sh status` and `loop.sh next`; the files are the truth.

Done when every task is approved or blocked, the built thing has run for real, summary.md is committed, and Ed has the short reply; or when the run stopped with one question for Ed.
