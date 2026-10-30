---
name: dev-loop
description: Start here. Looks at the repo and runs the next dev-loop step (spec, plan-tasks or build-loop), or says where a run stands. Use when Ed says "dev-loop", "keep going", "carry on", "what's next", or asks for the status of a build.
argument-hint: "[status] [anything Ed said, passed on to the next skill]"
---
# Dev loop

Words from Ed (may be empty): $ARGUMENTS

Find where this repo is, from the files only, then call the Skill tool with the skill for that step, passing Ed's words on. One skill per call.

| The repo has | Next |
| --- | --- |
| No `SPEC.md` | `spec` (interview, or convert what Ed gave) |
| `SPEC.md` without a `Status: approved` line under its title | `spec`, to finish it and get his approval |
| An approved `SPEC.md`, no `.dev-loop/tasks.json` | `plan-tasks` |
| `.dev-loop/tasks.json`, no `.dev-loop/state.json` | `build-loop` |
| `.dev-loop/state.json` with status `running` or `waiting_for_ed` | `build-loop` (it resumes at the exact step; an answer from Ed goes in as `answer: …`) |
| `.dev-loop/state.json` with status `finished` | No skill. Reply with the first lines of `.dev-loop/summary.md`: what works and what's left for Ed. |

**Status only.** When Ed's words are just "status" (or "where are we", "how's it going"), call no skill and change nothing. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/loop.sh status` when there is a state file, and answer in one or two spoken sentences, for example: "Task 4 of 8, QA is checking it. 3 approved, none blocked, nothing waiting on you." Without a state file, say which step the repo is at from the table.

Done when you called the one skill for the step, or answered the status, in a reply short enough to hear read aloud.
