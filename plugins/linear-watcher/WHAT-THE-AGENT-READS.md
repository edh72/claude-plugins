# What the agent actually reads

`linear-watcher` is **not a skill** — there is no `SKILL.md`. It's **hook-driven**.
The agent's "instructions" are the **stdout that the hook scripts emit**, which
Claude Code injects into the agent's context. This file shows that text verbatim,
so you can see exactly what shapes the agent's behavior.

The rest of the plugin (`check.sh`, `config.sh`, `hooks/hooks.json`,
`.claude-plugin/plugin.json`) is plumbing the harness runs — not text the agent reads.

---

## 1. At session start — `scripts/report.sh`

Fires on every `SessionStart` (startup / resume / clear / compact).

**When a Todo is waiting**, it injects:

```
Linear watcher: 1 item(s) in the Todo lane (APPS-517). This IS your go signal — do NOT wait for the user to type "to-dos". Work them now per the "to-dos" workflow (finish what you can → Done; anything where your part is done but it needs the user's review/decision → post a recommendation comment and move it to your review/feedback status, NOT Backlog). A ticket you recently acted on reappearing here is the normal revision loop — the user re-opened it with NEW feedback, so read the newest comments and act on those rather than re-verifying it. Unless the user's first message directs you elsewhere.

[linear-watcher — auto-arm] To catch Todos that arrive mid-session (even while the user is idle), start the background watcher NOW if you have not already started it this session, using the run_in_background tool with the sandbox disabled:
  CLAUDE_PROJECT_DIR='<repo path>' bash '<plugin>/scripts/watch.sh'
It sleeps cheaply (zero tokens) and exits the instant a Todo appears, which re-invokes you. When it fires: work the lane per the "to-dos" workflow, then re-arm it the same way. Never run a second copy if one is already running.
```

**When the lane is empty**, the first line becomes:

```
Linear watcher: Todo lane is empty.
```

…followed by the same `[linear-watcher — auto-arm]` block.

**When the repo isn't configured** (no `LINEAR_PROJECT_ID` / no API key): it emits
**nothing** (the plugin is inert there).

> The `"to-dos"` trigger phrase above is whatever `LINEAR_TRIGGER_PHRASE` is set to
> for the repo (default `to-dos`).

---

## 2. When the background watcher trips — `scripts/watch.sh`

`watch.sh` is the loop the agent starts via the `run_in_background` tool (per the
arm directive above). It polls every `LINEAR_POLL_SECONDS` (default 120) and exits
the moment a Todo appears, which re-invokes the agent with this text:

```
[linear-watcher] A Todo just landed in the lane: APPS-517 (1 total). This IS your go signal — do NOT ask the user to confirm or to type "to-dos". Work it now per the "to-dos" workflow: finish what you can (→ Done); anything where your part is done but it needs the user's review/decision gets a recommendation comment and moves to your review/feedback status (NOT Backlog). If this is a ticket you recently acted on, it's almost certainly the user re-opening it with NEW feedback — read the newest comments and act on those; don't waste turns re-verifying whether it's real. When finished, RE-ARM this watcher (start watch.sh via run_in_background again).
```

If the repo isn't configured, `watch.sh` exits immediately (code 2) instead of
looping, so no dead loop is left running.

---

## 3. The `/linear-watcher:init` slash command — `commands/init.md`

A setup helper the user (or agent) can invoke. It walks the agent through asking
for the Linear project ID + options and writing them into the repo's
`.claude/settings.json` `env` block. Full text lives in
[`commands/init.md`](commands/init.md). Summary of what it instructs:

1. Ask for the **Linear project ID** (UUID) — offer to look it up via Linear MCP if unknown.
2. Ask (with defaults) for **state/lane type** (`unstarted`), **trigger phrase** (`to-dos`), **poll interval** (`120`).
3. Write them into `.claude/settings.json` under `"env"`.
4. Confirm the global API key (`~/.config/linear-watcher/key` or `LINEAR_API_KEY`).
5. Tell the user it'll report on next session start, verifiable with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh"`.

---

## Important caveat

This behavior depends on the agent **obeying those injected directives**. Injected
context is strong guidance, not a hard guarantee — an agent can still choose to
ignore it (e.g. asking the user to confirm instead of acting). The wording above is
deliberately imperative to minimize that. If you ever see an agent ignore a
surfaced Todo, this is the text to tighten.
