# linear-watcher

A Claude Code plugin that **auto-pulls Linear "Todo" items into your session**.
Every time a Claude Code session starts in a configured repo, it does a tiny,
**zero-token** `curl` check against Linear's GraphQL API and reports whether
anything is waiting in that repo's Todo lane.

```
session starts ─► SessionStart hook ─► report.sh ─► check.sh ─► curl → Linear
                                                                     │
   "Linear watcher: 2 item(s) waiting in the Todo lane (ENG-1, ENG-2). ◄┘
    Say "to-dos" to work them."
```

Install once; it applies to **all** your repos but stays **silent** in any repo
that hasn't set a `LINEAR_PROJECT_ID` — so a global install is harmless.

## Install

```
/plugin marketplace add  https://github.com/edh72/claude-plugins
/plugin install linear-watcher@edh-claude-plugins
```

## One-time global setup: your API key

The key is a secret and is **never** read from a repo. Provide it once via env
var `LINEAR_API_KEY`, or a key file:

```bash
mkdir -p ~/.config/linear-watcher
printf '%s' 'lin_api_xxxxxxxx' > ~/.config/linear-watcher/key
```

Get a key in Linear → **Settings → Security & access → Personal API keys**.

## Per-repo setup (the tokenized bit)

Run the bundled command in a repo:

```
/linear-watcher:init
```

…or set it by hand in the repo's `.claude/settings.json`:

```json
{
  "env": {
    "LINEAR_PROJECT_ID": "64d4472d-3ce7-4359-b991-ee138b29574a",
    "LINEAR_STATE_TYPE": "unstarted",
    "LINEAR_TRIGGER_PHRASE": "to-dos",
    "LINEAR_POLL_SECONDS": "120"
  }
}
```

### Configuration values

Each value resolves in this order: **env var → `.claude/linear-watcher.json` →
`.claude/settings.json` → built-in default**.

| Value | Scope | Default | Meaning |
|---|---|---|---|
| `LINEAR_API_KEY` | global (secret) | — | env var, or `~/.config/linear-watcher/key` |
| `LINEAR_PROJECT_ID` | **per repo** | unset → watcher off | the project / "board" to watch |
| `LINEAR_STATE_TYPE` | per repo | `unstarted` | Linear state *type* of the lane (Todo = `unstarted`) |
| `LINEAR_TRIGGER_PHRASE` | per repo | `to-dos` | what the report tells you to say |
| `LINEAR_POLL_SECONDS` | per repo | `120` | interval for the optional in-session watcher |

## Verify it works

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check.sh"
# prints "NEW <n>" + identifiers, or "NONE"
# exit 0 = items exist · 1 = none · 2 = no key · 3 = repo not configured
```

## How it surfaces Todos (v0.3.0+ — a real, auto-armed watcher)

The `SessionStart` hook (`report.sh`) does two things, both as injected context:

1. **Reports the lane** at every session boundary (startup / resume / clear / compact).
2. **Auto-arms the watcher** — it instructs the agent to start `watch.sh` via the
   `run_in_background` tool. `watch.sh` polls the lane every `LINEAR_POLL_SECONDS`
   (default 120) and **exits the instant a Todo appears, which re-invokes the
   agent — even while you're idle, with no message from you.** It sleeps at zero
   model-token cost otherwise. When it fires, the agent works the lane and
   re-arms it.

This is a genuine background watcher (not a per-turn check). The one platform
reality: a plugin hook can't spawn a self-waking loop directly — only the agent
can, via `run_in_background` — so the hook injects an explicit directive to arm
it every session. Reliable, but it does depend on the agent following that
directive.

**No AFK coverage:** nothing can wake Claude Code while *no session is open*. The
watcher runs only within an open session. For checks with no session open, run a
scheduled job (a launchd timer / cron) that invokes the to-dos workflow.

## Files

| File | Purpose |
|---|---|
| `.claude-plugin/plugin.json` | Plugin manifest |
| `hooks/hooks.json` | Registers the `SessionStart` hook |
| `scripts/config.sh` | Resolves the tokenized config values |
| `scripts/check.sh` | The zero-token Linear query |
| `scripts/report.sh` | The session-start reporter (always exits 0) |
| `commands/init.md` | `/linear-watcher:init` to scaffold a repo |

## Notes / gotchas

- **No `jq` required** — JSON is parsed with `grep`/`sed`.
- **No secrets in any repo** — the API key is global only.
- **Sandbox**: if your hooks run sandboxed, the `curl` call needs network access.
- The watcher matches by Linear state **type** (`unstarted`), so it follows the
  Todo lane even if you rename it. Set `LINEAR_STATE_TYPE` to target a different
  lane (e.g. `started`, `backlog`).
