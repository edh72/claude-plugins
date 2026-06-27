# linear-watcher — development memory & learnings

Everything learned building and iterating this plugin, so work can continue in the
`claude-plugins` repo without re-deriving it. Companion docs:
[`README.md`](README.md) (usage) and [`WHAT-THE-AGENT-READS.md`](WHAT-THE-AGENT-READS.md)
(the verbatim text the agent sees).

## What it is
A Claude Code plugin that auto-pulls Linear "Todo" items into a session. It is
**not a skill** — there's no `SKILL.md`. It's **hook-driven**: the agent's
instructions are the **stdout of the hook scripts**, which Claude Code injects as
context. Everything else (`check.sh`, `config.sh`, `hooks/`, manifests) is plumbing.

## Architecture / how it works
- **`hooks/hooks.json`** registers one hook: `SessionStart` → `scripts/report.sh`.
- **`report.sh`** (SessionStart) does two things as injected context: (1) reports
  the watched lane, and (2) **auto-arms the watcher** — it instructs the agent to
  start `watch.sh` via the `run_in_background` tool. Always exits 0; silent when
  the repo isn't configured.
- **`watch.sh`** is the real proactive watcher: a poll loop the agent runs via
  `run_in_background`. It exits 0 the instant a Todo appears (printing a go-signal),
  which re-invokes the agent — even while the user is idle. Exits 2 fast if the repo
  isn't configured (so no dead loop).
- **`check.sh`** is the zero-token Linear GraphQL query (one-shot). Exit codes:
  `0` items exist, `1` none, `2` no key, `3` no project.
- **`config.sh`** resolves config: env var → `.claude/linear-watcher.json` →
  `.claude/settings.json` → default. No `jq` dependency (grep/sed). API key is
  global-only, never read from a repo.

## Platform constraints (the hard truths — don't relitigate these)
- Only THREE things make the agent act: (1) the user sends a message, (2) a session
  lifecycle event, (3) a background process the **agent itself** started via
  `run_in_background` (which re-invokes the agent when it exits).
- **A plugin hook CANNOT spawn a self-waking loop** — only the agent can, via
  `run_in_background`. That's why the SessionStart hook *injects a directive* telling
  the agent to arm `watch.sh`, rather than starting it itself. This is the one soft
  spot: it depends on the agent obeying injected context.
- A `SessionStart` hook with **no matcher** fires on `startup`, `resume`, `clear`,
  and `compact`.
- Hook stdout is injected as context the agent can act on **only** for
  `SessionStart`, `UserPromptSubmit`, and `UserPromptExpansion`. Other events' stdout
  goes to the debug log.
- **No AFK coverage is possible** — nothing wakes Claude Code while no session is
  open. True set-and-forget would require an external scheduler (launchd/cron) that
  starts a fresh session; not built (user declined).

## Behavior decisions (encoded in the injected text)
- **Detection IS the go signal.** Do not make the user type the trigger phrase to
  start working — surfacing a Todo (session start or watcher fire) means act.
- **Needs-review work → the feedback column, NEVER Backlog.** Backlog = deliberately
  deferred/not-started. Completed-pending-review work goes to the configured
  `LINEAR_FEEDBACK_STATUS` (e.g. "Needs Feedback").
- **Re-opens are the normal revision loop.** A recently-worked ticket reappearing in
  the watched lane means the user re-opened it with NEW feedback — read the newest
  comments and act, don't waste turns "verifying it's real."
- **Silent in unconfigured repos.** No `LINEAR_PROJECT_ID`/key ⇒ hooks emit nothing,
  so a global install is harmless everywhere.
- **Shareability principle:** keep the plugin generic. User-specific conventions
  (exact deploy steps, exact status names) belong in the user's own memory, not baked
  into the shared plugin. The plugin names a configured column if provided, else uses
  a generic phrase.

## Config values (per repo, in `.claude/settings.json` `env`)
| Key | Meaning | Default |
|---|---|---|
| `LINEAR_PROJECT_ID` | project/board to watch | unset → inert |
| `LINEAR_TODO_STATUS` | exact column NAME to watch | unset → use `LINEAR_STATE_TYPE` |
| `LINEAR_FEEDBACK_STATUS` | exact column needs-review work moves into | unset → generic phrase |
| `LINEAR_STATE_TYPE` | fallback watch by Linear state *type* | `unstarted` |
| `LINEAR_TRIGGER_PHRASE` | phrase referenced in the report | `to-dos` |
| `LINEAR_POLL_SECONDS` | watcher poll interval | `120` |
| `LINEAR_API_KEY` | **global** secret (env or `~/.config/linear-watcher/key`) | — |

`check.sh` filters by status **name** when `LINEAR_TODO_STATUS` is set, else by state
**type**. Quotes are escaped for JSON-in-JSON (`\\\"` in the shell var → `\"` in the
GraphQL body). `/linear-watcher:init` scans the board's columns via Linear MCP and
asks the user to pick the watch + feedback columns.

## Install / update gotchas (these bit us)
- The runtime copy lives at `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`
  (versioned subdir). The marketplace clone is separate at
  `~/.claude/plugins/marketplaces/<marketplace>/...`. `${CLAUDE_PLUGIN_ROOT}` resolves
  to the active versioned cache dir.
- `claude plugin update <name>` fails with "not found" — you must qualify it:
  `claude plugin update <name>@<marketplace>`.
- Once, `update` left a **stale/empty runtime copy**; a clean
  `uninstall` + `install` fixed it. If a new version's scripts don't seem live, verify
  the active `cache/.../<version>/scripts` dir and reinstall.
- Any plugin change needs a **session restart** to take effect.

## Release flow (versions are PINNED, so users only update when you bump)
1. Edit `.claude-plugin/plugin.json` `version` AND the matching entry in
   `.claude-plugin/marketplace.json` (they must agree).
2. `claude plugin validate ./plugins/linear-watcher` and `claude plugin validate .` —
   both must pass.
3. Commit + push to `main` (solo repo, no PRs).
4. `claude plugin tag ./plugins/linear-watcher` (creates `<name>--v<version>`), then
   `git push origin --tags`.
5. `gh release create <name>--v<version> --repo edh72/claude-plugins --title ... --notes ...`.
6. `claude plugin marketplace update <marketplace>` then
   `claude plugin update <name>@<marketplace>`; restart to apply.

## Version history (what & why)
- **0.1.0** initial: SessionStart hook reports the lane.
- **0.1.1** packaging/metadata.
- **0.2.0** added a `UserPromptSubmit` per-turn check — WRONG model (only fired on the
  user's turns, not proactively). Removed.
- **0.3.0** restored the real background watcher (`watch.sh`) and made SessionStart
  auto-arm it. Removed the per-turn hook.
- **0.3.1** detection reworded as an imperative GO signal (agent acts, doesn't ask the
  user to type the phrase).
- **0.3.2** needs-review work goes to a review/feedback status, NOT Backlog.
- **0.3.3** understand the re-open revision loop (read newest comments, don't re-verify).
- **0.4.0** configurable columns: `LINEAR_TODO_STATUS` + `LINEAR_FEEDBACK_STATUS`;
  `check.sh` filters by name; `init` scans the board.

## Environment / tooling notes
- `gh` is installed at `~/.local/bin/gh` (downloaded tarball, not brew), authed as
  `edh72` over SSH. The `claude` plugin CLI works non-interactively.
- `jq` is present but the scripts deliberately avoid it (portability).
- macOS has **no `timeout`** — don't use it in tests; rely on cases that exit fast.
- The default shell here is **zsh**, which does NOT word-split unquoted `$var` — use
  `printf '%s\n' a b c | while read -r x` for list loops, not `for x in $LIST`.
- Network calls (curl/ssh/rsync) need Bash run with the sandbox disabled.
- Don't commit `.DS_Store` (gitignored).
